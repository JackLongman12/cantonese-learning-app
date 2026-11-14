import 'package:duk/engine/deck_planner.dart';
import 'package:duk/engine/item_state.dart';
import 'package:duk/engine/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final memory = Memory();
  final t0 = DateTime.utc(2026, 11, 1);
  final now = DateTime.utc(2026, 11, 15);
  final states = <String, ItemState>{
    'b': memory.review(const ItemState(itemId: 'b'), Grade.again, t0),
    'd': memory.review(const ItemState(itemId: 'd'), Grade.good, now),
  };
  ItemState stateOf(String id) => states[id] ?? ItemState(itemId: id);
  final order = ['a', 'b', 'c', 'd', 'e', 'f'];

  test('due cards first, then new cards in deck order', () {
    final picks = pickCards(
      deckOrder: order,
      stateOf: stateOf,
      now: now,
      total: 4,
      maxNew: 2,
    );
    expect(picks, ['b', 'a', 'c']);
  });

  test('progress counts learnt and due', () {
    final p = deckProgress(order, stateOf, now);
    expect(p.learnt, 2);
    expect(p.due, 1);
  });
}
