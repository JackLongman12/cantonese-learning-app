/// How much everyday Cantonese the learner can read: the share of all characters in a
/// corpus of everyday Hong Kong Cantonese (HKCanCor, recorded conversations; built into
/// content.db as `char_freq` by the pipeline) that are characters they have learned.
/// The most common characters carry most text, so this rises fast at first.
library;

import 'item_state.dart';

/// [share]: character -> its share of all characters in the corpus (sums to about 1).
/// [learned]: characters the learner can read.
double everydayCoverage(Map<String, double> share, Iterable<String> learned) {
  var sum = 0.0;
  for (final ch in learned.toSet()) {
    sum += share[ch] ?? 0;
  }
  return sum.clamp(0.0, 1.0);
}

/// The character in an item id (`cr:yue:行:hang4` -> 行); null for other items.
String? charOfItem(String itemId) {
  final parts = itemId.split(':');
  return parts.length == 4 && parts[0] == 'cr' ? parts[2] : null;
}

/// The not-yet-learned characters that would add the most coverage, most useful first.
List<String> mostUsefulNext(
  Map<String, double> share,
  Set<String> learned, {
  int count = 5,
}) {
  final rest = share.entries.where((e) => !learned.contains(e.key)).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in rest.take(count)) e.key];
}

/// Characters the learner can read: met, then read again without help (the same
/// "learned" as the home and Progress screens).
Set<String> learnedChars(Iterable<ItemState> states) => {
  for (final s in states)
    if (s.reps >= 2 && (s.stability ?? 0) >= 1) ?charOfItem(s.itemId),
};
