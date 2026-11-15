/// A gentle reminder (Android) at the time the learner usually reads, only on days
/// without reading, and fading out if the app is not opened for a few days.
/// Inexact delivery: no exact-alarm permission needed, and no nagging if missed.
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Reminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const _id = 1;

  bool get supported => Platform.isAndroid;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(
        tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
      );
    } on Object {
      // keep UTC if the device zone is unknown; the time will still be daily
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// Asks for notification permission (Android 13+). Returns whether it was granted.
  Future<bool> requestPermission() async {
    await _init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Gentle, varied wording; never guilt, never a count of missed days.
  static const _bodies = [
    'A few lines when you have a moment.',
    'The characters you met are waiting, no rush.',
    'Five relaxed minutes of reading?',
    'Say a sentence or two out loud today?',
  ];

  /// Schedules the next few reminders at [minuteOfDay] local time: one per day for up
  /// to three days, skipping today when [readToday]. Called on every app open and
  /// after each session, so a day you already read gets no reminder, and if you stop
  /// opening the app the reminders stop too instead of nagging.
  Future<void> scheduleDaily(int minuteOfDay, {bool readToday = false}) async {
    if (!supported) return;
    await _init();
    await cancel();
    final now = tz.TZDateTime.now(tz.local);
    var day = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (readToday || !day.isAfter(now)) day = day.add(const Duration(days: 1));
    for (var i = 0; i < 3; i++) {
      final at = day.add(Duration(days: i));
      await _plugin.zonedSchedule(
        id: _id + i,
        title: 'DuckLearn',
        body: _bodies[(at.day + i) % _bodies.length],
        scheduledDate: at,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reading',
            'Daily reading reminder',
            channelDescription:
                'At most one a day, only on days you have not read yet.',
            importance: Importance.defaultImportance,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> cancel() async {
    if (!supported) return;
    await _init();
    for (var i = 0; i < 3; i++) {
      await _plugin.cancel(id: _id + i);
    }
  }
}
