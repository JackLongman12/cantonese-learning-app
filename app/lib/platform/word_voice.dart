/// Says single words with the device's own text-to-speech (Android: Google's
/// "Cantonese (Hong Kong)" voice; Windows: a zh-HK voice if installed). Whole sentences
/// and card names use the recorded audio instead; this is for any word you tap.
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

  /// False when no Cantonese voice is installed.
  Future<bool> say(String text) async {
    if (!await _init()) return false;
    await _tts.stop();
    await _tts.speak(text);
    return true;
  }
}
