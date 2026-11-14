/// Decides when the learner has finished reading a sentence aloud, so recording can
/// stop by itself. Energy-based: it learns the room's noise floor from the first
/// moments, waits for speech, then ends after a pause.
library;

import 'dart:math' as math;
import 'dart:typed_data';

class EndOfSpeech {
  EndOfSpeech({
    this.sampleRate = 16000,
    this.pause = const Duration(milliseconds: 900),
    this.minSpeech = const Duration(milliseconds: 300),
    this.noSpeechTimeout = const Duration(seconds: 7),
    this.maxLength = const Duration(seconds: 20),
  });

  final int sampleRate;

  /// Silence after speech that counts as "finished".
  final Duration pause;

  /// Speech shorter than this (a cough, a click) does not count.
  final Duration minSpeech;

  /// Give up if nothing is said for this long.
  final Duration noSpeechTimeout;

  /// Hard stop, whatever happens.
  final Duration maxLength;

  static const _frameMs = 30;
  int get _frame => sampleRate * _frameMs ~/ 1000;

  final _pending = <double>[];
  double? _floor;
  int _frames = 0;
  int _speechFrames = 0;
  int _silentRun = 0;
  bool _done = false;

  /// True once speech was heard (otherwise the attempt was empty).
  bool get heardSpeech => _speechFrames * _frameMs >= minSpeech.inMilliseconds;

  bool get done => _done;

  /// Feeds float samples in [-1, 1]; returns true when recording should stop.
  bool add(Float32List samples) {
    if (_done) return true;
    _pending.addAll(samples);
    while (_pending.length >= _frame && !_done) {
      var sum = 0.0;
      for (var i = 0; i < _frame; i++) {
        sum += _pending[i] * _pending[i];
      }
      _pending.removeRange(0, _frame);
      _step(math.sqrt(sum / _frame));
    }
    return _done;
  }

  void _step(double rms) {
    _frames++;
    // noise floor: tracks quiet frames quickly, loud ones very slowly
    final floor = _floor ??= rms;
    _floor = rms < floor
        ? floor * 0.8 + rms * 0.2
        : floor * 0.995 + rms * 0.005;
    final threshold = math.max(_floor! * 3, 0.015);
    final ms = _frames * _frameMs;
    if (rms > threshold) {
      _speechFrames++;
      _silentRun = 0;
    } else {
      _silentRun++;
    }
    if (heardSpeech && _silentRun * _frameMs >= pause.inMilliseconds) {
      _done = true;
    }
    if (!heardSpeech && ms >= noSpeechTimeout.inMilliseconds) _done = true;
    if (ms >= maxLength.inMilliseconds) _done = true;
  }
}
