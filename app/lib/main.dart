import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ulid/ulid.dart';

import 'app_services.dart';
import 'data/content_db.dart';
import 'data/prefs.dart';
import 'engine/experiments.dart';
import 'engine/learner_model.dart';
import 'engine/memory.dart';
import 'events/event_logger.dart';
import 'events/event_store.dart';
import 'platform/reminders.dart';
import 'platform/sfx.dart';
import 'platform/storage.dart';
import 'platform/telemetry.dart';
import 'platform/speech.dart';
import 'platform/word_voice.dart';
import 'platform/updater.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/theme.dart';
import 'ui/visual_novel.dart' show characterPictures;
import 'platform/character_pictures.dart';
import 'platform/word_photos.dart';
import 'ui/word_picture.dart' show wordPhotos;

const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0-dev',
);
const _contentAsset = 'assets/content/content.db';
const _contentStamp = 'assets/content/content.stamp';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // credits shown on Settings → About DuckLearn (the license page)
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['DuckLearn word icons'],
      'Icons by OpenMoji (https://openmoji.org), the open-source emoji and icon '
      'project. License: CC BY-SA 4.0.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['DuckLearn word photos'],
      'Photos from Wikimedia Commons, downloaded when first shown. The author and license '
      'of each photo are shown under it in the drill.',
    );
    // the data the content is built from (data/raw/SOURCES.lock.json); these licences
    // ask for credit (2026-11-17 launch check)
    yield const LicenseEntryWithLineBreaks(
      ['DuckLearn dictionary data'],
      'Meanings and readings from CC-CEDICT (https://cc-cedict.org, CC BY-SA 4.0) and '
      'CC-Canto with its Jyutping for CC-CEDICT (https://cantonese.org, Pleco, '
      'CC BY-SA 3.0); readings from rime-cantonese (CanCLID, CC BY 4.0) and the Unihan '
      'database (Unicode License v3); how words are said and how common they are from '
      'HKCanCor via PyCantonese (CC BY 4.0). The readings in DuckLearn are adapted from '
      'these and shared under the same terms.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['DuckLearn place names'],
      'Street and place names in Macau and Hong Kong: © OpenStreetMap contributors, '
      'available under the Open Database License (https://www.openstreetmap.org/copyright).',
    );
    yield const LicenseEntryWithLineBreaks(
      ['DuckLearn speech check'],
      'The read-aloud check runs the SenseVoiceSmall model by Alibaba Group '
      '(FunAudioLLM/SenseVoiceSmall, FunASR Model Open Source License 1.1, '
      'https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE), converted for '
      'sherpa-onnx by csukuangfj. It is downloaded on first use and runs on the device.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['DuckLearn dish names'],
      'Dish names in the food flashcards are from Cantonese Wikipedia '
      '(https://zh-yue.wikipedia.org) and the English names from English Wikipedia, '
      'CC BY-SA 4.0. The author and license of each dish photo (Wikimedia Commons) are '
      'shown on its card.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['DuckLearn conversation pictures'],
      'Conversation characters are illustrations by いらすとや (Irasutoya, '
      'https://www.irasutoya.com), downloaded from irasutoya.com on first use and used '
      'under its terms for non-commercial use. They are not part of DuckLearn.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['DuckLearn recorded voice'],
      'The recorded voice clips were made with Microsoft Edge\'s read-aloud voice '
      '(zh-HK-HiuMaanNeural) through the open-source edge-tts tool. DuckLearn is not '
      'affiliated with or endorsed by Microsoft.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['LXGW WenKai TC'],
      'LXGW WenKai TC, Copyright 2024 The LXGW WenKai Project Authors '
      '(https://github.com/lxgw/LxgwWenkaiTC). Subset to '
      'the characters DuckLearn uses. Licensed under the SIL Open Font License, '
      'Version 1.1 (https://openfontlicense.org).',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Noto Sans HK'],
      'Noto Sans HK, (c) 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font '
      'Name \'Source\'. Subset to the characters DuckLearn uses. Licensed under the SIL '
      'Open Font License, Version 1.1 (https://openfontlicense.org).',
    );
  });
  // one fixed folder for the audio player's clip copies, reused across launches
  AudioCache.instance = AudioCache(prefix: 'assets/', cacheId: audioCacheId);
  final services = await _bootstrap();
  final telemetry = services.telemetry!;
  // Crashes are kept on the device and sent only if the learner agreed to share.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    telemetry.recordCrash(details.exception, details.stack, where: 'flutter');
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    telemetry.recordCrash(error, stack, where: 'async');
    return false; // still reported the usual way
  };
  // send what is new now and whenever the app goes to the background
  final schedule = TelemetrySchedule(telemetry)..start();
  AppLifecycleListener(
    onPause: () {
      schedule.stop();
      unawaited(telemetry.upload());
    },
    onResume: () {
      schedule.start();
      unawaited(telemetry.upload());
    },
  );
  Future<void>.delayed(const Duration(seconds: 10), telemetry.upload).ignore();
  runApp(DukApp(services: services));
}

Future<AppServices> _bootstrap() async {
  final support = await getApplicationSupportDirectory();

  // The bundled content database is copied out of the app: it is read-only and replaced
  // wholesale, and progress never lives in it (docs/DESIGN.md section 4.2).
  final dbFile = File(p.join(support.path, 'content.db'));
  // Copied only when the bundled database changed (a new release): its fingerprint is
  // kept next to the copy. Saves reading and writing 20+ MB on every launch.
  final stampFile = File(p.join(support.path, 'content.stamp'));
  String? stamp;
  try {
    stamp = (await rootBundle.loadString(_contentStamp)).trim();
  } on Object {
    stamp = null; // an older bundle without a stamp: always copy
  }
  final fresh =
      stamp != null &&
      dbFile.existsSync() &&
      stampFile.existsSync() &&
      stampFile.readAsStringSync().trim() == stamp;
  if (!fresh) {
    final bytes = await rootBundle.load(_contentAsset);
    await dbFile.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    if (stamp != null) stampFile.writeAsStringSync(stamp, flush: true);
  }
  final content = ContentDb.open(dbFile.path);

  // Conversation pictures: downloaded here, never bundled (content/characters.yaml).
  // In the background, after start-up; a failure just leaves the coloured initials.
  final pictures = CharacterPictures(
    Directory(p.join(support.path, 'characters')),
  );
  characterPictures = pictures;
  // newcomer word photos: downloaded when first shown, kept in their own folder
  wordPhotos = WordPhotos(Directory(p.join(support.path, 'word_photos')));
  Future<void>.delayed(
    const Duration(seconds: 3),
    () => pictures.fetchMissing(content.characterPictureUrls()),
  ).ignore();

  // Leftovers from an earlier update (installer, unpack folders) are junk once it ran.
  try {
    final temp = await getTemporaryDirectory();
    Updater.cleanUp(temp);
    // audio player copies from earlier launches, old voice recordings
    cleanTemp(temp);
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
  final prefs = Prefs(File(p.join(support.path, 'prefs.json')));
  // which A/B arm this install is in, logged whenever the set of experiments changes
  final arms = jsonEncode(armsFor(deviceId));
  if (prefs.armsLogged != arms) {
    logger.log('experiment.assigned', {'arms': armsFor(deviceId)});
    prefs.armsLogged = arms;
  }
  final telemetry = Telemetry(
    prefs: prefs,
    eventDir: Directory(p.join(support.path, 'events', deviceId)),
    stateDir: support,
    appVersion: appVersion,
  );

  return AppServices(
    content: content,
    logger: logger,
    learner: learner,
    memory: memory,
    playAudio: createPlayAudio(),
    // "Slow": the same clip at 75% (pitch kept), instead of a second recording
    playAudioSlow: createPlayAudio(rate: 0.75),
    // the learner's own recording; resolves when it ends (to play the native after)
    playFile: (path) async {
      await _filePlayer.stop();
      // a stop (Next, leaving) ends the wait too
      final ended = Future.any<void>([
        _filePlayer.onPlayerComplete.first.then<void>((_) {}),
        _filePlayer.onPlayerStateChanged
            .firstWhere((s) => s == PlayerState.stopped)
            .then<void>((_) {}),
      ]);
      await _filePlayer.play(DeviceFileSource(path));
      await Future.any<void>([
        ended,
        Future<void>.delayed(const Duration(seconds: 15)),
      ]);
    },
    prefs: prefs,
    telemetry: telemetry,
    updater: Updater(),
    sfx: SoundEffects(),
    stopAudio: () async {
      await stopAllAudio();
      await _voice.stop();
    },
    voice: _voice,
    reminders: Platform.isAndroid ? Reminders() : null,
    speech: (Platform.isAndroid || Platform.isWindows || Platform.isMacOS)
        ? SpeechEngine(modelDir)
        : null,
  );
}

/// Plays a clip bundled under `assets/content/`. One player, so a new clip replaces the
/// one still playing.
final _filePlayer = AudioPlayer();

/// Every player that speaks Cantonese, so leaving a screen can silence them all.
final _players = <AudioPlayer>[_filePlayer];

Future<void> stopAllAudio() async {
  for (final p in _players) {
    await p.stop();
  }
}

PlayAudio createPlayAudio({double rate = 1.0}) {
  final player = AudioPlayer();
  _players.add(player);
  return (path) async {
    await player.stop();
    // listen before playing so a very short clip's end is not missed; a stop (leaving
    // the screen) also ends the wait
    final ended = Future.any<void>([
      player.onPlayerComplete.first.then<void>((_) {}),
      player.onPlayerStateChanged
          .firstWhere((s) => s == PlayerState.stopped)
          .then<void>((_) {}),
    ]);
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

final _voice = WordVoice();

/// Leaving a screen (Android back or the app's back arrow) stops its audio at once.
class StopAudioOnLeave extends NavigatorObserver {
  StopAudioOnLeave(this.services);
  final AppServices services;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      services.silence();
      services.speech?.cancel();
    }
  }
}

class DukApp extends StatelessWidget {
  const DukApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DuckLearn',
    debugShowCheckedModeBanner: false,
    navigatorObservers: [StopAudioOnLeave(services)],
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
