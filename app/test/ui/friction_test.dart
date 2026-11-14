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
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  test('prefs persist across restarts and survive a corrupt file', () {
    final dir = Directory.systemTemp.createTempSync('duk_prefs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/prefs.json');
    Prefs(f)
      ..sessionLength = 30
      ..setLastTopic('yue', 'scn-x');
    final again = Prefs(f);
    expect(again.lang, 'yue');
    expect(again.sessionLength, 30);
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

  testWidgets('home remembers the last topic and session length', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final prefs = Prefs.memory()..setLastTopic('yue', 'scn-mo-health');
    await t.pumpWidget(
      MaterialApp(home: HomeScreen(services: make(db, prefs))),
    );
    await t.pumpAndSettle();
    expect(find.text('Continue: Health and the doctor'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('length-5')));
    await t.pump();
    expect(prefs.sessionLength, 5);

    await t.tap(find.byKey(const ValueKey('continue-topic')));
    await t.pumpAndSettle();
    expect(find.text('Health and the doctor'), findsOneWidget); // reader title
    // a quick session never has more than the chosen length... topic sessions are
    // planner-sized; daily ones use the length
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
