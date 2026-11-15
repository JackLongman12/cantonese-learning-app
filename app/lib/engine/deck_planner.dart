/// Which flashcards to show. Every visit is a fresh, shuffled set:
///
/// * new cards: up to [maxNew], picked at random from the next few unseen cards in deck
///   order (the most important names come first, but not always the same ones);
/// * weak cards: cards you have seen, weakest first (lowest chance of recall, so overdue
///   and missed cards lead), filling the rest of the set;
/// * cards seen in the last [recent] (e.g. the set you just finished) are left out, and
///   only come back when there is nothing else to show.
///
/// Each card is its own memory item (its id), scheduled by the same FSRS model as
/// characters. There is always a set while the deck has cards: no "nothing due".
library;

import 'dart:math';

import 'item_state.dart';

List<String> pickCards({
  required List<String> deckOrder,
  required ItemState Function(String id) stateOf,
  required double Function(ItemState s) recall,
  required DateTime now,
  Random? random,
  int total = 15,
  int maxNew = 8,
  Duration recent = const Duration(minutes: 30),
}) {
  final rng = random ?? Random();
  final fresh = <String>[];
  final seen = <(String, double)>[];
  final justSeen = <(String, double)>[];
  for (final id in deckOrder) {
    final s = stateOf(id);
    if (s.isNew) {
      fresh.add(id);
      continue;
    }
    final last = s.lastReview;
    final r = recall(s);
    (last != null && now.difference(last) < recent ? justSeen : seen).add((
      id,
      r,
    ));
  }
  int weakestFirst((String, double) a, (String, double) b) =>
      a.$2.compareTo(b.$2);
  seen.sort(weakestFirst);
  justSeen.sort(weakestFirst);

  // new cards: a random handful from the next unseen ones
  final pool = fresh.take(maxNew * 2).toList()..shuffle(rng);
  final newCount = min(maxNew, pool.length);
  final out = <String>[...pool.take(newCount)];
  // weak cards fill the rest
  out.addAll(seen.take(total - out.length).map((e) => e.$1));
  // too few weak cards: more new ones
  if (out.length < total) {
    final more = [...pool.skip(newCount), ...fresh.skip(maxNew * 2)];
    out.addAll(more.take(total - out.length));
  }
  // still room (small or finished deck): cards from the last set, weakest first
  if (out.length < total) {
    out.addAll(justSeen.take(total - out.length).map((e) => e.$1));
  }
  return out..shuffle(rng);
}

/// (learned, due) for a deck: learned = seen at least once.
({int learned, int due}) deckProgress(
  List<String> ids,
  ItemState Function(String id) stateOf,
  DateTime now,
) {
  var learned = 0, due = 0;
  for (final id in ids) {
    final s = stateOf(id);
    if (s.isNew) continue;
    learned++;
    if (s.due != null && !s.due!.isAfter(now)) due++;
  }
  return (learned: learned, due: due);
}
