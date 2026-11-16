/// Newcomer mode (Home B, 2026-11-17): situations of essential words, an English-first
/// daily drill, and "What do you want to say?" search. For people new to Cantonese who
/// want to get their point across, not to read (content/situations.yaml).
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/deck_planner.dart';
import '../engine/scaffold.dart';
import 'cards_screen.dart' show CardSessionScreen;
import 'finish.dart' show pushOnce;
import 'ruby_text.dart';

IconData situationIcon(String name) => switch (name) {
  'waving' => Icons.waving_hand_outlined,
  'numbers' => Icons.pin_outlined,
  'bus' => Icons.directions_bus_outlined,
  'restaurant' => Icons.restaurant_outlined,
  'cafe' => Icons.local_cafe_outlined,
  'payments' => Icons.payments_outlined,
  'shopping' => Icons.shopping_bag_outlined,
  'people' => Icons.people_outline,
  'phone' => Icons.phone_iphone_outlined,
  'home' => Icons.home_outlined,
  'health' => Icons.local_hospital_outlined,
  'emergency' => Icons.emergency_outlined,
  'weather' => Icons.thunderstorm_outlined,
  'work' => Icons.work_outline,
  'errands' => Icons.account_balance_outlined,
  _ => Icons.chat_bubble_outline,
};

/// A word counts as one you can say once it was said right and stuck for a couple of days.
bool canSay(AppServices s, String cardId) {
  final st = s.learner.stateOf(cardId);
  return !st.isNew && (st.stability ?? 0) >= 2;
}

/// The situations this newcomer is working on (the first four if none were picked).
List<SituationRow> pickedSituations(AppServices s) {
  final all = s.content.situations();
  final picked = s.prefs.situations;
  if (picked.isEmpty) return all.take(4).toList();
  return [
    for (final id in picked) ?all.where((x) => x.deck.id == id).firstOrNull,
  ];
}

/// Today's drill: words due again first, then a few new ones, from the picked situations.
List<CardRow> todaysDrill(AppServices s, {int total = 12, int maxNew = 6}) {
  final cards = [
    for (final sit in pickedSituations(s)) ...s.content.cards(sit.deck.id),
  ];
  final byId = {for (final c in cards) c.id: c};
  return [
    for (final id in pickCards(
      deckOrder: [for (final c in cards) c.id],
      stateOf: s.learner.stateOf,
      recall: (st) => s.memory.retrievability(st, s.logger.now()),
      now: s.logger.now(),
      random: s.variety,
      total: total,
      maxNew: maxNew,
    ))
      byId[id]!,
  ];
}

Future<void> startDrill(
  BuildContext context,
  AppServices s, {
  required String title,
  required List<CardRow> cards,
}) => pushOnce(
  context,
  MaterialPageRoute<void>(
    builder: (_) => CardSessionScreen(
      services: s,
      deck: DeckRow('drill', title, 'both', '', cards.length),
      cards: cards,
      englishFirst: true,
    ),
  ),
);

/// The word in characters with its Jyutping on top.
Widget wordWithReading(List<TokenRow> tokens, {double size = 26}) => RubyText(
  lang: 'yue',
  fontSize: size,
  tokens: [
    for (final t in tokens)
      RubyToken(
        surface: t.surface,
        kind: t.kind,
        reading: t.reading,
        level: ScaffoldLevel.full,
        revealed: false,
        flagged: t.flagged,
      ),
  ],
);

// ---------------------------------------------------------------- Home (newcomer)

class NewcomerToday extends StatelessWidget {
  const NewcomerToday({
    super.key,
    required this.services,
    required this.onChanged,
    required this.openTab,
    this.header,
  });
  final AppServices services;
  final VoidCallback onChanged;
  final ValueChanged<int> openTab;

  /// Title row, update banner and similar from Home.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final s = services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final drill = todaysDrill(s);
    final picked = pickedSituations(s);
    final next = picked
        .where(
          (sit) => s.content.cards(sit.deck.id).any((c) => !canSay(s, c.id)),
        )
        .firstOrNull;
    final known = [
      for (final sit in s.content.situations())
        for (final c in s.content.cards(sit.deck.id))
          if (canSay(s, c.id)) c,
    ].length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        ?header,
        const SizedBox(height: 8),
        // "What do you want to say?": the word you need right now
        Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const ValueKey('phrase-search'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => pushOnce(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PhraseSearchScreen(services: s),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'What do you want to say?',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          key: const ValueKey('drill-card'),
          margin: EdgeInsets.zero,
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Today's drill",
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      drill.isEmpty
                          ? 'All done'
                          : '${drill.length} words · ${(drill.length / 3).ceil()} min',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
                if (drill.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Say it in Cantonese:',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '"${drill.first.alt}"',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('start-drill'),
                      onPressed: () async {
                        await startDrill(
                          context,
                          s,
                          title: "Today's drill",
                          cards: drill,
                        );
                        onChanged();
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Start drill'),
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Nothing due. Add a situation for new words.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (next != null) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              key: const ValueKey('next-situation'),
              leading: Icon(situationIcon(next.icon)),
              title: Text(next.deck.title),
              subtitle: const Text('Next situation'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                await pushOnce(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SituationScreen(services: s, sit: next),
                  ),
                );
                onChanged();
              },
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Your situations', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sit in picked)
              ActionChip(
                avatar: Icon(situationIcon(sit.icon), size: 18),
                label: Text(sit.deck.title),
                onPressed: () async {
                  await pushOnce(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SituationScreen(services: s, sit: sit),
                    ),
                  );
                  onChanged();
                },
              ),
            ActionChip(
              key: const ValueKey('add-situation'),
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
              onPressed: () => openTab(1),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Words you can say',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '$known',
                  key: const ValueKey('words-known'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Situations tab

class SituationsPage extends StatelessWidget {
  const SituationsPage({
    super.key,
    required this.services,
    required this.onChanged,
  });
  final AppServices services;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = services;
    final theme = Theme.of(context);
    final picked = s.prefs.situations.toSet();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('Situations', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          'The words you need for each part of daily life. Star the ones you want in your drill.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final sit in s.content.situations())
          _SituationTile(
            services: s,
            sit: sit,
            picked: picked.contains(sit.deck.id),
            onChanged: onChanged,
          ),
      ],
    );
  }
}

void toggleSituation(AppServices s, String id) {
  final list = [...s.prefs.situations];
  if (!list.remove(id)) list.add(id);
  s.prefs.situations = list;
  s.logger.log('settings.change', {'key': 'situations', 'to': list});
}

class _SituationTile extends StatelessWidget {
  const _SituationTile({
    required this.services,
    required this.sit,
    required this.picked,
    required this.onChanged,
  });
  final AppServices services;
  final SituationRow sit;
  final bool picked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = services;
    final theme = Theme.of(context);
    final cards = s.content.cards(sit.deck.id);
    final known = cards.where((c) => canSay(s, c.id)).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: ValueKey('situation-${sit.deck.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await pushOnce(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SituationScreen(services: s, sit: sit),
            ),
          );
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(situationIcon(sit.icon)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sit.deck.title, style: theme.textTheme.titleSmall),
                    Text(
                      sit.deck.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: cards.isEmpty ? 0 : known / cards.length,
                      minHeight: 4,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$known of ${cards.length} words',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('star-${sit.deck.id}'),
                tooltip: picked
                    ? 'Remove from your drill'
                    : 'Add to your drill',
                icon: Icon(
                  picked ? Icons.star_rounded : Icons.star_outline_rounded,
                ),
                onPressed: () {
                  toggleSituation(s, sit.deck.id);
                  onChanged();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SituationScreen extends StatefulWidget {
  const SituationScreen({super.key, required this.services, required this.sit});
  final AppServices services;
  final SituationRow sit;

  @override
  State<SituationScreen> createState() => _SituationScreenState();
}

class _SituationScreenState extends State<SituationScreen> {
  AppServices get _s => widget.services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sit = widget.sit;
    final cards = _s.content.cards(sit.deck.id);
    final picked = _s.prefs.situations.contains(sit.deck.id);
    return Scaffold(
      appBar: AppBar(title: Text(sit.deck.title)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                key: const ValueKey('situation-star'),
                onPressed: () =>
                    setState(() => toggleSituation(_s, sit.deck.id)),
                icon: Icon(
                  picked ? Icons.star_rounded : Icons.star_outline_rounded,
                ),
                label: Text(picked ? 'In your drill' : 'Add to drill'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('drill-situation'),
                  onPressed: () async {
                    await startDrill(
                      context,
                      _s,
                      title: sit.deck.title,
                      cards: cards,
                    );
                    if (mounted) setState(() {});
                  },
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.mic_rounded),
                  label: const Text('Drill these'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(sit.deck.description, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            for (final c in cards)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _s.sayWord(c.zh, 'yue'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    child: Row(
                      children: [
                        wordWithReading(c.tokens),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.alt, style: theme.textTheme.titleSmall),
                              if (c.note.isNotEmpty)
                                Text(
                                  c.note,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (canSay(_s, c.id))
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: scheme.primary,
                            size: 20,
                          ),
                        const Icon(Icons.volume_up_outlined),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Drill tab

class DrillPage extends StatelessWidget {
  const DrillPage({super.key, required this.services, required this.onChanged});
  final AppServices services;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = services;
    final theme = Theme.of(context);
    final now = s.logger.now();
    int due(SituationRow sit) => s.content.cards(sit.deck.id).where((c) {
      final st = s.learner.stateOf(c.id);
      return !st.isNew && st.due != null && !st.due!.isAfter(now);
    }).length;
    final drill = todaysDrill(s);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('Drill', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          'See the English, say it in Cantonese, then hear it. Words come back just before you\'d forget them.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('drill-today'),
          onPressed: drill.isEmpty
              ? null
              : () async {
                  await startDrill(
                    context,
                    s,
                    title: "Today's drill",
                    cards: drill,
                  );
                  onChanged();
                },
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          icon: const Icon(Icons.mic_rounded),
          label: Text(
            drill.isEmpty
                ? 'Nothing due'
                : "Today's drill · ${drill.length} words",
          ),
        ),
        const SizedBox(height: 16),
        Text('By situation', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final sit in s.content.situations())
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(situationIcon(sit.icon)),
            title: Text(sit.deck.title),
            subtitle: Text(
              due(sit) > 0 ? '${due(sit)} due' : '${sit.deck.count} words',
            ),
            trailing: const Icon(Icons.play_arrow_rounded),
            onTap: () async {
              await startDrill(
                context,
                s,
                title: sit.deck.title,
                cards: s.content.cards(sit.deck.id),
              );
              onChanged();
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Progress (newcomer)

class NewcomerProgress extends StatelessWidget {
  const NewcomerProgress({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final s = services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sits = s.content.situations();
    var known = 0, total = 0, started = 0;
    final rows = <(SituationRow, int, int)>[];
    for (final sit in sits) {
      final cards = s.content.cards(sit.deck.id);
      final k = cards.where((c) => canSay(s, c.id)).length;
      final seen = cards.any((c) => !s.learner.stateOf(c.id).isNew);
      known += k;
      total += cards.length;
      if (seen) started++;
      rows.add((sit, k, cards.length));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('Progress', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat(value: '$known', label: 'words you can say'),
            const SizedBox(width: 10),
            _Stat(
              value: '$started of ${sits.length}',
              label: 'situations started',
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final (sit, k, n) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(situationIcon(sit.icon), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sit.deck.title, style: theme.textTheme.bodyMedium),
                      LinearProgressIndicator(
                        value: n == 0 ? 0 : k / n,
                        minHeight: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text('$k/$n', style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        if (total > 0 && known == total)
          Text(
            'You know every word here. Time for a full course or real conversations.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.titleLarge),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Search

/// "What do you want to say?": type English (or Chinese) and get the word or a line
/// to say, with its reading and sound. Situation words first, then example sentences.
class PhraseSearchScreen extends StatefulWidget {
  const PhraseSearchScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<PhraseSearchScreen> createState() => _PhraseSearchScreenState();
}

class _PhraseSearchScreenState extends State<PhraseSearchScreen> {
  AppServices get _s => widget.services;
  String _q = '';
  late final List<CardRow> _words = [
    for (final sit in _s.content.situations()) ..._s.content.cards(sit.deck.id),
  ];
  late final List<SentenceRow> _lines = _s.content.allSentences('yue');

  static List<String> _terms(String q) => [
    for (final w in q.toLowerCase().split(RegExp(r'[^a-z0-9㐀-鿿]+')))
      if (w.length >= 2 || RegExp(r'[㐀-鿿]').hasMatch(w)) w,
  ];

  bool _hit(String en, String zh, List<String> terms) {
    final e = en.toLowerCase();
    return terms.every((t) => e.contains(t) || zh.contains(t));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = _terms(_q);
    final words = terms.isEmpty
        ? const <CardRow>[]
        : _words.where((c) => _hit(c.alt, c.zh, terms)).take(20).toList();
    final lines = terms.isEmpty
        ? const <SentenceRow>[]
        : _lines
              .where((l) => l.text.length <= 14 && _hit(l.en, l.text, terms))
              .take(20)
              .toList();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const ValueKey('search-field'),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'the bill, toilet, how much…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (terms.isNotEmpty && words.isEmpty && lines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nothing for "$_q" yet. Try a simpler word, like "pay" or "where".',
                  textAlign: TextAlign.center,
                ),
              ),
            if (words.isNotEmpty) ...[
              Text('Words', style: theme.textTheme.titleSmall),
              for (final c in words)
                ListTile(
                  key: ValueKey('search-word-${c.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: wordWithReading(c.tokens, size: 24),
                  subtitle: Text(c.alt),
                  trailing: const Icon(Icons.volume_up_outlined),
                  onTap: () => _s.sayWord(c.zh, 'yue'),
                ),
            ],
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Sentences', style: theme.textTheme.titleSmall),
              for (final l in lines)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.text, style: chineseStyle('yue', fontSize: 20)),
                  subtitle: Text(
                    '${[for (final t in l.tokens) ?t.reading].join(' ')}\n${l.en}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.volume_up_outlined),
                  onTap: () => _s.saySentence(l.text),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
