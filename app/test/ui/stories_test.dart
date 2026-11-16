import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/data/prefs.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/home_screen.dart';
import 'package:duk/ui/practice_screens.dart';
import 'package:duk/ui/stories_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reader_steps.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  AppServices make(ContentDb db, Prefs prefs, MemoryEventStore store) {
    final memory = Memory();
    return AppServices(
      content: db,
      memory: memory,
      learner: LearnerModel(memory),
      logger: EventLogger(
        store: store,
        deviceId: 't',
        deviceKind: 'android',
        appVersion: 't',
        contentVersion: db.contentVersion,
      ),
      playAudio: (_) async {},
      prefs: prefs,
    );
  }

  test('stories are kept apart from topics and Cantonese only', () {
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final yue = db.stories('yue');
    expect(yue.length, greaterThanOrEqualTo(6));
    expect(yue.first.level, 1);
    expect(db.stories('cmn'), isEmpty);
    expect(
      db
          .scenarios('yue')
          .any((s) => s.title == 'Stories' && s.sentenceCount > 0),
      isFalse,
    );
    expect(db.allSentences('yue').any((s) => s.id.startsWith('sty-')), isFalse);
  }, skip: !hasDb);

  test('sound fit: same, tone only, different', () {
    expect(soundFit('cing1', 'cing1'), SoundFit.same);
    expect(soundFit('cing1', 'cing4'), SoundFit.toneOnly);
    expect(soundFit('cing1', 'zing1'), SoundFit.different);
  });

  testWidgets(
    'a story reads in order, keeps earlier lines, and can be resumed',
    (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final db = ContentDb.open(dbPath);
      addTearDown(db.close);
      final prefs = Prefs.memory();
      final store = MemoryEventStore();
      final s = make(db, prefs, store);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoriesScreen(services: s, lang: 'yue'),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('story-next')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('story-sty-breakfast-yue')));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await finishSentence(t);
      }
      final lines = db.dialogueLines('sty-breakfast-yue', 'yue');
      expect(
        t.widget<Text>(find.byKey(const ValueKey('story-so-far'))).data,
        lines.take(3).map((l) => l.text).join(),
      );
      // leave mid-story: home offers to resume at line 4
      expect(prefs.resume?['index'], 3);
      // a fresh app, as after a restart
      await t.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: HomeScreen(services: s),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Resume: Breakfast downstairs'), findsOneWidget);
      expect(find.text('4 of ${lines.length}'), findsOneWidget);
    },
    skip: !hasDb,
  );

  testWidgets('sound families screen lists families from the content', (
    t,
  ) async {
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    expect(db.soundFamilies('yue'), isNotEmpty);
    await t.pumpWidget(
      MaterialApp(
        home: SoundFamiliesScreen(
          services: make(db, Prefs.memory(), MemoryEventStore()),
          lang: 'yue',
        ),
      ),
    );
    expect(find.text('Sound families'), findsOneWidget);
  }, skip: !hasDb);
}
