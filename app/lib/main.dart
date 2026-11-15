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
import 'platform/sfx.dart';
import 'platform/speech.dart';
import 'platform/word_voice.dart';
import 'platform/updater.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';
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

  // Leftovers from an earlier update (installer, unpack folders) are junk once it ran.
  try {
    Updater.cleanUp(await getTemporaryDirectory());
  } on Object {
    // temp dir unavailable: nothing to clean
  }
  // A speech-model download cut off part way leaves a .part file; it restarts anyway.
  final modelDir = Directory(p.join(support.path, 'models', 'sensevoice'));
  if (modelDir.existsSync()) {
    for (final f in modelDir.listSync().whereType<File>()) {
      if (f.path.endsWith('.part')) f.deleteSync();
    }
  }

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
    // "Slow": the same clip at 75% (pitch kept), instead of a second recording
    playAudioSlow: createPlayAudio(rate: 0.75),
    playFile: (path) => _filePlayer.play(DeviceFileSource(path)),
    prefs: Prefs(File(p.join(support.path, 'prefs.json'))),
    updater: Updater(),
    sfx: SoundEffects(),
    voice: WordVoice(),
    reminders: Platform.isAndroid ? Reminders() : null,
    speech: (Platform.isAndroid || Platform.isWindows || Platform.isMacOS)
        ? SpeechEngine(modelDir)
        : null,
  );
}

/// Plays a clip bundled under `assets/content/`. One player, so a new clip replaces the
/// one still playing.
final _filePlayer = AudioPlayer();

PlayAudio createPlayAudio({double rate = 1.0}) {
  final player = AudioPlayer();
  return (path) async {
    await player.stop();
    // listen before playing so a very short clip's end is not missed
    final ended = player.onPlayerComplete.first.then<void>((_) {});
    await player.setSource(AssetSource('content/$path'));
    if (rate != 1.0) await player.setPlaybackRate(rate);
    await player.resume();
    // resolve when the clip ends (shadowing records right after it); give up after 20 s
    await Future.any<void>([
      ended,
      Future<void>.delayed(const Duration(seconds: 20)),
    ]);
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
    home: _FirstRun(services: services),
  );
}

/// The setup screen once, for someone who has not read anything yet; then Home.
class _FirstRun extends StatefulWidget {
  const _FirstRun({required this.services});
  final AppServices services;

  @override
  State<_FirstRun> createState() => _FirstRunState();
}

class _FirstRunState extends State<_FirstRun> {
  late bool _setup =
      !widget.services.prefs.onboarded && widget.services.learner.known.isEmpty;

  @override
  Widget build(BuildContext context) => _setup
      ? OnboardingScreen(
          services: widget.services,
          onDone: () => setState(() => _setup = false),
        )
      : HomeScreen(services: widget.services);
}
