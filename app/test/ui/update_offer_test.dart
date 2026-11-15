// Opening the app with a newer release on GitHub shows an update dialog straight
// away, without going to Settings. GitHub and the installed build are faked.
import 'dart:convert';
import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/platform/updater.dart';
import 'package:duk/ui/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  const dbPath = 'assets/content/content.db';

  testWidgets('a newer release is offered as soon as the app opens', (t) async {
    PackageInfo.setMockInitialValues(
      appName: 'DuckLearn',
      packageName: 'app.duk.duk',
      version: '0.40.0',
      buildNumber: '2040',
      buildSignature: '',
    );
    final asset = assetNameFor(os: Platform.operatingSystem, dartVersion: '')!;
    final github = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'tag_name': 'b2050',
          'name': 'DuckLearn 0.50.0',
          'body': '',
          'assets': [
            {
              'name': asset,
              'browser_download_url': 'https://example.invalid/a',
              'size': 1000000,
            },
          ],
        }),
        200,
      ),
    );
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final memory = Memory();
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
      updater: Updater(client: github),
    );
    await t.pumpWidget(MaterialApp(home: HomeScreen(services: s)));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-offer')), findsOneWidget);
    expect(find.text('Update available · DuckLearn 0.50.0'), findsWidgets);
  }, skip: !File(dbPath).existsSync());
}
