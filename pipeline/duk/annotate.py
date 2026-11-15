"""Text -> tokens with one reading per token.

Design rules (docs/DESIGN.md section 5):
- Readings are an array aligned to tokens, never one string.
- Nothing ambiguous is guessed silently. Cantonese readings need two independent
  sources to agree. Flags end up in the review queue for the owner, who knows how the
  sentence sounds.
- Cantonese only: the Mandarin track was dropped (owner, 2026-11-15).
- Spoken readings win over citation readings (owner, 2026-11-16: "in spoken Cantonese I
  don't hear tones like that"). A third voter counts how each word is actually said in
  HKCanCor (recorded everyday Hong Kong speech, shipped with pycantonese): 澳門 ou3 mun2,
  錢 cin2, 會 wui5, 坐 co5, 魚 jyu2, 平 peng4. Unihan's context-free reading no longer
  breaks ties: it is the formal reading and was choosing 澳門 ou3 mun4.
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


# --------------------------------------------------------------------------- spoken

# A spoken reading counts only when it is clearly how people say the word.
SPOKEN_MIN_COUNT = 3
SPOKEN_MIN_SHARE = 0.8

# Characters whose counts on their own mislead: HKCanCor writes 仲 "still" as 重 (so 重
# looks like zung6), the particle 呢 ne1 outnumbers 呢 "this" ni1, and 會 "will" wui5
# outnumbers 會 "association" wui2.
SPOKEN_SKIP_SINGLE = frozenset("重呢會")

_spoken_cache: dict[str, str] | None = None


def spoken_readings() -> dict[str, str]:
    """word -> its dominant reading in HKCanCor ('nei5' / 'ou3 mun2'), only for words
    where one reading has at least SPOKEN_MIN_COUNT uses and SPOKEN_MIN_SHARE of them."""
    global _spoken_cache
    if _spoken_cache is not None:
        return _spoken_cache
    import collections

    import pycantonese

    counts: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for tok in pycantonese.hkcancor().tokens():
        word, jp = tok.word, tok.jyutping
        if not word or not jp or not all(is_han(c) for c in word):
            continue
        syl = _SYLLABLE_YUE.findall(jp)
        if len(syl) == len(word) and "".join(syl) == jp:
            counts[word][" ".join(syl)] += 1
    out = {}
    for word, c in counts.items():
        reading, n = c.most_common(1)[0]
        if n >= SPOKEN_MIN_COUNT and n / sum(c.values()) >= SPOKEN_MIN_SHARE:
            out[word] = reading
    _spoken_cache = out
    return out


def _lazy(spoken: str, written: str) -> bool:
    """Is the spoken form only a "lazy sound" of the written one (n -> l, ng- dropped)?
    Common in fast speech, wrong to teach."""
    a, b = spoken[:-1], written[:-1]
    return (b.startswith("n") and not b.startswith("ng") and a == "l" + b[1:]) or (
        b.startswith("ng") and a == b[2:]
    )


def _spoken_by_index(
    text: str, spans: list[tuple[int, int]], spoken: dict[str, str]
) -> dict[int, str]:
    """Per character, the spoken reading of the word it belongs to (pycantonese's
    segmentation; characters outside a multi-character word are words of their own)."""
    out: dict[int, str] = {}
    in_word = set()
    for s, e in spans:
        in_word.update(range(s, e))
        if (r := spoken.get(text[s:e])) is not None:
            for k, syl in enumerate(r.split()):
                out[s + k] = syl
    for i, ch in enumerate(text):
        if (
            i not in in_word
            and is_han(ch)
            and ch not in SPOKEN_SKIP_SINGLE
            and (r := spoken.get(ch)) is not None
        ):
            out[i] = r
    return out


def load_word_readings(path) -> dict[str, str]:
    """rime-cantonese words that have exactly one reading ('糖水' -> 'tong4 seoi2').
    Words listed with several readings (澳門 mun2 / mun4) say nothing and are left out.
    The file is untrusted data: parsed as tab-separated text only."""
    from pathlib import Path

    path = Path(path)
    if not path.exists():
        return {}
    seen: dict[str, set[str]] = {}
    body = False
    for line in path.open(encoding="utf-8"):
        if not body:
            body = line.startswith("...")
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 2 or len(parts[0]) < 2 or not all(is_han(c) for c in parts[0]):
            continue
        syl = parts[1].split()
        if len(syl) == len(parts[0]) and all(_VALID_YUE.match(x) for x in syl):
            seen.setdefault(parts[0], set()).add(" ".join(syl))
    return {w: next(iter(r)) for w, r in seen.items() if len(r) == 1}


def _lexicon_by_index(
    text: str, words: dict[str, str], spans: list[tuple[int, int]]
) -> dict[int, str]:
    """Dictionary readings for pycantonese's words ({index: reading}). Only whole words
    as segmented: matching across word boundaries finds words that are not there
    (飛能便|度街, 食|糖水)."""
    out: dict[int, str] = {}
    for s, e in spans:
        if (r := words.get(text[s:e])) is not None:
            for k, syl in enumerate(r.split()):
                out[s + k] = syl
    return out


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
    spoken: dict[str, str] | None = None,
    words: dict[str, str] | None = None,
    names: bool = False,
) -> Annotation:
    """`prior` maps a character to its context-free dictionary reading (Unihan). It never
    overrules two sources that disagree; it confirms a lone source and picks the default
    shown while a disagreement waits for review.

    `spoken` (see spoken_readings) is the third voter: how the word is said in real
    speech. With two of three agreeing the reading is settled; when both written sources
    agree on a reading that speech clearly does not use, the spoken one is shown and the
    token is flagged for the owner. `words` (load_word_readings) settles the remaining
    disagreements when it sides with one of the two sources."""
    if lang not in LANGS:
        raise ValueError(f"unknown lang {lang!r}")
    tokens = tokenize(text)
    by_start = {t.start: i for i, t in enumerate(tokens)}

    a, cands = _yue_source_a(text)
    b, spans = _yue_source_b(text)
    # names (streets, dishes): how a character is said on its own says nothing about
    # its reading inside a name or a transliteration (飛能便度 dou6, not "degree")
    listed = _lexicon_by_index(text, words or {}, spans)
    said = _spoken_by_index(text, spans, spoken or {})
    # a word the dictionary knows (糖水 tong4 seoi2) outranks how its first character
    # is said on its own (糖 "sweets" tong2)
    single = {i for i in said if not any(s <= i < e for s, e in spans)}
    for i in single & (listed.keys() if not names else set(said)):
        del said[i]

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
        rs = said.get(i)
        if rs and any(_lazy(rs, r) for r in (ra, rb) if r):
            rs = None
        # how a character is said on its own only breaks ties; a whole word said a
        # certain way (澳門 ou3 mun2) can overrule both dictionaries
        rs_word = rs if i not in single else None
        if rs and rs not in t.candidates:
            t.candidates.append(rs)
        if ra and rb and ra == rb:
            t.reading, t.status = ra, OK
            if rs_word and rs_word != ra:
                t.reading, t.status = rs_word, FLAG
                t.note = f"spoken {rs} (HKCanCor), dictionaries {ra}"
        elif ra and rb and rs in (ra, rb):
            t.reading, t.status = rs, OK  # two of three agree, one of them real speech
        elif ra and rb and listed.get(i) in (ra, rb):
            t.reading, t.status = listed[i], OK  # the word dictionary sides with one
        elif ra and rb:
            # Sentences: ToJyutping reads in context and keeps colloquial tones, so it
            # wins over the formal context-free reading. Names and transliterations
            # (飛能便度, 鄉事會) keep the dictionary's reading.
            t.reading, t.status = (rb if names and rc == rb else ra), FLAG
            t.note = f"sources disagree: {ra} / {rb}"
        elif ra or rb:
            t.reading = ra or rb
            # One source only is acceptable when the character has a single known reading
            # or the context-free dictionary reading confirms it.
            if rs_word and rs_word != t.reading:
                t.reading, t.status = rs_word, FLAG
                t.note = f"spoken {rs_word} (HKCanCor), one dictionary {ra or rb}"
            elif rs == t.reading or len(t.candidates) <= 1 or rc == t.reading:
                t.status = OK
            else:
                t.status, t.note = FLAG, "single source"
        elif rs:
            t.reading, t.status, t.note = rs, FLAG, "spoken reading only (HKCanCor)"
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
