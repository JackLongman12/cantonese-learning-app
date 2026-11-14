/// Small per-device preferences (a JSON file next to the event log): what to show when
/// the app opens. Changes are also logged as `settings.change` events by the UI.
library;

import 'dart:convert';
import 'dart:io';

class Prefs {
  Prefs(File this.file) {
    final f = file!;
    if (f.existsSync()) {
      try {
        _data.addAll(
          (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>(),
        );
      } on Object {
        // a corrupt prefs file only loses conveniences; start fresh
      }
    }
  }

  /// In-memory only (tests).
  Prefs.memory() : file = null;

  final File? file;
  final Map<String, Object?> _data = {};

  /// Cantonese only (the Mandarin track was dropped, 2026-11-15).
  String get lang => 'yue';

  /// Sentences per daily session.
  int get sessionLength => (_data['session_length'] as num?)?.toInt() ?? 15;
  set sessionLength(int v) => _set('session_length', v);

  /// Last topic opened, per language: shown as "Continue" on the home screen.
  String? lastTopic(String lang) => _data['last_topic_$lang'] as String?;
  void setLastTopic(String lang, String scenarioId) =>
      _set('last_topic_$lang', scenarioId);

  /// Jyutping help: +1 more, 0 normal, -1 less (shifts every character's fade level).
  int get helpShift => (_data['help_shift'] as num?)?.toInt() ?? 0;
  set helpShift(int v) => _set('help_shift', v);

  /// Reader text size multiplier.
  double get textScale => (_data['text_scale'] as num?)?.toDouble() ?? 1.0;
  set textScale(double v) => _set('text_scale', v);

  /// Soft UI sounds on taps, next, save, results (on by default).
  bool get soundEffects => _data['sound_effects'] != false;
  set soundEffects(bool v) => _set('sound_effects', v);

  /// Play each sentence's audio as soon as it appears (on by default).
  bool get autoPlay => _data['auto_play'] != false;
  set autoPlay(bool v) => _set('auto_play', v);

  /// Stories start in read-along mode.
  bool get readAlong => _data['read_along'] == true;
  set readAlong(bool v) => _set('read_along', v);

  /// Offer to read copied Chinese text when the app opens.
  bool get clipboardPrompt => _data['clipboard_prompt'] != false;
  set clipboardPrompt(bool v) => _set('clipboard_prompt', v);

  /// Daily reminder: off by default; null minute = use the learned usual time.
  bool get reminderOn => _data['reminder_on'] == true;
  set reminderOn(bool v) => _set('reminder_on', v);
  int? get reminderMinute => (_data['reminder_minute'] as num?)?.toInt();
  set reminderMinute(int? v) => _set('reminder_minute', v);

  /// A session left part-way: offered as "Resume" on the home screen.
  Map<String, Object?>? get resume =>
      (_data['resume'] as Map?)?.cast<String, Object?>();
  set resume(Map<String, Object?>? v) => _set('resume', v);

  /// Clipboard text already offered, so the same copy is not suggested twice.
  String? get lastClipboardOffer => _data['last_clipboard'] as String?;
  set lastClipboardOffer(String? v) => _set('last_clipboard', v);

  void _set(String key, Object? value) {
    _data[key] = value;
    final f = file;
    if (f == null) return;
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(_data));
  }
}
