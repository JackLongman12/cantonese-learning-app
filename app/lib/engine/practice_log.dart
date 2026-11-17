/// Newcomer practice beyond single words (content/practice.yaml), rebuilt from the event
/// log: which challenges were done for real, which replies were misheard, and how well
/// each tone set is heard. Pure Dart; events are the source of truth.
library;

import '../events/event.dart';

class PracticeLog {
  PracticeLog._();

  /// Challenges the learner said they did (`challenge.done`).
  final Set<String> challengesDone = {};

  /// Replies whose meaning was picked wrong last time they came up (`listen.answer`).
  final Set<String> repliesMissed = {};

  /// Replies heard at least once.
  final Set<String> repliesHeard = {};

  /// Tone set -> the last answers (true = heard right), newest last, at most [window].
  final Map<String, List<bool>> _tones = {};

  /// Frame sentences said right at least once (`frame.say`, ok).
  final Set<String> framesSaid = {};

  static const window = 10;

  factory PracticeLog.replay(Iterable<Event> events) {
    final log = PracticeLog._();
    for (final e in events) {
      log.apply(e);
    }
    return log;
  }

  void apply(Event e) {
    final p = e.payload;
    switch (e.type) {
      case 'challenge.done':
        if (p['id'] case final String id) challengesDone.add(id);
      case 'listen.answer':
        if (p['id'] case final String id) {
          repliesHeard.add(id);
          if (p['correct'] == true) {
            repliesMissed.remove(id);
          } else {
            repliesMissed.add(id);
          }
        }
      case 'tone.answer':
        if (p['set'] case final String set) {
          final list = _tones[set] ??= [];
          list.add(p['correct'] == true);
          if (list.length > window) list.removeAt(0);
        }
      // 'picture.rate' (b2079–b2080, retired): the owner chose to keep every picture
      case 'frame.say':
        if (p['id'] case final String id when p['ok'] == true) {
          framesSaid.add(id);
        }
    }
  }

  /// Share of the last answers heard right for a tone set; null if never tried.
  double? toneScore(String set) {
    final list = _tones[set];
    if (list == null || list.isEmpty) return null;
    return list.where((ok) => ok).length / list.length;
  }

  /// Tone sets in practice order: never tried first (in the given order), then the
  /// weakest.
  List<String> toneOrder(List<String> sets) {
    final fresh = [
      for (final s in sets)
        if (toneScore(s) == null) s,
    ];
    final tried = [
      for (final s in sets)
        if (toneScore(s) != null) s,
    ]..sort((a, b) => toneScore(a)!.compareTo(toneScore(b)!));
    return [...fresh, ...tried];
  }
}
