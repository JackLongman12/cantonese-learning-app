/// One way around the app from anywhere: the six tools, a × that always goes Home, and
/// the finish screen that offers the next step of today's plan or any tool, so choosing
/// something else never needs a trail of Back presses.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import 'critters.dart';

/// The places you can jump to from Home and from every finish screen.
const tools = [
  (id: 'topics', icon: Icons.map_outlined, label: 'Topics'),
  (id: 'stories', icon: Icons.auto_stories_outlined, label: 'Stories'),
  (id: 'cards', icon: Icons.style_outlined, label: 'Cards'),
  (id: 'speak', icon: Icons.mic_none_rounded, label: 'Speak'),
  (id: 'words', icon: Icons.bookmark_border_rounded, label: 'My words'),
  (id: 'skills', icon: Icons.extension_outlined, label: 'Skills'),
];

/// Six small tiles, three to a row.
class ToolGrid extends StatelessWidget {
  const ToolGrid({super.key, required this.onTap, this.badges = const {}});
  final ValueChanged<String> onTap;

  /// A small count under a tool's name ("8 due").
  final Map<String, String> badges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 2 * 8) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in tools)
              SizedBox(
                width: w,
                child: Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: ValueKey('tool-${t.id}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onTap(t.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Icon(
                            t.icon,
                            size: 22,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.label,
                            style: theme.textTheme.labelLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (badges[t.id] case final b?)
                            Text(
                              b,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Back to Home from however deep you are. What you did so far counts.
void goHome(BuildContext context) =>
    Navigator.of(context).popUntil((r) => r.isFirst);

/// The × in every exercise.
Widget closeToHome(BuildContext context) => IconButton(
  key: const ValueKey('close'),
  tooltip: 'Home',
  icon: const Icon(Icons.close_rounded),
  onPressed: () => goHome(context),
);

/// The duckling progress bar under an exercise's title.
PreferredSizeWidget duckBar(double value) => PreferredSize(
  preferredSize: const Size.fromHeight(28),
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
    child: DuckProgress(value: value),
  ),
);

/// The end of any exercise: the chick, what happened, then where to go next.
class FinishView extends StatelessWidget {
  const FinishView({
    super.key,
    required this.services,
    required this.title,
    this.titleKey,
    this.subtitle,
    this.mood = ChickMood.happy,
    this.children = const [],
    this.onKeepGoing,
  });
  final AppServices services;
  final String title;
  final Key? titleKey;
  final String? subtitle;
  final ChickMood mood;
  final List<Widget> children;

  /// More of the same (only where it makes sense).
  final VoidCallback? onKeepGoing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final link = services.home;
    final next = link?.next();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(child: Chick(mood: mood, size: 110)),
            const SizedBox(height: 4),
            Text(
              title,
              key: titleKey,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            ...children,
            const SizedBox(height: 20),
            if (link != null) ...[
              if (next != null)
                Material(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: const ValueKey('up-next'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: link.startNext,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          EggMarker(number: next.number, current: true),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Up next',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                Text(
                                  next.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.play_arrow_rounded,
                            color: scheme.onPrimaryContainer,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Text(
                  "That's today's plan done. Anything else is a bonus.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 14),
              Text(
                'Or switch to',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ToolGrid(onTap: link.openTool),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                if (onKeepGoing != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('keep-going'),
                      onPressed: onKeepGoing,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      child: const Text('Keep going'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('done'),
                    onPressed: () => goHome(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    child: const Text('Home'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
