import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/data/prefs.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/home_screen.dart';
import 'package:duk/ui/paste_reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reader_steps.dart';

import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  test('prefs persist across restarts and survive a corrupt file', () {
    final dir = Directory.systemTemp.createTempSync('duk_prefs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/prefs.json');
    Prefs(f)
      ..helpShift = 1
      ..setLastTopic('yue', 'scn-x');
    final again = Prefs(f);
    expect(again.lang, 'yue');
    expect(again.helpShift, 1);
    expect(again.lastTopic('yue'), 'scn-x');
    f.writeAsStringSync('{broken');
    expect(Prefs(f).lang, 'yue');
  });

  AppServices make(ContentDb db, Prefs prefs) {
    final memory = Memory();
    return AppServices(
      content: db,
      memory: memory,
      learner: LearnerModel(memory),
      logger: EventLogger(
        store: MemoryEventStore(),
        deviceId: 't',
        deviceKind: 'windows',
        appVersion: 't',
        contentVersion: db.contentVersion,
      ),
      playAudio: (_) async {},
      prefs: prefs,
    );
  }

  testWidgets("Today's plan starts the next step and ticks it off", (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final prefs = Prefs.memory();
    final services = make(db, prefs);
    await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
    await t.pumpAndSettle();
    // Today's plan: a new learner starts with the first topic on the path
    expect(find.byKey(const ValueKey('plan-learn')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('plan-review')),
      findsNothing,
    ); // nothing due yet
    await t.tap(find.byKey(const ValueKey('start-daily')));
    await t.pumpAndSettle();
    expect(readerHasMore(), isTrue); // in the reader
    // finishing the session ticks the step
    while (readerHasMore()) {
      await finishSentence(t);
    }
    final day = services.logger.now().toLocal().toIso8601String().substring(
      0,
      10,
    );
    expect(prefs.planDone(day), contains('learn'));
  }, skip: !hasDb);

  testWidgets('shared text opens straight into the reader', (t) async {
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    await t.pumpWidget(
      MaterialApp(
        home: PasteReaderScreen(
          services: make(db, Prefs.memory()),
          lang: 'yue',
          initialText: '我去銀行',
          source: 'share',
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('coverage')), findsOneWidget);
    expect(find.byKey(const ValueKey('paste-input')), findsNothing);
  }, skip: !hasDb);
}
