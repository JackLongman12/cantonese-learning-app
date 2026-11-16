import 'package:duk/engine/coverage.dart';
import 'package:duk/engine/experiments.dart';
import 'package:duk/events/event.dart';
import 'package:duk/events/telemetry_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('experiments', () {
    test('an install always gets the same arm', () {
      for (final e in experiments) {
        expect(armFor('install-a', e), armFor('install-a', e));
        expect(e.arms, contains(armFor('install-a', e)));
      }
    });

    test('installs spread across the arms', () {
      for (final e in experiments) {
        final counts = <String, int>{};
        for (var i = 0; i < 2000; i++) {
          final a = armFor('install-$i', e);
          counts[a] = (counts[a] ?? 0) + 1;
        }
        for (final arm in e.arms) {
          // roughly even: each arm within 10 points of its fair share
          expect(counts[arm]! / 2000, closeTo(1 / e.arms.length, 0.1));
        }
      }
    });

    test('experiment ids are unique', () {
      final ids = [for (final e in experiments) e.id];
      expect(ids.toSet().length, ids.length);
    });
  });

  group('coverage', () {
    const share = {'的': 0.05, '我': 0.04, '係': 0.03, '銀': 0.001};

    test('sums the shares of learned characters, once each', () {
      expect(everydayCoverage(share, ['我', '我', '係']), closeTo(0.07, 1e-9));
      expect(everydayCoverage(share, ['未見過']), 0);
    });

    test('item ids name their character', () {
      expect(charOfItem('cr:yue:行:hang4'), '行');
      expect(charOfItem('card:mtr:中環'), isNull);
    });

    test('common characters are worth more to the planner', () {
      expect(frequencyValue(0.05), closeTo(1.5, 0.01));
      expect(frequencyValue(0.001), greaterThan(frequencyValue(0.00001)));
      expect(frequencyValue(null), 0.5);
      expect(itemValues(['cr:yue:的:dik1'], share), {
        'cr:yue:的:dik1': closeTo(1.5, 0.01),
      });
    });

    test('suggests the most common characters not learned yet', () {
      expect(mostUsefulNext(share, {'的'}, count: 2), ['我', '係']);
    });
  });

  group('telemetry filter', () {
    Event ev(String type, Map<String, Object?> payload) => Event(
      id: 'e1',
      tsUtc: DateTime.utc(2026, 11, 17),
      tzOffsetMin: 480,
      monoMs: 0,
      deviceId: 'device-secret',
      deviceKind: 'android',
      sessionId: 's1',
      appVersion: 'b2070',
      contentVersion: 'c1',
      type: type,
      payload: payload,
    );

    test('replaces the device id and keeps lesson data', () {
      final out = shareable(
        ev('review.applied', {'item_id': 'cr:yue:我:ngo5', 'grade': 'good'}),
        'tid',
      )!;
      expect(out['install_id'], 'tid');
      expect(out.containsKey('device_id'), isFalse);
      expect(out.toString(), isNot(contains('device-secret')));
      expect((out['payload'] as Map)['item_id'], 'cr:yue:我:ngo5');
    });

    test('drops anything the learner typed, pasted or said', () {
      final saved = shareable(
        ev('word.save', {'text': '我老婆個名', 'en': 'x', 'lang': 'yue'}),
        'tid',
      )!;
      expect(saved['payload'], {'lang': 'yue'});
      final spoken = shareable(
        ev('speech.attempt', {
          'score': 0.8,
          'per_token': ['...'],
        }),
        'tid',
      )!;
      expect(spoken['payload'], {'score': 0.8});
      final pasted = shareable(
        ev('reader.lookup', {'item_id': 'cr:yue:秘:bei3', 'level': 'tap'}),
        'tid',
      )!;
      expect(pasted['payload'], {'level': 'tap'});
      final lesson = shareable(
        ev('reader.lookup', {'char': '銀', 'in_sentence': 'sent-1'}),
        'tid',
      )!;
      expect(lesson['payload'], {'char': '銀', 'in_sentence': 'sent-1'});
    });

    test('crash text is scrubbed of what the learner typed', () {
      expect(
        redactCrashText('FormatException: 我老婆電話 98765432 a@b.com line 12'),
        'FormatException: [zh] [number] [email] line 12',
      );
    });

    test('unlisted event types never leave the device', () {
      expect(shareable(ev('idle.end', {}), 'tid'), isNull);
      // newcomer practice: content ids only, shared as they are
      final tone = shareable(
        ev('tone.answer', {'set': 'tones-si', 'played': '詩', 'correct': true}),
        'tid',
      )!;
      expect(tone['payload'], {'set': 'tones-si', 'played': '詩', 'correct': true});
      expect(shareable(ev('challenge.done', {'id': 'ch-noice'}), 'tid'), isNotNull);
      expect(shareable(ev('update.apply', {}), 'tid'), isNull);
    });
  });
}
