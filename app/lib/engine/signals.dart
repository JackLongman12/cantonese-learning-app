/// Turns what the learner did with a sentence into one grade per item
/// (docs/DESIGN.md section 2.3). No explicit grading buttons needed.
library;

import 'item_state.dart';
import 'scaffold.dart';

/// [missed]: after checking (hearing the answer) the learner said they got it wrong.
enum Signal { introduced, noReveal, slow, reveal, missed, explicit }

class ItemOutcome {
  const ItemOutcome(this.itemId, this.grade, this.signal);
  final String itemId;
  final Grade grade;
  final Signal signal;
}

class SignalPolicy {
  const SignalPolicy({
    this.minActiveMsPerItem = 150,
    this.slowMsPerItem = 2500,
  });

  /// Below this the sentence was skipped, not read: nothing is learned from it.
  final int minActiveMsPerItem;

  /// Above this a correct read was laboured and is graded "hard".
  final int slowMsPerItem;

  /// [shown] is the scaffold level each item was displayed at; [revealed] the items whose
  /// reading the learner asked for; [missed] the items they marked wrong after checking
  /// their reading against the audio. [activeMs] excludes idle time (for a checked
  /// sentence, the time spent reading before the check).
  List<ItemOutcome> outcomes({
    required Map<String, ScaffoldLevel> shown,
    required Set<String> revealed,
    required int activeMs,
    Set<String> missed = const {},
  }) {
    if (shown.isEmpty || activeMs < minActiveMsPerItem * shown.length) {
      return const [];
    }
    final slow = activeMs > slowMsPerItem * shown.length;
    return [
      for (final e in shown.entries)
        if (e.value == ScaffoldLevel.full)
          // The reading was on screen: an introduction, not a test.
          ItemOutcome(e.key, Grade.good, Signal.introduced)
        else if (revealed.contains(e.key))
          ItemOutcome(e.key, Grade.again, Signal.reveal)
        else if (missed.contains(e.key))
          ItemOutcome(e.key, Grade.again, Signal.missed)
        else if (slow)
          ItemOutcome(e.key, Grade.hard, Signal.slow)
        else
          ItemOutcome(e.key, Grade.good, Signal.noReveal),
    ];
  }
}
