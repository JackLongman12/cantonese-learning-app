"""Compact reading lexicon for annotating arbitrary text on the device.

The app reads any pasted or photographed text, so it needs readings without the Python
libraries. Shipping whole dictionaries would be large; instead we ship:

- one default reading per character, plus how many readings it has (ambiguity flag);
- only those multi-character words whose reading differs from reading each character
  with its default (銀行 -> ngan4 hong4 because 行 alone defaults to hang4).

Longest-match over the exception words, falling back to per-character defaults, then
reproduces the dictionary's choice for nearly every word while staying a few MB.
Owner overrides (content/overrides/readings.yaml) win over everything.
"""

from __future__ import annotations

from collections.abc import Iterator

from .annotate import is_han, valid_reading

MAX_WORD = 6


def _tojyutping_entries() -> Iterator[tuple[str, list[list[str]]]]:
    """Walk ToJyutping's trie: (word, [reading option, ...]) with each option a syllable list."""
    from ToJyutping import Trie as trie_mod

    stack = [("", trie_mod.root)]
    while stack:
        prefix, node = stack.pop()
        if node.v:
            options = []
            for v in node.v:
                syls = [str(x) for x in v] if isinstance(v, list) else [str(v)]
                options.append(syls)
            yield prefix, options
        for ch, child in node.items():
            stack.append((prefix + ch, child))


def yue_lexicon(
    overrides: dict[str, list[str]],
) -> tuple[dict[str, tuple[str, int]], dict[str, str]]:
    """Returns (char -> (default reading, number of readings), word -> 'r1 r2 ...')."""
    chars: dict[str, tuple[str, int]] = {}
    words: dict[str, list[str]] = {}
    for word, options in _tojyutping_entries():
        if len(word) == 1 and is_han(word):
            readings = [o[0] for o in options if o and valid_reading("yue", o[0])]
            if readings:
                chars[word] = (readings[0], len(dict.fromkeys(readings)))
        elif 1 < len(word) <= MAX_WORD and all(is_han(c) for c in word):
            best = options[0]
            if len(best) == len(word) and all(valid_reading("yue", r) for r in best):
                words[word] = best
    return _finish(chars, words, overrides)


def cmn_lexicon(
    overrides: dict[str, list[str]],
) -> tuple[dict[str, tuple[str, int]], dict[str, str]]:
    import json
    from pathlib import Path

    import pypinyin
    from pypinyin import Style, pinyin

    root = Path(pypinyin.__file__).parent
    chars: dict[str, tuple[str, int]] = {}
    for cp, _marked in json.loads((root / "pinyin_dict.json").read_text("utf-8")).items():
        ch = chr(int(cp))
        if not is_han(ch):
            continue
        opts = pinyin(ch, style=Style.TONE3, heteronym=True, neutral_tone_with_five=True)[0]
        opts = [o for o in opts if valid_reading("cmn", o)]
        if opts:
            chars[ch] = (opts[0], len(opts))
    words: dict[str, list[str]] = {}
    for phrase in json.loads((root / "phrases_dict.json").read_text("utf-8")):
        if not (1 < len(phrase) <= MAX_WORD and all(is_han(c) for c in phrase)):
            continue
        if all(chars.get(c, ("", 1))[1] == 1 for c in phrase):
            continue  # nothing ambiguous inside: per-character defaults are already right
        r = [x[0] for x in pinyin(phrase, style=Style.TONE3, neutral_tone_with_five=True)]
        if len(r) == len(phrase) and all(valid_reading("cmn", x) for x in r):
            words[phrase] = r
    return _finish(chars, words, overrides)


def _finish(
    chars: dict[str, tuple[str, int]],
    words: dict[str, list[str]],
    overrides: dict[str, list[str]],
) -> tuple[dict[str, tuple[str, int]], dict[str, str]]:
    for word, readings in overrides.items():
        if len(word) == 1:
            n = chars.get(word, (readings[0], 1))[1]
            chars[word] = (readings[0], n)
        else:
            words[word] = list(readings)
    exceptions: dict[str, str] = {}
    for word, readings in words.items():
        default = [chars.get(c, ("", 0))[0] for c in word]
        if readings != default or word in overrides:
            exceptions[word] = " ".join(readings)
    return chars, exceptions
