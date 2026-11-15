/// Says words and sentences with the device's own text-to-speech (Android: Google's
/// "Cantonese (Hong Kong)" voice; Windows: a zh-HK voice if installed). Sentences use it
/// unless the learner picks the recorded voice (Settings): the recorded voice reads some
/// words in their dictionary tone rather than the one people say.
library;

import 'package:flutter_tts/flutter_tts.dart';

class WordVoice {
  final _tts = FlutterTts();
  bool? _ready;

  /// Locale names differ between engines; the first one available wins.
  static const _locales = ['yue-HK', 'zh-HK', 'yue_HK', 'zh_HK'];

  Future<bool> _init() async {
    if (_ready != null) return _ready!;
    try {
      for (final l in _locales) {
        if (await _tts.isLanguageAvailable(l) == true) {
          await _tts.setLanguage(l);
          await _tts.setSpeechRate(0.42);
          await _tts.awaitSpeakCompletion(true);
          return _ready = true;
        }
      }
    } on Object {
      // no engine at all
    }
    return _ready = false;
  }

  Future<void> stop() async {
    if (_ready == true) await _tts.stop();
  }

  /// False when no Cantonese voice is installed.
  Future<bool> say(String text) => _say(text, 0.42);

  /// A whole sentence at talking speed (or slowed down); waits until it is said.
  Future<bool> sayLine(String text, {bool slow = false}) =>
      _say(text, slow ? 0.32 : 0.5);

  /// Is there a Cantonese voice on this device?
  Future<bool> get available => _init();

  Future<bool> _say(String text, double rate) async {
    if (!await _init()) return false;
    await _tts.stop();
    await _tts.setSpeechRate(rate);
    await _tts.speak(text);
    return true;
  }
}
