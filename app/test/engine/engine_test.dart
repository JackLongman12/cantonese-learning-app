import 'dart:io';
import 'dart:math';

import 'package:duk/engine/item_state.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/engine/planner.dart';
import 'package:duk/engine/scaffold.dart';
import 'package:duk/engine/signals.dart';
import 'package:duk/events/event.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 11, 15, 9);

Event review(
  String id,
  String item,
  String grade,
  DateTime at, {
  String device = 'a',
}) => Event(
  id: id,
  tsUtc: at,
  tzOffsetMin: 480,
  monoMs: 0,
  deviceId: device,
  deviceKind: 'android',
  sessionId: 's',
  appVersion: '0.1.0',
  contentVersion: 'c',
  type: 'review.applied',
  payload: {'item_id': item, 'grade': grade},
);

/// Good reviews, each taken when the item falls due, until it is in long-term review.
List<Event> wellLearned(String item, {int reviews = 8}) {
  final memory = Memory();
  var s = ItemState(itemId: item);
  var at = t0;
  final out = <Event>[];
  for (var i = 0; i < reviews; i++) {
    out.add(review('$item-$i', item, 'good', at));
    s = memory.review(s, Grade.good, at);
    at = s.due!;
  }
  return out;
}

void main() {
  final memory = Memory();
  const policy = ScaffoldPolicy();

  group('memory', () {
    test('recall probability starts high after a review and decays', () {
      var s = memory.review(const ItemState(itemId: 'x'), Grade.good, t0);
      s = memory.review(s, Grade.good, s.due!);
      s = memory.review(s, Grade.good, s.due!);
      expect(s.phase, Phase.review);
      final soon = memory.retrievability(
        s,
        s.lastReview!.add(const Duration(hours: 1)),
      );
      final later = memory.retrievability(
        s,
        s.lastReview!.add(const Duration(days: 60)),
      );
      expect(soon, greaterThan(0.95));
      expect(later, lessThan(soon));
      expect(memory.retrievability(const ItemState(itemId: 'new'), t0), 0);
    });

    test('a lapse shortens stability and is counted', () {
      final good = LearnerModel.replay(wellLearned('x'), memory).stateOf('x');
      final lapsed = memory.review(good, Grade.again, good.due!);
      expect(lapsed.stability!, lessThan(good.stability!));
      expect(lapsed.lapses, 1);
      expect(lapsed.phase, Phase.relearning);
    });

    test('is deterministic', () {
      final a = LearnerModel.replay(wellLearned('x'), Memory()).stateOf('x');
      final b = LearnerModel.replay(wellLearned('x'), Memory()).stateOf('x');
      expect(a, b);
    });
  });

  group('scaffold', () {
    test('fades from full to none as the item is established', () {
      final levels = <ScaffoldLevel>[];
      var s = const ItemState(itemId: 'x');
      var at = t0;
      for (var i = 0; i < 10; i++) {
        levels.add(policy.levelFor(s, memory, at));
        s = memory.review(s, Grade.good, at);
        at = s.due!;
      }
      expect(levels.first, ScaffoldLevel.full);
      expect(levels, contains(ScaffoldLevel.hint));
      expect(levels, contains(ScaffoldLevel.tap));
      // Never moves back towards more help while every review succeeds.
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i].index, greaterThanOrEqualTo(levels[i - 1].index));
      }
      // Right after a successful review of a long-established item nothing is shown.
      expect(s.stability!, greaterThan(21));
      expect(
        policy.levelFor(s, memory, s.lastReview!.add(const Duration(hours: 1))),
        ScaffoldLevel.none,
      );
    });

    test('a lapse brings help back', () {
      final s = LearnerModel.replay(wellLearned('x'), memory).stateOf('x');
      final lapsed = memory.review(s, Grade.again, s.due!);
      expect(
        policy.levelFor(lapsed, memory, lapsed.lastReview!),
        ScaffoldLevel.hint,
      );
    });

    test('a decayed item stays hidden so it gets tested', () {
      final s = LearnerModel.replay(
        wellLearned('x', reviews: 4),
        memory,
      ).stateOf('x');
      final muchLater = s.due!.add(const Duration(days: 400));
      expect(memory.retrievability(s, muchLater), lessThan(0.7));
      expect(policy.levelFor(s, memory, muchLater), ScaffoldLevel.tap);
    });

    test('shift overrides in both directions and clamps', () {
      const fresh = ItemState(itemId: 'x');
      expect(
        const ScaffoldPolicy(shift: -1).levelFor(fresh, memory, t0),
        ScaffoldLevel.hint,
      );
      expect(
        const ScaffoldPolicy(shift: 5).levelFor(fresh, memory, t0),
        ScaffoldLevel.full,
      );
    });
  });

  group('signals', () {
    const signals = SignalPolicy();
    final shown = {
      'intro': ScaffoldLevel.full,
      'revealed': ScaffoldLevel.tap,
      'read': ScaffoldLevel.tap,
      'mastered': ScaffoldLevel.none,
    };

    test('grades each item from what happened', () {
      final out = {
        for (final o in signals.outcomes(
          shown: shown,
          revealed: {'revealed'},
          activeMs: 4000,
        ))
          o.itemId: o,
      };
      expect(out['intro']!.signal, Signal.introduced);
      expect(out['revealed']!.grade, Grade.again);
      expect(out['read']!.grade, Grade.good);
      expect(out['mastered']!.grade, Grade.good);
    });

    test('a skipped sentence teaches nothing', () {
      expect(
        signals.outcomes(shown: shown, revealed: {}, activeMs: 200),
        isEmpty,
      );
    });

    test('a laboured read is hard, not good', () {
      final out = signals.outcomes(shown: shown, revealed: {}, activeMs: 60000);
      expect(out.firstWhere((o) => o.itemId == 'read').grade, Grade.hard);
      expect(out.firstWhere((o) => o.itemId == 'intro').grade, Grade.good);
    });
  });

  group('replay', () {
    final events = [
      ...wellLearned('a'),
      ...wellLearned('b', reviews: 3),
      review('z1', 'a', 'again', DateTime.utc(2027, 6, 1)),
    ];

    test('order and duplicates do not change the result', () {
      final forward = LearnerModel.replay(events, memory).snapshot();
      final shuffled = [...events.reversed, ...events.take(5)];
      expect(LearnerModel.replay(shuffled, memory).snapshot(), forward);
    });

    test('incremental apply in time order equals replay', () {
      final live = LearnerModel(memory);
      final inOrder = [...events]..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));
      inOrder.forEach(live.apply);
      expect(live.needsReplay, isFalse);
      expect(live.snapshot(), LearnerModel.replay(events, memory).snapshot());
    });

    test('an older event arriving late asks for a rebuild', () {
      final live = LearnerModel(memory);
      events.forEach(live.apply); // the 2027 lapse arrives after later reviews
      expect(live.needsReplay, isTrue);
    });

    test('unknown and malformed events are ignored', () {
      final odd = [
        ...events,
        review('q1', 'a', 'brilliant', DateTime.utc(2027, 7, 1)),
        Event.fromJson({
          'id': 'q2',
          'ts_utc': '2027-07-02T00:00:00Z',
          'type': 'from.the.future',
          'payload': {'anything': 1},
          'extra_field': true,
        }),
      ];
      expect(
        LearnerModel.replay(odd, memory).snapshot(),
        LearnerModel.replay(events, memory).snapshot(),
      );
    });
  });

  group('event log', () {
    test('JSONL round trip, per-device files, corrupt line skipped', () {
      final dir = Directory.systemTemp.createTempSync('duk_events');
      addTearDown(() => dir.deleteSync(recursive: true));
      var now = DateTime.utc(2026, 11, 30, 23, 59);
      var n = 0;
      final logger = EventLogger(
        store: JsonlEventStore(dir, 'phone'),
        deviceId: 'phone',
        deviceKind: 'android',
        appVersion: '0.1.0',
        contentVersion: 'c1',
        clock: () => now,
        newId: () => 'id${n++}',
      );
      logger.log('review.applied', {
        'item_id': 'cr:yue:行:hong4',
        'grade': 'good',
      });
      now = now.add(const Duration(minutes: 2)); // crosses into December
      logger.log('review.applied', {
        'item_id': 'cr:yue:行:hong4',
        'grade': 'good',
      });
      File('${dir.path}/phone/2026-12.jsonl')
          .writeAsStringSync('{"id": "cut off', mode: FileMode.append);
      // a second device's file, as sync would deliver it
      JsonlEventStore(
        dir,
        'pc',
      ).append(review('pc1', 'cr:yue:門:mun4', 'good', now, device: 'pc'));

      expect(File('${dir.path}/phone/2026-11.jsonl').existsSync(), isTrue);
      final all = JsonlEventStore(dir, 'phone').readAll().toList();
      expect(all, hasLength(3));
      expect(
        all.where((e) => e.deviceId == 'phone').first.payload['item_id'],
        'cr:yue:行:hong4',
      );
      final model = LearnerModel.replay(all, memory);
      expect(model.stateOf('cr:yue:行:hong4').reps, 2);
      expect(model.stateOf('cr:yue:門:mun4').reps, 1);
    });

    test('idle time is excluded from active time', () {
      var now = t0;
      final logger = EventLogger(
        store: MemoryEventStore(),
        deviceId: 'd',
        deviceKind: 'windows',
        appVersion: '0',
        contentVersion: 'c',
        clock: () => now,
      );
      final mark = logger.mark();
      logger.touch();
      now = now.add(const Duration(seconds: 5));
      logger.touch();
      now = now.add(const Duration(minutes: 10)); // walked away
      logger.touch();
      now = now.add(const Duration(seconds: 3));
      logger.touch();
      expect(logger.activeMsSince(mark), 8000);
    });
  });

  group('planner', () {
    const planner = Planner();
    Candidate c(
      String id,
      List<String> items, {
      String region = 'macau',
      String? pattern,
    }) => Candidate(
      id: id,
      itemIds: items.toSet(),
      region: region,
      pattern: pattern,
    );

    test('prefers the sentence that covers more due items', () {
      final events = [
        for (final item in ['a', 'b', 'c']) review('e$item', item, 'good', t0),
      ];
      final learner = LearnerModel.replay(events, memory);
      final now = t0.add(const Duration(days: 30));
      final picks = planner.plan(
        candidates: [
          c('one', ['a']),
          c('three', ['a', 'b', 'c']),
        ],
        learner: learner,
        now: now,
        count: 2,
      );
      expect(picks.first.candidate.id, 'three');
      // 'one' has nothing left to offer once 'three' covered item a.
      expect(picks, hasLength(1));
      expect(picks.first.reasons.join(' '), contains('3 due'));
    });

    test('limits new items per session and avoids overloaded sentences', () {
      final learner = LearnerModel(memory);
      final picks = planner.plan(
        candidates: [
          c('heavy', ['n1', 'n2', 'n3', 'n4', 'n5', 'n6']),
          c('light1', ['n1', 'n2']),
          c('light2', ['n3']),
          c('light3', ['n7', 'n8']),
        ],
        learner: learner,
        now: t0,
        count: 4,
        maxNew: 3,
      );
      final ids = picks.map((p) => p.candidate.id).toList();
      expect(ids, isNot(contains('heavy')));
      final introduced = picks.expand((p) => p.candidate.itemIds).toSet();
      expect(introduced.length, lessThanOrEqualTo(3));
    });

    test('prefers Macau content and spreads out variations of one pattern', () {
      final learner = LearnerModel(memory);
      final picks = planner.plan(
        candidates: [
          c('gen', ['x1'], region: 'general'),
          c('mo-a', ['x2'], pattern: 'where-is'),
          c('mo-b', ['x3'], pattern: 'where-is'),
          c('hk', ['x4'], region: 'hk'),
        ],
        learner: learner,
        now: t0,
        count: 4,
      );
      final ids = picks.map((p) => p.candidate.id).toList();
      expect(ids.first, startsWith('mo-'));
      // the second variation is pushed behind unrelated sentences
      expect(ids.last, startsWith('mo-'));
    });

    test('jitter varies sentences that teach the same thing', () {
      final learner = LearnerModel(memory);
      final cands = [
        for (var i = 0; i < 8; i++) c('s$i', ['n$i']),
      ];
      final firsts = {
        for (var seed = 0; seed < 8; seed++)
          planner
              .plan(
                candidates: cands,
                learner: learner,
                now: t0,
                count: 3,
                random: Random(seed),
                jitter: 0.5,
              )
              .first
              .candidate
              .id,
      };
      expect(firsts.length, greaterThan(1));
    });

    test('jitter never beats a due item; recent sentences go behind', () {
      final learner = LearnerModel.replay([
        review('ea', 'a', 'good', t0),
      ], memory);
      final now = t0.add(const Duration(days: 30));
      for (var seed = 0; seed < 10; seed++) {
        final picks = planner.plan(
          candidates: [
            c('new', ['n1'], region: 'general'),
            c('due-old', ['a']),
            c('due-recent', ['a']),
          ],
          learner: learner,
          now: now,
          count: 1,
          recentlySeen: {'due-recent'},
          random: Random(seed),
          jitter: 0.5,
        );
        expect(picks.single.candidate.id, 'due-old');
      }
    });
  });
}
