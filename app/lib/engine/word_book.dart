/// "My words": words and word groups the learner saved while reading, each with the
/// sentence it came from. Rebuilt from `word.save` / `word.remove` events, so it never
/// drifts from the event log (docs/EVENTS_SCHEMA.md).
library;

import '../events/event.dart';

class SavedWord {
  const SavedWord({
    required this.text,
    required this.lang,
    required this.savedAt,
    this.reading,
    this.en,
    this.sentenceId,
    this.context,
    this.contextEn,
  });

  /// The word as written (Traditional).
  final String text;
  final String lang;
  final DateTime savedAt;

  /// Space-separated Jyutping, as shown when it was saved.
  final String? reading;

  /// Dictionary meaning at the time of saving.
  final String? en;
  final String? sentenceId;

  /// The sentence it was saved from, and that sentence's translation.
  final String? context;
  final String? contextEn;

  String get key => '$lang:$text';
}

class WordBook {
  final _words = <String, SavedWord>{};
  final _seen = <String>{};

  static WordBook replay(Iterable<Event> events) {
    final sorted = events.toList()
      ..sort((a, b) {
        final c = a.tsUtc.compareTo(b.tsUtc);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final book = WordBook();
    sorted.forEach(book.apply);
    return book;
  }

  void apply(Event e) {
    if (e.type != 'word.save' && e.type != 'word.remove') return;
    if (!_seen.add(e.id)) return;
    final text = e.payload['text'];
    final lang = e.payload['lang'];
    if (text is! String || lang is! String || text.isEmpty) return;
    final key = '$lang:$text';
    if (e.type == 'word.remove') {
      _words.remove(key);
      return;
    }
    String? str(String k) =>
        e.payload[k] is String ? e.payload[k] as String : null;
    _words[key] = SavedWord(
      text: text,
      lang: lang,
      savedAt: e.tsUtc,
      reading: str('reading'),
      en: str('en'),
      sentenceId: str('sentence_id'),
      context: str('context'),
      contextEn: str('context_en'),
    );
  }

  bool contains(String lang, String text) => _words.containsKey('$lang:$text');

  /// Newest first.
  List<SavedWord> words(String lang) =>
      _words.values.where((w) => w.lang == lang).toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  /// Character ranges of saved words inside [text], longest match first, no overlaps.
  List<(int, int)> highlights(String lang, String text) {
    final saved = [
      for (final w in _words.values)
        if (w.lang == lang && w.text.isNotEmpty) w.text,
    ]..sort((a, b) => b.length.compareTo(a.length));
    final taken = List<bool>.filled(text.length, false);
    final out = <(int, int)>[];
    for (final w in saved) {
      var from = 0;
      while (true) {
        final i = text.indexOf(w, from);
        if (i < 0) break;
        final end = i + w.length;
        if (!taken.sublist(i, end).contains(true)) {
          for (var k = i; k < end; k++) {
            taken[k] = true;
          }
          out.add((i, end));
        }
        from = i + 1;
      }
    }
    return out..sort((a, b) => a.$1.compareTo(b.$1));
  }
}
