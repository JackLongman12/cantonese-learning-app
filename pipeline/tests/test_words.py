from duk.annotate import Word
from duk.words import refine_words


def test_keeps_dictionary_words_and_splits_glued_ones():
    vocab = {"餐廳", "好食", "大雨"}
    words = [Word("餐廳", 2, 2), Word("好撚", 4, 2), Word("落大雨", 0, 3)]
    out = [(w.text, w.start, w.length) for w in refine_words(words, vocab)]
    assert out == [("餐廳", 2, 2), ("大雨", 1, 2)]


def test_without_a_dictionary_nothing_changes():
    words = [Word("好撚", 4, 2)]
    assert refine_words(words, None) == words
