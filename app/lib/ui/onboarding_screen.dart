/// First run: do you speak Cantonese (sets what help and meanings the reader shows),
/// how much can you read (sets how much Jyutping help you get), what for (topic order),
/// and whether to share anonymous usage data. Everything here can be changed later in
/// Settings.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../platform/telemetry.dart' show setSharing;
import 'goal_picker.dart';
import 'logo.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.services,
    required this.onDone,
  });
  final AppServices services;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool? _speaker;
  int? _help;
  String? _goal;
  bool? _share;

  void _finish() {
    final s = widget.services;
    final p = s.prefs;
    p.speaker = _speaker ?? true;
    // someone learning the language too keeps Jyutping a step longer
    p.helpShift = ((_help ?? 0) + (p.isSpeaker ? 0 : 1)).clamp(-1, 2);
    p.goal = _goal ?? 'all';
    p.onboarded = true;
    setSharing(s, _share ?? false);
    s.logger.log('onboarding.done', {
      'speaker': p.isSpeaker,
      'help_shift': p.helpShift,
      'goal': p.goal,
      'share': p.shareData,
    });
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget choice<T>(
      String key,
      T value,
      T? selected,
      ValueChanged<T> pick,
      String title,
      String detail,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton(
        key: ValueKey(key),
        onPressed: () => setState(() => pick(value)),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(16),
          backgroundColor: selected == value ? scheme.primaryContainer : null,
          side: BorderSide(
            color: selected == value ? scheme.primary : scheme.outlineVariant,
            width: selected == value ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
    Widget level(int value, String title, String detail) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton(
        key: ValueKey('onboard-level-$value'),
        onPressed: () => setState(() => _help = value),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(16),
          backgroundColor: _help == value ? scheme.primaryContainer : null,
          side: BorderSide(
            color: _help == value ? scheme.primary : scheme.outlineVariant,
            width: _help == value ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
    Widget tip(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: DuckLogo(size: 56, tile: true),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome to DuckLearn',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Learn to read Cantonese, one character at a time, with real '
                    'Hong Kong and Macau sentences.',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Do you speak Cantonese?',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  choice(
                    'onboard-speaker',
                    true,
                    _speaker,
                    (v) => _speaker = v,
                    'Yes, I speak it',
                    'You know the words by ear. Hearing a sentence tells you if you read it right.',
                  ),
                  choice(
                    'onboard-learner',
                    false,
                    _speaker,
                    (v) => _speaker = v,
                    "I'm learning it",
                    'Meanings in English stay on, and Jyutping stays a little longer.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'How much Chinese can you read now?',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  level(
                    1,
                    'None yet',
                    'Jyutping stays on longer while you start.',
                  ),
                  level(0, 'A few characters', 'The usual pace.'),
                  level(
                    -1,
                    'Quite a lot',
                    'Jyutping fades faster; you get tested sooner.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'What do you want Cantonese for?',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your topics come first. You can change this any time.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  GoalList(
                    selected: _goal,
                    onPick: (g) => setState(() => _goal = g.id),
                  ),
                  const SizedBox(height: 16),
                  Text('How it works', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  tip(
                    Icons.hearing_rounded,
                    'Read each sentence first, then Check to hear it. Tap any character you got wrong.',
                  ),
                  tip(
                    Icons.text_fields_rounded,
                    'New characters have Jyutping on top. It fades as you learn each one.',
                  ),
                  tip(
                    Icons.touch_app_rounded,
                    'Tap a word to hear it and see its reading and meaning.',
                  ),
                  tip(
                    Icons.translate_rounded,
                    'Save words you want to keep to My words from there.',
                  ),
                  tip(
                    Icons.mic_rounded,
                    'Or read aloud with the mic: it checks for you.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Help improve DuckLearn?',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share anonymous usage and crash reports: which sentences are hard, '
                    'where people get stuck, what crashes. No name, no account, nothing '
                    'you type, paste or say. You can turn it off in Settings.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: choice(
                          'onboard-share-yes',
                          true,
                          _share,
                          (v) => _share = v,
                          'Share',
                          'Anonymous',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: choice(
                          'onboard-share-no',
                          false,
                          _share,
                          (v) => _share = v,
                          "Don't share",
                          'Nothing is sent',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton(
                key: const ValueKey('onboard-start'),
                // the two questions that change how the app behaves need an answer
                onPressed: _speaker == null || _share == null ? null : _finish,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                child: Text(
                  _speaker == null
                      ? 'Answer: do you speak Cantonese?'
                      : _share == null
                      ? 'Answer: share usage data? (below)'
                      : 'Start reading',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
