"""Text -> tokens with one reading per token.

Design rules (docs/DESIGN.md section 5):
- Readings are an array aligned to tokens, never one string.
- Nothing ambiguous is guessed silently. Cantonese readings need two independent
  sources to agree. Flags end up in the review queue for the owner, who knows how the
  sentence sounds.
- Cantonese only: the Mandarin track was dropped (owner, 2026-11-15).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

LANGS = ("yue",)

# Token kinds
HAN, LATIN, PUNCT, SPACE = "han", "latin", "punct", "space"

# Status of a reading
OK = "ok"  # sources agree, or unambiguous
FLAG = "flag"  # needs a human decision
OVERRIDE = "override"  # from content/overrides/readings.yaml
FIXED = "fixed"  # from the sentence's own fix_<lang> map
NONE = "none"  # token has no reading (punctuation, Latin, space)

_SYLLABLE_YUE = re.compile(r"[a-z]+[1-6]")
_VALID_YUE = re.compile(r"^(?:[a-z]{1,6})[1-6]$")


def is_han(ch: str) -> bool:
    cp = ord(ch)
    return (
        0x4E00 <= cp <= 0x9FFF
        or 0x3400 <= cp <= 0x4DBF
        or 0xF900 <= cp <= 0xFAFF
        or 0x20000 <= cp <= 0x323AF
        or ch == "〇"
    )


def valid_reading(lang: str, reading: str) -> bool:
    return lang == "yue" and bool(_VALID_YUE.match(reading))


@dataclass
class Token:
    surface: str
    kind: str
    start: int  # index into the source string
    reading: str | None = None
    candidates: list[str] = field(default_factory=list)
    status: str = NONE
    note: str = ""


@dataclass
class Word:
    text: str
    start: int  # token index of first character
    length: int  # number of tokens


@dataclass
class Annotation:
    lang: str
    text: str
    tokens: list[Token]
    words: list[Word]

    @property
    def readings(self) -> list[str | None]:
        return [t.reading for t in self.tokens]

    @property
    def flags(self) -> list[Token]:
        return [t for t in self.tokens if t.status == FLAG]


def tokenize(text: str) -> list[Token]:
    """One token per Han character, per ASCII alphanumeric run, per other character."""
    tokens: list[Token] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if is_han(ch):
            tokens.append(Token(ch, HAN, i))
            i += 1
        elif ch.isascii() and ch.isalnum():
            j = i + 1
            while j < n and (
                (text[j].isascii() and text[j].isalnum())
                or (
                    text[j] in ".,"
                    and j + 1 < n
                    and text[j + 1].isdigit()
                    and text[j - 1].isdigit()
                )
            ):
                j += 1
            tokens.append(Token(text[i:j], LATIN, i))
            i = j
        elif ch.isspace():
            tokens.append(Token(ch, SPACE, i))
            i += 1
        else:
            tokens.append(Token(ch, PUNCT, i))
            i += 1
    return tokens


# --------------------------------------------------------------------------- sources


def _yue_source_a(text: str) -> tuple[list[str | None], list[list[str]]]:
    """ToJyutping: per-character reading and candidate list."""
    import ToJyutping

    best = [r for _, r in ToJyutping.get_jyutping_list(text)]
    cands = [list(c) for _, c in ToJyutping.get_jyutping_candidates(text)]
    if len(best) != len(text) or len(cands) != len(text):
        # Astral characters or library quirks: fall back to character-by-character.
        best, cands = [], []
        for ch in text:
            b = ToJyutping.get_jyutping_list(ch)
            c = ToJyutping.get_jyutping_candidates(ch)
            best.append(b[0][1] if b else None)
            cands.append(list(c[0][1]) if c else [])
    return best, cands


def _yue_source_b(text: str) -> tuple[list[str | None], list[tuple[int, int]]]:
    """pycantonese: per-character reading plus word spans (start, end) in the string."""
    import pycantonese

    per_char: list[str | None] = [None] * len(text)
    spans: list[tuple[int, int]] = []
    pos = 0
    try:
        pairs = pycantonese.characters_to_jyutping(text)
    except Exception:  # pragma: no cover - defensive, library failure must not stop a build
        return per_char, spans
    for word, jp in pairs:
        while pos < len(text) and text[pos].isspace():
            pos += 1
        if not text.startswith(word, pos):
            found = text.find(word, pos)
            if found < 0:
                return [None] * len(text), []
            pos = found
        syllables = _SYLLABLE_YUE.findall(jp) if jp else []
        if syllables and len(syllables) == len(word):
            for k, syl in enumerate(syllables):
                per_char[pos + k] = syl
        if len(word) > 1 and all(is_han(c) for c in word):
            spans.append((pos, pos + len(word)))
        pos += len(word)
    return per_char, spans


# --------------------------------------------------------------------------- annotate


def _apply_overrides(text: str, overrides: dict[str, list[str]]) -> dict[int, str]:
    """Longest-match word overrides -> {string index: reading}."""
    hits: dict[int, str] = {}
    if not overrides:
        return hits
    keys = sorted(overrides, key=len, reverse=True)
    i = 0
    while i < len(text):
        for k in keys:
            if text.startswith(k, i):
                for off, r in enumerate(overrides[k]):
                    hits[i + off] = r
                i += len(k) - 1
                break
        i += 1
    return hits


def _parse_fix(fix: dict[str, str] | None, tokens: list[Token]) -> dict[int, str]:
    """`{'長#2': 'coeng4', '搭': 'daap3'}` -> {token index: reading}.

    A bare character applies to every occurrence; `字#n` to the n-th (1-based).
    """
    out: dict[int, str] = {}
    for key, reading in (fix or {}).items():
        ch, _, nth = str(key).partition("#")
        idxs = [i for i, t in enumerate(tokens) if t.surface == ch]
        if not idxs:
            raise ValueError(f"fix key {key!r}: character not in sentence")
        if nth:
            n = int(nth)
            if not 1 <= n <= len(idxs):
                raise ValueError(f"fix key {key!r}: only {len(idxs)} occurrence(s)")
            idxs = [idxs[n - 1]]
        for i in idxs:
            out[i] = reading
    return out


def annotate(
    text: str,
    lang: str,
    *,
    overrides: dict[str, list[str]] | None = None,
    fix: dict[str, str] | None = None,
    prior: dict[str, str] | None = None,
) -> Annotation:
    """`prior` maps a character to its context-free dictionary reading (Unihan). It never
    overrules two sources that disagree; it confirms a lone source and picks the default
    shown while a disagreement waits for review."""
    if lang not in LANGS:
        raise ValueError(f"unknown lang {lang!r}")
    tokens = tokenize(text)
    by_start = {t.start: i for i, t in enumerate(tokens)}

    a, cands = _yue_source_a(text)
    b, spans = _yue_source_b(text)

    for t in tokens:
        if t.kind != HAN:
            continue
        i = t.start
        ra, rb = a[i], b[i]
        rc = (prior or {}).get(t.surface)
        t.candidates = [c for c in cands[i] if c]
        for r in (ra, rb):
            if r and r not in t.candidates:
                t.candidates.append(r)
        if ra and rb and ra == rb:
            t.reading, t.status = ra, OK
        elif ra and rb:
            t.reading, t.status = (rb if rc == rb else ra), FLAG
            t.note = f"sources disagree: {ra} / {rb}"
        elif ra or rb:
            t.reading = ra or rb
            # One source only is acceptable when the character has a single known reading
            # or the context-free dictionary reading confirms it.
            if len(t.candidates) <= 1 or rc == t.reading:
                t.status = OK
            else:
                t.status, t.note = FLAG, "single source"
        else:
            t.status, t.note = FLAG, "no reading found"

    for i, r in _apply_overrides(text, (overrides or {})).items():
        if i in by_start and tokens[by_start[i]].kind == HAN:
            tok = tokens[by_start[i]]
            tok.reading, tok.status, tok.note = r, OVERRIDE, ""
            if r not in tok.candidates:
                tok.candidates.append(r)

    for i, r in _parse_fix(fix, tokens).items():
        tok = tokens[i]
        tok.reading, tok.status, tok.note = r, FIXED, ""
        if r not in tok.candidates:
            tok.candidates.append(r)

    for t in tokens:
        if t.reading and not valid_reading(lang, t.reading):
            raise ValueError(f"invalid {lang} reading {t.reading!r} for {t.surface!r}")

    words = []
    for s, e in spans:
        if e - s > 1 and all(is_han(c) for c in text[s:e]) and s in by_start:
            words.append(Word(text[s:e], by_start[s], e - s))
    return Annotation(lang, text, tokens, words)
