/// Short UI sounds (assets/sfx, synthesised by tool/make_sfx.py). They mix with
/// other audio and never take audio focus, so a tap never cuts off a sentence.
library;

import 'package:audioplayers/audioplayers.dart';

enum Sfx { tap, reveal, next, save, good, tryAgain, finish, quack, mic }

class SoundEffects {
  SoundEffects() {
    for (var i = 0; i < _players.length; i++) {
      _players[i] = AudioPlayer()
        ..setPlayerMode(PlayerMode.lowLatency)
        ..setAudioContext(
          AudioContextConfig(
            focus: AudioContextConfigFocus.mixWithOthers,
            respectSilence: true, // silent mode on iOS/macOS mutes them
          ).build(),
        )
        ..setVolume(0.6);
    }
  }

  // a few players, round robin, so quick taps overlap instead of cutting each other
  final _players = List<AudioPlayer?>.filled(3, null);
  var _next = 0;

  static String _file(Sfx s) => switch (s) {
    Sfx.tryAgain => 'sfx/try.wav',
    _ => 'sfx/${s.name}.wav',
  };

  void play(Sfx s) {
    final p = _players[_next]!;
    _next = (_next + 1) % _players.length;
    p.stop().then((_) => p.play(AssetSource(_file(s)))).ignore();
  }
}
