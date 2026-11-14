import 'package:duk/engine/insights.dart';
import 'package:duk/events/event.dart';
import 'package:flutter_test/flutter_test.dart';

Event start(DateTime utc, {int tz = 480}) => Event(
  id: utc.toIso8601String(),
  tsUtc: utc,
  tzOffsetMin: tz,
  monoMs: 0,
  deviceId: 'd',
  deviceKind: 'android',
  sessionId: 's',
  appVersion: 't',
  contentVersion: 'c',
  type: 'session.start',
);

void main() {
  final now = DateTime.utc(2026, 11, 20);
  test('usual study time comes from local session starts', () {
    // 21:10, 21:40, 21:20 Macau time (UTC+8) and one morning outlier
    final events = [
      start(DateTime.utc(2026, 11, 10, 13, 10)),
      start(DateTime.utc(2026, 11, 11, 13, 40)),
      start(DateTime.utc(2026, 11, 12, 13, 20)),
      start(DateTime.utc(2026, 11, 13, 0, 5)),
    ];
    expect(usualStudyMinute(events, now: now), 21 * 60 + 15);
  });

  test('not enough history, or too old', () {
    expect(
      usualStudyMinute([start(DateTime.utc(2026, 11, 10, 13))], now: now),
      isNull,
    );
    final old = [
      for (var d = 1; d <= 5; d++) start(DateTime.utc(2026, 8, d, 13)),
    ];
    expect(usualStudyMinute(old, now: now), isNull);
  });
}
