/// Everything the screens need, built once at start-up and passed down explicitly.
library;

import 'dart:io';
import 'dart:math';

import 'data/content_db.dart';
import 'data/prefs.dart';
import 'engine/learner_model.dart';
import 'engine/insights.dart' as insights;
import 'engine/memory.dart';
import 'engine/planner.dart';
import 'engine/scaffold.dart';
import 'engine/signals.dart';
import 'engine/word_book.dart';
import 'events/event_logger.dart';
import 'platform/reminders.dart';
import 'platform/sfx.dart';
import 'platform/share_inbox.dart';
import 'platform/updater.dart';
import 'platform/speech.dart';
import 'platform/word_voice.dart';

/// Plays a bundled clip. Implemented outside the engine so tests need no audio device.
typedef PlayAudio = Future<void> Function(String assetRelativePath);

/// Plays a file on disk (the learner's own recording).
typedef PlayFile = Future<void> Function(String path);

/// What a finish screen needs from Home: the next step of today's plan, starting it,
/// and opening one of the tools. Each goes back to Home first.
class HomeLink {
  const HomeLink({
    required this.next,
    required this.startNext,
    required this.openTool,
  });
  final ({String title, int number})? Function() next;
  final void Function() startNext;
  final void Function(String tool) openTool;
}

class AppServices {
  AppServices({
    required this.content,
    required this.logger,
    required this.learner,
    required this.memory,
    required PlayAudio playAudio,
    PlayAudio? playAudioSlow,
    this.stopAudio,
    this.speech,
    this.playFile,
    Prefs? prefs,
    ShareInbox? shares,
    this.updater,
    this.reminders,
    this.sfx,
    this.voice,
    this.signals = const SignalPolicy(),
    this.planner = const Planner(),
  }) : _playAudio = playAudio, // ignore: prefer_initializing_formals
       _playAudioSlow = playAudioSlow, // ignore: prefer_initializing_formals
       prefs = prefs ?? Prefs.memory(),
       shares = shares ?? ShareInbox() {
    voice?.wanted = this.prefs.voiceName;
    // starting the mic silences whatever is playing
    speech?.beforeRecording = () async => stopAudio?.call();
    logger.addListener(learner.apply);
    logger.addListener((e) => words.apply(e));
  }

  /// Words saved from reading ("My words"), rebuilt from the event log.
  late final WordBook words = WordBook.replay(logger.store.readAll());

  /// A fresh shuffle for picking what to study, so sessions vary. Fixed under tests so
  /// previews and flows stay the same run to run.
  Random get variety => _inTest ? Random(0) : Random();
  static final _inTest = Platform.environment.containsKey('FLUTTER_TEST');

  /// How much randomness the planner may add (less than one due item).
  static const plannerJitter = 0.5;

  /// Sentences read or said in the last two days (next sessions prefer others).
  Set<String> recentSentences() =>
      insights.recentSentences(logger.store.readAll(), logger.now().toUtc());

  final ContentDb content;
  final EventLogger logger;
  final LearnerModel learner;
  final Memory memory;
  final PlayAudio _playAudio;
  final PlayAudio? _playAudioSlow;

  /// True while the mic records: nothing plays then (it would be recorded too).
  bool get micBusy => speech?.recording ?? false;

  /// Plays a clip, unless the mic is recording.
  PlayAudio get playAudio => (path) async {
    if (micBusy) return;
    await _playAudio(path);
  };

  /// Plays a clip at reduced speed (null in tests: falls back to [playAudio]).
  PlayAudio? get playAudioSlow => _playAudioSlow == null
      ? null
      : (path) async {
          if (micBusy) return;
          await _playAudioSlow(path);
        };

  /// Silences every clip and the word voice (null in tests).
  final Future<void> Function()? stopAudio;

  int _playback = 0;

  /// Changes whenever playback is cancelled; a sequence (your attempt, then the
  /// native) checks it between clips and stops if it moved.
  int get playbackToken => _playback;

  /// Next / leaving: stop what is playing and anything queued to play after it.
  Future<void> silence() async {
    _playback++;
    await stopAudio?.call();
  }

  /// On-device recogniser for the read-aloud check (null where unavailable).
  final SpeechEngine? speech;
  final PlayFile? playFile;
  final Prefs prefs;
  final ShareInbox shares;

  /// Checks GitHub Releases for a newer build (null in tests).
  final Updater? updater;

  /// Daily reminder (Android; null in tests).
  final Reminders? reminders;

  /// Device text-to-speech: tapped words, and sentences unless the learner picks the
  /// recorded voice (null in tests).
  final WordVoice? voice;

  /// Says a word: the device's Cantonese voice (unless the learner picked the recorded
  /// voice), else a recorded clip of it. False if neither is available.
  Future<bool> sayWord(String text, String lang) async {
    if (micBusy) return true;
    if (prefs.phoneVoice && (await voice?.say(text) ?? false)) return true;
    final path = content.audioPath(lang, text);
    if (path != null) {
      await playAudio(path);
      return true;
    }
    return await voice?.say(text) ?? false;
  }

  /// Plays a sentence (or a card name): the phone's Cantonese voice when the learner
  /// keeps that setting and one is installed, otherwise the recorded clip. False if
  /// neither exists.
  Future<bool> saySentence(String text, {bool slow = false}) async {
    if (micBusy) return true;
    final v = voice;
    if (prefs.phoneVoice && v != null && await v.sayLine(text, slow: slow)) {
      return true;
    }
    final path = content.audioPath('yue', text);
    if (path == null) return false;
    await (slow ? (playAudioSlow ?? playAudio) : playAudio)(path);
    return true;
  }

  /// Can [saySentence] play [text]?
  Future<bool> canSay(String text) async =>
      content.audioPath('yue', text) != null ||
      (prefs.phoneVoice && (await voice?.available ?? false));

  /// Home's plan and tools, for finish screens deep in the app (null until Home shows).
  HomeLink? home;

  /// Silent recordings in a row (two: ask "can't speak right now?").
  int speechSilences = 0;

  /// The "no Cantonese voice" notice is shown once per launch.
  bool voiceNoticeShown = false;

  /// UI sounds (null in tests).
  final SoundEffects? sfx;

  /// Plays a UI sound unless the learner turned them off.
  void sound(Sfx s) {
    // only moving on and finishing make a sound: anything more is noise
    if (prefs.soundEffects && (s == Sfx.next || s == Sfx.finish)) sfx?.play(s);
  }

  /// Fade rules, shifted by the learner's "Jyutping help" setting.
  ScaffoldPolicy get scaffold => ScaffoldPolicy(shift: prefs.helpShift);
  final SignalPolicy signals;
  final Planner planner;
}
