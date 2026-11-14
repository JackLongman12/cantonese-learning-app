"""Per-character reference data from downloaded sources (Unihan, Make Me a Hanzi).

Downloaded files are untrusted data: they are parsed as text/JSON lines only.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class CharRef:
    yue: list[str] = field(default_factory=list)
    cmn: list[str] = field(default_factory=list)
    simplified: list[str] = field(default_factory=list)
    traditional: list[str] = field(default_factory=list)
    phonetic: str | None = None
    semantic: str | None = None
    definition: str | None = None


@dataclass
class Reference:
    chars: dict[str, CharRef]

    def char_rows(self):
        for ch, r in sorted(self.chars.items()):
            yield (
                ch,
                " ".join(r.yue) or None,
                " ".join(r.cmn) or None,
                "".join(r.simplified) or None,
                "".join(r.traditional) or None,
                r.phonetic,
                r.semantic,
                r.definition,
            )

    def prior(self, lang: str) -> dict[str, str]:
        """Context-free first-listed reading per character, in pipeline notation."""
        if lang == "yue":
            return {c: r.yue[0] for c, r in self.chars.items() if r.yue}
        return {}  # Cantonese only

    def family_rows(self):
        seen = set()
        for ch, r in sorted(self.chars.items()):
            if r.phonetic and r.phonetic != ch and (r.phonetic, ch) not in seen:
                seen.add((r.phonetic, ch))
                yield (r.phonetic, ch)


def _cp(token: str) -> str | None:
    # 'U+4E00' or 'U+4E00<kLau...' -> character
    try:
        return chr(int(token.split("<")[0].removeprefix("U+"), 16))
    except ValueError:
        return None


def load_reference(raw_root: Path) -> Reference | None:
    unihan = raw_root / "unihan"
    mmah = raw_root / "makemeahanzi" / "dictionary.txt"
    if not (unihan / "Unihan_Readings.txt").exists() and not mmah.exists():
        return None
    chars: dict[str, CharRef] = {}

    def ref(ch: str) -> CharRef:
        return chars.setdefault(ch, CharRef())

    readings = unihan / "Unihan_Readings.txt"
    if readings.exists():
        for line in readings.open(encoding="utf-8"):
            if line.startswith("#") or "\t" not in line:
                continue
            cp, key, value = line.rstrip("\n").split("\t", 2)
            ch = _cp(cp)
            if ch is None:
                continue
            if key == "kCantonese":
                ref(ch).yue = value.split()
            elif key == "kMandarin":
                ref(ch).cmn = value.split()
            elif key == "kDefinition":
                ref(ch).definition = value[:200]
    variants = unihan / "Unihan_Variants.txt"
    if variants.exists():
        for line in variants.open(encoding="utf-8"):
            if line.startswith("#") or "\t" not in line:
                continue
            cp, key, value = line.rstrip("\n").split("\t", 2)
            ch = _cp(cp)
            if ch is None or key not in ("kSimplifiedVariant", "kTraditionalVariant"):
                continue
            others = [c for c in (_cp(v) for v in value.split()) if c and c != ch]
            if key == "kSimplifiedVariant":
                ref(ch).simplified = others
            else:
                ref(ch).traditional = others
    if mmah.exists():
        for line in mmah.open(encoding="utf-8"):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            ety = row.get("etymology") or {}
            ch = row.get("character")
            if not ch or ety.get("type") != "pictophonetic":
                continue
            r = ref(ch)
            r.phonetic = ety.get("phonetic") or None
            r.semantic = ety.get("semantic") or None
    return Reference(chars)
