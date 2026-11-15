/// Session size without a "session length" setting: the app watches how you practice
/// and adapts. Sessions are a starting batch, never a cap ("Keep going" adds more).
///
/// Signals from the last two weeks of sessions:
/// - how many sentences you read before stopping (your natural session size),
/// - how often you finish a session versus leave part way,
/// - how often you need help (reveals) per sentence.
/// Doing well and finishing: bigger batches with more new characters (harder).
/// Leaving early or needing lots of help: smaller batches, mostly review (gentler).
library;

import '../events/event.dart';

class SessionPlan {
  const SessionPlan({
    required this.count,
    required this.maxNew,
    required this.reason,
  });

  /// Sentences in the first batch.
  final int count;

  /// New characters allowed in it.
  final int maxNew;

  /// Why, in a few words (shown to the learner).
  final String reason;
}

SessionPlan adaptSession(Iterable<Event> events, DateTime nowUtc) {
  final since = nowUtc.subtract(const Duration(days: 14));
  // per session: sentences read, sentences with a reveal, finished?
  final read = <String, int>{};
  final helped = <String, int>{};
  final finished = <String>{};
  final started = <String>{};
  for (final e in events) {
    if (e.tsUtc.isBefore(since)) continue;
    switch (e.type) {
      case 'session.start':
        started.add(e.sessionId);
      case 'session.end':
        if (e.payload['reason'] == 'done') finished.add(e.sessionId);
      case 'item.done':
        if (e.payload['skipped'] == true) break;
        read.update(e.sessionId, (v) => v + 1, ifAbsent: () => 1);
        if (((e.payload['reveals'] as num?) ?? 0) > 0) {
          helped.update(e.sessionId, (v) => v + 1, ifAbsent: () => 1);
        }
    }
  }
  final sessions = read.keys.toList();
  if (sessions.length < 2) {
    return const SessionPlan(count: 8, maxNew: 4, reason: 'Starting gently');
  }
  final sizes = [for (final s in sessions) read[s]!]..sort();
  final typical = sizes[sizes.length ~/ 2];
  final totalRead = sizes.fold(0, (a, b) => a + b);
  final helpRate = helped.values.fold(0, (a, b) => a + b) / totalRead;
  final finishRate = started.isEmpty ? 1.0 : finished.length / started.length;

  var count = typical;
  var maxNew = (typical / 2).round();
  String reason;
  if (helpRate < 0.2 && finishRate >= 0.6) {
    // reading comfortably: more, and more that is new
    count = typical + 3;
    maxNew = (count * 0.6).round();
    reason = 'You are reading comfortably: a bit more, and more new';
  } else if (helpRate > 0.45 || finishRate < 0.4) {
    // struggling or leaving early: shorter, mostly review
    count = typical - 2;
    maxNew = (count * 0.25).round();
    reason = 'Lighter today: mostly characters you have met';
  } else {
    reason = 'About your usual amount';
  }
  return SessionPlan(
    count: count.clamp(5, 30),
    maxNew: maxNew.clamp(1, 15),
    reason: reason,
  );
}
