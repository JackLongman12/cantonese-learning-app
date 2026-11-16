// Read, then check: the sentence is read with no sound, Check plays it and shows the
// readings, and a character tapped after that is graded as a miss. Real content.db.
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/data/prefs.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  Future<(AppServices, MemoryEventStore, List<String>)> open(
    WidgetTester t, {
    required bool speaker,
  }) async {
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final store = MemoryEventStore();
    var now = DateTime.utc(2026, 11, 17, 9);
    final memory = Memory();
    final played = <String>[];
    final services = AppServices(
      content: db,
      memory: memory,
      learner: LearnerModel(memory),
      logger: EventLogger(
        store: store,
        deviceId: 'test',
        deviceKind: 'windows',
        appVersion: 'test',
        contentVersion: db.contentVersion,
        clock: () => now = now.add(const Duration(seconds: 2)),
      ),
      playAudio: (path) async => played.add(path),
      // no Jyutping at all: every character is being tested
      prefs: Prefs.memory()
        ..helpShift = -3
        ..speaker = speaker,
    )..armOverrides['meaning_after_check'] = 'hidden';
    final sentence = db.sentencesByIds(['sent-var-001:yue']).single;
    await t.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          services: services,
          title: 'Test',
          sentences: [sentence],
          lang: 'yue',
          ordered: true,
        ),
      ),
    );
    await t.pumpAndSettle();
    return (services, store, played);
  }

  testWidgets('a speaker reads first, checks, and marks a miss', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (services, store, played) = await open(t, speaker: true);

    // reading first: no Listen, no sound, no meaning
    expect(find.byKey(const ValueKey('listen')), findsNothing);
    expect(find.byKey(const ValueKey('check')), findsOneWidget);
    expect(find.text('Show meaning'), findsOneWidget);
    expect(played, isEmpty);

    await t.tap(find.byKey(const ValueKey('check')));
    await t.pumpAndSettle();
    expect(played, hasLength(1));
    // the speaker arm 'hidden' keeps the meaning closed after hearing it
    expect(find.text('Show meaning'), findsOneWidget);
    expect(find.byKey(const ValueKey('got-it')), findsOneWidget);
    expect(store.events.where((e) => e.type == 'item.check'), hasLength(1));

    // tap the first character: read wrong
    final s = services.content.sentencesByIds(['sent-var-001:yue']).single;
    final first = s.tokens.indexWhere((x) => x.itemId != null);
    await t.tap(find.byKey(ValueKey('cell-$first')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('got-it')), findsNothing);
    expect(find.textContaining('1 to practice'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('next')));
    await t.pumpAndSettle();

    final grades = {
      for (final e in store.events.where((e) => e.type == 'review.applied'))
        e.payload['item_id']! as String: e.payload['signal'],
    };
    expect(grades[s.tokens[first].itemId], 'missed');
    expect(
      grades.entries
          .where((e) => e.key != s.tokens[first].itemId)
          .map((e) => e.value),
      everyElement(anyOf('noReveal', 'slow')),
    );
    // the session ends on the summary, which counts what was read on your own
    expect(find.byKey(const ValueKey('done')), findsOneWidget);
  }, skip: !hasDb);

  testWidgets('a learner sees the meaning from the start', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await open(t, speaker: false);
    expect(find.text('Meaning'), findsOneWidget);
    // reading all right: the confirm button lights the characters up, then moves on
    await t.tap(find.byKey(const ValueKey('check')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('got-it')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('done')), findsNothing);
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('done')), findsOneWidget);
  }, skip: !hasDb);

  testWidgets('Not quite marks every tested character; tap to unmark', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (services, store, _) = await open(t, speaker: false);
    expect(find.text('Read this sentence, then tap Check'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('check')));
    await t.pumpAndSettle();
    expect(find.text('Did you read it right?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('not-quite')));
    await t.pumpAndSettle();
    final s = services.content.sentencesByIds(['sent-var-001:yue']).single;
    final tested = [
      for (var i = 0; i < s.tokens.length; i++)
        if (s.tokens[i].itemId != null) i,
    ];
    expect(find.textContaining('${tested.length} to practice'), findsOneWidget);
    // the first one was read right after all
    await t.tap(find.byKey(ValueKey('cell-${tested.first}')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('${tested.length - 1} to practice'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('next')));
    await t.pumpAndSettle();
    final signals = [
      for (final e in store.events.where((e) => e.type == 'review.applied'))
        e.payload['signal'],
    ];
    expect(signals.where((x) => x == 'missed'), hasLength(tested.length - 1));
  }, skip: !hasDb);
}
