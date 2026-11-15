import 'package:duk/engine/item_state.dart';
import 'package:duk/engine/weak_spots.dart';
import 'package:duk/events/event.dart';
import 'package:flutter_test/flutter_test.dart';

var _n = 0;
Event ev(String type, Map<String, Object?> p, DateTime utc) => Event(
  id: 'e${_n++}',
  tsUtc: utc,
  tzOffsetMin: 480,
  monoMs: 0,
  deviceId: 'd',
  deviceKind: 'android',
  sessionId: 's',
  appVersion: 't',
  contentVersion: 'c',
  type: type,
  payload: p,
);

void main() {
  final t = DateTime.utc(2026, 11, 16, 2);

  test('splits Jyutping into start, ending and tone', () {
    expect(splitJyutping('nei5'), (initial: 'n', rhyme: 'ei', tone: '5'));
    expect(splitJyutping('gwong2'), (initial: 'gw', rhyme: 'ong', tone: '2'));
    expect(splitJyutping('ngo5'), (initial: 'ng', rhyme: 'o', tone: '5'));
    expect(splitJyutping('m4'), (initial: '', rhyme: 'm', tone: '4'));
    expect(splitJyutping('aa3'), (initial: '', rhyme: 'aa', tone: '3'));
  });

  test('finds the sounds you mix up most', () {
    final attempt = {
      'per_token': [
        {'expected': 'nei5', 'heard': 'lei5', 'v': 'wrong'},
        {'expected': 'naam4', 'heard': 'laam4', 'v': 'wrong'},
        {'expected': 'si3', 'heard': 'si6', 'v': 'tone'},
        {'expected': 'gong2', 'heard': 'gong2', 'v': 'ok'},
      ],
    };
    final weak = weakSounds([
      ev('speech.attempt', attempt, t),
      ev('speech.attempt', attempt, t),
    ]);
    expect(weak.first.label, 'n → l');
    expect(weak.first.count, 4);
    expect(weak.map((m) => m.label), contains('tone 3 → 6'));
  });

  test('weak characters are the most lapsed', () {
    final states = [
      const ItemState(itemId: 'cr:yue:銀:ngan4', lapses: 3, reps: 5),
      const ItemState(itemId: 'cr:yue:行:hong4', lapses: 1, reps: 4),
      const ItemState(itemId: 'cr:yue:你:nei5', reps: 6),
    ];
    expect(weakCharacters(states, 'yue').map((s) => s.itemId), [
      'cr:yue:銀:ngan4',
      'cr:yue:行:hong4',
    ]);
  });

  test('week activity counts days and sentences', () {
    final now = DateTime(2026, 11, 16, 20);
    final w = weekActivity([
      ev('item.done', {'active_ms': 60000}, DateTime.utc(2026, 11, 16, 2)),
      ev('item.done', {'active_ms': 60000}, DateTime.utc(2026, 11, 14, 2)),
      ev('item.done', {'skipped': true}, DateTime.utc(2026, 11, 13, 2)),
      ev('item.done', {
        'active_ms': 60000,
      }, DateTime.utc(2026, 11, 1, 2)), // too old
    ], now);
    expect(w.days, [false, false, false, false, true, false, true]);
    expect(w.sentences, 2);
    expect(w.minutes, 2);
  });
}
