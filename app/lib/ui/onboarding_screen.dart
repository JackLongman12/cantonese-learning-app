/// First run: one question (how much can you read?) that sets how much Jyutping help
/// you get, and four things worth knowing about the reader. Everything here can be
/// changed later in Settings.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
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
  int? _help;
  String? _goal;

  void _finish() {
    final p = widget.services.prefs;
    p.helpShift = _help ?? 0;
    p.goal = _goal ?? 'all';
    p.onboarded = true;
    widget.services.logger.log('settings.change', {
      'key': 'onboarding',
      'from': null,
      'to': {'help_shift': p.helpShift, 'goal': p.goal},
    });
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                  const Text('Learn to read the Cantonese you already speak.'),
                  const SizedBox(height: 24),
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
                    'Read aloud with the mic: words you miss are saved for practice.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton(
                key: const ValueKey('onboard-start'),
                onPressed: _finish,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                child: const Text('Start reading'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
