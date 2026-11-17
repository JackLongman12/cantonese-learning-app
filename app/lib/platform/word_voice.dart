/// Says words and sentences with the device's own text-to-speech (Android: Google's
/// "Cantonese (Hong Kong)" voice, an online one by default; Windows: a zh-HK voice if
/// installed). Sentences use it unless the learner picks the recorded voice (Settings):
/// the recorded voice reads some
/// words in their dictionary tone rather than the one people say.
library;

import 'package:flutter_tts/flutter_tts.dart';

/// One of the phone's Cantonese voices.
class PhoneVoice {
  const PhoneVoice(this.name, this.locale, {this.online = false, this.quality});
  final String name;
  final String locale;

  /// Needs the internet (Google's online voices usually sound better).
  final bool online;

  /// The engine's own rating ('very high', 'high', ...), if it gives one.
  final String? quality;
}

class WordVoice {
  final _tts = FlutterTts();
  bool? _ready;
  String? _locale;

  /// The voice to use (a [PhoneVoice.name]); null = the phone's default.
  String? wanted;
  String? _applied;

  /// Locale names differ between engines; the first one available wins.
  static const _locales = ['yue-HK', 'zh-HK', 'yue_HK', 'zh_HK'];

  Future<bool> _init() async {
    if (_ready != null) return _ready!;
    try {
      for (final l in _locales) {
        if (await _tts.isLanguageAvailable(l) == true) {
          await _tts.setLanguage(l);
          _locale = l;
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

  /// Every Cantonese voice the phone's engine offers (online ones first).
  Future<List<PhoneVoice>> voices() async {
    if (!await _init()) return const [];
    try {
      final raw = await _tts.getVoices as List<Object?>? ?? const [];
      final out = <PhoneVoice>[];
      for (final v in raw.whereType<Map<Object?, Object?>>()) {
        final name = '${v['name'] ?? ''}';
        final locale = '${v['locale'] ?? ''}';
        final l = locale.toLowerCase().replaceAll('_', '-');
        if (name.isEmpty || !(l.startsWith('yue') || l == 'zh-hk')) continue;
        out.add(
          PhoneVoice(
            name,
            locale,
            online: '${v['network_required']}' == '1',
            quality: switch ('${v['quality'] ?? ''}') {
              'very high' || 'veryHigh' || 'VERY_HIGH' => 'very high',
              'high' || 'HIGH' => 'high',
              'normal' || 'NORMAL' => 'normal',
              'low' || 'LOW' || 'very low' || 'VERY_LOW' => 'low',
              _ => null,
            },
          ),
        );
      }
      out.sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      return out;
    } on Object {
      return const [];
    }
  }

  /// The voice used when the learner hasn't picked one (owner, 2026-11-17): "Phone voice
  /// 2 (online)" in the picker, i.e. the second voice of [voices] (online first, then by
  /// name) when it is online; else the first online voice; else the engine's default.
  /// Offline, Google's engine falls back to its built-in voice itself.
  static PhoneVoice? defaultVoice(List<PhoneVoice> all) {
    if (all.length > 1 && all[1].online) return all[1];
    return all.where((v) => v.online).firstOrNull;
  }

  Future<void> _apply() async {
    if (_applied == (wanted ?? '')) return;
    final all = await voices();
    final v = wanted == null
        ? defaultVoice(all)
        : all.where((x) => x.name == wanted).firstOrNull;
    if (v != null) {
      await _tts.setVoice({'name': v.name, 'locale': v.locale});
    } else if (_locale != null) {
      await _tts.setLanguage(_locale!); // back to the engine's default voice
    }
    _applied = wanted ?? '';
  }

  Future<bool> _say(String text, double rate) async {
    if (!await _init()) return false;
    await _tts.stop();
    try {
      await _apply();
    } on Object {
      // keep whatever voice the engine has
    }
    await _tts.setSpeechRate(rate);
    await _tts.speak(text);
    return true;
  }
}
