/// Everything the screens need, built once at start-up and passed down explicitly.
library;

import 'data/content_db.dart';
import 'data/prefs.dart';
import 'engine/learner_model.dart';
import 'engine/memory.dart';
import 'engine/planner.dart';
import 'engine/scaffold.dart';
import 'engine/signals.dart';
import 'events/event_logger.dart';
import 'platform/reminders.dart';
import 'platform/share_inbox.dart';
import 'platform/updater.dart';
import 'platform/speech.dart';

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
    this.signals = const SignalPolicy(),
    this.planner = const Planner(),
  }) : prefs = prefs ?? Prefs.memory(),
       shares = shares ?? ShareInbox() {
    logger.addListener(learner.apply);
  }

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

  /// Fade rules, shifted by the learner's "Jyutping help" setting.
  ScaffoldPolicy get scaffold => ScaffoldPolicy(shift: prefs.helpShift);
  final SignalPolicy signals;
  final Planner planner;
}
