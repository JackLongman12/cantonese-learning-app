// End-to-end: the real content.db built by the pipeline, the real engine, a fake clock.
// Skipped when the pipeline has not been run (`duk build && duk bundle`).
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/engine/scaffold.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/home_screen.dart';
import 'package:duk/ui/reader_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  test('content.db opens and tokens line up with the text', () {
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    expect(db.contentVersion, isNotEmpty);
    final scenarios = db.scenarios('yue');
    expect(scenarios, isNotEmpty);
    expect(scenarios.first.region, 'macau');
    for (final sc in scenarios) {
      for (final s in db.sentences(sc.id, 'yue')) {
        expect(s.tokens.map((t) => t.surface).join(), s.text, reason: s.id);
        for (final t in s.tokens.where((t) => t.kind == 'han')) {
          expect(t.reading, isNotNull, reason: '${s.id} ${t.surface}');
          expect(t.itemId, 'cr:yue:${t.surface}:${t.reading}');
        }
      }
    }
  }, skip: hasDb ? false : 'run the pipeline first');

  testWidgets('reading a scenario logs reviews and fades the readings', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    var now = DateTime.utc(2026, 11, 15, 9);
    final store = MemoryEventStore();
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
        clock: () => now,
      ),
      playAudio: (path) async => played.add(path),
    );

    String stat(String key) => (t.widget<Text>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Text),
          )
          .first,
    )).data!;
    await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('stat-met')),
      200,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    expect(stat('stat-met'), '0');
    await t.tap(find.byKey(const ValueKey('tab-topics')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Getting around Macau'),
      200,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    await t.ensureVisible(
      find.ancestor(
        of: find.text('Getting around Macau'),
        matching: find.byType(InkWell),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(
      find.ancestor(
        of: find.text('Getting around Macau'),
        matching: find.byType(InkWell),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('practice')));
    await t.pumpAndSettle();

    // First pass: everything is new, so readings are shown in full.
    final shown = store.events.lastWhere((e) => e.type == 'item.shown');
    expect((shown.payload['scaffold']! as List).toSet(), {'full'});

    // attempt first: nothing plays until you have tried to read it
    expect(played, isEmpty);
    await t.tap(find.text('Listen'));
    await t.pump();
    expect(played.single, startsWith('audio/'));
    // once it has played, the meaning shows by itself
    await t.pump();
    expect(
      store.events.any(
        (e) => e.type == 'item.reveal' && e.payload['auto'] == true,
      ),
      isTrue,
    );

    // The planner caps new characters per session, so a first session is shorter than
    // the whole topic. Read until it ends.
    var read = 0;
    while (find.byKey(const ValueKey('next')).evaluate().isNotEmpty) {
      now = now.add(const Duration(seconds: 6)); // time spent reading
      await t.tap(find.byKey(const ValueKey('next')));
      await t.pumpAndSettle();
      read++;
    }
    expect(read, greaterThan(0));
    // the session ends on a summary screen
    expect(find.byKey(const ValueKey('done')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('done')));
    await t.pumpAndSettle();
    // back from the topic page to home
    await t.pageBack();
    await t.pumpAndSettle();
    final introduced = {
      for (final e in store.events.where((e) => e.type == 'review.applied'))
        e.payload['item_id']! as String,
    };
    expect(introduced.length, lessThanOrEqualTo(12));
    // back on the Today tab, where the stats are
    await t.tap(find.byKey(const ValueKey('tab-today')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('stat-met')),
      200,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    expect(stat('stat-met'), '${introduced.length}');

    final reviews = store.events
        .where((e) => e.type == 'review.applied')
        .toList();
    expect(reviews, isNotEmpty);
    // The first meeting of each character is an introduction; a character that comes up
    // again later in the same session is already being tested with less help.
    final firstSignal = <String, Object?>{};
    for (final e in reviews) {
      firstSignal.putIfAbsent(
        e.payload['item_id']! as String,
        () => e.payload['signal'],
      );
    }
    expect(firstSignal.values.toSet(), {'introduced'});
    expect(
      store.events.lastWhere((e) => e.type != 'nav.screen').type,
      'session.end',
    );

    // The live model equals a rebuild from the log.
    expect(
      LearnerModel.replay(store.events, Memory()).snapshot(),
      services.learner.snapshot(),
    );

    // Next day: the same characters are no longer shown in full.
    now = now.add(const Duration(days: 1));
    final item = reviews.first.payload['item_id']! as String;
    final level = services.scaffold.levelFor(
      services.learner.stateOf(item),
      memory,
      now,
    );
    expect(level, isNot(ScaffoldLevel.full));

    await t.tap(find.byKey(const ValueKey('tab-topics')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Getting around Macau'),
      200,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    await t.ensureVisible(
      find.ancestor(
        of: find.text('Getting around Macau'),
        matching: find.byType(InkWell),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(
      find.ancestor(
        of: find.text('Getting around Macau'),
        matching: find.byType(InkWell),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('practice')));
    await t.pumpAndSettle();
    final again = store.events.lastWhere((e) => e.type == 'item.shown');
    final ids = (again.payload['item_ids']! as List).cast<String>();
    final levels = (again.payload['scaffold']! as List).cast<String>();
    for (var i = 0; i < ids.length; i++) {
      // met yesterday -> help has faded; never met -> still introduced in full
      expect(levels[i] == 'full', !introduced.contains(ids[i]), reason: ids[i]);
    }
  }, skip: !hasDb);

  testWidgets(
    'a conversation plays as a visual novel: stage, choices on your turn, backlog',
    (t) async {
      await t.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final db = ContentDb.open(dbPath);
      addTearDown(db.close);
      final memory = Memory();
      final store = MemoryEventStore();
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
      final dialogues = db.dialogues('scn-mo-getting-around', 'yue');
      expect(dialogues.length, greaterThanOrEqualTo(5));
      final lines = db.dialogueLines(dialogues.first.id, 'yue');
      expect(lines.map((l) => l.turn), [
        for (var i = 1; i <= lines.length; i++) i,
      ]);
      await t.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            services: services,
            title: dialogues.first.title,
            sentences: lines,
            lang: 'yue',
            conversation: true,
            scenarioId: 'scn-mo-getting-around',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('stage')), findsOneWidget);
      for (var k = 0; k < 2; k++) {
        if (lines[k].speaker == '你') {
          // your turn: pick your line from three before it appears
          expect(find.byKey(const ValueKey('choices')), findsOneWidget);
          await t.tap(find.text(lines[k].text));
          await t.pumpAndSettle();
          expect(
            store.events
                .lastWhere((e) => e.type == 'conv.choice')
                .payload['correct'],
            isTrue,
          );
        } else {
          expect(find.byKey(const ValueKey('choices')), findsNothing);
        }
        await t.tap(find.byKey(const ValueKey('next')));
        await t.pumpAndSettle();
      }
      // earlier lines are in the backlog
      await t.tap(find.byKey(const ValueKey('backlog')));
      await t.pumpAndSettle();
      expect(find.text(lines[0].text), findsOneWidget);
      expect(find.text(lines[1].text), findsOneWidget);
      final shown = store.events
          .where((e) => e.type == 'item.shown')
          .map((e) => e.payload['sentence_id']);
      expect(shown, [lines[0].id, lines[1].id, lines[2].id]);
    },
    skip: !hasDb,
  );
}
