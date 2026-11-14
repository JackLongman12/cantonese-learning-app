"""Command line: `duk fetch | annotate | validate | build | tts`."""

from __future__ import annotations

import argparse
import sys

from . import paths
from .content import ContentError, load_content


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(prog="duk")
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fetch", help="download reference datasets into data/raw/")
    f.add_argument("--only", nargs="*", help="source names, e.g. osm_macau osm_hk")
    a = sub.add_parser("annotate", help="show readings for a piece of text")
    a.add_argument("text")
    a.add_argument("--lang", choices=["yue"], default="yue")
    sub.add_parser("validate", help="check the YAML content tree")
    sub.add_parser("build", help="build build/content.db and the review queue")
    t = sub.add_parser("tts", help="synthesise audio for every sentence in content.db")
    t.add_argument("--limit", type=int, default=None)
    sub.add_parser("bundle", help="copy content.db and audio into the app's assets")
    args = ap.parse_args(argv)

    try:
        if args.cmd == "fetch":
            from .fetch_sources import fetch

            print("\n".join(fetch(only=args.only)))
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
            if n_audio == 0:
                print(
                    "content.db has no audio rows: run `duk tts` after `duk build`", file=sys.stderr
                )
                return 1

            dest = paths.ROOT / "app" / "assets" / "content"
            (dest / "audio").mkdir(parents=True, exist_ok=True)
            shutil.copy2(paths.CONTENT_DB, dest / "content.db")
            wanted = {f.name for f in paths.AUDIO.glob("*.mp3")} if paths.AUDIO.exists() else set()
            for stale in dest.glob("audio/*.mp3"):
                if stale.name not in wanted:
                    stale.unlink()
            for name in wanted:
                if not (dest / "audio" / name).exists():
                    shutil.copy2(paths.AUDIO / name, dest / "audio" / name)
            print(f"bundled content.db and {len(wanted)} audio files -> {dest}")
    except ContentError as e:
        print("Content problems:", file=sys.stderr)
        for p in e.problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
