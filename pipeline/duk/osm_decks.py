"""Flashcard decks of real Macau and Hong Kong names, from OpenStreetMap (ODbL).

Nothing here is typed from memory: every name, Portuguese/English form and street-word
pattern comes from the downloaded OSM extracts (`duk fetch`). Readings are added by the
normal annotator at build time, and uncertain ones go to the review queue.

Decks
  mo-streets   Macau streets, most-mapped first (a rough proxy for how long/important)
  mo-lrt       Macau Light Rapid Transit stations
  hk-mtr       Hong Kong MTR stations
  hk-streets   Hong Kong streets, most-mapped first
"""

from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

_HAN = re.compile(r"^[㐀-鿿豈-﫿]+$")
_ALIAS = re.compile(r"^(.*?)\s*[（(]\s*(.*?)\s*[)）]\s*$")

STREET_LIMIT = 400

DECKS = {
    "mo-streets": ("Macau streets", "macau", "Street names on Macau signs, with the Portuguese"),
    "mo-lrt": ("Macau LRT stations", "macau", "Light Rapid Transit stops"),
    "hk-mtr": ("Hong Kong MTR stations", "hk", "Every MTR station name"),
    "hk-streets": ("Hong Kong streets", "hk", "Street names on Hong Kong signs, with the English"),
}

# Street-type endings to look for when learning patterns (longest first). Which
# Portuguese word goes with each is counted from the data, not assumed.
_SUFFIXES = sorted(
    ["大馬路", "馬路", "街", "巷", "斜巷", "圍", "前地", "里", "坊", "斜路", "圓形地", "公路",
     "大橋", "隧道", "廣場", "台", "徑", "道", "路", "橋", "碼頭", "海傍"],
    key=len,
    reverse=True,
)  # fmt: skip


@dataclass
class Card:
    id: str
    deck: str
    zh: str
    alt: str  # Portuguese (Macau) or English (HK)
    note: str = ""
    rank: int = 0


@dataclass
class Decks:
    cards: list[Card] = field(default_factory=list)
    # (region, zh suffix, pt word, n with that word, n with the suffix)
    patterns: list[tuple[str, str, str, int, int]] = field(default_factory=list)


def _split_alias(zh: str) -> tuple[str, str]:
    m = _ALIAS.match(zh)
    return (m.group(1), m.group(2)) if m else (zh, "")


def _elements(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return json.loads(path.read_text("utf-8")).get("elements", [])


def _streets(els, deck: str, alt_key: str) -> list[Card]:
    count: Counter[str] = Counter()
    alt: dict[str, Counter[str]] = defaultdict(Counter)
    alias: dict[str, str] = {}
    for e in els:
        t = e.get("tags", {})
        if "highway" not in t or not t.get("name:zh"):
            continue
        zh, other = _split_alias(t["name:zh"].strip())
        if not _HAN.match(zh) or len(zh) < 2:
            continue
        count[zh] += 1
        if t.get(alt_key):
            alt[zh][t[alt_key].strip()] += 1
        if other and _HAN.match(other):
            alias.setdefault(zh, other)
    cards = []
    for rank, (zh, _) in enumerate(count.most_common(STREET_LIMIT)):
        a = alt[zh].most_common(1)[0][0] if alt[zh] else ""
        note = f"Also called {alias[zh]}" if zh in alias else ""
        cards.append(Card(f"card:{deck}:{zh}", deck, zh, a, note, rank))
    return cards


def _stations(els, deck: str, alt_key: str, keep) -> list[Card]:
    seen: dict[str, str] = {}
    for e in els:
        t = e.get("tags", {})
        if not keep(t) or not t.get("name:zh"):
            continue
        zh = t["name:zh"].strip()
        if not _HAN.match(zh):
            continue
        seen.setdefault(zh, (t.get(alt_key) or t.get("name:en") or "").strip())
    return [
        Card(f"card:{deck}:{zh}", deck, zh, a, "", rank)
        for rank, (zh, a) in enumerate(sorted(seen.items()))
    ]


def street_patterns(cards: list[Card], region: str) -> list[tuple[str, str, str, int, int]]:
    """For each Chinese street ending, the first word of the Portuguese/English name that
    most often goes with it, kept only when it is clearly the usual one."""
    by_suffix: dict[str, Counter[str]] = defaultdict(Counter)
    for c in cards:
        if not c.alt:
            continue
        suffix = next((s for s in _SUFFIXES if c.zh.endswith(s)), None)
        if not suffix:
            continue
        words = c.alt.split()
        key = words[0] if region == "macau" else words[-1]
        by_suffix[suffix][key] += 1
    out = []
    for suffix, words in by_suffix.items():
        total = sum(words.values())
        word, n = words.most_common(1)[0]
        if total >= 5 and n / total >= 0.6:
            out.append((region, suffix, word, n, total))
    return sorted(out, key=lambda r: -r[4])


def _drop_simplified(cards: list[Card]) -> list[Card]:
    """OSM occasionally has a Simplified duplicate (荃湾 beside 荃灣): keep the
    Traditional spelling only. A name counts as Simplified when converting it to
    Traditional changes it and that Traditional form is also a card."""
    import opencc

    to_trad = opencc.OpenCC("s2hk")
    names = {c.zh for c in cards}
    return [
        c for c in cards if not (to_trad.convert(c.zh) != c.zh and to_trad.convert(c.zh) in names)
    ]


def load_decks(raw_root: Path) -> Decks | None:
    mo = _elements(raw_root / "osm_macau" / "osm_macau.json")
    hk = _elements(raw_root / "osm_hk" / "osm_hk.json")
    if not mo and not hk:
        return None
    d = Decks()
    mo_streets = _streets(mo, "mo-streets", "name:pt")
    hk_streets = _streets(hk, "hk-streets", "name:en")
    d.cards += mo_streets
    d.cards += _stations(mo, "mo-lrt", "name:pt", lambda t: t.get("railway") in ("station", "stop"))
    d.cards += _stations(
        hk,
        "hk-mtr",
        "name:en",
        lambda t: (
            t.get("railway") == "station"
            and "MTR" in (t.get("network", "") + t.get("operator", ""))
            and t.get("station") in ("subway", "train")
        ),
    )
    d.cards += hk_streets
    d.cards = _drop_simplified(d.cards)
    d.patterns = street_patterns(mo_streets, "macau") + street_patterns(hk_streets, "hk")
    return d
