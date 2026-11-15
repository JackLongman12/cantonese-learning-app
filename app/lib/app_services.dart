/// Everything the screens need, built once at start-up and passed down explicitly.
library;

import 'data/content_db.dart';
import 'data/prefs.dart';
import 'engine/learner_model.dart';
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

class AppServices {
  AppServices({
    required this.content,
    required this.logger,
    required this.learner,
    required this.memory,
    required this.playAudio,
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
  }) : prefs = prefs ?? Prefs.memory(),
       shares = shares ?? ShareInbox() {
    logger.addListener(learner.apply);
    logger.addListener((e) => words.apply(e));
  }

  /// Words saved from reading ("My words"), rebuilt from the event log.
  late final WordBook words = WordBook.replay(logger.store.readAll());

  final ContentDb content;
  final EventLogger logger;
  final LearnerModel learner;
  final Memory memory;
  final PlayAudio playAudio;

  /// On-device recogniser for the read-aloud check (null where unavailable).
  final SpeechEngine? speech;
  final PlayFile? playFile;
  final Prefs prefs;
  final ShareInbox shares;

  /// Checks GitHub Releases for a newer build (null in tests).
  final Updater? updater;

  /// Daily reminder (Android; null in tests).
  final Reminders? reminders;

  /// Device text-to-speech for single words (null in tests).
  final WordVoice? voice;

  /// Says a word: the recorded clip when there is one (card names, sentences),
  /// otherwise the device's Cantonese voice. False if neither is available.
  Future<bool> sayWord(String text, String lang) async {
    final path = content.audioPath(lang, text);
    if (path != null) {
      await playAudio(path);
      return true;
    }
    return await voice?.say(text) ?? false;
  }

  /// The "no Cantonese voice" notice is shown once per launch.
  bool voiceNoticeShown = false;

  /// UI sounds (null in tests).
  final SoundEffects? sfx;

  /// Plays a UI sound unless the learner turned them off.
  void sound(Sfx s) {
    if (prefs.soundEffects) sfx?.play(s);
  }

  /// Fade rules, shifted by the learner's "Jyutping help" setting.
  ScaffoldPolicy get scaffold => ScaffoldPolicy(shift: prefs.helpShift);
  final SignalPolicy signals;
  final Planner planner;
}
