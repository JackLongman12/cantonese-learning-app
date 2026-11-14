/// Everything the screens need, built once at start-up and passed down explicitly.
library;

import 'data/content_db.dart';
import 'engine/learner_model.dart';
import 'engine/memory.dart';
import 'engine/planner.dart';
import 'engine/scaffold.dart';
import 'engine/signals.dart';
import 'events/event_logger.dart';
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
    this.scaffold = const ScaffoldPolicy(),
    this.signals = const SignalPolicy(),
    this.planner = const Planner(),
  }) {
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
  final ScaffoldPolicy scaffold;
  final SignalPolicy signals;
  final Planner planner;
}
