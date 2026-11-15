/// Tiles instead of long lists: easier to spot one thing among many. One look for
/// every grid in the app (Jump to, stories, decks, conversations, skills).
library;

import 'package:material_ui/material_ui.dart';

/// A square-ish tile: icon, title, an optional line under it, an optional progress bar
/// and an optional small badge ("Up next", "Advanced").
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.progress,
    this.badge,
    this.highlight = false,
    this.titleStyle,
    this.subtitleStyle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final double? progress;
  final String? badge;
  final bool highlight;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.tertiary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor: scheme.onSecondaryContainer,
                    child: Icon(icon, size: 18),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle ?? theme.textTheme.titleSmall,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      subtitleStyle ??
                      theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiles in two columns on a phone, three on wider screens.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = box.maxWidth >= 560 ? 3 : 2;
      final w = (box.maxWidth - 10 * (cols - 1)) / cols;
      // a part-filled last row stretches its tiles to fill it: no blank gap
      final rest = children.length % cols;
      final wLast = rest == 0 ? w : (box.maxWidth - 10 * (rest - 1)) / rest;
      final firstOfLast = children.length - rest;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (i, c) in children.indexed)
            SizedBox(width: i >= firstOfLast ? wLast : w, child: c),
        ],
      );
    },
  );
}
