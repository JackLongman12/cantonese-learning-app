import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ulid/ulid.dart';

import 'app_services.dart';
import 'data/content_db.dart';
import 'data/prefs.dart';
import 'engine/learner_model.dart';
import 'engine/memory.dart';
import 'events/event_logger.dart';
import 'events/event_store.dart';
import 'platform/reminders.dart';
import 'platform/speech.dart';
import 'platform/updater.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0-dev',
);
const _contentAsset = 'assets/content/content.db';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DukApp(services: await _bootstrap()));
}

Future<AppServices> _bootstrap() async {
  final support = await getApplicationSupportDirectory();

  // The bundled content database is copied out on every start: it is small, read-only and
  // replaced wholesale, and progress never lives in it (docs/DESIGN.md section 4.2).
  final dbFile = File(p.join(support.path, 'content.db'));
  final bytes = await rootBundle.load(_contentAsset);
  await dbFile.writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    flush: true,
  );
  final content = ContentDb.open(dbFile.path);

  final idFile = File(p.join(support.path, 'device_id'));
  if (!idFile.existsSync()) idFile.writeAsStringSync(Ulid().toString());
  final deviceId = idFile.readAsStringSync().trim();

  final store = JsonlEventStore(
    Directory(p.join(support.path, 'events')),
    deviceId,
  );
  final memory = Memory();
  final learner = LearnerModel.replay(store.readAll(), memory);
  final logger = EventLogger(
    store: store,
    deviceId: deviceId,
    deviceKind: Platform.operatingSystem,
    appVersion: appVersion,
    contentVersion: content.contentVersion,
  );
  logger.log('app.open', {
    'source': 'icon',
    'replayed_items': learner.known.length,
  });

  return AppServices(
    content: content,
    logger: logger,
    learner: learner,
    memory: memory,
    playAudio: createPlayAudio(),
    playFile: (path) => _filePlayer.play(DeviceFileSource(path)),
    prefs: Prefs(File(p.join(support.path, 'prefs.json'))),
    updater: Updater(),
    reminders: Platform.isAndroid ? Reminders() : null,
    speech: (Platform.isAndroid || Platform.isWindows || Platform.isMacOS)
        ? SpeechEngine(Directory(p.join(support.path, 'models', 'sensevoice')))
        : null,
  );
}

/// Plays a clip bundled under `assets/content/`. One player, so a new clip replaces the
/// one still playing.
final _filePlayer = AudioPlayer();

PlayAudio createPlayAudio() {
  final player = AudioPlayer();
  return (path) async {
    await player.stop();
    await player.play(AssetSource('content/$path'));
    // resolve when the clip ends, so shadowing can start recording right after it
    await player.onPlayerComplete.first.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  };
}

class DukApp extends StatelessWidget {
  const DukApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DuckLearn',
    debugShowCheckedModeBanner: false,
    theme: dukTheme(Brightness.light),
    darkTheme: dukTheme(Brightness.dark),
    home: HomeScreen(services: services),
  );
}
