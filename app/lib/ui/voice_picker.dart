/// Settings → Sentence voice: the phone's default Cantonese voice (the default), any
/// other Cantonese voice the phone's engine has, or the recorded voice. Tapping one picks
/// it and plays a sample line.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../platform/word_voice.dart';

/// "Phone voice (default)", "Phone voice: yue-hk-x-jar-network", "Recorded voice".
String voiceLabel(AppServices s) {
  if (!s.prefs.phoneVoice) return 'Recorded voice (Microsoft)';
  final n = s.prefs.voiceName;
  return n == null ? 'Phone voice (default)' : 'Phone voice: $n';
}

/// A short line to try each voice on (one that has a recording too).
String sampleLine(AppServices s) {
  for (final id in const ['sent-var-001:yue', 'sent-var-053:yue']) {
    final r = s.content.sentencesByIds([id]);
    if (r.isNotEmpty) return r.first.text;
  }
  final all = s.content.allSentences('yue');
  return all.isEmpty ? '你好' : all.first.text;
}

Future<void> showVoicePicker(
  BuildContext context,
  AppServices s, {
  required void Function(String from, String to) onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _VoicePicker(s, onChanged),
);

class _VoicePicker extends StatefulWidget {
  const _VoicePicker(this.s, this.onChanged);
  final AppServices s;
  final void Function(String from, String to) onChanged;

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  AppServices get _s => widget.s;
  List<PhoneVoice>? _voices;

  @override
  void initState() {
    super.initState();
    (_s.voice?.voices() ?? Future.value(const <PhoneVoice>[])).then((v) {
      if (mounted) setState(() => _voices = v);
    });
  }

  Future<void> _pick({required bool phone, String? name}) async {
    final from = voiceLabel(_s);
    await _s.silence();
    _s.prefs.phoneVoice = phone;
    _s.prefs.voiceName = phone ? name : null;
    _s.voice?.wanted = _s.prefs.voiceName;
    setState(() {});
    widget.onChanged(from, voiceLabel(_s));
    await _s.saySentence(sampleLine(_s));
  }

  Widget _tile({
    required Key key,
    required bool selected,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) => ListTile(
    key: key,
    leading: Icon(
      selected ? Icons.check_circle_rounded : Icons.circle_outlined,
      color: selected ? Theme.of(context).colorScheme.primary : null,
    ),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: const Icon(Icons.volume_up_rounded),
    onTap: onTap,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = _s.prefs.phoneVoice;
    final name = _s.prefs.voiceName;
    final voices = _voices;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Sentence voice: tap one to pick it and hear a sample. '
                'Tapped words use the phone voice you pick too.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            _tile(
              key: const ValueKey('voice-default'),
              selected: phone && name == null,
              title: 'Phone voice (default)',
              subtitle: 'Everyday tones, the same as before',
              onTap: () => _pick(phone: true),
            ),
            if (voices == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final (i, v) in voices.indexed)
                _tile(
                  key: ValueKey('voice-${v.name}'),
                  selected: phone && name == v.name,
                  title:
                      'Phone voice ${i + 1}'
                      '${v.online ? ' (online)' : ''}',
                  subtitle: [
                    v.name,
                    if (v.quality != null) '${v.quality} quality',
                  ].join(' · '),
                  onTap: () => _pick(phone: true, name: v.name),
                ),
            _tile(
              key: const ValueKey('voice-recorded'),
              selected: !phone,
              title: 'Recorded voice (Microsoft)',
              subtitle: 'Works offline everywhere; some tones sound formal',
              onTap: () => _pick(phone: false),
            ),
            if (voices != null && voices.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  'No other Cantonese voices on this device. On Android: Settings > '
                  'Text-to-speech > Speech services by Google > Install voice data '
                  '> Chinese (Hong Kong).',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The voice switch in every exercise's top bar: change voice mid-practice.
class VoiceButton extends StatelessWidget {
  const VoiceButton(this.services, {super.key});
  final AppServices services;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('voice-button'),
    tooltip: 'Voice: ${voiceLabel(services)}',
    icon: const Icon(Icons.record_voice_over_rounded),
    onPressed: () => showVoicePicker(
      context,
      services,
      onChanged: (from, to) => services.logger.log('settings.change', {
        'key': 'voice',
        'from': from,
        'to': to,
      }),
    ),
  );
}
