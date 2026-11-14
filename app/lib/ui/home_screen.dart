/// Start screen: one obvious action ("Start today's reading"), progress you can see,
/// and topics with how far along each one is.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/item_state.dart';
import 'logo.dart';
import 'mascot.dart';
import 'paste_reader_screen.dart';
import 'reader_screen.dart';
import 'ruby_text.dart';
import 'theme.dart';

/// An item counts as solid once its memory lasts three weeks.
const _solidStabilityDays = 21.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lang = 'yue';

  AppServices get _s => widget.services;

  bool _isLang(ItemState st) => st.itemId.startsWith('cr:$_lang:');

  Future<void> _open({
    required String title,
    required List<SentenceRow> sentences,
    required String mode,
    String? scenarioId,
    int? count,
    int maxNew = 12,
  }) async {
    _s.logger.log('nav.screen', {
      'screen': 'reader',
      'mode': mode,
      'scenario_id': ?scenarioId,
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          services: _s,
          title: title,
          sentences: sentences,
          lang: _lang,
          mode: mode,
          scenarioId: scenarioId,
          count: count,
          maxNew: maxNew,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = _s.logger.now();
    final scenarios = _s.content
        .scenarios(_lang)
        .where((x) => x.sentenceCount > 0)
        .toList();
    final itemsByScenario = _s.content.charItemsByScenario(_lang);
    final states = _s.learner.known.where(_isLang).toList();
    final met = states.length;
    final solid = states
        .where((x) => (x.stability ?? 0) >= _solidStabilityDays)
        .length;
    final due = states
        .where((x) => x.due != null && !x.due!.isAfter(now))
        .length;
    final totalChars = itemsByScenario.values.expand((x) => x).toSet().length;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    const DuckLogo(size: 40, tile: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'DuckLearn',
                        style: theme.textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: [
                        const ButtonSegment(value: 'yue', label: Text('粵語')),
                        ButtonSegment(
                          value: 'cmn',
                          // simplified glyphs need the SC font
                          label: Text(
                            '普通话',
                            style: chineseStyle('cmn', fontSize: 14),
                          ),
                        ),
                      ],
                      selected: {_lang},
                      onSelectionChanged: (v) {
                        _s.logger.log('settings.change', {
                          'key': 'lang',
                          'from': _lang,
                          'to': v.first,
                        });
                        setState(() => _lang = v.first);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _TodayCard(
                  due: due,
                  known: solid,
                  isFirstTime: met == 0,
                  hasContent: scenarios.isNotEmpty,
                  onStart: () => _open(
                    title: met == 0 ? 'First steps' : "Today's reading",
                    sentences: _s.content.allSentences(_lang),
                    mode: 'daily',
                    count: 15,
                    maxNew: 8,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    key: const ValueKey('open-free-reader'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      foregroundColor: theme.colorScheme.onSecondaryContainer,
                      child: const Icon(Icons.document_scanner_rounded),
                    ),
                    title: Text(
                      'Read anything',
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: const Text(
                      'Paste or photograph a menu, sign or message. '
                      "Readings only over what you don't know yet.",
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      _s.logger.log('nav.screen', {'screen': 'free_reader'});
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PasteReaderScreen(services: _s, lang: _lang),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Stat(
                          key: const ValueKey('stat-met'),
                          value: '$met',
                          label: 'met',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Stat(
                          key: const ValueKey('stat-solid'),
                          value: '$solid',
                          label: 'known well',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Stat(
                          value: totalChars == 0
                              ? '–'
                              : '${(100 * solid / totalChars).round()}%',
                          label: 'readable',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Characters you have met, can read reliably, and the share of all content you can read.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Text('Topics', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Pick a situation to practise. Characters you meet anywhere count everywhere.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (scenarios.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No ${_lang == 'cmn' ? 'Mandarin' : 'Cantonese'} content yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final sc in scenarios)
                  _TopicTile(
                    scenario: sc,
                    total: itemsByScenario[sc.id]?.length ?? 0,
                    met: (itemsByScenario[sc.id] ?? const {})
                        .where((id) => !_s.learner.stateOf(id).isNew)
                        .length,
                    onTap: () => _open(
                      title: sc.title,
                      sentences: _s.content.sentences(sc.id, _lang),
                      mode: 'topic',
                      scenarioId: sc.id,
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

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.due,
    required this.known,
    required this.isFirstTime,
    required this.hasContent,
    required this.onStart,
  });

  final int due;
  final int known;
  final bool isFirstTime;
  final bool hasContent;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final String headline;
    final String detail;
    if (isFirstTime) {
      headline = 'Start reading';
      detail =
          'Short real-life sentences with Jyutping over every new character. '
          'The Jyutping fades as you learn each one.';
    } else if (due > 0) {
      headline = '$due ${due == 1 ? 'character' : 'characters'} to review';
      detail = 'Mixed with a few new ones. About 5 minutes.';
    } else {
      headline = 'All caught up';
      detail = 'Nothing is due. Keep going with some new characters.';
    }
    return Card(
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(height: 12),
                  _GrowthLine(known: known),
                  FilledButton.icon(
                    key: const ValueKey('start-daily'),
                    onPressed: hasContent ? onStart : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      isFirstTime ? 'Start' : "Start today's reading",
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            DuckMascot(
              size: 104,
              stage: DuckStage.forKnown(known),
              mood: due == 0 && !isFirstTime ? DuckMood.sleepy : DuckMood.happy,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      ),
    );
  }
}

/// Icons chosen from the scenario id so new topics get a sensible default.
IconData _topicIcon(String id) {
  const byKeyword = {
    'around': Icons.directions_bus_rounded,
    'food': Icons.restaurant_rounded,
    'shop': Icons.shopping_bag_rounded,
    'health': Icons.local_hospital_rounded,
    'home': Icons.home_rounded,
    'chat': Icons.forum_rounded,
    'weather': Icons.thunderstorm_rounded,
    'gov': Icons.account_balance_rounded,
    'work': Icons.work_rounded,
    'numbers': Icons.pin_rounded,
    'signs': Icons.signpost_rounded,
    'messaging': Icons.smartphone_rounded,
    'tourism': Icons.hotel_rounded,
  };
  for (final e in byKeyword.entries) {
    if (id.contains(e.key)) return e.value;
  }
  return Icons.menu_book_rounded;
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.scenario,
    required this.total,
    required this.met,
    required this.onTap,
  });

  final ScenarioRow scenario;
  final int total;
  final int met;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fraction = total == 0 ? 0.0 : met / total;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.secondaryContainer,
                foregroundColor: scheme.onSecondaryContainer,
                child: Icon(_topicIcon(scenario.id)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(scenario.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$met of $total characters met · ${scenario.sentenceCount} sentences',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// "小鴨 Duckling · 18 more to grow": the mascot grows with characters known well.
class _GrowthLine extends StatelessWidget {
  const _GrowthLine({required this.known});
  final int known;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = DuckStage.forKnown(known);
    final next = stage.next;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${stage.zh} ',
              style: const TextStyle(
                fontFamily: brushFont,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: stage.en),
            if (next != null)
              TextSpan(
                text:
                    ' · ${next.from - known} more known characters to become a ${next.en.toLowerCase()}',
              ),
          ],
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
