/// Choosing (or changing) your goal: one list, used by the first-run screen, Today and
/// Settings.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../engine/goals.dart';

/// The goals as tappable rows; [selected] is highlighted.
class GoalList extends StatelessWidget {
  const GoalList({super.key, required this.selected, required this.onPick});
  final String? selected;
  final ValueChanged<Goal> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in goals)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              key: ValueKey('goal-${g.id}'),
              onPressed: () => onPick(g),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                backgroundColor: selected == g.id
                    ? scheme.primaryContainer
                    : null,
                side: BorderSide(
                  color: selected == g.id
                      ? scheme.primary
                      : scheme.outlineVariant,
                  width: selected == g.id ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.title, style: theme.textTheme.titleSmall),
                  Text(g.detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Saves the goal and logs the change.
void setGoal(AppServices s, Goal g) {
  final from = s.prefs.goal;
  s.prefs.goal = g.id;
  s.logger.log('settings.change', {'key': 'goal', 'from': from, 'to': g.id});
}

/// A sheet to change the goal. Returns true when it changed.
Future<bool> pickGoal(BuildContext context, AppServices s) async {
  final picked = await showModalBottomSheet<Goal>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What do you want Cantonese for?',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Your topics go first on the path and in Today. Everything else stays open.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            GoalList(
              selected: s.prefs.goal,
              onPick: (g) => Navigator.pop(ctx, g),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || picked.id == s.prefs.goal) return false;
  setGoal(s, picked);
  return true;
}
