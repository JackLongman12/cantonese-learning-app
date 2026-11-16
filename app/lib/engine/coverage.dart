/// How much everyday Cantonese the learner can read: the share of all characters in a
/// corpus of everyday Hong Kong Cantonese (HKCanCor, recorded conversations; built into
/// content.db as `char_freq` by the pipeline) that are characters they have learned.
/// The most common characters carry most text, so this rises fast at first.
library;

import 'dart:math' as math;

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

/// How much learning a new character is worth to the planner (its `itemValue`): from
/// 0.5 (not in everyday speech) to 1.5 (the most common characters), on a log scale of
/// its share, so 係 唔 我 come before rare characters (owner, 2026-11-17). The range is
/// kept near 1 so the planner's overload penalty still keeps sentences light.
double frequencyValue(double? share) {
  if (share == null || share <= 0) return 0.5;
  final x = (math.log(share) / math.ln10 + 6) / 4.7;
  return (0.5 + x).clamp(0.5, 1.5);
}

/// [frequencyValue] for each item id.
Map<String, double> itemValues(
  Iterable<String> itemIds,
  Map<String, double> share,
) => {for (final id in itemIds) id: frequencyValue(share[charOfItem(id)])};
