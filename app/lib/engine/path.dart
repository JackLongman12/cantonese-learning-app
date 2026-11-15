/// The beginner path and reading levels.
///
/// Path: topics ordered from easiest to hardest, where a topic is easier when its
/// characters are the common ones (they appear in many sentences across all content),
/// so a beginner meets the most useful characters first. "Up next" is the first topic
/// on the path whose characters you have not mostly met.
///
/// Levels: milestones of characters you can read reliably. They only describe where
/// you are; nothing is locked and nothing is lost.
library;

/// Topic ids, easiest first. [itemsByTopic]: character items per topic;
/// [frequency]: in how many sentences each item appears.
List<String> orderTopics(
  Map<String, Set<String>> itemsByTopic,
  Map<String, int> frequency,
) {
  double ease(Set<String> items) {
    if (items.isEmpty) return 0;
    // share of the topic's characters that are common (in 20+ sentences)
    final common = items.where((i) => (frequency[i] ?? 0) >= 20).length;
    return common / items.length;
  }

  final ids = itemsByTopic.keys.toList()
    ..sort((a, b) {
      final c = ease(itemsByTopic[b]!).compareTo(ease(itemsByTopic[a]!));
      return c != 0 ? c : a.compareTo(b);
    });
  return ids;
}

/// The first topic on the path whose characters are less than [enough] met.
String? upNext(
  List<String> path,
  Map<String, Set<String>> itemsByTopic,
  bool Function(String item) met, {
  double enough = 0.7,
}) {
  for (final id in path) {
    final items = itemsByTopic[id] ?? const {};
    if (items.isEmpty) continue;
    if (items.where(met).length / items.length < enough) return id;
  }
  return null;
}

/// Characters known well needed to reach each level (level 1 starts at 0).
const levelThresholds = [0, 25, 75, 150, 300, 500, 800, 1200, 1700, 2300];

({int level, int have, int need}) readingLevel(int knownWell) {
  var level = 1;
  for (var i = 0; i < levelThresholds.length; i++) {
    if (knownWell >= levelThresholds[i]) level = i + 1;
  }
  final next = level < levelThresholds.length ? levelThresholds[level] : null;
  return (
    level: level,
    have: knownWell - levelThresholds[level - 1],
    need: next == null ? 0 : next - levelThresholds[level - 1],
  );
}
