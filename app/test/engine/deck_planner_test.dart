import 'dart:math';

import 'package:duk/engine/deck_planner.dart';
import 'package:duk/engine/item_state.dart';
import 'package:duk/engine/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final memory = Memory();
  final t0 = DateTime.utc(2026, 11, 1);
  final now = DateTime.utc(2026, 11, 15, 12);
  final order = [for (var i = 0; i < 40; i++) 'c$i'];

  // c0 missed long ago (weak), c1 got right long ago, c2 got right a minute ago
  final states = <String, ItemState>{
    'c0': memory.review(const ItemState(itemId: 'c0'), Grade.again, t0),
    'c1': memory.review(const ItemState(itemId: 'c1'), Grade.good, t0),
    'c2': memory.review(
      const ItemState(itemId: 'c2'),
      Grade.good,
      now.subtract(const Duration(minutes: 1)),
    ),
  };
  ItemState stateOf(String id) => states[id] ?? ItemState(itemId: id);
  double recall(ItemState s) => memory.retrievability(s, now);

  List<String> pick({int seed = 1, int total = 6, int maxNew = 3}) => pickCards(
    deckOrder: order,
    stateOf: stateOf,
    recall: recall,
    now: now,
    random: Random(seed),
    total: total,
    maxNew: maxNew,
  );

  test('mixes new cards with weak ones, skipping the set just seen', () {
    final p = pick();
    expect(p, hasLength(6));
    expect(p, containsAll(['c0', 'c1']));
    expect(p, isNot(contains('c2')));
    final newOnes = p.where((id) => stateOf(id).isNew).toList();
    expect(newOnes.length, greaterThanOrEqualTo(3));
    // new cards come from near the front of the deck
    for (final id in newOnes) {
      expect(order.indexOf(id), lessThan(3 + 6 + 3));
    }
  });

  test('different visits give different sets', () {
    final sets = {for (var s = 0; s < 6; s++) (pick(seed: s)..sort()).join()};
    expect(sets.length, greaterThan(1));
  });

  test('a finished deck still gives a set, just-seen cards last', () {
    final small = ['c0', 'c1', 'c2'];
    final p = pickCards(
      deckOrder: small,
      stateOf: stateOf,
      recall: recall,
      now: now,
      random: Random(1),
    );
    expect(p.toSet(), small.toSet());
  });

  test('progress counts learned and due', () {
    final p = deckProgress(order, stateOf, now);
    expect(p.learned, 3);
    expect(p.due, 2); // c0 (missed) and c1 (two weeks old)
  });
}
