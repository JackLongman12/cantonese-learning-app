/// How much reading help a character gets (docs/DESIGN.md section 2.2).
///
/// The level follows how well the item is established, not how likely it is to be
/// recalled right now: an item that has decayed is exactly the one to test, so it stays
/// hidden and a reveal is logged as a lapse.
library;

import 'item_state.dart';
import 'memory.dart';

enum ScaffoldLevel {
  /// Reading shown. Used to introduce an item.
  full,

  /// Tone only. Used during short-term (re)learning steps.
  hint,

  /// Nothing shown; tap reveals and counts as a lapse.
  tap,

  /// Nothing shown and no affordance; long-press still reveals.
  none,
}

class ScaffoldPolicy {
  const ScaffoldPolicy({
    this.masteredStabilityDays = 21,
    this.masteredRetrievability = 0.85,
    this.shift = 0,
  });

  final double masteredStabilityDays;

  /// Below the scheduler's 0.9 target on purpose: an item that is merely due stays
  /// unassisted, one that is well overdue gets its tap affordance back.
  final double masteredRetrievability;

  /// Session override: +1 shows more help everywhere, -1 shows less.
  final int shift;

  ScaffoldLevel levelFor(ItemState s, Memory memory, DateTime now) {
    final ScaffoldLevel base;
    if (s.isNew) {
      base = ScaffoldLevel.full;
    } else if (s.phase != Phase.review) {
      base = ScaffoldLevel.hint;
    } else if ((s.stability ?? 0) >= masteredStabilityDays &&
        memory.retrievability(s, now) >= masteredRetrievability) {
      base = ScaffoldLevel.none;
    } else {
      base = ScaffoldLevel.tap;
    }
    final i = (base.index - shift).clamp(0, ScaffoldLevel.values.length - 1);
    return ScaffoldLevel.values[i];
  }
}

/// Tone of a Jyutping or numbered-Pinyin syllable ("hong4" -> "4").
String toneOf(String reading) {
  final m = RegExp(r'[1-6]$').firstMatch(reading);
  return m == null ? '' : m.group(0)!;
}
