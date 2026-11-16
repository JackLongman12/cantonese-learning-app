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

  /// Steps of Today's plan finished on [day] ('2026-11-15').
  Set<String> planDone(String day) {
    final m = _data['plan_done'];
    return m is Map && m['day'] == day
        ? {...(m['steps'] as List? ?? const []).cast<String>()}
        : <String>{};
  }

  void markPlanDone(String day, String step) => _set('plan_done', {
    'day': day,
    'steps': [...planDone(day), step],
  });

  /// The daily reminder was offered once after the first session.
  bool get reminderOffered => _data['reminder_offered'] == true;
  set reminderOffered(bool v) => _set('reminder_offered', v);

  /// What the learner wants to do with Cantonese (engine/goals.dart); null = not asked yet.
  String? get goal => _data['goal'] as String?;
  set goal(String? v) => _set('goal', v);

  /// First-run setup done (how much you can read; how the reader works).
  bool get onboarded => _data['onboarded'] == true;
  set onboarded(bool v) => _set('onboarded', v);

  /// Speaks Cantonese already (reads to learn the characters for words they know) or is
  /// learning the language too. Null: not asked (installs from before 2026-11-17 were
  /// all speakers). Sets what help and meanings the reader shows.
  bool? get speaker => _data['speaker'] as bool?;
  set speaker(bool? v) => _set('speaker', v);
  bool get isSpeaker => level == 'fluent';

  /// Which kind of learner (onboarding, 2026-11-17): 'new' (new to Cantonese), 'some'
  /// (knows a little) or 'fluent' (speaks it, can't read). The first two get newcomer
  /// mode: situations and English-first drills (Home B); 'fluent' gets the reading app
  /// (Home A). Installs from before the question: from [speaker].
  String get level =>
      _data['level'] as String? ?? (speaker == false ? 'some' : 'fluent');
  set level(String v) {
    _set('level', v);
    speaker = v == 'fluent';
  }

  bool get newcomerMode => level != 'fluent';

  /// Situations a newcomer is working on (deck ids, in the order shown).
  List<String> get situations =>
      (_data['situations'] as List?)?.cast<String>() ?? const [];
  set situations(List<String> v) => _set('situations', v);

  /// Anonymous usage and crash reports (docs/TELEMETRY.md). Null: not asked yet;
  /// nothing is sent until this is true.
  bool? get shareData => _data['share_data'] as bool?;
  set shareData(bool? v) => _set('share_data', v);

  /// Random id sent with shared data instead of the device id; a new one each time
  /// sharing is turned on, so turning it off and on starts a fresh, unlinked record.
  String? get telemetryId => _data['telemetry_id'] as String?;
  set telemetryId(String? v) => _set('telemetry_id', v);

  /// Sharing was turned on at some point (history is only sent the first time).
  bool get sharedBefore => _data['shared_before'] == true;
  set sharedBefore(bool v) => _set('shared_before', v);

  /// The experiment arms last logged (`experiment.assigned` once per change).
  String? get armsLogged => _data['arms_logged'] as String?;
  set armsLogged(String? v) => _set('arms_logged', v);

  /// Soft UI sounds on taps, next, save, results (on by default).
  bool get soundEffects => _data['sound_effects'] != false;
  set soundEffects(bool v) => _set('sound_effects', v);

  /// Play each sentence's audio as soon as it appears (on by default).
  bool get autoPlay => _data['auto_play'] != false;
  set autoPlay(bool v) => _set('auto_play', v);

  /// Sentences in the phone's own Cantonese voice (on by default): it reads tones the
  /// way people say them, like the word you tap. Off: the recorded voice.
  bool get phoneVoice => _data['phone_voice'] != false;
  set phoneVoice(bool v) => _set('phone_voice', v);

  /// Which of the phone's Cantonese voices (its engine name); null = the phone's default.
  String? get voiceName => _data['voice_name'] as String?;
  set voiceName(String? v) => _set('voice_name', v);

  /// Stories start in read-along mode.

  /// Daily reminder: off by default; null minute = use the learned usual time.
  bool get reminderOn => _data['reminder_on'] == true;
  set reminderOn(bool v) => _set('reminder_on', v);
  int? get reminderMinute => (_data['reminder_minute'] as num?)?.toInt();
  set reminderMinute(int? v) => _set('reminder_minute', v);

  /// A session left part-way: offered as "Resume" on the home screen.
  Map<String, Object?>? get resume =>
      (_data['resume'] as Map?)?.cast<String, Object?>();
  set resume(Map<String, Object?>? v) => _set('resume', v);

  void _set(String key, Object? value) {
    _data[key] = value;
    final f = file;
    if (f == null) return;
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(_data));
  }
}
