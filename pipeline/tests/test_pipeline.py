import json
import sqlite3
import textwrap

import pytest

from duk.annotate import FIXED, FLAG, HAN, LATIN, OK, OVERRIDE, annotate, tokenize
from duk.build_db import build
from duk.content import ContentError, load_content


# ----------------------------------------------------------------- tokenize
def test_tokenize_kinds_and_alignment():
    toks = tokenize("MOP 25.5蚊，好平！")
    assert [t.surface for t in toks] == ["MOP", " ", "25.5", "蚊", "，", "好", "平", "！"]
    assert [t.kind for t in toks][:4] == [LATIN, "space", LATIN, HAN]
    assert "".join(t.surface for t in toks) == "MOP 25.5蚊，好平！"


def test_tokenize_trailing_dot_is_punctuation():
    assert [t.surface for t in tokenize("買3個.")] == ["買", "3", "個", "."]


# ----------------------------------------------------------------- annotate
def test_yue_agreeing_sources_are_ok():
    ann = annotate("唔該，埋單。", "yue")
    assert ann.readings == ["m4", "goi1", None, "maai4", "daan1", None]
    assert all(t.status == OK for t in ann.tokens if t.kind == HAN)


def test_yue_context_polyphone():
    ann = annotate("我去銀行", "yue")
    assert ann.readings[-1] == "hong4"


def test_yue_disagreement_is_flagged_not_guessed():
    # The two sources read 搭 differently (daap6 / daap3); a human must decide.
    ann = annotate("要搭幾號巴士", "yue")
    tok = ann.tokens[1]
    assert tok.status == FLAG and "daap3" in tok.candidates


def test_fix_pins_reading_by_occurrence():
    ann = annotate("長大咗，條路好長", "yue", fix={"長#2": "coeng4", "長#1": "zoeng2"})
    longs = [t for t in ann.tokens if t.surface == "長"]
    assert [t.reading for t in longs] == ["zoeng2", "coeng4"]
    assert all(t.status == FIXED for t in longs)


def test_fix_rejects_unknown_character_and_bad_reading():
    with pytest.raises(ValueError):
        annotate("你好", "yue", fix={"佢": "keoi5"})
    with pytest.raises(ValueError):
        annotate("你好", "yue", fix={"好": "hou9"})


def test_override_longest_match():
    ann = annotate("搭巴士", "yue", overrides={"搭": ["daap3"]})
    assert ann.tokens[0].reading == "daap3" and ann.tokens[0].status == OVERRIDE


def test_cmn_citation_tones_for_yi_and_bu():
    ann = annotate("一个不对", "cmn")
    assert ann.readings[0] == "yi1" and ann.readings[2] == "bu4"


def test_cmn_lone_polyphone_flagged():
    ann = annotate("这条路很长", "cmn")
    assert ann.tokens[-1].status == FLAG
    assert {"chang2", "zhang3"} <= set(ann.tokens[-1].candidates)


def test_words_are_token_spans():
    ann = annotate("我去銀行", "yue")
    assert any(w.text == "銀行" and w.length == 2 for w in ann.words)


# ----------------------------------------------------------------- content + build
def _tree(tmp_path, sentences: str, places: str = "places: []", overrides: str = ""):
    (tmp_path / "scenarios").mkdir()
    (tmp_path / "places").mkdir()
    (tmp_path / "overrides").mkdir()
    (tmp_path / "scenarios" / "a.yaml").write_text(
        "scenario: {id: scn-test-a, title: Test, region: macau}\nsentences:\n"
        + textwrap.indent(textwrap.dedent(sentences), "  "),
        "utf-8",
    )
    (tmp_path / "places" / "p.yaml").write_text(places, "utf-8")
    if overrides:
        (tmp_path / "overrides" / "readings.yaml").write_text(overrides, "utf-8")
    return tmp_path


GOOD = """
- id: sent-test-001
  yue: 唔該，埋單。
  cmn: 请结账。
  en: The bill, please.
  register: spoken
"""


def test_validation_collects_every_problem(tmp_path):
    root = _tree(
        tmp_path,
        """
        - {id: sent-test-001, yue: 你好, en: Hi, register: spoken}
        - {id: sent-test-001, yue: 你好, en: Hi, register: spoken}
        - {id: sent-test-002, yue: 你好, register: shouted, places: [place-none]}
        """,
    )
    with pytest.raises(ContentError) as e:
        load_content(root)
    text = "\n".join(e.value.problems)
    assert "duplicate id" in text and "register" in text and "en required" in text
    assert "unknown place" in text


def test_build_writes_aligned_tokens_and_items(tmp_path):
    (tmp_path / "c").mkdir()
    root = _tree(tmp_path / "c", GOOD)
    out = tmp_path / "out" / "content.db"
    r = build(root, out, raw_root=tmp_path / "noraw")
    assert r.sentences == 2 and any("reference data missing" in w for w in r.warnings)
    db = sqlite3.connect(out)
    toks = db.execute(
        "SELECT surface, reading, item_id FROM token WHERE sentence_id=? ORDER BY idx",
        ("sent-test-001:yue",),
    ).fetchall()
    assert "".join(t[0] for t in toks) == "唔該，埋單。"
    assert toks[0] == ("唔", "m4", "cr:yue:唔:m4") and toks[2][1] is None
    assert db.execute("SELECT COUNT(*) FROM item WHERE kind='word' AND key='唔該'").fetchone()[0]
    pair = db.execute("SELECT pair_id FROM sentence WHERE lang='cmn'").fetchone()[0]
    assert pair == "sent-test-001"
    assert db.execute("SELECT value FROM meta WHERE key='schema_version'").fetchone()[0] == "1"


def test_flags_reach_review_queue_until_fixed(tmp_path):
    (tmp_path / "c").mkdir()
    root = _tree(
        tmp_path / "c",
        "- {id: sent-test-001, yue: 要搭幾號巴士, en: Which bus, register: spoken}\n",
    )
    out = tmp_path / "out" / "content.db"
    r = build(root, out, raw_root=tmp_path / "noraw")
    assert r.flags and "搭" in (out.parent / "review_queue.md").read_text("utf-8")

    (root / "scenarios" / "a.yaml").write_text(
        "scenario: {id: scn-test-a, title: Test, region: macau}\nsentences:\n"
        "  - {id: sent-test-001, yue: 要搭幾號巴士, en: Which bus, register: spoken, fix_yue: {搭: daap3}}\n",
        "utf-8",
    )
    assert not build(root, out, raw_root=tmp_path / "noraw").flags


def test_reviewed_readings_are_locked_against_drift(tmp_path):
    (tmp_path / "c").mkdir()
    line = "- {id: sent-test-001, yue: 要搭幾號巴士, en: Which bus, register: spoken, reviewed: true%s}\n"
    root = _tree(tmp_path / "c", line % ", fix_yue: {搭: daap3}")
    out = tmp_path / "out" / "content.db"
    build(root, out, raw_root=tmp_path / "noraw")
    lock = json.loads((root / "readings.lock.json").read_text("utf-8"))
    assert lock["sent-test-001:yue"]["readings"] == ["jiu3", "daap3", "gei2", "hou6", "baa1", "si2"]

    # Removing the pin would silently change an approved reading: the build must refuse.
    (root / "scenarios" / "a.yaml").write_text(
        "scenario: {id: scn-test-a, title: Test, region: macau}\nsentences:\n  " + line % "",
        "utf-8",
    )
    with pytest.raises(ContentError) as e:
        build(root, out, raw_root=tmp_path / "noraw")
    assert "reviewed readings changed" in str(e.value)
