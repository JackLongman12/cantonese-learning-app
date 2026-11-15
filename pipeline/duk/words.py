"""Word groups for underlining: which characters in a sentence form one word.

pycantonese segments by context but sometimes glues a word to its neighbour (好撚,
帶遮). A group is kept only when the dictionary (CC-Canto, CC-CEDICT) or an owner
override lists it as a word; otherwise it is split into the longest dictionary words
inside it, and leftover characters stand alone.
"""

from __future__ import annotations

from .annotate import Word


def refine_words(words: list[Word], vocab: set[str] | None) -> list[Word]:
    if vocab is None:
        return words
    out: list[Word] = []
    for w in words:
        if w.text in vocab:
            out.append(w)
            continue
        i = 0
        while i < w.length:
            for n in range(w.length - i, 1, -1):
                piece = w.text[i : i + n]
                if piece in vocab:
                    out.append(Word(piece, w.start + i, n))
                    i += n
                    break
            else:
                i += 1
    return out


def vocabulary(entries, overrides: dict[str, list[str]]) -> set[str]:
    words = {e.trad for e in entries if len(e.trad) > 1}
    words |= {w for w in overrides if len(w) > 1}
    return words
