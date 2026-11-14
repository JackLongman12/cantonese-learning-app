/// Start screen: one obvious action ("Start today's reading"), progress you can see,
/// and topics with how far along each one is.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/item_state.dart';
import 'cards_screen.dart';
import 'logo.dart';
import 'mascot.dart';
import 'paste_reader_screen.dart';
import 'reader_screen.dart';
import 'practice_screens.dart';
import '../platform/home_widget_sync.dart';
import '../platform/sfx.dart';
import 'settings_screen.dart';
import 'stories_screen.dart';
import 'topic_screen.dart';
import 'words_screen.dart';
import 'update_ui.dart';
import '../platform/updater.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late String _lang = _s.prefs.lang;
  int _tab = 0;
  StreamSubscription<String>? _shareSub;
  UpdateInfo? _update;

  /// Chinese text waiting on the clipboard: '' = some text (Android, unread), null = none.
  String? _clip;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shareSub = _s.shares.incoming.listen(
      (t) => _openReader(t, source: 'share'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(_checkUpdate());
      final launch = await _s.shares.takeLaunchText();
      if (launch != null && mounted) {
        await _openReader(launch, source: 'share');
      } else {
        await _checkClipboard();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkClipboard();
  }

  Future<void> _checkUpdate() async {
    final u = _s.updater;
    if (u == null) return;
    final info = await u.check();
    _s.logger.log('update.check', {'channel': 'release', 'found': info?.build});
    if (mounted && info != null) setState(() => _update = info);
  }

  /// Offer to read copied Chinese text. On Android reading the clipboard shows a system
  /// notice, so we only ask whether there is text and read it when the learner taps.
  Future<void> _checkClipboard() async {
    if (!_s.prefs.clipboardPrompt) {
      if (_clip != null) setState(() => _clip = null);
      return;
    }
    String? clip;
    try {
      if (Platform.isAndroid) {
        clip = await Clipboard.hasStrings() ? '' : null;
      } else {
        final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
        final han = RegExp(r'[\u3400-\u9fff]').allMatches(t ?? '').length;
        clip = (t != null && han >= 2 && t != _s.prefs.lastClipboardOffer)
            ? t
            : null;
      }
    } on Object {
      clip = null;
    }
    if (mounted && clip != _clip) setState(() => _clip = clip);
  }

  Future<void> _openReader(String? text, {required String source}) async {
    _s.logger.log('nav.screen', {'screen': 'free_reader', 'source': source});
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PasteReaderScreen(
          services: _s,
          lang: _lang,
          initialText: text,
          source: source,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _readClipboard() async {
    final t = _clip == null || _clip!.isEmpty
        ? (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim()
        : _clip;
    _s.prefs.lastClipboardOffer = t;
    setState(() => _clip = null);
    if (t != null && t.isNotEmpty) await _openReader(t, source: 'clipboard');
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  Future<void> _openTopic(ScenarioRow sc, {bool practise = false}) async {
    _s.prefs.setLastTopic(_lang, sc.id);
    _s.logger.log('nav.screen', {
      'screen': practise ? 'reader' : 'topic',
      'scenario_id': sc.id,
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => practise
            ? ReaderScreen(
                services: _s,
                title: sc.title,
                sentences: _s.content.sentences(sc.id, _lang),
                lang: _lang,
                scenarioId: sc.id,
              )
            : TopicScreen(services: _s, scenario: sc, lang: _lang),
      ),
    );
    if (mounted) setState(() {});
  }

  bool _isLang(ItemState st) => st.itemId.startsWith('cr:$_lang:');

  ({
    String title,
    String mode,
    List<SentenceRow> lines,
    int index,
    bool conversation,
    bool story,
  })?
  _resumable() {
    final r = _s.prefs.resume;
    if (r == null || r['lang'] != _lang) return null;
    final lines = _s.content.sentencesByIds(
      (r['ids'] as List? ?? const []).cast<String>(),
    );
    final index = (r['index'] as num?)?.toInt() ?? 0;
    if (lines.isEmpty || index <= 0 || index >= lines.length) return null;
    return (
      title: r['title'] as String? ?? 'Reading',
      mode: r['mode'] as String? ?? 'topic',
      lines: lines,
      index: index,
      conversation: r['conversation'] == true,
      story: r['story'] == true,
    );
  }

  ScenarioRow? _continueTopic(List<ScenarioRow> scenarios) {
    final id = _s.prefs.lastTopic(_lang);
    for (final sc in scenarios) {
      if (sc.id == id) return sc;
    }
    return null;
  }

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
    unawaited(syncHomeWidget(due: due, known: solid));

    Widget page(List<Widget> children) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: children,
        ),
      ),
    );

    final pages = <Widget>[
      page([
        _header(theme),
        const SizedBox(height: 20),
        if (_update case final u?)
          UpdateBanner(
            info: u,
            onLater: () => setState(() => _update = null),
            onUpdate: () => runUpdate(context, _s, u),
          ),
        _TodayCard(
          due: due,
          known: solid,
          isFirstTime: met == 0,
          hasContent: scenarios.isNotEmpty,
          onQuack: () => _s.sound(Sfx.quack),
          onStart: () => _open(
            title: met == 0 ? 'First steps' : "Today's reading",
            sentences: _s.content.allSentences(_lang),
            mode: 'daily',
            count: _s.prefs.sessionLength,
            maxNew: (_s.prefs.sessionLength / 2).ceil().clamp(3, 12),
          ),
          length: _s.prefs.sessionLength,
          onLength: (n) {
            _s.logger.log('settings.change', {
              'key': 'session_length',
              'from': _s.prefs.sessionLength,
              'to': n,
            });
            setState(() => _s.prefs.sessionLength = n);
          },
        ),
        if (_clip != null) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.tertiaryContainer,
            child: ListTile(
              key: const ValueKey('read-clipboard'),
              leading: const Icon(Icons.content_paste_go_rounded),
              title: const Text('Read what you copied'),
              subtitle: _clip!.isEmpty
                  ? null
                  : Text(
                      _clip!.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: chineseStyle(_lang, fontSize: 14),
                    ),
              trailing: IconButton(
                tooltip: 'Not now',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _s.prefs.lastClipboardOffer = _clip;
                  setState(() => _clip = null);
                },
              ),
              onTap: _readClipboard,
            ),
          ),
        ],
        if (_resumable() case final r?) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.secondaryContainer,
            child: ListTile(
              key: const ValueKey('resume'),
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: Text('Resume: ${r.title}'),
              subtitle: Text('${r.index + 1} of ${r.lines.length}'),
              trailing: IconButton(
                tooltip: 'Discard',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _s.prefs.resume = null),
              ),
              onTap: () async {
                _s.logger.log('nav.screen', {
                  'screen': 'reader',
                  'mode': 'resume',
                });
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReaderScreen(
                      services: _s,
                      title: r.title,
                      sentences: r.lines,
                      lang: _lang,
                      mode: r.mode,
                      ordered: true,
                      conversation: r.conversation,
                      story: r.story,
                      startAt: r.index,
                    ),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
        if (_continueTopic(scenarios) case final last?) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              key: const ValueKey('continue-topic'),
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: const Icon(Icons.replay_rounded),
              ),
              title: Text('Continue: ${last.title}'),
              subtitle: const Text('Straight back into its sentences'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openTopic(last, practise: true),
            ),
          ),
        ],
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
        const SizedBox(height: 20),
        Text('Reading skills', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SkillTile(
                key: const ValueKey('open-families'),
                icon: Icons.hub_rounded,
                title: 'Sound families',
                subtitle: '青 → 清 晴 請',
                onTap: () =>
                    _push(SoundFamiliesScreen(services: _s, lang: _lang)),
              ),
            ),
            if (_lang == 'yue') ...[
              const SizedBox(width: 10),
              Expanded(
                child: _SkillTile(
                  key: const ValueKey('open-spoken-written'),
                  icon: Icons.compare_arrows_rounded,
                  title: 'Spoken vs written',
                  subtitle: '佢係 · 他是',
                  onTap: () => _push(const SpokenWrittenScreen()),
                ),
              ),
            ],
          ],
        ),
      ]),
      page([
        _header(theme),
        const SizedBox(height: 20),
        if (_lang == 'yue')
          DeckSection(services: _s, onChanged: () => setState(() {})),
        Text('Topics', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Each topic has sentences and conversations. Characters you meet anywhere count everywhere.',
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
            onTap: () {
              _s.sound(Sfx.tap);
              _openTopic(sc);
            },
          ),
      ]),
      StoriesScreen(key: ValueKey('stories-$_lang'), services: _s, lang: _lang),
      WordsScreen(key: ValueKey('words-$_lang'), services: _s, lang: _lang),
      PasteReaderScreen(
        key: ValueKey('read-$_lang'),
        services: _s,
        lang: _lang,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        key: const ValueKey('nav-bar'),
        selectedIndex: _tab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          if (i == _tab) return;
          _s.sound(Sfx.tap);
          _s.logger.log('nav.screen', {
            'screen': _tabNames[i],
            'source': 'tab',
          });
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(
            key: ValueKey('tab-today'),
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny_rounded),
            label: 'Today',
          ),
          NavigationDestination(
            key: ValueKey('tab-topics'),
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Topics',
          ),
          NavigationDestination(
            key: ValueKey('tab-stories'),
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories_rounded),
            label: 'Stories',
          ),
          NavigationDestination(
            key: ValueKey('tab-words'),
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks_rounded),
            label: 'Words',
          ),
          NavigationDestination(
            key: ValueKey('tab-read'),
            icon: Icon(Icons.chrome_reader_mode_outlined),
            selectedIcon: Icon(Icons.chrome_reader_mode_rounded),
            label: 'Read',
          ),
        ],
      ),
    );
  }

  static const _tabNames = [
    'today',
    'topics',
    'stories',
    'words',
    'free_reader',
  ];

  Widget _header(ThemeData theme) {
    return Row(
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
        IconButton(
          key: const ValueKey('open-settings'),
          tooltip: 'Settings',
          onPressed: () async {
            await _push(SettingsScreen(services: _s));
            setState(() => _lang = _s.prefs.lang);
          },
          icon: const Icon(Icons.settings_rounded),
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
              label: Text('普通话', style: chineseStyle('cmn', fontSize: 14)),
            ),
          ],
          selected: {_lang},
          onSelectionChanged: (v) {
            _s.logger.log('settings.change', {
              'key': 'lang',
              'from': _lang,
              'to': v.first,
            });
            _s.prefs.lang = v.first;
            setState(() => _lang = v.first);
          },
        ),
      ],
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
    required this.length,
    required this.onLength,
    this.onQuack,
  });

  final VoidCallback? onQuack;

  final int due;
  final int known;
  final bool isFirstTime;
  final bool hasContent;
  final VoidCallback onStart;
  final int length;
  final ValueChanged<int> onLength;

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
      detail = 'Mixed with a few new ones. Pick how long you have.';
    } else {
      headline = 'All caught up';
      detail = 'Nothing is due. Keep going with some new characters.';
    }
    return Card(
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // headline beside the mascot; controls get the full width below
            Row(
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
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  key: const ValueKey('mascot'),
                  onTap: onQuack,
                  child: DuckMascot(
                    size: 92,
                    stage: DuckStage.forKnown(known),
                    mood: due == 0 && !isFirstTime
                        ? DuckMood.sleepy
                        : DuckMood.happy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _GrowthLine(known: known),
            Row(
              children: [
                Text(
                  'Sentences',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                for (final n in const [5, 15, 30]) ...[
                  ChoiceChip(
                    key: ValueKey('length-$n'),
                    label: Text('$n'),
                    showCheckmark: false,
                    selected: length == n,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onLength(n),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('start-daily'),
              onPressed: hasContent ? onStart : null,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(isFirstTime ? 'Start' : "Start today's reading"),
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

class _SkillTile extends StatelessWidget {
  const _SkillTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(title, style: theme.textTheme.titleSmall),
              Text(subtitle, style: chineseStyle('yue', fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
