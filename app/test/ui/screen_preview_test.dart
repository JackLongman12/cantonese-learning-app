// Renders the real screens with the real content.db and bundled fonts to PNGs, so UI work
// can be reviewed as pictures: test/ui/goldens/preview_*.png
//   flutter test --update-goldens --tags golden test/ui/screen_preview_test.dart
@Tags(['golden'])
library;

import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/main.dart';
import 'package:duk/ui/cards_screen.dart';
import 'package:duk/ui/theme.dart';
import 'package:duk/ui/visual_novel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> loadFont(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

void main() {
  // keep Irasutoya pictures out of committed snapshots (public repo)
  characterPicturesEnabled = false;

  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  setUpAll(() async {
    await loadFont('NotoSansHK', 'assets/fonts/NotoSansHK.ttf');
    final kai = FontLoader('LXGWWenKaiTC');
    for (final f in ['Regular', 'Bold']) {
      kai.addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/LXGWWenKaiTC-$f.ttf').readAsBytesSync(),
          ),
        ),
      );
    }
    await kai.load();
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
    await loadFont(
      'MaterialIcons',
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
  });

  Future<AppServices> services(DateTime Function() clock) async {
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final memory = Memory();
    return AppServices(
      content: db,
      memory: memory,
      learner: LearnerModel(memory),
      logger: EventLogger(
        store: MemoryEventStore(),
        deviceId: 'preview',
        deviceKind: 'android',
        appVersion: 'preview',
        contentVersion: db.contentVersion,
        clock: clock,
      ),
      playAudio: (_) async {},
    );
  }

  for (final (name, size) in [
    ('phone', const Size(400, 860)),
    ('desktop', const Size(1100, 760)),
  ]) {
    testWidgets('preview $name', (t) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      var now = DateTime.utc(2026, 11, 15, 9);
      final s = await services(() => now);
      await t.pumpWidget(DukApp(services: s));
      await t.pumpAndSettle();
      // first run: the setup screen
      await t.tap(find.byKey(const ValueKey('onboard-level-1')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/preview_${name}_onboarding.png'),
      );
      await t.tap(find.byKey(const ValueKey('onboard-start')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/preview_${name}_home.png'),
      );

      Future<void> shot(String what) => expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/preview_${name}_$what.png'),
      );

      // Day 1: first session, everything new.
      await t.tap(find.byKey(const ValueKey('tab-topics')));
      await t.pumpAndSettle();
      await shot('topics');
      await t.tap(find.byKey(const ValueKey('tab-cards')));
      await t.pumpAndSettle();
      await shot('cards');
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
      await t.tap(find.byKey(const ValueKey('practise')));
      await t.pumpAndSettle();
      await shot('reader_new');
      while (find.byKey(const ValueKey('next')).evaluate().isNotEmpty) {
        now = now.add(const Duration(seconds: 6));
        await t.tap(find.byKey(const ValueKey('next')));
        await t.pumpAndSettle();
      }
      await shot('summary');
      await t.tap(find.byKey(const ValueKey('done')));
      await t.pumpAndSettle();

      // Day 2: help has faded on what was met yesterday.
      now = now.add(const Duration(days: 1));
      await t.pumpWidget(DukApp(key: UniqueKey(), services: s));
      await t.pumpAndSettle();
      await shot('home_day2');
      await t.tap(find.byKey(const ValueKey('start-daily')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('meaning')));
      await t.pumpAndSettle();
      await shot('reader_day2');
      await t.tap(find.byTooltip('How reading help works'));
      await t.pumpAndSettle();
      await shot('help');
    }, skip: !hasDb);
  }

  testWidgets('preview conversation', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 860));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var now = DateTime.utc(2026, 11, 15, 9);
    final s = await services(() => now);
    s.prefs.onboarded = true;
    await t.pumpWidget(DukApp(services: s));
    await t.pumpAndSettle();
    final topic = find.ancestor(
      of: find.text('Eating out and paying'),
      matching: find.byType(InkWell),
    );
    await t.tap(find.byKey(const ValueKey('tab-topics')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Eating out and paying'),
      200,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    await t.ensureVisible(topic);
    await t.pumpAndSettle();
    await t.tap(topic);
    await t.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/preview_phone_topic.png'),
    );
    await t.tap(find.byKey(const ValueKey('dlg-dlg-mo-food-01')));
    await t.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(seconds: 6));
      await t.tap(find.byKey(const ValueKey('next')));
      await t.pumpAndSettle();
    }
    // Character pictures (Irasutoya) are left undecoded here on purpose: these
    // snapshots are committed to a public repo, and the pictures must not be.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/preview_phone_conversation.png'),
    );
    // pick your line: it appears in your colour, with the other person dimmed
    await t.tap(find.text('通粉，唔該。'));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/preview_phone_conversation_line.png'),
    );
  }, skip: !hasDb);

  testWidgets('preview food card', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 860));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final s = await services(() => DateTime.utc(2026, 11, 15, 9));
    final deck = s.content.decks().firstWhere((d) => d.id == 'food');
    await t.pumpWidget(
      MaterialApp(
        theme: dukTheme(Brightness.light),
        home: CardSessionScreen(services: s, deck: deck),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('flip')));
    await t.pumpAndSettle();
    // dish photos are Commons images under free licences; decode before the snapshot
    for (final e in find.byType(Image).evaluate()) {
      await t.runAsync(() => precacheImage((e.widget as Image).image, e));
    }
    await t.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/preview_phone_food_card.png'),
    );
  }, skip: !hasDb);
}
