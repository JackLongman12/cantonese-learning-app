/// Chooses what to read next (docs/DESIGN.md section 2.4): sentences that cover the most
/// due items, introduce at most a couple of new ones, and are otherwise readable.
library;

import 'item_state.dart';
import 'learner_model.dart';

class Candidate {
  const Candidate({
    required this.id,
    required this.itemIds,
    this.region = 'general',
    this.pattern,
    this.itemValue = const {},
  });

  final String id;

  /// Character-reading items in the sentence (duplicates removed).
  final Set<String> itemIds;
  final String region;

  /// Sentences sharing a pattern are variations of one frame; the planner spreads them out.
  final String? pattern;

  /// Per-item unlock value (frequency, family size). Missing items count as 1.
  final Map<String, double> itemValue;
}

class PlannerWeights {
  const PlannerWeights({
    this.due = 1.0,
    this.newItem = 0.6,
    this.relevance = 0.5,
    this.overload = 1.5,
    this.repeat = 2.0,
    this.maxNewPerSentence = 2,
    this.regionRelevance = const {
      'macau': 1.0,
      'both': 0.8,
      'hk': 0.6,
      'general': 0.4,
    },
  });

  final double due;
  final double newItem;
  final double relevance;
  final double overload;
  final double repeat;
  final int maxNewPerSentence;
  final Map<String, double> regionRelevance;
}

class Pick {
  const Pick(this.candidate, this.score, this.reasons);
  final Candidate candidate;
  final double score;

  /// Human-readable breakdown for the "why this?" debug overlay.
  final List<String> reasons;
}

class Planner {
  const Planner({this.weights = const PlannerWeights()});

  final PlannerWeights weights;

  /// Greedy selection, re-scored after every pick so one sentence's due items are not
  /// counted again for the next. [maxNew] caps new items for the whole session.
  List<Pick> plan({
    required List<Candidate> candidates,
    required LearnerModel learner,
    required DateTime now,
    required int count,
    int maxNew = 10,
    Set<String> recentlySeen = const {},
  }) {
    final remaining = [...candidates];
    final covered = <String>{};
    final usedPatterns = <String>{};
    final picks = <Pick>[];
    var newBudget = maxNew;

    while (picks.length < count && remaining.isNotEmpty) {
      Pick? best;
      for (final c in remaining) {
        final p = _score(
          c,
          learner,
          now,
          covered,
          usedPatterns,
          recentlySeen,
          newBudget,
        );
        if (p != null && (best == null || p.score > best.score)) best = p;
      }
      if (best == null) break;
      picks.add(best);
      remaining.remove(best.candidate);
      for (final id in best.candidate.itemIds) {
        if (covered.add(id) && learner.stateOf(id).isNew) newBudget--;
      }
      final pattern = best.candidate.pattern;
      if (pattern != null) usedPatterns.add(pattern);
    }
    return picks;
  }

  Pick? _score(
    Candidate c,
    LearnerModel learner,
    DateTime now,
    Set<String> covered,
    Set<String> usedPatterns,
    Set<String> recentlySeen,
    int newBudget,
  ) {
    var dueScore = 0.0;
    var dueCount = 0;
    final newItems = <String>[];
    for (final id in c.itemIds) {
      if (covered.contains(id)) continue;
      final s = learner.stateOf(id);
      if (s.isNew) {
        newItems.add(id);
      } else if (_isDue(s, now)) {
        dueCount++;
        // Lower recall probability means more urgent.
        dueScore += 1 + (1 - learner.memory.retrievability(s, now));
      }
    }
    if (dueCount == 0 && newItems.isEmpty) return null; // nothing to gain
    if (newItems.length > newBudget) return null;

    newItems.sort(
      (a, b) => (c.itemValue[b] ?? 1).compareTo(c.itemValue[a] ?? 1),
    );
    final counted = newItems.take(weights.maxNewPerSentence).toList();
    final newScore = counted.fold(
      0.0,
      (sum, id) => sum + (c.itemValue[id] ?? 1),
    );
    final overload = newItems.length - counted.length;
    final relevance = weights.regionRelevance[c.region] ?? 0.4;
    final repeated =
        recentlySeen.contains(c.id) ||
        (c.pattern != null && usedPatterns.contains(c.pattern));

    final score =
        weights.due * dueScore +
        weights.newItem * newScore +
        weights.relevance * relevance -
        weights.overload * overload -
        (repeated ? weights.repeat : 0);
    return Pick(c, score, [
      if (dueCount > 0)
        '$dueCount due (+${(weights.due * dueScore).toStringAsFixed(2)})',
      if (newItems.isNotEmpty)
        '${newItems.length} new (+${(weights.newItem * newScore).toStringAsFixed(2)})',
      '${c.region} (+${(weights.relevance * relevance).toStringAsFixed(2)})',
      if (overload > 0)
        '$overload too many new (-${(weights.overload * overload).toStringAsFixed(2)})',
      if (repeated) 'seen recently (-${weights.repeat.toStringAsFixed(2)})',
    ]);
  }

  bool _isDue(ItemState s, DateTime now) =>
      s.due != null && !s.due!.isAfter(now);
}
