import 'package:duk/engine/adaptive.dart';
import 'package:duk/events/event.dart';
import 'package:flutter_test/flutter_test.dart';

var _n = 0;
Event ev(String type, String session, Map<String, Object?> p) => Event(
  id: 'e${_n++}',
  tsUtc: DateTime.utc(2026, 11, 15),
  tzOffsetMin: 480,
  monoMs: 0,
  deviceId: 'd',
  deviceKind: 'android',
  sessionId: session,
  appVersion: 't',
  contentVersion: 'c',
  type: type,
  payload: p,
);

List<Event> session(
  String id,
  int sentences, {
  int helped = 0,
  bool done = true,
}) => [
  ev('session.start', id, {}),
  for (var i = 0; i < sentences; i++)
    ev('item.done', id, {'reveals': i < helped ? 1 : 0}),
  if (done) ev('session.end', id, {'reason': 'done'}),
];

void main() {
  final now = DateTime.utc(2026, 11, 16);

  test('new learners start gently', () {
    final p = adaptSession(const [], now);
    expect(p.count, 8);
  });

  test('reading comfortably: bigger batches with more new', () {
    final p = adaptSession([
      ...session('a', 10),
      ...session('b', 10),
      ...session('c', 12),
    ], now);
    expect(p.count, greaterThan(10));
    expect(p.maxNew, greaterThan(6));
  });

  test('needing lots of help or leaving early: smaller, mostly review', () {
    final p = adaptSession([
      ...session('a', 10, helped: 6, done: false),
      ...session('b', 10, helped: 6, done: false),
      ...session('c', 10, helped: 5),
    ], now);
    expect(p.count, lessThan(10));
    expect(p.maxNew, lessThanOrEqualTo(2));
  });
}
