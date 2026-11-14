import 'dart:math' as math;
import 'dart:typed_data';

import 'package:duk/engine/end_of_speech.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List tone(int ms, double amp) => Float32List.fromList([
  for (var i = 0; i < 16 * ms; i++) amp * math.sin(i * 0.1),
]);

/// Feeds audio in 100 ms chunks; returns the ms at which it said stop, or null.
int? stopAt(List<Float32List> parts) {
  final e = EndOfSpeech();
  final all = Float32List.fromList([for (final p in parts) ...p]);
  for (var off = 0; off < all.length; off += 1600) {
    if (e.add(
      Float32List.sublistView(all, off, math.min(off + 1600, all.length)),
    )) {
      return (off + 1600) ~/ 16;
    }
  }
  return null;
}

void main() {
  test('stops about a second after the learner finishes', () {
    final at = stopAt([tone(500, 0.002), tone(2000, 0.3), tone(3000, 0.002)]);
    expect(at, isNotNull);
    expect(at!, inInclusiveRange(3300, 3600));
  });

  test('short pauses between words do not stop it', () {
    final at = stopAt([
      tone(300, 0.002),
      tone(800, 0.3),
      tone(400, 0.002),
      tone(800, 0.3),
      tone(2000, 0.002),
    ]);
    expect(at!, greaterThan(2300));
  });

  test('a click is not speech; gives up after the timeout', () {
    final e = EndOfSpeech();
    e.add(tone(60, 0.5));
    expect(e.add(tone(6500, 0.002)), isFalse);
    expect(e.add(tone(600, 0.002)), isTrue);
    expect(e.heardSpeech, isFalse);
  });

  test('hard cap on length', () {
    final e = EndOfSpeech(maxLength: const Duration(seconds: 3));
    expect(e.add(tone(2900, 0.3)), isFalse);
    expect(e.add(tone(200, 0.3)), isTrue);
  });
}
