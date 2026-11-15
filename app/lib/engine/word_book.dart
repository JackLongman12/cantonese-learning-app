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

/// A word the app noticed you struggled with: you revealed its reading when you were
/// meant to read it, or read-aloud heard it wrong. Cleared after two correct practices
/// in a row.
class PracticeWord {
  PracticeWord({
    required this.text,
    required this.lang,
    required this.flaggedAt,
    this.reading,
    this.sentenceId,
    this.context,
    this.contextEn,
  });
  final String text;
  final String lang;
  DateTime flaggedAt;
  String? reading;
  String? sentenceId;
  String? context;
  String? contextEn;

  /// Why: 'read' (couldn't read it) and/or 'say' (said it wrong).
  final reasons = <String>{};
  int misses = 0;

  /// Correct practices in a row; two clears the word.
  int streak = 0;
}

/// Correct practices in a row that take a word off the practice list.
const practiceClearStreak = 2;

class WordBook {
  final _words = <String, SavedWord>{};
  final _practice = <String, PracticeWord>{};
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
    const types = {'word.save', 'word.remove', 'word.flag', 'word.practice'};
    if (!types.contains(e.type)) return;
    if (!_seen.add(e.id)) return;
    final text = e.payload['text'];
    final lang = e.payload['lang'];
    if (text is! String || lang is! String || text.isEmpty) return;
    final key = '$lang:$text';
    String? str(String k) =>
        e.payload[k] is String ? e.payload[k] as String : null;
    if (e.type == 'word.flag') {
      final w = _practice.putIfAbsent(
        key,
        () => PracticeWord(text: text, lang: lang, flaggedAt: e.tsUtc),
      );
      w
        ..flaggedAt = e.tsUtc
        ..reading = str('reading') ?? w.reading
        ..sentenceId = str('sentence_id') ?? w.sentenceId
        ..context = str('context') ?? w.context
        ..contextEn = str('context_en') ?? w.contextEn
        ..streak = 0
        ..misses += 1;
      if (str('reason') case final r?) w.reasons.add(r);
      return;
    }
    if (e.type == 'word.practice') {
      final w = _practice[key];
      if (w == null) return;
      if (e.payload['ok'] == true) {
        w.streak += 1;
        if (w.streak >= practiceClearStreak) _practice.remove(key);
      } else {
        w
          ..streak = 0
          ..misses += 1;
      }
      return;
    }
    if (e.type == 'word.remove') {
      _words.remove(key);
      return;
    }
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

  bool needsPractice(String lang, String text) =>
      _practice.containsKey('$lang:$text');

  /// Words to practice, most missed first.
  List<PracticeWord> practice(String lang) =>
      _practice.values.where((w) => w.lang == lang).toList()..sort(
        (a, b) => b.misses != a.misses
            ? b.misses.compareTo(a.misses)
            : b.flaggedAt.compareTo(a.flaggedAt),
      );

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
