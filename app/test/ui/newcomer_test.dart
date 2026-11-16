// Newcomer mode (Home B): onboarding picks it, the drill is English first, search finds
// the word to say. Real content.db (skipped without it).
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/data/prefs.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/main.dart' show DukApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  (AppServices, MemoryEventStore) make(ContentDb db, Prefs prefs) {
    final memory = Memory();
    final store = MemoryEventStore();
    return (
      AppServices(
        content: db,
        memory: memory,
        learner: LearnerModel(memory),
        logger: EventLogger(
          store: store,
          deviceId: 'test',
          deviceKind: 'android',
          appVersion: 'test',
          contentVersion: db.contentVersion,
        ),
        playAudio: (_) async {},
        prefs: prefs,
      ),
      store,
    );
  }

  testWidgets('"new to Cantonese" gets situations and an English-first drill', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final prefs = Prefs.memory();
    final (s, store) = make(db, prefs);
    await t.pumpWidget(DukApp(services: s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('intro-skip')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('onboard-new')));
    await t.pumpAndSettle();
    // newcomers pick situations; the first four are suggested
    expect(
      find.byKey(const ValueKey('onboard-sit-sit-basics')),
      findsOneWidget,
    );
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('onboard-share-no')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.byKey(const ValueKey('onboard-share-no')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('onboard-share-no')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('onboard-start')));
    await t.pumpAndSettle();
    expect(prefs.newcomerMode, isTrue);
    expect(prefs.situations, hasLength(4));

    // Home B
    expect(find.byKey(const ValueKey('drill-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-situations')), findsOneWidget);
    expect(find.byKey(const ValueKey('continue-topic')), findsNothing);

    // the drill: English first, then the word
    await t.tap(find.byKey(const ValueKey('start-drill')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('card-prompt')), findsOneWidget);
    expect(find.byKey(const ValueKey('flip')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('flip')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('got-it')));
    await t.pumpAndSettle();
    final graded = [
      for (final e in store.events.where((e) => e.type == 'review.applied'))
        e.payload['item_id']! as String,
    ];
    // only the word card is graded: no character reading was tested
    expect(graded, hasLength(1));
    expect(graded.single, startsWith('card:sit-'));
  }, skip: !hasDb);

  testWidgets('search finds the word to say', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final prefs = Prefs.memory()
      ..level = 'new'
      ..onboarded = true
      ..shareData = false;
    final (s, _) = make(db, prefs);
    await t.pumpWidget(DukApp(services: s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('phrase-search')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('search-field')), 'the bill');
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('search-word-card:sit-food:埋單')),
      findsOneWidget,
    );
  }, skip: !hasDb);

  testWidgets('replaying onboarding from Settings keeps progress', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final prefs = Prefs.memory()
      ..level = 'fluent'
      ..onboarded = true
      ..shareData = true
      ..telemetryId = 'tid';
    final (s, store) = make(db, prefs);
    s.logger.log('review.applied', {
      'item_id': 'cr:yue:我:ngo5',
      'grade': 'good',
      'signal': 'noReveal',
    });
    final before = s.learner.known.length;
    await t.pumpWidget(DukApp(services: s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('open-settings')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('replay-onboarding')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const ValueKey('replay-onboarding')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('intro-skip')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('onboard-new')));
    await t.pumpAndSettle();
    // the sharing answer is already filled in, so Start is ready
    await t.tap(find.byKey(const ValueKey('onboard-start')));
    await t.pumpAndSettle();
    expect(prefs.newcomerMode, isTrue);
    expect(find.byKey(const ValueKey('drill-card')), findsOneWidget);
    expect(s.learner.known.length, before); // progress kept
    expect(prefs.telemetryId, 'tid'); // no new anonymous id
    expect(store.events.where((e) => e.type == 'review.applied'), hasLength(1));

    // leave the test: the original setup comes back
    await t.tap(find.byKey(const ValueKey('open-settings')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('restore-setup')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.byKey(const ValueKey('restore-setup')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('restore-setup')));
    await t.pumpAndSettle();
    expect(prefs.newcomerMode, isFalse);
    expect(prefs.level, 'fluent');
    expect(prefs.hasSavedSetup, isFalse);
    expect(find.byKey(const ValueKey('continue-topic')), findsOneWidget);
  }, skip: !hasDb);

  test('installs from before the question keep the reading app', () {
    final p = Prefs.memory();
    expect(p.newcomerMode, isFalse); // speaker unknown: the old default
    p.speaker = false;
    expect(p.newcomerMode, isTrue); // chose "I'm learning it" in b2068
    p.level = 'fluent';
    expect(p.newcomerMode, isFalse);
    expect(p.isSpeaker, isTrue);
    p.level = 'new'; // Settings: "I speak Cantonese" off
    expect(p.newcomerMode, isTrue);
    expect(p.isSpeaker, isFalse);
  });
}
