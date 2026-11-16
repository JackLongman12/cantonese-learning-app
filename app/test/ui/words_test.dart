// Long-press a character, save the word, see it in My words. Uses the real content.db
// (dictionary included); skipped when the pipeline has not been run.
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/reader_screen.dart';
import 'package:duk/ui/words_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reader_steps.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  test('dictionary offers the longest word first', () {
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final found = db.wordsAt('行路去銀行', 3, 'yue');
    expect(found.first.start, 3);
    expect(found.first.end, 5);
    expect(found.first.entries.first.en.toLowerCase(), contains('bank'));
  }, skip: hasDb ? false : 'run the pipeline first');

  testWidgets('save a word from a sentence; it shows in My words', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final store = MemoryEventStore();
    final memory = Memory();
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
      ),
      playAudio: (_) async {},
    );
    final s = db
        .allSentences('yue')
        .firstWhere((s) => s.tokens.where((t) => t.kind == 'han').length >= 4);
    await t.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          services: services,
          title: 'T',
          sentences: [s],
          lang: 'yue',
          ordered: true,
        ),
      ),
    );
    await t.pumpAndSettle();
    final han = s.tokens.indexWhere((t) => t.kind == 'han');
    await t.longPress(find.byKey(ValueKey('cell-$han')));
    await t.pumpAndSettle();
    final save = find.byWidgetPredicate(
      (w) =>
          w is IconButton &&
          (w.key is ValueKey<String>) &&
          (w.key! as ValueKey<String>).value.startsWith('save-'),
    );
    expect(save, findsWidgets);
    await t.tap(save.first);
    await t.pumpAndSettle();
    final saved = store.events.lastWhere((e) => e.type == 'word.save');
    expect(saved.payload['context'], s.text);
    expect(saved.payload['context_en'], s.en);
    final word = saved.payload['text']! as String;
    expect(services.words.contains('yue', word), isTrue);

    await t.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: WordsScreen(services: services, lang: 'yue'),
        ),
      ),
    );
    expect(find.byKey(ValueKey('my-word-$word')), findsOneWidget);
    expect(find.byKey(const ValueKey('practice-flagged')), findsOneWidget);
  }, skip: !hasDb);

  testWidgets('a reading you had to reveal becomes a word to practice', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final store = MemoryEventStore();
    final memory = Memory();
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
      ),
      playAudio: (_) async {},
    );
    // 銀行: pretend both characters are known, so their readings are hidden
    final s = db.allSentences('yue').firstWhere((x) => x.text.contains('銀行'));
    final now = services.logger.now();
    for (final id in s.itemIds) {
      for (var d = 60; d > 0; d -= 20) {
        services.logger.log('review.applied', {'item_id': id, 'grade': 'good'});
      }
    }
    expect(now, isNotNull);
    await t.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          services: services,
          title: 'T',
          sentences: [s],
          lang: 'yue',
          ordered: true,
        ),
      ),
    );
    await t.pumpAndSettle();
    final bank = s.tokens.indexWhere((x) => x.surface == '銀');
    await t.tap(find.byKey(ValueKey('cell-$bank')));
    await t.pumpAndSettle();
    // no device voice in tests: let the one-time notice go away
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    // the tap opened the meaning too: close it
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await finishSentence(t);
    final flag = store.events.lastWhere((e) => e.type == 'word.flag');
    expect(flag.payload['reason'], 'read');
    final word = flag.payload['text']! as String;
    expect(word, contains('銀'));
    expect(services.words.needsPractice('yue', word), isTrue);

    // practice it (no mic in tests: check the reading and grade yourself), twice
    for (var round = 0; round < 2; round++) {
      await t.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Scaffold(
            body: WordsScreen(services: services, lang: 'yue'),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('practice-flagged')));
      await t.pumpAndSettle();
      while (find
          .byKey(const ValueKey('practice-show'))
          .evaluate()
          .isNotEmpty) {
        await t.tap(find.byKey(const ValueKey('practice-show')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('self-right')));
        await t.pumpAndSettle();
      }
    }
    expect(services.words.needsPractice('yue', word), isFalse);
  }, skip: !hasDb);
}
