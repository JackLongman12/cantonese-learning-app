// Newcomer practice (content/practice.yaml): Listen, tones, sentences, challenges and the
// Jyutping guide run on the real content.db (skipped without it) and log their events.
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/data/prefs.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/picture_rating.dart';
import 'package:duk/ui/practice_drills.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  (AppServices, MemoryEventStore, ContentDb) make() {
    final db = ContentDb.open(dbPath);
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
        prefs: Prefs.memory(),
      ),
      store,
      db,
    );
  }

  Future<void> open(WidgetTester t, Widget screen) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: screen));
    await t.pumpAndSettle();
  }

  List<String> types(MemoryEventStore store) => [
    for (final e in store.readAll()) e.type,
  ];

  test('practice content is in the database', () {
    final (_, _, db) = make();
    addTearDown(db.close);
    expect(db.practice('reply').length, greaterThan(40));
    expect(db.practice('tone').length, greaterThan(20));
    expect(db.practice('frame').length, greaterThan(30));
    expect(db.practice('challenge').length, greaterThan(10));
    // every line has its readings; tone clips are in more than one voice
    for (final r in db.practice('reply')) {
      expect(
        r.card.tokens
            .where((t) => t.kind == 'han')
            .every((t) => t.reading != null),
        isTrue,
        reason: r.card.zh,
      );
    }
    expect(
      db.audioPaths(db.practice('tone').first.card.zh).length,
      greaterThan(1),
    );
  }, skip: !hasDb);

  testWidgets('Listen: hear a reply, pick, see it, next', (t) async {
    final (s, store, db) = make();
    addTearDown(db.close);
    await open(
      t,
      ListenDrillScreen(
        services: s,
        title: 'Listen',
        situations: const {'sit-food'},
      ),
    );
    await t.tap(find.byKey(const ValueKey('listen-option-0')));
    await t.pumpAndSettle();
    expect(types(store), contains('listen.answer'));
    expect(s.practiceLog.repliesHeard, hasLength(1));
    await t.tap(find.byKey(const ValueKey('listen-next')));
    await t.pumpAndSettle();
  }, skip: !hasDb);

  testWidgets('Tones: pick the one heard', (t) async {
    final (s, store, db) = make();
    addTearDown(db.close);
    await open(t, ToneDrillScreen(services: s));
    await t.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('tone-option-'),
          )
          .first,
    );
    await t.pumpAndSettle();
    expect(types(store), contains('tone.answer'));
    expect(find.byKey(const ValueKey('tone-next')), findsOneWidget);
  }, skip: !hasDb);

  testWidgets('Sentences: show, then grade', (t) async {
    final (s, store, db) = make();
    addTearDown(db.close);
    await open(t, FrameDrillScreen(services: s));
    expect(find.byKey(const ValueKey('frame-english')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('frame-show')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('frame-got-it')));
    await t.pumpAndSettle();
    expect(types(store), contains('frame.say'));
    expect(s.practiceLog.framesSaid, hasLength(1));
  }, skip: !hasDb);

  testWidgets('Challenge: "I did it" moves on, no streak', (t) async {
    final (s, store, db) = make();
    addTearDown(db.close);
    await open(t, Scaffold(body: ChallengeCard(services: s)));
    await t.tap(find.byKey(const ValueKey('challenge-done')));
    await t.pumpAndSettle();
    expect(s.practiceLog.challengesDone, hasLength(1));
    expect(find.text('1 done'), findsOneWidget);
  }, skip: !hasDb);

  testWidgets('Rate pictures: Bad, OK and Good, one tap each, Back to change', (
    t,
  ) async {
    final (s, store, db) = make();
    addTearDown(db.close);
    final total = doubtfulPictures(s).length;
    expect(total, greaterThan(100));
    await open(t, PictureRatingScreen(services: s));
    await t.tap(find.byKey(const ValueKey('rate-good')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rate-ok')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rate-bad')));
    await t.pumpAndSettle();
    expect(find.text('3 / $total'), findsOneWidget);
    expect(picturesToRate(s), total - 3);
    final rates = [
      for (final e in store.readAll())
        if (e.type == 'picture.rate') (e.payload['rating'], e.payload['good']),
    ];
    expect(rates, [('good', true), ('ok', true), ('bad', false)]);
    // Back, change the Bad to Good: the newest rating wins
    await t.tap(find.byKey(const ValueKey('rate-back')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rate-good')));
    await t.pumpAndSettle();
    expect(s.practiceLog.pictureRatings.values.where((g) => !g), isEmpty);
  }, skip: !hasDb);

  testWidgets('Jyutping guide shows letters and the six tones', (t) async {
    final (s, _, db) = make();
    addTearDown(db.close);
    await open(t, JyutpingGuideScreen(services: s));
    expect(find.text('Reading Jyutping'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const ValueKey('guide-tone-5')), 300);
    expect(find.textContaining('Tone 6'), findsOneWidget);
  }, skip: !hasDb);
}
