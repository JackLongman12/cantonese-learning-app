"""English meanings for words, from CC-CEDICT (Mandarin) and CC-Canto (Cantonese).

Line formats (downloaded files are parsed as text only):
  CC-CEDICT        trad simp [pin1 yin1] /meaning/meaning/
  CC-Canto         trad simp [pin1 yin1] {jyut6 ping3} /meaning/
  canto readings   trad simp [pin1 yin1] {jyut6 ping3}      (Jyutping for CEDICT entries)
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

_LINE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\](?: \{([^}]*)\})?(?: /(.*)/)?\s*$")


@dataclass
class Entry:
    trad: str
    simp: str
    pinyin: str
    jyutping: str
    en: str
    source: str  # cccanto | cedict


def _parse(path: Path):
    for line in path.read_text("utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        m = _LINE.match(line)
        if m:
            yield m.groups()


def _clean_en(defs: str) -> str:
    parts = [d for d in defs.split("/") if d and not d.startswith("CL:")]
    return "; ".join(parts[:4])[:240]


def load_dictionary(raw_root: Path) -> list[Entry] | None:
    cedict = next(iter((raw_root / "cedict").glob("*.u8")), None)
    canto = next(iter((raw_root / "cccanto").glob("*.txt")), None)
    readings = next(iter((raw_root / "cccanto_readings").glob("*.txt")), None)
    if not cedict:
        return None
    jyut: dict[tuple[str, str], str] = {}
    if readings:
        for trad, _simp, pinyin, jp, _ in _parse(readings):
            if jp:
                jyut.setdefault((trad, pinyin.replace(" ", "").lower()), jp)
    out: list[Entry] = []
    seen: set[tuple[str, str]] = set()
    # Cantonese entries first: their meaning is the Cantonese one (e.g. 埋單).
    if canto:
        for trad, simp, pinyin, jp, defs in _parse(canto):
            if defs:
                out.append(Entry(trad, simp, pinyin, jp or "", _clean_en(defs), "cccanto"))
                seen.add((trad, _clean_en(defs)))
    for trad, simp, pinyin, _, defs in _parse(cedict):
        if not defs:
            continue
        en = _clean_en(defs)
        if (trad, en) in seen or not en:
            continue
        jp = jyut.get((trad, pinyin.replace(" ", "").lower()), "")
        out.append(Entry(trad, simp, pinyin, jp, en, "cedict"))
    return out
