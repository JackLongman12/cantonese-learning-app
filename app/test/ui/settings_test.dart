import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/data/prefs.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/engine/scaffold.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';

  testWidgets('settings change preferences and the fade rules follow', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final prefs = Prefs.memory();
    final memory = Memory();
    final s = AppServices(
      content: db,
      memory: memory,
      learner: LearnerModel(memory),
      logger: EventLogger(
        store: MemoryEventStore(),
        deviceId: 't',
        deviceKind: 't',
        appVersion: 't',
        contentVersion: 'c',
      ),
      playAudio: (_) async {},
      prefs: prefs,
    );
    await t.pumpWidget(MaterialApp(home: SettingsScreen(services: s)));
    await t.tap(find.text('More'));
    await t.pump();
    expect(prefs.helpShift, 1);
    expect(s.scaffold.shift, 1);
    await t.tap(find.text('普通话'));
    await t.pump();
    expect(prefs.lang, 'cmn');
    await t.tap(find.byKey(const ValueKey('set-read-along')));
    await t.pump();
    expect(prefs.readAlong, isTrue);
    expect(const ScaffoldPolicy(shift: 1).shift, 1);
  }, skip: !File(dbPath).existsSync());
}
