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
  bool Function(int weekday)? onDays,
}) {
  final cutoff = (now ?? DateTime.now().toUtc()).subtract(
    const Duration(days: 30),
  );
  final minutes = <int>[
    for (final e in events)
      if (e.type == 'session.start' && e.tsUtc.isAfter(cutoff))
        if (e.tsUtc.add(Duration(minutes: e.tzOffsetMin)) case final local
            when onDays == null || onDays(local.weekday))
          local.hour * 60 + local.minute,
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

/// When the reminder goes out before there is any history: early evening.
const defaultReminderMinute = 20 * 60;

/// "Smart" reminder times, learned from when you actually start sessions: one for
/// weekdays and one for weekends (people read at different times on days off), each
/// falling back to your overall usual time, then to [defaultReminderMinute].
/// [learned] is false while there is too little history to go on.
({int weekday, int weekend, bool learned}) smartReminderTimes(
  Iterable<Event> events, {
  DateTime? now,
}) {
  final list = events.toList();
  final all = usualStudyMinute(list, now: now);
  final weekday =
      usualStudyMinute(list, now: now, onDays: (d) => d <= DateTime.friday) ??
      all;
  final weekend =
      usualStudyMinute(list, now: now, onDays: (d) => d > DateTime.friday) ??
      all;
  return (
    weekday: weekday ?? defaultReminderMinute,
    weekend: weekend ?? defaultReminderMinute,
    learned: all != null,
  );
}
