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
from .annotate import FLAG, HAN, Annotation, annotate, load_word_readings, spoken_readings
from .content import Content, ContentError, load_content
from .reference import load_reference
from .words import refine_words

SCHEMA_VERSION = 9  # 2: lex_char/lex_word; 3: dialogue; 4: stories; 5: dict_entry;
# 6: decks; 7: card image + credit, food deck; 8: slim dict_entry (Cantonese only);
# 9: char_info.hint, skill / skill_entry

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
  phonetic TEXT, semantic TEXT, definition TEXT, hint TEXT);
CREATE TABLE skill(id TEXT PRIMARY KEY, title TEXT NOT NULL, subtitle TEXT NOT NULL);
CREATE TABLE skill_entry(
  skill_id TEXT NOT NULL, id TEXT PRIMARY KEY, zh TEXT NOT NULL, reading TEXT,
  emoji TEXT NOT NULL, meaning TEXT NOT NULL, example TEXT NOT NULL, example_en TEXT NOT NULL,
  rank INTEGER NOT NULL);
CREATE TABLE family(component TEXT NOT NULL, member TEXT NOT NULL,
  PRIMARY KEY(component, member)) WITHOUT ROWID;
CREATE TABLE lex_char(
  lang TEXT NOT NULL, char TEXT NOT NULL, reading TEXT NOT NULL, n_readings INTEGER NOT NULL,
  PRIMARY KEY(lang, char)) WITHOUT ROWID;
CREATE TABLE lex_word(
  lang TEXT NOT NULL, word TEXT NOT NULL, reading TEXT NOT NULL,
  PRIMARY KEY(lang, word)) WITHOUT ROWID;
CREATE TABLE dialogue(
  id TEXT PRIMARY KEY, scenario_id TEXT NOT NULL REFERENCES scenario(id), title TEXT NOT NULL,
  lines INTEGER NOT NULL, kind TEXT NOT NULL, lang TEXT NOT NULL, level INTEGER NOT NULL,
  pair_id TEXT);
CREATE TABLE dict_entry(
  trad TEXT NOT NULL, jyutping TEXT NOT NULL, en TEXT NOT NULL, source TEXT NOT NULL);
CREATE INDEX dict_trad ON dict_entry(trad);
CREATE TABLE deck(
  id TEXT PRIMARY KEY, title TEXT NOT NULL, region TEXT NOT NULL, description TEXT NOT NULL,
  source TEXT NOT NULL);
CREATE TABLE card(
  id TEXT PRIMARY KEY, deck_id TEXT NOT NULL REFERENCES deck(id), zh TEXT NOT NULL,
  alt TEXT NOT NULL, note TEXT NOT NULL, rank INTEGER NOT NULL, flagged INTEGER NOT NULL,
  image TEXT, credit TEXT NOT NULL DEFAULT '');
CREATE TABLE card_token(
  card_id TEXT NOT NULL, idx INTEGER NOT NULL, surface TEXT NOT NULL, kind TEXT NOT NULL,
  reading TEXT, item_id TEXT, flagged INTEGER NOT NULL, PRIMARY KEY(card_id, idx)) WITHOUT ROWID;
CREATE TABLE street_pattern(
  region TEXT NOT NULL, zh TEXT NOT NULL, word TEXT NOT NULL, n INTEGER NOT NULL,
  total INTEGER NOT NULL);
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
    priors = {"yue": ref.prior("yue") if ref else {}}
    spoken = spoken_readings()  # how words are said in HKCanCor (third voter)
    word_readings = load_word_readings(
        raw_root / "rime_cantonese" / "jyut6ping3.words.dict.yaml"
    )
    # dictionary words, to keep only real words as underlined groups
    vocab = None
    _entries = None
    if with_lexicon:
        from .dictionary import load_dictionary
        from .words import vocabulary

        _entries = load_dictionary(raw_root)
        if _entries is not None:
            vocab = vocabulary(_entries, content.overrides.get("yue", {}))

    for sc in content.scenarios:
        db.execute(
            "INSERT INTO scenario VALUES(?,?,?,?)",
            (sc.id, sc.title, sc.region, json.dumps(sc.tags, ensure_ascii=False)),
        )

    for d in content.dialogues:
        db.execute(
            "INSERT INTO dialogue VALUES(?,?,?,?,?,?,?,?)",
            (d.id, d.scenario, d.title, d.lines, d.kind, d.lang, d.level, d.pair),
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
                    spoken=spoken,
                    words=word_readings,
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
            for w in refine_words(ann.words, vocab):
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
        for lang, text in (("yue", p.zh),):
            try:
                ann = annotate(
                    text,
                    lang,
                    overrides=content.overrides.get(lang),
                    fix=p.fix.get(lang),
                    prior=priors[lang],
                    spoken=spoken,
                    words=word_readings,
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

    from .osm_decks import DECKS, load_decks

    flagged_cards = 0

    def add_card(cid, deck, zh, alt, note, rank, image=None, credit=""):
        nonlocal flagged_cards
        try:
            ann = annotate(
                zh,
                "yue",
                overrides=content.overrides.get("yue"),
                prior=priors["yue"],
                names=True,
                spoken=spoken,
                    words=word_readings,
            )
        except ValueError as e:
            result.warnings.append(f"{cid}: {e}")
            return
        flagged = bool(ann.flags)
        flagged_cards += flagged
        if flagged:
            result.flags.append((cid, "yue", ann))
        db.execute(
            "INSERT OR IGNORE INTO card VALUES(?,?,?,?,?,?,?,?,?)",
            (cid, deck, zh, alt, note, rank, int(flagged), image, credit),
        )
        for idx, t in enumerate(ann.tokens):
            item_id = None
            if t.kind == HAN and t.reading:
                item_id = char_item_id("yue", t.surface, t.reading)
                item_rows.setdefault(item_id, ("char_reading", "yue", t.surface, t.reading))
            db.execute(
                "INSERT OR IGNORE INTO card_token VALUES(?,?,?,?,?,?,?)",
                (cid, idx, t.surface, t.kind, t.reading, item_id, int(t.status == FLAG)),
            )  # fmt: skip

    decks = load_decks(raw_root)
    if decks is None:
        result.warnings.append("OSM extracts missing (run `duk fetch`): no flashcard decks")
    else:
        for did, (title, region, desc) in DECKS.items():
            db.execute(
                "INSERT INTO deck VALUES(?,?,?,?,?)",
                (did, title, region, desc, "OpenStreetMap (ODbL)"),
            )
        for c in decks.cards:
            add_card(c.id, c.deck, c.zh, c.alt, c.note, c.rank)
        db.executemany("INSERT INTO street_pattern VALUES(?,?,?,?,?)", decks.patterns)
        result.warnings.append(
            f"decks: {len(decks.cards)} cards, {flagged_cards} with an unconfirmed reading"
        )

    from .wiki_food import load_food_deck

    food = load_food_deck(raw_root)
    if food is None:
        result.warnings.append("food pages missing (run `duk fetch --only food`): no food deck")
    else:
        import yaml

        d = yaml.safe_load((content_root / "decks" / "food.yaml").read_text("utf-8"))["deck"]
        db.execute(
            "INSERT INTO deck VALUES(?,?,?,?,?)",
            (d["id"], d["title"], d["region"], d["description"],
             "Cantonese Wikipedia; photos Wikimedia Commons"),
        )  # fmt: skip
        # English: the dictionary's meaning first (plain), else the English article title
        meanings = {}
        for e in _entries or []:
            meanings.setdefault(e.trad, e.en.split(";")[0].strip())
        cats = list(
            yaml.safe_load((content_root / "decks" / "food.yaml").read_text("utf-8"))["categories"]
            or {}
        )
        food.sort(key=lambda c: (cats.index(c.category) if c.category in cats else 99, c.zh))
        for rank, c in enumerate(food):
            add_card(f"card:food:{c.zh}", "food", c.zh, meanings.get(c.zh) or c.en, "", rank,
                     c.image, c.credit)  # fmt: skip
        result.warnings.append(f"food deck: {len(food)} dishes")

    # Reading-skill lessons (content/skills/*.yaml): particles, measure words, ...
    import yaml

    for path in (
        sorted((content_root / "skills").glob("*.yaml"))
        if (content_root / "skills").exists()
        else []
    ):
        doc = yaml.safe_load(path.read_text("utf-8")) or {}
        sid = doc["skill"]
        db.execute("INSERT INTO skill VALUES(?,?,?)", (sid, doc["title"], doc.get("subtitle", "")))
        for rank, e in enumerate(doc.get("entries") or []):
            try:
                ann = annotate(
                    e["zh"], "yue", overrides=content.overrides.get("yue"), prior=priors["yue"],
                    spoken=spoken,
                    words=word_readings,
                )
                reading = " ".join(r for r in ann.readings if r)
            except ValueError as err:
                problems.append(f"{e.get('id')}: {err}")
                continue
            db.execute(
                "INSERT INTO skill_entry VALUES(?,?,?,?,?,?,?,?,?)",
                (sid, e["id"], e["zh"], reading or None, e.get("emoji", ""), e["meaning"],
                 e["example"], e["example_en"], rank),
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
        db.executemany("INSERT INTO char_info VALUES(?,?,?,?,?,?,?,?,?)", ref.char_rows())
        db.executemany("INSERT INTO family VALUES(?,?)", ref.family_rows())

    if with_lexicon:
        from .lexicon import yue_lexicon

        for lang, make in (("yue", yue_lexicon),):
            chars, words = make(content.overrides.get(lang, {}))
            db.executemany(
                "INSERT INTO lex_char VALUES(?,?,?,?)",
                ((lang, c, r, n) for c, (r, n) in chars.items()),
            )
            db.executemany(
                "INSERT INTO lex_word VALUES(?,?,?)", ((lang, w, r) for w, r in words.items())
            )
            result.warnings.append(f"lexicon {lang}: {len(chars)} chars, {len(words)} words")

    if with_lexicon:
        from .dictionary import load_dictionary

        entries = load_dictionary(raw_root)
        if entries is None:
            result.warnings.append("dictionary missing (run `duk fetch`): word meanings empty")
        else:
            # Cantonese only: keep entries with a Jyutping reading (or from CC-Canto),
            # meanings shortened; Mandarin-only columns are gone (smaller app)
            kept = [e for e in entries if e.jyutping or e.source == "cccanto"]
            db.executemany(
                "INSERT INTO dict_entry VALUES(?,?,?,?)",
                ((e.trad, e.jyutping, e.en[:100], e.source) for e in kept),
            )
            result.warnings.append(f"dictionary: {len(kept)} entries")

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


def _write_review_queue(path: Path, result: BuildResult) -> None:
    lines = [
        "# Review queue",
        "",
        "Readings the pipeline could not settle on its own. Say the line aloud, pick the",
        "reading you actually use, then pin it with `fix_yue:` on the entry",
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
