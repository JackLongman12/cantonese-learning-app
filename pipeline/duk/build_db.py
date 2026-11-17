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
from .annotate import (
    FLAG,
    HAN,
    Annotation,
    annotate,
    char_frequency,
    load_word_readings,
    spoken_readings,
)
from .content import Content, ContentError, load_content
from .reference import load_reference
from .words import refine_words

SCHEMA_VERSION = 17  # 2: lex_char/lex_word; 3: dialogue; 4: stories; 5: dict_entry;
# 6: decks; 7: card image + credit, food deck; 8: slim dict_entry (Cantonese only);
# 9: char_info.hint, skill / skill_entry; 10: variant (words for the same thing);
# 11: character_pic (links the app downloads; the images are never bundled);
# 12: char_freq (share of each character in HKCanCor: "% of everyday Cantonese");
# 13: scenario.description (what a topic is about, shown on its tile and page);
# 14: situation (newcomer mode: decks of essential words, content/situations.yaml);
# 15: card_picture (a photo or an icon per newcomer word, content/pictures.yaml)
# 16: practice (replies, tone sets, frames, challenges: content/practice.yaml)
# 17: card_picture.doubt (pictures to rate in Settings > Developer)

SCHEMA = """
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE scenario(
  id TEXT PRIMARY KEY, title TEXT NOT NULL, region TEXT NOT NULL, tags TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '');
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
CREATE TABLE situation(id TEXT PRIMARY KEY REFERENCES deck(id), icon TEXT NOT NULL,
  rank INTEGER NOT NULL) WITHOUT ROWID;
CREATE TABLE practice(id TEXT PRIMARY KEY, kind TEXT NOT NULL, grp TEXT NOT NULL,
  card_id TEXT NOT NULL, en TEXT NOT NULL, extra TEXT NOT NULL, rank INTEGER NOT NULL)
  WITHOUT ROWID;
CREATE TABLE card_picture(card_id TEXT PRIMARY KEY, kind TEXT NOT NULL, ref TEXT NOT NULL,
  credit TEXT NOT NULL DEFAULT '', doubt INTEGER NOT NULL DEFAULT 0) WITHOUT ROWID;
CREATE TABLE street_pattern(
  region TEXT NOT NULL, zh TEXT NOT NULL, word TEXT NOT NULL, n INTEGER NOT NULL,
  total INTEGER NOT NULL);
CREATE TABLE variant(
  group_id TEXT NOT NULL, en TEXT NOT NULL, note TEXT NOT NULL, word TEXT NOT NULL,
  reading TEXT, rank INTEGER NOT NULL, PRIMARY KEY(group_id, word)) WITHOUT ROWID;
CREATE TABLE character_pic(role TEXT PRIMARY KEY, url TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE char_freq(ch TEXT PRIMARY KEY, share REAL NOT NULL) WITHOUT ROWID;
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
        self.unlisted: list[tuple[str, str]] = []  # (variant group, word not in a dictionary)


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
    word_readings = load_word_readings(raw_root / "rime_cantonese" / "jyut6ping3.words.dict.yaml")
    # dictionary words, to keep only real words as underlined groups
    vocab = None
    _entries = None
    if with_lexicon:
        from .dictionary import load_dictionary
        from .words import vocabulary

        _entries = load_dictionary(raw_root)
        if _entries is not None:
            vocab = vocabulary(_entries, content.overrides.get("yue", {}))
            # variant words count as words even when no dictionary lists them (白車)
            _vp = content_root / "variants.yaml"
            if _vp.exists():
                import yaml as _yaml

                for g in (_yaml.safe_load(_vp.read_text("utf-8")) or {}).get("groups") or []:
                    vocab |= {w for w in g.get("words") or [] if len(w) > 1}

    for sc in content.scenarios:
        db.execute(
            "INSERT INTO scenario VALUES(?,?,?,?,?)",
            (
                sc.id,
                sc.title,
                sc.region,
                json.dumps(sc.tags, ensure_ascii=False),
                sc.description,
            ),
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

    # Newcomer situations (content/situations.yaml): each a deck of essential words and
    # short chunks with English, drilled English-first in newcomer mode
    import yaml

    spath = content_root / "situations.yaml"
    sdoc = yaml.safe_load(spath.read_text("utf-8")) if spath.exists() else None
    seen_sit: set[str] = set()
    for srank, sit in enumerate((sdoc or {}).get("situations") or []):
        sid = str(sit.get("id", ""))
        if not sid.startswith("sit-") or sid in seen_sit:
            problems.append(f"situations.yaml: bad or repeated id {sid!r}")
            continue
        seen_sit.add(sid)
        title, desc = str(sit.get("title", "")), str(sit.get("description", ""))
        if not title or not 0 < len(desc) <= 160:
            problems.append(f"situations.yaml {sid}: title and a one-line description required")
            continue
        db.execute(
            "INSERT INTO deck VALUES(?,?,?,?,?)",
            (sid, title, "both", desc, "DuckLearn (LLM-drafted; readings from dictionaries)"),
        )
        db.execute("INSERT INTO situation VALUES(?,?,?)", (sid, str(sit.get("icon", "")), srank))
        words_seen: set[str] = set()
        for wrank, w in enumerate(sit.get("words") or []):
            if not isinstance(w, list) or len(w) < 2 or not w[0] or not w[1]:
                problems.append(f"situations.yaml {sid}: each word is [Cantonese, English, tip?]")
                continue
            zh, en = str(w[0]), str(w[1])
            if zh in words_seen:
                problems.append(f"situations.yaml {sid}: {zh} listed twice")
                continue
            words_seen.add(zh)
            add_card(f"card:{sid}:{zh}", sid, zh, en, str(w[2]) if len(w) > 2 else "", wrank)

    # Newcomer practice (content/practice.yaml): each Cantonese line is a card in a hidden
    # prc-* deck (readings, review queue and audio as for any card); `practice` says
    # what it is for
    ppath_ = content_root / "practice.yaml"
    pr = (yaml.safe_load(ppath_.read_text("utf-8")) if ppath_.exists() else None) or {}
    for did, title in (("prc-replies", "Replies"), ("prc-tones", "Tones"),
                       ("prc-frames", "Sentences"), ("prc-challenges", "Challenges")):
        db.execute("INSERT INTO deck VALUES(?,?,?,?,?)",
                   (did, title, "both", "", "DuckLearn (LLM-drafted; readings from dictionaries)"))
    seen_prc: set[str] = set()
    prank = 0

    def practice(pid, kind, grp, deck, zh, en, extra=""):
        nonlocal prank
        if pid in seen_prc:
            problems.append(f"practice.yaml: {pid} listed twice")
            return None
        seen_prc.add(pid)
        cid = f"card:{deck}:{zh}"
        add_card(cid, deck, zh, "", "", prank)
        db.execute("INSERT INTO practice VALUES(?,?,?,?,?,?,?)",
                   (pid, kind, grp, cid, en, extra, prank))
        prank += 1
        return cid

    for sid, lines in (pr.get("replies") or {}).items():
        if sid not in seen_sit or len(lines or []) < 4:
            problems.append(f"practice.yaml replies {sid}: unknown situation or under 4 replies")
            continue
        for zh, en in lines:
            practice(f"rep:{sid}:{zh}", "reply", sid, "prc-replies", zh, en)
    for ts in pr.get("tone_sets") or []:
        tid = str(ts.get("id", ""))
        syllables = set()
        tones = []
        for ch, en in ts.get("chars") or []:
            cid = practice(f"tone:{tid}:{ch}", "tone", tid, "prc-tones", ch, en, ts["title"])
            row = db.execute(
                "SELECT reading FROM card_token WHERE card_id = ?", (cid,)
            ).fetchall() if cid else []
            if len(row) != 1 or not row[0][0]:
                problems.append(f"practice.yaml {tid}: {ch} has no single reading")
                continue
            syllables.add(row[0][0][:-1])
            tones.append(row[0][0][-1])
        if len(syllables) != 1 or len(set(tones)) != len(tones) or len(tones) < 2:
            problems.append(f"practice.yaml {tid}: members must share a syllable, tones differ "
                            f"({sorted(syllables)}, {tones})")
    for fr in pr.get("frames") or []:
        fid, fzh, fen = str(fr.get("id", "")), str(fr.get("zh", "")), str(fr.get("en", ""))
        if fzh.count("＿") != 1 or fen.count("___") != 1:
            problems.append(f"practice.yaml {fid}: one ＿ in zh and one ___ in en")
            continue
        for word, wen in (fr.get("fill") or {}).items():
            en = fen.replace("___", str(wen))
            practice(f"frame:{fid}:{word}", "frame", fid, "prc-frames",
                     fzh.replace("＿", str(word)), en[0].upper() + en[1:], fzh)
    for ch in pr.get("challenges") or []:
        if ch.get("sit") not in seen_sit:
            problems.append(f"practice.yaml {ch.get('id')}: unknown situation")
            continue
        practice(str(ch["id"]), "challenge", ch["sit"], "prc-challenges", ch["zh"], ch["en"])

    # Word pictures (content/pictures.yaml): photo = a Wikimedia Commons file the phone
    # downloads (with its credit), icon = an OpenMoji hexcode bundled as a small PNG
    ppath = content_root / "pictures.yaml"
    pdoc = yaml.safe_load(ppath.read_text("utf-8")) if ppath.exists() else None
    cards_now = {r[0] for r in db.execute("SELECT id FROM card")}
    for cid, pic in (pdoc or {}).items():
        if not pic or cid not in cards_now:
            continue
        if pic.get("photo"):
            db.execute(
                "INSERT INTO card_picture VALUES(?,?,?,?,?)",
                (cid, "photo", str(pic["photo"]), str(pic.get("credit", "")),
                 int(bool(pic.get("doubt")))),
            )
        elif pic.get("icon"):
            db.execute(
                "INSERT INTO card_picture VALUES(?,?,?,?,?)",
                (cid, "icon", str(pic["icon"]), "", int(bool(pic.get("doubt")))),
            )

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
                    e["zh"],
                    "yue",
                    overrides=content.overrides.get("yue"),
                    prior=priors["yue"],
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

    # Conversation pictures (content/characters.yaml): only the links go into the app,
    # which downloads each picture on the device (Irasutoya forbids redistributing files)
    cpath = content_root / "characters.yaml"
    cdoc = yaml.safe_load(cpath.read_text("utf-8")) if cpath.exists() else None
    for role, info in ((cdoc or {}).get("characters") or {}).items():
        url = (info or {}).get("image", "")
        if not url.startswith("https://"):
            problems.append(f"characters.yaml {role}: image must be an https link")
            continue
        db.execute("INSERT INTO character_pic VALUES(?,?)", (role, url))

    # How common each character is in everyday Hong Kong Cantonese (HKCanCor): the app's
    # "you can read N% of everyday Cantonese". Characters seen at least twice.
    for ch, share in char_frequency().items():
        db.execute("INSERT INTO char_freq VALUES(?,?)", (ch, share))

    # Words for the same thing (content/variants.yaml): "Also said" on a tapped word
    vpath = content_root / "variants.yaml"
    vdoc = yaml.safe_load(vpath.read_text("utf-8")) if vpath.exists() else None
    listed = {e.trad for e in _entries} if _entries is not None else None
    seen_groups: set[str] = set()
    for g in (vdoc or {}).get("groups") or []:
        gid = g.get("id", "")
        if not gid.startswith("var-") or gid in seen_groups:
            problems.append(f"variants: bad or duplicate id {gid!r}")
            continue
        seen_groups.add(gid)
        if len(g.get("words") or []) < 2:
            problems.append(f"{gid}: needs at least two words")
            continue
        for rank, w in enumerate(g["words"]):
            try:
                ann = annotate(
                    w,
                    "yue",
                    overrides=content.overrides.get("yue"),
                    prior=priors["yue"],
                    spoken=spoken,
                    words=word_readings,
                )
            except ValueError as err:
                problems.append(f"{gid} {w}: {err}")
                continue
            if ann.flags:
                result.flags.append((gid, "yue", ann))
            if listed is not None and w not in listed:
                result.unlisted.append((gid, w))
            db.execute(
                "INSERT INTO variant VALUES(?,?,?,?,?,?)",
                (gid, g["en"], g.get("note", ""), w,
                 " ".join(x for x in ann.readings if x) or None, rank),
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
    if result.unlisted:
        lines += [
            "## Variant words not in CC-Canto or CC-CEDICT",
            "",
            "Confirm each is really said this way (content/variants.yaml), or remove it.",
            "",
        ]
        lines += [f"- {gid}: {w}" for gid, w in result.unlisted]
        lines.append("")
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
