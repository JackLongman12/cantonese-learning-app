"""Command line: `duk fetch | annotate | validate | build | tts`."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import paths
from .content import ContentError, load_content


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(prog="duk")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("characters", help="download conversation characters (git-ignored)")
    f = sub.add_parser("fetch", help="download reference datasets into data/raw/")
    f.add_argument("--only", nargs="*", help="source names, e.g. osm_macau osm_hk")
    a = sub.add_parser("annotate", help="show readings for a piece of text")
    a.add_argument("text")
    a.add_argument("--lang", choices=["yue"], default="yue")
    sub.add_parser("validate", help="check the YAML content tree")
    sub.add_parser("build", help="build build/content.db and the review queue")
    t = sub.add_parser("tts", help="synthesise audio for every sentence in content.db")
    t.add_argument("--limit", type=int, default=None)
    bundle = sub.add_parser("bundle", help="copy content.db and audio into the app's assets")
    bundle.add_argument(
        "--no-audio",
        action="store_true",
        help="allow a build without audio (CI, which cannot synthesise speech)",
    )
    args = ap.parse_args(argv)

    try:
        if args.cmd == "characters":
            from .characters import fetch_characters

            print(chr(10).join(fetch_characters()))
            return 0
        if args.cmd == "fetch":
            from .fetch_sources import fetch

            only = args.only or None
            report = []
            if not only or "food" in only:
                from .wiki_food import fetch_food

                report += fetch_food()
            rest = [x for x in (only or []) if x != "food"]
            if not only or rest:
                report += fetch(only=rest or None)
            print("\n".join(report))
        elif args.cmd == "annotate":
            from .annotate import annotate

            content = load_content(paths.CONTENT)
            ann = annotate(args.text, args.lang, overrides=content.overrides.get(args.lang))
            for tok in ann.tokens:
                mark = {"flag": " ?", "override": " *", "fixed": " *"}.get(tok.status, "")
                note = (
                    f"   [{tok.note}; {' | '.join(tok.candidates)}]" if tok.status == "flag" else ""
                )
                print(f"{tok.surface}\t{tok.reading or ''}{mark}{note}")
        elif args.cmd == "validate":
            c = load_content(paths.CONTENT)
            print(f"OK: {len(c.scenarios)} scenarios, {len(c.sentences)} sentences, "
                  f"{len(c.places)} places")  # fmt: skip
        elif args.cmd == "build":
            from .build_db import build

            r = build()
            print(f"built {paths.CONTENT_DB}")
            print(f"  {r.sentences} sentence rows, {r.items} items")
            print(f"  {sum(len(a.flags) for _, _, a in r.flags)} readings to review "
                  f"-> {paths.REVIEW_QUEUE}")  # fmt: skip
            for w in r.warnings:
                print(f"  warning: {w}")
        elif args.cmd == "tts":
            from .tts import synthesise_all

            made, cached, failed = synthesise_all(limit=args.limit)
            print(f"audio: {made} new, {cached} cached, {failed} failed -> {paths.AUDIO}")
            return 1 if failed else 0
        elif args.cmd == "bundle":
            import shutil
            import sqlite3

            with sqlite3.connect(paths.CONTENT_DB) as check:
                n_audio = check.execute("SELECT COUNT(*) FROM audio").fetchone()[0]
            if n_audio == 0 and not args.no_audio:
                print(
                    "content.db has no audio rows: run `duk tts` after `duk build`", file=sys.stderr
                )
                return 1

            dest = paths.ROOT / "app" / "assets" / "content"
            (dest / "audio").mkdir(parents=True, exist_ok=True)
            shutil.copy2(paths.CONTENT_DB, dest / "content.db")
            # only clips the database uses (old ones, e.g. slow-speed copies, stay behind)
            with sqlite3.connect(paths.CONTENT_DB) as check:
                wanted = {
                    Path(r[0]).name
                    for r in check.execute("SELECT path FROM audio")
                    if (paths.AUDIO / Path(r[0]).name).exists()
                }
            for stale in dest.glob("audio/*.mp3"):
                if stale.name not in wanted:
                    stale.unlink()
            for name in wanted:
                if not (dest / "audio" / name).exists():
                    shutil.copy2(paths.AUDIO / name, dest / "audio" / name)
            # Reading font cut down to the characters the app uses (content, cards,
            # dictionary), from the full copy in data/fonts-full (git-ignored). Text with
            # other characters (pasted) falls back to the phone's own Chinese font.
            full_font = paths.ROOT / "data" / "fonts-full" / "NotoSansHK.ttf"
            if full_font.exists():
                from fontTools import subset

                with sqlite3.connect(paths.CONTENT_DB) as check:
                    chars: set[str] = set()
                    for q in (
                        "SELECT text FROM sentence",
                        "SELECT zh FROM card",
                        "SELECT trad FROM dict_entry",
                        "SELECT key FROM item",
                        "SELECT zh || example FROM skill_entry",
                        "SELECT semantic FROM char_info WHERE semantic IS NOT NULL",
                        "SELECT phonetic FROM char_info WHERE phonetic IS NOT NULL",
                    ):
                        for (t,) in check.execute(q):
                            chars.update(t)
                chars.update(chr(c) for c in range(0x20, 0x7F))
                chars.update("，。！？、：；「」『』（）《》…—～·→←↔")
                opts = subset.Options()
                opts.layout_features = ["*"]
                opts.name_IDs = ["*"]
                font = subset.load_font(str(full_font), opts)
                sub = subset.Subsetter(opts)
                sub.populate(text="".join(chars))
                sub.subset(font)
                out = paths.ROOT / "app" / "assets" / "fonts" / "NotoSansHK.ttf"
                subset.save_font(font, str(out), opts)
                print(f"font: {len(chars)} characters, {out.stat().st_size // 1000} KB")
            # card photos (freely licensed, credited on each card)
            with sqlite3.connect(paths.CONTENT_DB) as check:
                images = {
                    r[0] for r in check.execute("SELECT image FROM card WHERE image IS NOT NULL")
                }
            img_dest = paths.ROOT / "app" / "assets" / "cards"
            img_dest.mkdir(parents=True, exist_ok=True)
            for stale in img_dest.glob("*.jpg"):
                if stale.name not in images:
                    stale.unlink()
            for name in images:
                src = paths.RAW / "food" / "img" / name
                if src.exists() and not (img_dest / name).exists():
                    shutil.copy2(src, img_dest / name)
            print(f"bundled content.db, {len(wanted)} audio files, {len(images)} photos -> {dest}")
    except ContentError as e:
        print("Content problems:", file=sys.stderr)
        for p in e.problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
