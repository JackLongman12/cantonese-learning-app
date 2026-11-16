// Moving through the reader in tests: a sentence with characters to test is read
// first (Check), then confirmed (I read it right / Next); one with only new characters
// just has Next.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _keys = [ValueKey('check'), ValueKey('got-it'), ValueKey('next')];

/// Any of the reader's main buttons is on screen.
bool readerHasMore() => _keys.any((k) => find.byKey(k).evaluate().isNotEmpty);

/// Finishes the sentence on screen: Check if needed, then on to the next one.
Future<void> finishSentence(WidgetTester t) async {
  if (find.byKey(const ValueKey('check')).evaluate().isNotEmpty) {
    await t.tap(find.byKey(const ValueKey('check')));
    await t.pumpAndSettle();
  }
  for (final k in _keys.skip(1)) {
    if (find.byKey(k).evaluate().isNotEmpty) {
      await t.tap(find.byKey(k));
      // "I read it right" lights the characters up for a moment first
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      return;
    }
  }
}
