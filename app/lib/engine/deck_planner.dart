/// Which flashcards to show: cards that are due first (most overdue first), then new
/// cards in deck order (most important names first). Each card is its own memory item
/// (its id), scheduled by the same FSRS model as characters.
library;

import 'item_state.dart';

List<String> pickCards({
  required List<String> deckOrder,
  required ItemState Function(String id) stateOf,
  required DateTime now,
  int total = 15,
  int maxNew = 8,
}) {
  final due = <(String, DateTime)>[];
  final fresh = <String>[];
  for (final id in deckOrder) {
    final s = stateOf(id);
    if (s.isNew) {
      fresh.add(id);
    } else if (s.due != null && !s.due!.isAfter(now)) {
      due.add((id, s.due!));
    }
  }
  due.sort((a, b) => a.$2.compareTo(b.$2));
  final out = [for (final d in due.take(total)) d.$1];
  final room = total - out.length;
  out.addAll(fresh.take(room < maxNew ? room : maxNew));
  return out;
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
