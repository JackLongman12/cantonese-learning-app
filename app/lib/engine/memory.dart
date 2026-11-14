/// The only file that talks to the FSRS package. Everything else uses [ItemState].
library;

import 'package:fsrs/fsrs.dart' as fsrs;

import 'item_state.dart';

class Memory {
  /// Fuzzing is off on purpose: replaying the event log must give the same state on
  /// every device, every time.
  Memory({double desiredRetention = 0.9, List<double>? parameters})
    : _scheduler = fsrs.Scheduler(
        parameters: parameters ?? fsrs.defaultParameters,
        desiredRetention: desiredRetention,
        enableFuzzing: false,
      );

  final fsrs.Scheduler _scheduler;

  /// Probability (0..1) that the item is recalled at [now]. 0 for unseen items.
  double retrievability(ItemState s, DateTime now) {
    if (s.isNew || s.stability == null) return 0;
    return _scheduler.getCardRetrievability(
      _card(s),
      currentDateTime: now.toUtc(),
    );
  }

  ItemState review(ItemState s, Grade grade, DateTime at) {
    final r = _scheduler.reviewCard(
      _card(s, fallbackDue: at),
      fsrs.Rating.fromValue(grade.value),
      reviewDateTime: at.toUtc(),
    );
    final c = r.card;
    return ItemState(
      itemId: s.itemId,
      phase: Phase.values[c.state.value - 1],
      step: c.step,
      stability: c.stability,
      difficulty: c.difficulty,
      due: c.due,
      lastReview: c.lastReview,
      reps: s.reps + 1,
      lapses: s.lapses + (grade == Grade.again && !s.isNew ? 1 : 0),
    );
  }

  fsrs.Card _card(ItemState s, {DateTime? fallbackDue}) => fsrs.Card(
    cardId: 0,
    state: fsrs.State.fromValue(s.phase.index + 1),
    step: s.step,
    stability: s.stability,
    difficulty: s.difficulty,
    due: (s.due ?? fallbackDue ?? DateTime.now()).toUtc(),
    lastReview: s.lastReview?.toUtc(),
  );
}
