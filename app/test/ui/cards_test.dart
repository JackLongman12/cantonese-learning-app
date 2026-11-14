// Flashcards of real names: decks load from content.db, a card flips and grades both
// itself and its characters. Skipped when the pipeline has not been run.
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/cards_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  test('decks have real names with their sign names', () {
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final decks = db.decks();
    expect(decks.map((d) => d.id), containsAll(['mo-streets', 'mo-lrt', 'hk-mtr', 'hk-streets']));
    final streets = db.cards('mo-streets');
    expect(streets.length, greaterThan(100));
    expect(streets.where((c) => c.alt.isNotEmpty).length, greaterThan(90 * streets.length ~/ 100));
    for (final c in streets.take(50)) {
      expect(c.tokens.map((t) => t.surface).join(), c.zh);
    }
    expect(db.streetPatterns('macau').map((p) => p.zh), contains('街'));
  }, skip: hasDb ? false : 'run the pipeline first');

  testWidgets('flip a card and grade it', (t) async {
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
    final deck = db.decks().firstWhere((d) => d.id == 'hk-mtr');
    await t.pumpWidget(
      MaterialApp(home: CardSessionScreen(services: services, deck: deck)),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('flip')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('card-alt')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('got-it')));
    await t.pumpAndSettle();
    final reviews = store.events.where((e) => e.type == 'review.applied').toList();
    expect(reviews.any((e) => (e.payload['item_id']! as String).startsWith('card:hk-mtr:')), isTrue);
    expect(reviews.any((e) => (e.payload['item_id']! as String).startsWith('cr:yue:')), isTrue);
    final cardId = reviews.last.payload['item_id']! as String;
    expect(services.learner.stateOf(cardId).isNew, isFalse);
  }, skip: !hasDb);
}
