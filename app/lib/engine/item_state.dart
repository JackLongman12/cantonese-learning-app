/// Memory state of one item (see docs/DESIGN.md section 2.1). Pure data.
library;

enum Grade {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Grade(this.value);
  final int value;

  static Grade parse(String name) =>
      Grade.values.firstWhere((g) => g.name == name);
}

/// Mirrors the scheduler's phases: short-term steps, then long-term review.
enum Phase { learning, review, relearning }

class ItemState {
  const ItemState({
    required this.itemId,
    this.phase = Phase.learning,
    this.step,
    this.stability,
    this.difficulty,
    this.due,
    this.lastReview,
    this.reps = 0,
    this.lapses = 0,
  });

  final String itemId;
  final Phase phase;
  final int? step;

  /// Days until recall probability falls to 90%.
  final double? stability;
  final double? difficulty;
  final DateTime? due;
  final DateTime? lastReview;
  final int reps;
  final int lapses;

  bool get isNew => reps == 0;

  @override
  bool operator ==(Object other) =>
      other is ItemState &&
      other.itemId == itemId &&
      other.phase == phase &&
      other.step == step &&
      other.stability == stability &&
      other.difficulty == difficulty &&
      other.due == due &&
      other.lastReview == lastReview &&
      other.reps == reps &&
      other.lapses == lapses;

  @override
  int get hashCode => Object.hash(
    itemId,
    phase,
    step,
    stability,
    difficulty,
    due,
    lastReview,
    reps,
    lapses,
  );

  @override
  String toString() =>
      'ItemState($itemId, $phase, S=${stability?.toStringAsFixed(2)}, reps=$reps, lapses=$lapses, due=$due)';
}
