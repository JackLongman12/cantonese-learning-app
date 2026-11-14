// Runs the real app build with real plugins (sqlite, audio) on a device:
//   flutter test integration_test -d windows
// Progress goes to a temp folder, never to the owner's real event log.
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled content opens, a sentence renders and audio plays', (
    t,
  ) async {
    final dir = Directory.systemTemp.createTempSync('duk_it');
    final bytes = await rootBundle.load('assets/content/content.db');
    final dbFile = File('${dir.path}/content.db')
      ..writeAsBytesSync(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    final db = ContentDb.open(dbFile.path);
    final store = JsonlEventStore(Directory('${dir.path}/events'), 'it');
    final memory = Memory();
    final services = AppServices(
      content: db,
      memory: memory,
      learner: LearnerModel(memory),
      logger: EventLogger(
        store: store,
        deviceId: 'it',
        deviceKind: Platform.operatingSystem,
        appVersion: 'it',
        contentVersion: db.contentVersion,
      ),
      playAudio: createPlayAudio(),
    );

    await t.pumpWidget(DukApp(services: services));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Getting around Macau'), 200);
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
    expect(find.byKey(const ValueKey('ruby-0')), findsOneWidget);

    await t.tap(find.text('Listen'));
    await t.pump(const Duration(seconds: 3)); // let the clip start
    expect(find.textContaining('Could not play audio'), findsNothing);
    expect(find.textContaining('No audio'), findsNothing);

    await t.tap(find.byKey(const ValueKey('next')));
    await t.pumpAndSettle();
    final types = store.readAll().map((e) => e.type).toSet();
    expect(
      types,
      containsAll(['session.start', 'item.shown', 'item.audio', 'item.done']),
    );
    db.close();
  });
}
