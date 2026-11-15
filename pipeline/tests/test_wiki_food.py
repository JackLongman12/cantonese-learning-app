import json

from duk.wiki_food import load_food_deck


def test_food_cards_strip_disambiguation_and_credit_photos(tmp_path):
    d = tmp_path / "food"
    d.mkdir()
    pages = [
        {"title": "馬仔 (食品)", "category": "點心", "en": "Sachima", "file": "a.jpg",
         "thumb": "x", "licence": "CC BY-SA 3.0", "author": "Someone", "image": "abc.jpg"},
        {"title": "晶餅", "category": "點心", "en": "", "file": None, "thumb": None,
         "licence": "", "author": "", "image": None},
        {"title": "春卷", "category": "點心", "en": "Spring roll", "file": "b.jpg", "thumb": "y",
         "licence": "CC BY-SA 3.0", "author": "No machine-readable author provided.",
         "image": "def.jpg"},
    ]  # fmt: skip
    (d / "pages.json").write_text(json.dumps(pages, ensure_ascii=False), "utf-8")
    cards = {c.zh: c for c in load_food_deck(tmp_path)}
    assert set(cards) == {"馬仔", "晶餅", "春卷"}
    assert cards["馬仔"].credit == "Photo: Someone, CC BY-SA 3.0"
    assert cards["晶餅"].image is None and cards["晶餅"].credit == ""
    assert cards["春卷"].credit == "Photo: Wikimedia Commons contributor, CC BY-SA 3.0"


def test_no_download_means_no_deck(tmp_path):
    assert load_food_deck(tmp_path) is None
