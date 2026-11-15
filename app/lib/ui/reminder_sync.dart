/// One place that decides when the daily reminder goes out. Smart by default: the time
/// you usually start reading (weekdays and weekends learned separately), moved as your
/// habits change. A fixed time only when you pick one.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../engine/insights.dart';

/// Today's reminder times, weekday and weekend (the same when the time is fixed).
({int weekday, int weekend, bool smart, bool learned}) reminderTimes(
  AppServices s,
) {
  final fixed = s.prefs.reminderMinute;
  if (fixed != null) {
    return (weekday: fixed, weekend: fixed, smart: false, learned: true);
  }
  final t = smartReminderTimes(
    s.logger.store.readAll(),
    now: s.logger.now().toUtc(),
  );
  return (
    weekday: t.weekday,
    weekend: t.weekend,
    smart: true,
    learned: t.learned,
  );
}

String clock(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// "Smart: around 21:15 (weekends 10:30)", "Smart: 20:00 until it learns when you
/// read", or "At 20:00".
String reminderLabel(AppServices s) {
  final t = reminderTimes(s);
  if (!t.smart) return 'At ${clock(t.weekday)}';
  if (!t.learned) {
    return 'Smart: ${clock(t.weekday)} until it learns when you read';
  }
  return t.weekday == t.weekend
      ? 'Smart: around ${clock(t.weekday)}, when you usually read'
      : 'Smart: around ${clock(t.weekday)} (weekends ${clock(t.weekend)})';
}

/// Read anything today? (that day's reminder is then skipped)
bool readToday(AppServices s) {
  final now = s.logger.now().toLocal();
  return s.learner.known.any((x) {
    final l = x.lastReview?.toLocal();
    return l != null &&
        l.year == now.year &&
        l.month == now.month &&
        l.day == now.day;
  });
}

/// Re-plans the next reminders (on open, after a session, after a settings change).
Future<void> syncReminders(AppServices s) async {
  final r = s.reminders;
  if (r == null) return;
  if (!s.prefs.reminderOn) {
    await r.cancel();
    return;
  }
  final t = reminderTimes(s);
  final now = s.logger.now();
  final due = s.learner.known
      .where((x) => x.due != null && !x.due!.isAfter(now))
      .length;
  await r.schedule(
    minuteFor: (weekday) => weekday > DateTime.friday ? t.weekend : t.weekday,
    readToday: readToday(s),
    reviewsReady: due,
  );
}

/// Two choices under the reminder switch: smart (default) or a time you pick.
/// [onChanged] gets the old and new fixed minute (null = smart).
List<Widget> reminderTimeTiles(
  BuildContext context,
  AppServices s,
  void Function(int? from, int? to) onChanged,
) {
  final fixed = s.prefs.reminderMinute;
  final t = reminderTimes(s);
  Future<void> set(int? to) async {
    final from = s.prefs.reminderMinute;
    s.prefs.reminderMinute = to;
    await syncReminders(s);
    onChanged(from, to);
  }

  return [
    ListTile(
      key: const ValueKey('reminder-smart'),
      leading: Icon(
        fixed == null ? Icons.check_circle_rounded : Icons.circle_outlined,
      ),
      title: const Text('Smart time'),
      subtitle: const Text(
        'Around when you usually start reading, weekdays and weekends '
        'separately. Skips days you already read.',
      ),
      onTap: fixed == null ? null : () => set(null),
    ),
    ListTile(
      key: const ValueKey('reminder-fixed'),
      leading: Icon(
        fixed != null ? Icons.check_circle_rounded : Icons.circle_outlined,
      ),
      title: const Text('Set a time'),
      subtitle: Text(fixed == null ? 'Pick your own time' : clock(fixed)),
      onTap: () async {
        final m = fixed ?? t.weekday;
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
        );
        if (picked != null) await set(picked.hour * 60 + picked.minute);
      },
    ),
  ];
}
