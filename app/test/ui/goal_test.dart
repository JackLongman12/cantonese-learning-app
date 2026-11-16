// Today asks for a goal once and the plan follows it.
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/data/prefs.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';

  testWidgets('picking a goal puts its topics first in the plan', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final memory = Memory();
    final prefs = Prefs.memory();
    final s = AppServices(
      content: db,
      memory: memory,
      learner: LearnerModel(memory),
      logger: EventLogger(
        store: MemoryEventStore(),
        deviceId: 'test',
        deviceKind: 'windows',
        appVersion: 'test',
        contentVersion: db.contentVersion,
      ),
      playAudio: (_) async {},
      prefs: prefs,
    );
    await t.pumpWidget(MaterialApp(home: HomeScreen(services: s)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('goal-ask')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('goal-food')));
    await t.pumpAndSettle();
    expect(prefs.goal, 'food');
    expect(find.byKey(const ValueKey('goal-ask')), findsNothing);
    // the topic to continue with is a food/shopping/numbers one
    final texts = [
      for (final w in t.widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('continue-topic')),
          matching: find.byType(Text),
        ),
      ))
        w.data ?? '',
    ];
    final title = texts.join(' | ');
    expect(
      [
        'Eating out',
        'Dishes and menus',
        'Shopping',
        'Numbers',
      ].any(title.contains),
      isTrue,
      reason: title,
    );
  }, skip: !File(dbPath).existsSync());
}
