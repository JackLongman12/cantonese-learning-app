import json

from duk.osm_decks import load_decks


def _write(root, name, elements):
    d = root / name
    d.mkdir(parents=True)
    (d / f"{name}.json").write_text(json.dumps({"elements": elements}), "utf-8")


def _way(zh, pt):
    return {"type": "way", "tags": {"highway": "residential", "name:zh": zh, "name:pt": pt}}


def test_decks_from_osm(tmp_path):
    mo = [_way(f"{c}街", f"Rua {c}") for c in "甲乙丙丁戊"] * 2
    mo += [_way("新馬路 (亞美打)", "Avenida X"), _way("abc", "Rua Latin")]
    mo += [{"type": "node", "tags": {"railway": "stop", "name:zh": "媽閣", "name:pt": "Barra"}}]
    hk = [
        {"type": "node", "tags": {"railway": "station", "station": "subway",
                                  "network": "港鐵 MTR", "name:zh": "荃灣", "name:en": "Tsuen Wan"}},
        {"type": "way", "tags": {"railway": "station", "station": "subway",
                                 "network": "MTR", "name:zh": "荃湾", "name:en": "Tsuen Wan"}},
    ]  # fmt: skip
    _write(tmp_path, "osm_macau", mo)
    _write(tmp_path, "osm_hk", hk)
    d = load_decks(tmp_path)
    streets = [c for c in d.cards if c.deck == "mo-streets"]
    assert {c.zh for c in streets} == {"甲街", "乙街", "丙街", "丁街", "戊街", "新馬路"}
    assert next(c for c in streets if c.zh == "新馬路").note == "Also called 亞美打"
    assert [c.zh for c in d.cards if c.deck == "mo-lrt"] == ["媽閣"]
    # the Simplified duplicate is dropped
    assert [c.zh for c in d.cards if c.deck == "hk-mtr"] == ["荃灣"]
    assert ("macau", "街", "Rua", 5, 5) in d.patterns
