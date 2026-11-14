/// Scores a read-aloud attempt by comparing readings, not characters: the recogniser
/// often writes a homophone (俾/比, 返/翻), which is fine, because what matters is
/// whether the learner produced the right syllable and tone for each character.
library;

import 'dart:math' as math;

enum Verdict {
  /// Right syllable, right tone.
  ok,

  /// Right syllable, wrong tone: the most common reading mistake.
  tone,

  /// A different syllable.
  wrong,

  /// Nothing was heard for this character.
  missed,
}

class CharScore {
  const CharScore(this.expected, this.verdict, {this.heard});
  final String expected;
  final Verdict verdict;

  /// What was heard in its place (null when missed).
  final String? heard;

  bool get isError => verdict == Verdict.tone || verdict == Verdict.wrong;
}

class AttemptScore {
  const AttemptScore(this.chars);
  final List<CharScore> chars;

  int get correct => chars.where((c) => c.verdict == Verdict.ok).length;
  double get ratio => chars.isEmpty ? 0 : correct / chars.length;
}

String _base(String r) => r.replaceAll(RegExp(r'[1-6]$'), '');

/// Some sounds merge in everyday speech (DESIGN §5 rule 9): accept them as correct.
String _relaxed(String r) {
  var s = _base(r);
  if (s.startsWith('n') && !s.startsWith('ng')) {
    s = 'l${s.substring(1)}'; // n -> l
  }
  if (s.startsWith('ng') && s.length > 2) s = s.substring(2); // ngo -> o
  if (s.startsWith('gw') && s.startsWith('gwo')) {
    s = 'g${s.substring(2)}'; // gwok -> gok
  }
  if (s.startsWith('kw') && s.startsWith('kwo')) s = 'k${s.substring(2)}';
  return s;
}

String _tone(String r) => RegExp(r'[1-6]$').firstMatch(r)?.group(0) ?? '';

/// Needleman-Wunsch style alignment of expected vs heard syllables.
AttemptScore scoreAttempt(List<String> expected, List<String> heard) {
  final n = expected.length, m = heard.length;
  double sub(String e, String h) {
    if (_relaxed(e) != _relaxed(h)) return 1.0;
    return _tone(e) == _tone(h) ? 0.0 : 0.4;
  }

  const gap = 0.7;
  final cost = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    cost[i][0] = i * gap;
  }
  for (var j = 1; j <= m; j++) {
    cost[0][j] = j * gap;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      cost[i][j] = math.min(
        cost[i - 1][j - 1] + sub(expected[i - 1], heard[j - 1]),
        math.min(cost[i - 1][j] + gap, cost[i][j - 1] + gap),
      );
    }
  }
  final out = List<CharScore?>.filled(n, null);
  var i = n, j = m;
  while (i > 0) {
    if (j > 0 &&
        cost[i][j] == cost[i - 1][j - 1] + sub(expected[i - 1], heard[j - 1])) {
      final e = expected[i - 1], h = heard[j - 1];
      final v = _relaxed(e) != _relaxed(h)
          ? Verdict.wrong
          : (_tone(e) == _tone(h) ? Verdict.ok : Verdict.tone);
      out[i - 1] = CharScore(e, v, heard: h);
      i--;
      j--;
    } else if (j > 0 && cost[i][j] == cost[i][j - 1] + gap) {
      j--; // extra syllable heard
    } else {
      out[i - 1] = CharScore(expected[i - 1], Verdict.missed);
      i--;
    }
  }
  return AttemptScore(out.cast<CharScore>());
}
