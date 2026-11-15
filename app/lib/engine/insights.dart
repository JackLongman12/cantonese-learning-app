/// Things learned from the event log about how this person studies.
library;

import '../events/event.dart';

/// The local time of day this learner usually starts reading, as minutes after midnight,
/// rounded to the quarter hour. Uses session starts from the last 30 days; null until
/// there are at least [minSessions].
int? usualStudyMinute(
  Iterable<Event> events, {
  DateTime? now,
  int minSessions = 3,
}) {
  final cutoff = (now ?? DateTime.now().toUtc()).subtract(
    const Duration(days: 30),
  );
  final minutes = <int>[
    for (final e in events)
      if (e.type == 'session.start' && e.tsUtc.isAfter(cutoff))
        (() {
          final local = e.tsUtc.add(Duration(minutes: e.tzOffsetMin));
          return local.hour * 60 + local.minute;
        })(),
  ];
  if (minutes.length < minSessions) return null;
  // the busiest hour, then the median minute within it
  final byHour = <int, List<int>>{};
  for (final m in minutes) {
    byHour.putIfAbsent(m ~/ 60, () => []).add(m);
  }
  final busiest = byHour.values.reduce((a, b) => b.length > a.length ? b : a)
    ..sort();
  final median = busiest[busiest.length ~/ 2];
  return (median ~/ 15) * 15;
}

/// Sentences shown in reading or speaking in the last [window], so the next session can
/// pick different ones (they come back once the window has passed, or when nothing else
/// covers what is due).
Set<String> recentSentences(
  Iterable<Event> events,
  DateTime nowUtc, {
  Duration window = const Duration(days: 2),
}) {
  final since = nowUtc.subtract(window);
  return {
    for (final e in events)
      if ((e.type == 'item.shown' || e.type == 'speech.attempt') &&
          e.tsUtc.isAfter(since))
        if (e.payload['sentence_id'] case final String id) id,
  };
}
