"""Compile the YAML content tree into build/content.db.

Outputs:
- build/content.db         read-only database shipped to the app
- build/review_queue.md    every reading a human still has to confirm
- content/readings.lock.json   approved readings of reviewed sentences; a later build
                               that would change one of them fails instead of silently
                               teaching a different reading
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path

from . import __version__, paths
from .annotate import FLAG, HAN, Annotation, annotate
from .content import Content, ContentError, load_content
from .reference import load_reference

SCHEMA_VERSION = 2  # 2: lex_char / lex_word for on-device annotation

SCHEMA = """
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE scenario(
  id TEXT PRIMARY KEY, title TEXT NOT NULL, region TEXT NOT NULL, tags TEXT NOT NULL);
CREATE TABLE sentence(
  id TEXT PRIMARY KEY,             -- '<pair_id>:<lang>'
  pair_id TEXT NOT NULL, lang TEXT NOT NULL, text TEXT NOT NULL, en TEXT NOT NULL,
  register TEXT NOT NULL, region TEXT NOT NULL, scenario_id TEXT NOT NULL REFERENCES scenario(id),
  tags TEXT NOT NULL, notes TEXT NOT NULL, source TEXT NOT NULL, reviewed INTEGER NOT NULL,
  dialogue TEXT, speaker TEXT, turn INTEGER, pattern TEXT);
CREATE INDEX sentence_pair ON sentence(pair_id);
CREATE INDEX sentence_scenario ON sentence(scenario_id);
CREATE TABLE token(
  sentence_id TEXT NOT NULL REFERENCES sentence(id), idx INTEGER NOT NULL,
  surface TEXT NOT NULL, kind TEXT NOT NULL, reading TEXT, item_id TEXT, flagged INTEGER NOT NULL,
  PRIMARY KEY(sentence_id, idx)) WITHOUT ROWID;
CREATE TABLE item(
  id TEXT PRIMARY KEY,             -- 'cr:<lang>:<char>:<reading>' | 'w:<lang>:<word>'
  kind TEXT NOT NULL, lang TEXT NOT NULL, key TEXT NOT NULL, reading TEXT,
  n_sentences INTEGER NOT NULL);
CREATE TABLE sentence_item(
  sentence_id TEXT NOT NULL, item_id TEXT NOT NULL,
  PRIMARY KEY(sentence_id, item_id)) WITHOUT ROWID;
CREATE INDEX sentence_item_item ON sentence_item(item_id);
CREATE TABLE sentence_word(
  sentence_id TEXT NOT NULL, start_idx INTEGER NOT NULL, length INTEGER NOT NULL,
  item_id TEXT NOT NULL, PRIMARY KEY(sentence_id, start_idx)) WITHOUT ROWID;
CREATE TABLE sentence_place(
  pair_id TEXT NOT NULL, place_id TEXT NOT NULL, PRIMARY KEY(pair_id, place_id)) WITHOUT ROWID;
CREATE TABLE place(
  id TEXT PRIMARY KEY, zh TEXT NOT NULL, readings TEXT NOT NULL, official_pt TEXT, en TEXT,
  region TEXT NOT NULL, district TEXT, type TEXT NOT NULL, lat REAL, lon REAL, photo TEXT,
  nearby TEXT NOT NULL, example TEXT, reviewed INTEGER NOT NULL, flagged INTEGER NOT NULL);
CREATE TABLE char_info(
  char TEXT PRIMARY KEY, yue TEXT, cmn TEXT, simplified TEXT, traditional TEXT,
  phonetic TEXT, semantic TEXT, definition TEXT);
CREATE TABLE family(component TEXT NOT NULL, member TEXT NOT NULL,
  PRIMARY KEY(component, member)) WITHOUT ROWID;
CREATE TABLE lex_char(
  lang TEXT NOT NULL, char TEXT NOT NULL, reading TEXT NOT NULL, n_readings INTEGER NOT NULL,
  PRIMARY KEY(lang, char)) WITHOUT ROWID;
CREATE TABLE lex_word(
  lang TEXT NOT NULL, word TEXT NOT NULL, reading TEXT NOT NULL,
  PRIMARY KEY(lang, word)) WITHOUT ROWID;
CREATE TABLE audio(
  hash TEXT PRIMARY KEY, lang TEXT NOT NULL, voice TEXT NOT NULL, rate TEXT NOT NULL,
  text TEXT NOT NULL, path TEXT NOT NULL);
"""


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def char_item_id(lang: str, char: str, reading: str) -> str:
    return f"cr:{lang}:{char}:{reading}"


def word_item_id(lang: str, word: str) -> str:
    return f"w:{lang}:{word}"


class BuildResult:
    def __init__(self) -> None:
        self.sentences = 0
        self.items = 0
        self.flags: list[tuple[str, str, Annotation]] = []  # (owner id, lang, annotation)
        self.warnings: list[str] = []


def build(
    content_root: Path = paths.CONTENT,
    out_db: Path = paths.CONTENT_DB,
    *,
    lock_path: Path | None = None,
    review_path: Path | None = None,
    raw_root: Path = paths.RAW,
    content: Content | None = None,
    with_lexicon: bool = True,
) -> BuildResult:
    content = content or load_content(content_root)
    lock_path = lock_path or content_root / "readings.lock.json"
    review_path = review_path or out_db.parent / "review_queue.md"
    lock: dict[str, dict] = json.loads(lock_path.read_text("utf-8")) if lock_path.exists() else {}
    new_lock: dict[str, dict] = {}
    result = BuildResult()
    problems: list[str] = []

    out_db.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_db.with_suffix(".db.tmp")
    tmp.unlink(missing_ok=True)
    db = sqlite3.connect(tmp)
    db.executescript(SCHEMA)

    ref = load_reference(raw_root)
    priors = {lang: ref.prior(lang) if ref else {} for lang in ("yue", "cmn")}

    for sc in content.scenarios:
        db.execute(
            "INSERT INTO scenario VALUES(?,?,?,?)",
            (sc.id, sc.title, sc.region, json.dumps(sc.tags, ensure_ascii=False)),
        )

    item_rows: dict[str, tuple[str, str, str, str | None]] = {}
    item_count: Counter[str] = Counter()

    def locked(key: str, text: str, ann: Annotation, reviewed: bool) -> None:
        """Reviewed readings are frozen; drift is an error, not a silent change."""
        if not reviewed:
            return
        entry = lock.get(key)
        current = {"text": _sha(text), "readings": ann.readings}
        if entry and entry["text"] == current["text"] and entry["readings"] != current["readings"]:
            diff = [
                f"{t.surface}: {old} -> {t.reading}"
                for t, old in zip(ann.tokens, entry["readings"], strict=False)
                if old != t.reading
            ]
            problems.append(
                f"{key}: reviewed readings changed ({'; '.join(diff)}). "
                "Add a fix_<lang> entry or an override to pin them."
            )
            new_lock[key] = entry
        else:
            new_lock[key] = current

    for s in content.sentences:
        for lang, text in s.text.items():
            sid = f"{s.id}:{lang}"
            try:
                ann = annotate(
                    text,
                    lang,
                    overrides=content.overrides.get(lang),
                    fix=s.fix.get(lang),
                    prior=priors[lang],
                )
            except ValueError as e:
                problems.append(f"{sid}: {e}")
                continue
            locked(sid, text, ann, s.reviewed)
            if ann.flags and not s.reviewed:
                result.flags.append((sid, lang, ann))
            db.execute(
                "INSERT INTO sentence VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    sid, s.id, lang, text, s.en, s.register, s.region, s.scenario,
                    json.dumps(s.tags, ensure_ascii=False), s.notes, s.source, int(s.reviewed),
                    s.dialogue, s.speaker, s.turn, s.pattern,
                ),
            )  # fmt: skip
            used: set[str] = set()
            for idx, t in enumerate(ann.tokens):
                item_id = None
                if t.kind == HAN and t.reading:
                    item_id = char_item_id(lang, t.surface, t.reading)
                    item_rows[item_id] = ("char_reading", lang, t.surface, t.reading)
                    used.add(item_id)
                db.execute(
                    "INSERT INTO token VALUES(?,?,?,?,?,?,?)",
                    (sid, idx, t.surface, t.kind, t.reading, item_id,
                     int(t.status == FLAG and not s.reviewed)),
                )  # fmt: skip
            for w in ann.words:
                wid = word_item_id(lang, w.text)
                reading = " ".join(
                    t.reading or "?" for t in ann.tokens[w.start : w.start + w.length]
                )
                item_rows.setdefault(wid, ("word", lang, w.text, reading))
                used.add(wid)
                db.execute(
                    "INSERT INTO sentence_word VALUES(?,?,?,?)", (sid, w.start, w.length, wid)
                )
            for item_id in used:
                item_count[item_id] += 1
                db.execute("INSERT INTO sentence_item VALUES(?,?)", (sid, item_id))
            result.sentences += 1
        for pid in s.places:
            db.execute("INSERT OR IGNORE INTO sentence_place VALUES(?,?)", (s.id, pid))

    for p in content.places:
        readings: dict[str, list[str | None]] = {}
        flagged = False
        for lang, text in (("yue", p.zh), ("cmn", _to_simplified(p.zh))):
            try:
                ann = annotate(
                    text,
                    lang,
                    overrides=content.overrides.get(lang),
                    fix=p.fix.get(lang),
                    prior=priors[lang],
                )
            except ValueError as e:
                problems.append(f"{p.id}:{lang}: {e}")
                continue
            locked(f"{p.id}:{lang}", text, ann, p.reviewed)
            readings[lang] = ann.readings
            if ann.flags and not p.reviewed:
                flagged = True
                result.flags.append((f"{p.id}:{lang}", lang, ann))
        lat, lon = p.coords if p.coords else (None, None)
        db.execute(
            "INSERT INTO place VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                p.id, p.zh, json.dumps(readings, ensure_ascii=False), p.official_pt, p.en,
                p.region, p.district, p.type, lat, lon, p.photo,
                json.dumps(p.nearby), p.example, int(p.reviewed), int(flagged),
            ),
        )  # fmt: skip

    for item_id, (kind, lang, key, reading) in item_rows.items():
        db.execute(
            "INSERT INTO item VALUES(?,?,?,?,?,?)",
            (item_id, kind, lang, key, reading, item_count[item_id]),
        )
    result.items = len(item_rows)

    if ref is None:
        result.warnings.append("reference data missing (run `duk fetch`): char_info/family empty")
    else:
        db.executemany("INSERT INTO char_info VALUES(?,?,?,?,?,?,?,?)", ref.char_rows())
        db.executemany("INSERT INTO family VALUES(?,?)", ref.family_rows())

    if with_lexicon:
        from .lexicon import cmn_lexicon, yue_lexicon

        for lang, make in (("yue", yue_lexicon), ("cmn", cmn_lexicon)):
            chars, words = make(content.overrides.get(lang, {}))
            db.executemany(
                "INSERT INTO lex_char VALUES(?,?,?,?)",
                ((lang, c, r, n) for c, (r, n) in chars.items()),
            )
            db.executemany(
                "INSERT INTO lex_word VALUES(?,?,?)", ((lang, w, r) for w, r in words.items())
            )
            result.warnings.append(f"lexicon {lang}: {len(chars)} chars, {len(words)} words")

    if problems:
        db.close()
        tmp.unlink(missing_ok=True)
        raise ContentError(problems)

    content_version = _sha(
        json.dumps(
            [db.execute("SELECT group_concat(id || text, '|') FROM sentence").fetchone()[0],
             sorted(item_rows)],
            ensure_ascii=False,
        )
    )  # fmt: skip
    for k, v in {
        "schema_version": str(SCHEMA_VERSION),
        "content_version": content_version,
        "pipeline_version": __version__,
        "built_at": datetime.now(UTC).isoformat(timespec="seconds"),
    }.items():
        db.execute("INSERT INTO meta VALUES(?,?)", (k, v))
    db.commit()
    db.execute("VACUUM")
    db.close()
    tmp.replace(out_db)

    lock_path.write_text(
        json.dumps(dict(sorted(new_lock.items())), ensure_ascii=False, indent=1) + "\n", "utf-8"
    )
    _write_review_queue(review_path, result)
    return result


def _to_simplified(text: str) -> str:
    import opencc

    return opencc.OpenCC("hk2s").convert(text)


def _write_review_queue(path: Path, result: BuildResult) -> None:
    lines = [
        "# Review queue",
        "",
        "Readings the pipeline could not settle on its own. Say the line aloud, pick the",
        "reading you actually use, then pin it with `fix_yue:` / `fix_cmn:` on the entry",
        "(or a word in `content/overrides/readings.yaml` if it applies everywhere).",
        "",
        f"Open items: {sum(len(a.flags) for _, _, a in result.flags)}",
        "",
    ]
    for owner, lang, ann in result.flags:
        lines += [f"## {owner}", "", f"`{ann.text}`", ""]
        for t in ann.flags:
            n = sum(1 for u in ann.tokens[: ann.tokens.index(t) + 1] if u.surface == t.surface)
            total = sum(1 for u in ann.tokens if u.surface == t.surface)
            key = f"{t.surface}#{n}" if total > 1 else t.surface
            options = " | ".join(t.candidates) or "(none)"
            lines.append(
                f"- **{key}** using `{t.reading}` — {t.note}. Options: {options}"
                f"  → `fix_{lang}: {{{key}: ...}}`"
            )
        lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), "utf-8")
