/// Settings: everything a learner might want to change, in one place.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_services.dart';
import '../engine/insights.dart';
import '../platform/sfx.dart';
import '../platform/speech.dart';
import '../platform/storage.dart';
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
  ({int model, int content, int progress, int cache})? _storage;
  String? _updateStatus;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _measure();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) {
        setState(() => _version = '${i.version} (build ${i.buildNumber})');
      }
    }).ignore();
  }

  /// What the app keeps on this phone (the app itself is counted by Android separately).
  Future<void> _measure() async {
    try {
      final support = await getApplicationSupportDirectory();
      final temp = await getTemporaryDirectory();
      final r = (
        model: sizeOf(Directory(p.join(support.path, 'models'))),
        content: sizeOf(File(p.join(support.path, 'content.db'))),
        progress: sizeOf(Directory(p.join(support.path, 'events'))),
        cache: sizeOf(temp),
      );
      if (mounted) setState(() => _storage = r);
    } on Object {
      // not available (tests): the section stays hidden
    }
  }

  Future<void> _clearCache() async {
    final temp = await getTemporaryDirectory();
    final freed = cleanTemp(temp, includeAudioCache: true);
    _s.logger.log('settings.change', {
      'key': 'clear_cache',
      'from': null,
      'to': freed,
    });
    await _measure();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Freed ${formatBytes(freed)}')));
    }
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
      setState(
        () => _updateStatus = u.lastError == null
            ? 'You have the latest version.'
            : "Couldn't check: ${u.lastError}",
      );
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
    await _measure();
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
                SwitchListTile(
                  key: const ValueKey('set-auto-meaning'),
                  title: const Text('Show meaning after listening'),
                  subtitle: const Text(
                    'The English appears when a sentence finishes playing',
                  ),
                  value: p.autoMeaning,
                  onChanged: (v) {
                    p.autoMeaning = v;
                    _changed('auto_meaning', !v, v);
                  },
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
                if (_storage case final st?) ...[
                  section('Storage on this phone'),
                  ListTile(
                    key: const ValueKey('storage-model'),
                    dense: true,
                    title: const Text('Speech model (read aloud)'),
                    trailing: Text(formatBytes(st.model)),
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('Content (sentences, dictionary)'),
                    trailing: Text(formatBytes(st.content)),
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('Your progress'),
                    trailing: Text(formatBytes(st.progress)),
                  ),
                  ListTile(
                    key: const ValueKey('storage-cache'),
                    title: const Text(
                      'Cache (played clips, your last recording)',
                    ),
                    subtitle: const Text(
                      'Safe to clear; it refills as you play audio',
                    ),
                    trailing: TextButton(
                      onPressed: _clearCache,
                      child: Text('Clear ${formatBytes(st.cache)}'),
                    ),
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
