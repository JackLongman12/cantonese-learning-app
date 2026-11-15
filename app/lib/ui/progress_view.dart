/// The Progress tab: how far you have come (with this week against last week and your
/// first week), and what to work on next, each with a button that opens it. Outcomes
/// only: no streaks, no attendance.
library;

import 'package:material_ui/material_ui.dart';

import '../engine/item_state.dart';
import '../engine/weak_spots.dart';
import 'ruby_text.dart';
import 'theme.dart';

class ProgressView extends StatelessWidget {
  const ProgressView({
    super.key,
    required this.met,
    required this.learned,
    required this.readablePct,
    required this.thisWeek,
    required this.lastWeek,
    required this.firstWeek,
    required this.metByWeek,
    required this.chars,
    required this.sounds,
    required this.wordsToPractice,
    required this.cardsDue,
    required this.onChar,
    this.onReview,
    this.onWords,
    this.onCards,
    this.onSpeak,
  });

  final int met;
  final int learned;
  final int? readablePct;
  final PeriodStats thisWeek;
  final PeriodStats lastWeek;
  final PeriodStats? firstWeek;
  final List<int> metByWeek;
  final List<ItemState> chars;
  final List<SoundMixup> sounds;
  final int wordsToPractice;
  final int cardsDue;
  final ValueChanged<String> onChar;
  final VoidCallback? onReview;
  final VoidCallback? onWords;
  final VoidCallback? onCards;
  final VoidCallback? onSpeak;

  /// One plain sentence about the week, picking the change that stands out most.
  String get _headline {
    if (lastWeek.isEmpty) {
      return thisWeek.isEmpty
          ? 'Read a few sentences and your progress shows up here.'
          : 'Your first week of numbers. Next week you can compare.';
    }
    final changes = <(double, String)>[
      if (thisWeek.readingPct case final a?)
        if (lastWeek.readingPct case final b?)
          (
            (a - b) / 4,
            a >= b
                ? 'You read ${a - b} points more without help than last week.'
                : '',
          ),
      if (thisWeek.speakingPct case final a?)
        if (lastWeek.speakingPct case final b?)
          (
            (a - b) / 10,
            a >= b ? 'Your sounds are ${a - b} points more accurate.' : '',
          ),
      (
        (thisWeek.newChars - lastWeek.newChars) / 5,
        'You met ${thisWeek.newChars - lastWeek.newChars} more new '
            'characters than last week.',
      ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final best = changes.first;
    if (best.$1 > 0 && best.$2.isNotEmpty) return best.$2;
    return 'A quieter week than last. Everything you learned is still here.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final first = firstWeek;
    final todo = <Widget>[
      if (chars.isNotEmpty)
        _TodoTile(
          key: const ValueKey('todo-weak'),
          icon: Icons.history_edu_rounded,
          title: 'Review ${chars.length} weak characters',
          detail: 'You keep needing help with these. Tap one to hear it.',
          onTap: onReview,
          extra: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in chars)
                ActionChip(
                  onPressed: () => onChar(c.itemId.split(':')[2]),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.itemId.split(':')[3],
                        style: theme.textTheme.labelSmall,
                      ),
                      Text(
                        c.itemId.split(':')[2],
                        style: chineseStyle('yue', fontSize: 20),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (sounds.isNotEmpty)
        _TodoTile(
          key: const ValueKey('todo-sounds'),
          icon: Icons.record_voice_over_rounded,
          title: 'Sounds you mix up',
          detail: [
            for (final m in sounds.take(3)) '${_explain(m)} (${m.count} times)',
          ].join('\n'),
          onTap: onSpeak,
          action: 'Speak',
        ),
      if (wordsToPractice > 0)
        _TodoTile(
          key: const ValueKey('todo-words'),
          icon: Icons.bookmark_rounded,
          title: '$wordsToPractice words to practice',
          detail: 'Words you struggled with, in the sentence they came from.',
          onTap: onWords,
        ),
      if (cardsDue > 0)
        _TodoTile(
          key: const ValueKey('todo-cards'),
          icon: Icons.style_rounded,
          title: '$cardsDue flashcards due',
          detail: 'Names you are about to forget.',
          onTap: onCards,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Progress', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(_headline, key: const ValueKey('progress-headline'), style: muted),
        const SizedBox(height: 12),

        // how far you have come
        Card(
          key: const ValueKey('weak-spots'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Metric(
                      key: const ValueKey('stat-met'),
                      value: '$met',
                      label: 'characters met',
                    ),
                    _Metric(value: '$learned', label: 'learned'),
                    _Metric(
                      value: readablePct == null ? '–' : '$readablePct%',
                      label: 'of the app readable',
                    ),
                  ],
                ),
                if (metByWeek.any((n) => n > 0)) ...[
                  const SizedBox(height: 14),
                  _Bars(values: metByWeek),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('${metByWeek.length - 1} weeks ago', style: muted),
                      const Spacer(),
                      Text('Characters met', style: muted),
                      const Spacer(),
                      Text('Now', style: muted),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // this week against last week
        Text('This week vs last week', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _Grid(
          children: [
            _Compare(
              key: const ValueKey('metric-new'),
              label: 'New characters',
              now: thisWeek.newChars,
              before: lastWeek.newChars,
            ),
            _Compare(
              key: const ValueKey('metric-reading'),
              label: 'Read without help',
              now: thisWeek.readingPct,
              before: lastWeek.readingPct,
              percent: true,
            ),
            _Compare(
              key: const ValueKey('metric-speaking'),
              label: 'Sounds said right',
              now: thisWeek.speakingPct,
              before: lastWeek.speakingPct,
              percent: true,
            ),
            _Compare(
              key: const ValueKey('metric-sentences'),
              label: 'Sentences read',
              now: thisWeek.sentences,
              before: lastWeek.sentences,
            ),
          ],
        ),

        // what to do with all this
        const SizedBox(height: 18),
        Text('What to work on', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (todo.isEmpty)
          Text(
            'Nothing stands out. Keep reading new topics.',
            key: const ValueKey('todo-none'),
            style: muted,
          )
        else
          for (final w in todo)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: w),
        // since the beginning
        if (first != null &&
            (first.readingPct != null || first.speakingPct != null)) ...[
          const SizedBox(height: 18),
          Text('Since your first week', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            key: const ValueKey('since-first'),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (first.readingPct case final a?)
                    if (thisWeek.readingPct case final b?)
                      _Since(label: 'Read without help', from: a, to: b),
                  if (first.speakingPct case final a?)
                    if (thisWeek.speakingPct case final b?)
                      _Since(label: 'Sounds said right', from: a, to: b),
                  _Since(
                    label: 'Characters met',
                    from: first.newChars,
                    to: met,
                    percent: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _explain(SoundMixup m) => switch (m.kind) {
    'tone' => 'Tone ${m.expected} said as ${m.heard}',
    'start' => 'Starts with ${m.expected}, said as ${m.heard}',
    _ => 'Ends in ${m.expected}, said as ${m.heard}',
  };
}

/// Two tiles per row, all the same size.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = (box.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in children) SizedBox(width: w, height: 92, child: c),
        ],
      );
    },
  );
}

Color _upColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFAFC096)
    : Palette.sageDeep;

/// A number this week, with how it moved since last week.
class _Compare extends StatelessWidget {
  const _Compare({
    super.key,
    required this.label,
    required this.now,
    required this.before,
    this.percent = false,
  });
  final String label;
  final int? now;
  final int? before;
  final bool percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = now, b = before;
    final unit = percent ? ' pts' : '';
    final (String change, Color color, IconData? icon) = switch ((n, b)) {
      (final n?, final b?) when n > b => (
        '+${n - b}$unit vs last week',
        _upColor(context),
        Icons.arrow_upward_rounded,
      ),
      (final n?, final b?) when n < b => (
        '-${b - n}$unit vs last week',
        scheme.onSurfaceVariant,
        Icons.arrow_downward_rounded,
      ),
      (_?, _?) => ('Same as last week', scheme.onSurfaceVariant, null),
      (_?, null) => ('No data last week', scheme.onSurfaceVariant, null),
      _ => ('Nothing yet this week', scheme.onSurfaceVariant, null),
    };
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              n == null ? '–' : '$n${percent ? '%' : ''}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            Row(
              children: [
                if (icon != null) Icon(icon, size: 13, color: color),
                Flexible(
                  child: Text(
                    change,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
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

/// "Read without help   35% → 72%"
class _Since extends StatelessWidget {
  const _Since({
    required this.label,
    required this.from,
    required this.to,
    this.percent = true,
  });
  final String label;
  final int from;
  final int to;
  final bool percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = percent ? '%' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            '$from$p → $to$p',
            style: theme.textTheme.titleSmall?.copyWith(
              color: to > from ? _upColor(context) : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Running totals as small bars, oldest left.
class _Bars extends StatelessWidget {
  const _Bars({required this.values});
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, v) in values.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  height: top == 0 ? 2 : 2 + 54 * v / top,
                  decoration: BoxDecoration(
                    color: i == values.length - 1
                        ? scheme.primary
                        : scheme.primary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Something to work on, with the button that opens it.
class _TodoTile extends StatelessWidget {
  const _TodoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.extra,
    this.action = 'Start',
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final Widget? extra;
  final String action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  FilledButton.tonal(onPressed: onTap, child: Text(action)),
              ],
            ),
            if (extra case final e?) ...[const SizedBox(height: 10), e],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
