/// Settings: everything a learner might want to change, in one place.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_services.dart';
import '../engine/insights.dart';
import '../platform/sfx.dart';
import '../platform/speech.dart';
import 'ruby_text.dart';
import 'update_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  String? _updateStatus;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) {
        setState(() => _version = '${i.version} (build ${i.buildNumber})');
      }
    }).ignore();
  }

  void _changed(String key, Object? from, Object? to) {
    _s.logger.log('settings.change', {'key': key, 'from': from, 'to': to});
    setState(() {});
  }

  int _reminderMinute() =>
      _s.prefs.reminderMinute ??
      usualStudyMinute(
        _s.logger.store.readAll(),
        now: _s.logger.now().toUtc(),
      ) ??
      20 * 60;

  String _clock(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _checkUpdate() async {
    final u = _s.updater;
    if (u == null) return;
    setState(() => _updateStatus = 'Checking…');
    final info = await u.check();
    if (!mounted) return;
    if (info == null) {
      setState(() => _updateStatus = 'You have the latest version.');
    } else {
      setState(() => _updateStatus = null);
      await runUpdate(context, _s, info);
    }
  }

  Future<void> _deleteSpeechModel(SpeechEngine eng) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove the speech model?'),
        content: const Text(
          'Frees ${modelBytes ~/ 1000000} MB. Read aloud will ask to download it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (eng.modelDir.existsSync()) eng.modelDir.deleteSync(recursive: true);
    _changed('speech_model', 'installed', 'removed');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _s.prefs;
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    final speech = _s.speech;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                section('Reading'),
                ListTile(
                  title: const Text('Language'),
                  trailing: SegmentedButton<String>(
                    key: const ValueKey('set-lang'),
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(value: 'yue', label: Text('粵語')),
                      ButtonSegment(
                        value: 'cmn',
                        label: Text(
                          '普通话',
                          style: chineseStyle('cmn', fontSize: 14),
                        ),
                      ),
                    ],
                    selected: {p.lang},
                    onSelectionChanged: (v) {
                      final from = p.lang;
                      p.lang = v.first;
                      _changed('lang', from, v.first);
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Jyutping help'),
                  subtitle: const Text(
                    'How quickly readings fade as you learn',
                  ),
                  trailing: SegmentedButton<int>(
                    key: const ValueKey('set-help'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 1, label: Text('More')),
                      ButtonSegment(value: 0, label: Text('Normal')),
                      ButtonSegment(value: -1, label: Text('Less')),
                    ],
                    selected: {p.helpShift},
                    onSelectionChanged: (v) {
                      final from = p.helpShift;
                      p.helpShift = v.first;
                      _changed('help_shift', from, v.first);
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Text size'),
                  subtitle: Slider(
                    key: const ValueKey('set-text-size'),
                    value: p.textScale,
                    min: 0.8,
                    max: 1.5,
                    divisions: 7,
                    label: '${(p.textScale * 100).round()}%',
                    onChanged: (v) => setState(() => p.textScale = v),
                    onChangeEnd: (v) => _changed('text_scale', null, v),
                  ),
                  trailing: Text(
                    '字',
                    style: chineseStyle(p.lang, fontSize: 22 * p.textScale),
                  ),
                ),
                ListTile(
                  title: const Text("Today's reading length"),
                  trailing: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 5, label: Text('5')),
                      ButtonSegment(value: 15, label: Text('15')),
                      ButtonSegment(value: 30, label: Text('30')),
                    ],
                    selected: {p.sessionLength},
                    onSelectionChanged: (v) {
                      final from = p.sessionLength;
                      p.sessionLength = v.first;
                      _changed('session_length', from, v.first);
                    },
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('set-sfx'),
                  title: const Text('Sound effects'),
                  subtitle: const Text(
                    'Soft sounds on taps, saves and results',
                  ),
                  value: p.soundEffects,
                  onChanged: (v) {
                    p.soundEffects = v;
                    if (v) _s.sound(Sfx.tap);
                    _changed('sound_effects', !v, v);
                  },
                ),
                SwitchListTile(
                  key: const ValueKey('set-auto-play'),
                  title: const Text('Play sentences automatically'),
                  subtitle: const Text(
                    'Hear each sentence and line as it opens',
                  ),
                  value: p.autoPlay,
                  onChanged: (v) {
                    p.autoPlay = v;
                    _changed('auto_play', !v, v);
                  },
                ),
                SwitchListTile(
                  key: const ValueKey('set-read-along'),
                  title: const Text('Read along in stories'),
                  subtitle: const Text('Play each line as it appears'),
                  value: p.readAlong,
                  onChanged: (v) {
                    p.readAlong = v;
                    _changed('read_along', !v, v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Offer to read copied text'),
                  subtitle: const Text(
                    'When you open the app with Chinese copied',
                  ),
                  value: p.clipboardPrompt,
                  onChanged: (v) {
                    p.clipboardPrompt = v;
                    _changed('clipboard_prompt', !v, v);
                  },
                ),
                if (_s.reminders != null) ...[
                  section('Reminder'),
                  SwitchListTile(
                    key: const ValueKey('reminder-switch'),
                    title: const Text('Daily reminder'),
                    subtitle: Text(
                      p.reminderMinute == null
                          ? 'At ${_clock(_reminderMinute())}, when you usually read'
                          : 'At ${_clock(_reminderMinute())}',
                    ),
                    value: p.reminderOn,
                    onChanged: (on) async {
                      final r = _s.reminders!;
                      if (on && !await r.requestPermission()) return;
                      p.reminderOn = on;
                      on
                          ? await r.scheduleDaily(_reminderMinute())
                          : await r.cancel();
                      _changed('reminder', !on, on);
                    },
                  ),
                  ListTile(
                    title: const Text('Reminder time'),
                    trailing: Text(_clock(_reminderMinute())),
                    onTap: () async {
                      final m = _reminderMinute();
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
                      );
                      if (t == null) return;
                      p.reminderMinute = t.hour * 60 + t.minute;
                      if (p.reminderOn) {
                        await _s.reminders!.scheduleDaily(_reminderMinute());
                      }
                      _changed('reminder_minute', m, p.reminderMinute);
                    },
                  ),
                ],
                if (speech != null) ...[
                  section('Read aloud'),
                  ListTile(
                    title: const Text('Speech model'),
                    subtitle: Text(
                      speech.installed
                          ? 'Installed (${modelBytes ~/ 1000000} MB, on this device only)'
                          : 'Downloads on first use (${modelBytes ~/ 1000000} MB)',
                    ),
                    trailing: speech.installed
                        ? TextButton(
                            onPressed: () => _deleteSpeechModel(speech),
                            child: const Text('Remove'),
                          )
                        : null,
                  ),
                ],
                section('App'),
                if (_s.updater != null)
                  ListTile(
                    key: const ValueKey('check-update'),
                    title: const Text('Check for updates'),
                    subtitle: Text(_updateStatus ?? _version),
                    trailing: const Icon(Icons.system_update_rounded),
                    onTap: _checkUpdate,
                  ),
                ListTile(
                  title: const Text('About DuckLearn'),
                  subtitle: Text(
                    'Learn to read the Cantonese you already speak. '
                    '${Platform.operatingSystem} · $_version',
                  ),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'DuckLearn',
                    applicationVersion: _version,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
