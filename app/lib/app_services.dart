/// Everything the screens need, built once at start-up and passed down explicitly.
library;

import 'data/content_db.dart';
import 'engine/learner_model.dart';
import 'engine/memory.dart';
import 'engine/planner.dart';
import 'engine/scaffold.dart';
import 'engine/signals.dart';
import 'events/event_logger.dart';

/// Plays a bundled clip. Implemented outside the engine so tests need no audio device.
typedef PlayAudio = Future<void> Function(String assetRelativePath);

class AppServices {
  AppServices({
    required this.content,
    required this.logger,
    required this.learner,
    required this.memory,
    required this.playAudio,
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
  final ScaffoldPolicy scaffold;
  final SignalPolicy signals;
  final Planner planner;
}
