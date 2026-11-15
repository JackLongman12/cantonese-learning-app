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

  test('the week is measured in progress, not days', () {
    final now = DateTime.utc(2026, 11, 16, 12);
    final w = weekProgress([
      ev('review.applied', {
        'item_id': 'cr:yue:銀:ngan4',
        'signal': 'introduced',
      }, DateTime.utc(2026, 11, 15)),
      ev('review.applied', {
        'item_id': 'cr:yue:銀:ngan4',
        'signal': 'introduced',
      }, DateTime.utc(2026, 11, 15)),
      ev('review.applied', {
        'item_id': 'cr:yue:行:hong4',
        'signal': 'noReveal',
      }, DateTime.utc(2026, 11, 15)),
      ev('item.done', {}, DateTime.utc(2026, 11, 14)),
      ev('item.done', {'skipped': true}, DateTime.utc(2026, 11, 14)),
      ev('item.done', {}, DateTime.utc(2026, 11, 1)), // older than a week
    ], now);
    expect(w.newChars, 1);
    expect(w.sentences, 1);
  });

  test('week accuracy for reading and speaking', () {
    final now = DateTime.utc(2026, 11, 16, 12);
    final a = weekAccuracy([
      ev('item.done', {'reveals': 0}, DateTime.utc(2026, 11, 15)),
      ev('item.done', {'reveals': 2}, DateTime.utc(2026, 11, 15)),
      ev('speech.attempt', {
        'per_token': [
          {'v': 'ok'},
          {'v': 'tone'},
          {'v': 'wrong'},
          {'v': 'ok'},
        ],
      }, DateTime.utc(2026, 11, 15)),
    ], now);
    expect(a.readingPct, 50);
    expect(a.speakingPct, 75);
    expect(weekAccuracy(const [], now).readingPct, isNull);
  });
}
