// Speak drill and "Keep going", on the real content.db (skipped without it).
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/reader_screen.dart';
import 'package:duk/ui/speak_drill_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  AppServices make(
    ContentDb db,
    MemoryEventStore store,
    DateTime Function() clock,
  ) {
    final memory = Memory();
    return AppServices(
      content: db,
      memory: memory,
      learner: LearnerModel(memory),
      logger: EventLogger(
        store: store,
        deviceId: 'test',
        deviceKind: 'windows',
        appVersion: 'test',
        contentVersion: db.contentVersion,
        clock: clock,
      ),
      playAudio: (_) async {},
    );
  }

  testWidgets('speak drill runs line after line and finishes', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final store = MemoryEventStore();
    final s = make(db, store, DateTime.now);
    final lines = pickSpeakLines(
      s,
      db.sentences('scn-mo-getting-around', 'yue'),
      count: 3,
    );
    expect(lines, hasLength(3));
    expect(
      lines.every((l) => l.tokens.where((t) => t.kind == 'han').length <= 12),
      isTrue,
    );
    var completed = false;
    await t.pumpWidget(
      MaterialApp(
        home: SpeakDrillScreen(
          services: s,
          title: 'Speak',
          sentences: lines,
          onComplete: () => completed = true,
        ),
      ),
    );
    await t.pumpAndSettle();
    // no mic here: say it aloud yourself, then go on
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(const ValueKey('speak-meaning')), findsNothing);
      await t.tap(find.byKey(const ValueKey('speak-said')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('speak-meaning')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('speak-next')));
      await t.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('speak-done')), findsOneWidget);
    expect(completed, isTrue);
  }, skip: !hasDb);

  testWidgets('keep going adds another batch instead of a fixed length', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    var now = DateTime.utc(2026, 11, 16, 9);
    final store = MemoryEventStore();
    final s = make(db, store, () => now);
    await t.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          services: s,
          title: 'T',
          sentences: db.sentences('scn-mo-getting-around', 'yue'),
          lang: 'yue',
          count: 2,
          maxNew: 4,
        ),
      ),
    );
    await t.pumpAndSettle();
    Future<void> readAll() async {
      while (find.byKey(const ValueKey('next')).evaluate().isNotEmpty) {
        now = now.add(const Duration(seconds: 6));
        await t.tap(find.byKey(const ValueKey('next')));
        await t.pumpAndSettle();
      }
    }

    await readAll();
    expect(find.byKey(const ValueKey('keep-going')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('keep-going')));
    await t.pumpAndSettle();
    await readAll();
    final shown = store.events
        .where((e) => e.type == 'item.shown')
        .map((e) => e.payload['sentence_id'])
        .toList();
    expect(shown.length, greaterThan(2)); // more than the first batch
    expect(shown.toSet().length, shown.length); // no sentence twice
  }, skip: !hasDb);
}
