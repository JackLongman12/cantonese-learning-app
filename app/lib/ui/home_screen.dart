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
import '../engine/path.dart';
import 'cards_screen.dart';
import 'logo.dart';
import 'mascot.dart';
import 'paste_reader_screen.dart';
import 'practice_words_screen.dart';
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

  late final Map<String, int> _frequency = _s.content.itemFrequency(_lang);

  /// Topics from easiest to hardest (common characters first); swearing goes last.
  List<ScenarioRow> _pathOrder(
    List<ScenarioRow> scenarios,
    Map<String, Set<String>> items,
  ) {
    final byId = {for (final sc in scenarios) sc.id: sc};
    final order = orderTopics({
      for (final sc in scenarios)
        if (sc.id != 'scn-swearing') sc.id: items[sc.id] ?? const {},
    }, _frequency);
    return [for (final id in order) byId[id]!, ?byId['scn-swearing']];
  }

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

  Future<void> _open({
    required String title,
    required List<SentenceRow> sentences,
    required String mode,
    String? scenarioId,
    int? count,
    int maxNew = 12,
    VoidCallback? onComplete,
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
          onComplete: onComplete,
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
    final path = _pathOrder(scenarios, itemsByScenario);
    final upNextId = upNext(
      [for (final sc in path) sc.id],
      itemsByScenario,
      (id) => !_s.learner.stateOf(id).isNew,
    );
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

    // Today's plan: a few clear steps, ticked off as they are finished.
    final day = now.toLocal().toIso8601String().substring(0, 10);
    final done = _s.prefs.planDone(day);
    void finished(String id) {
      _s.prefs.markPlanDone(day, id);
      _s.logger.log('plan.step', {'step': id, 'day': day});
    }

    final nextTopic = scenarios.where((x) => x.id == upNextId).firstOrNull;
    final practiseWords = _s.words.practice(_lang);
    final cardsDue = _lang == 'yue'
        ? dueCards(_s, _s.content.decks())
        : const <CardRow>[];
    final plan = <_PlanStep>[
      if (due > 0 || done.contains('review'))
        _PlanStep(
          id: 'review',
          icon: Icons.history_edu_rounded,
          title: 'Review ${due > 0 ? '$due ' : ''}characters',
          detail: 'Sentences with characters you have met, before they fade.',
          done: done.contains('review'),
          start: () => _open(
            title: 'Review',
            sentences: _s.content.allSentences(_lang),
            mode: 'review',
            count: due.clamp(5, 15),
            maxNew: 0,
            onComplete: () => finished('review'),
          ),
        ),
      if (nextTopic != null)
        _PlanStep(
          id: 'learn',
          icon: Icons.flag_rounded,
          title: 'Learn: ${nextTopic.title}',
          detail: 'New sentences from the next topic on your path.',
          done: done.contains('learn'),
          start: () {
            _s.prefs.setLastTopic(_lang, nextTopic.id);
            return _open(
              title: nextTopic.title,
              sentences: _s.content.sentences(nextTopic.id, _lang),
              mode: 'path',
              scenarioId: nextTopic.id,
              count: 8,
              maxNew: 5,
              onComplete: () => finished('learn'),
            );
          },
        ),
      if (practiseWords.isNotEmpty || done.contains('words'))
        _PlanStep(
          id: 'words',
          icon: Icons.record_voice_over_rounded,
          title: practiseWords.isEmpty
              ? 'Practise words'
              : 'Practise ${practiseWords.length} ${practiseWords.length == 1 ? 'word' : 'words'}',
          detail: 'Words you needed help with, read aloud in their sentences.',
          done: done.contains('words'),
          start: () => _push(
            PracticeWordsScreen(
              services: _s,
              words: practiseWords.take(10).toList(),
              onComplete: () => finished('words'),
            ),
          ),
        ),
      if (cardsDue.isNotEmpty || done.contains('cards'))
        _PlanStep(
          id: 'cards',
          icon: Icons.style_rounded,
          title: cardsDue.isEmpty
              ? 'Flashcards'
              : 'Review ${cardsDue.length} flashcards',
          detail: 'Dishes, streets and stations you are learning.',
          done: done.contains('cards'),
          start: () => _push(
            CardSessionScreen(
              services: _s,
              deck: const DeckRow('due', 'Cards due', 'both', '', 0),
              cards: cardsDue.take(20).toList(),
              onComplete: () => finished('cards'),
            ),
          ),
        ),
    ];
    final nextStep = plan.where((x) => !x.done).firstOrNull;

    void startDaily() => _open(
      title: met == 0 ? 'First steps' : "Today's reading",
      sentences: _s.content.allSentences(_lang),
      mode: 'daily',
      count: _s.prefs.sessionLength,
      maxNew: (_s.prefs.sessionLength / 2).ceil().clamp(3, 12),
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
          onStart: startDaily,
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
        const SizedBox(height: 16),
        for (final step in plan) _PlanTile(step: step),
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
      ]),
      page([
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No content yet.', textAlign: TextAlign.center),
          ),
        // two columns: half the scrolling on a phone
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 560 ? 3 : 2;
            final w = (box.maxWidth - 10 * (cols - 1)) / cols;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (step, sc) in _pathOrder(
                  scenarios,
                  itemsByScenario,
                ).indexed)
                  SizedBox(
                    width: w,
                    child: _TopicTile(
                      step: sc.id == 'scn-swearing' ? null : step + 1,
                      next: sc.id == upNextId,
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
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 24),
      ]),
      page([
        if (_lang == 'yue')
          DeckSection(services: _s, onChanged: () => setState(() {})),
      ]),
      StoriesScreen(key: ValueKey('stories-$_lang'), services: _s, lang: _lang),
      WordsScreen(key: ValueKey('words-$_lang'), services: _s, lang: _lang),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      // the day's main action sits right above the tabs, under the thumb
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tab == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('start-daily'),
                    onPressed: scenarios.isEmpty
                        ? null
                        : nextStep?.start ?? startDaily,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 56),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      nextStep != null
                          ? (nextStep.id == 'learn' && met == 0
                                ? 'Start'
                                : 'Next: ${nextStep.title}')
                          : 'All done today. Read more',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          NavigationBar(
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
                key: ValueKey('tab-cards'),
                icon: Icon(Icons.style_outlined),
                selectedIcon: Icon(Icons.style_rounded),
                label: 'Cards',
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
            ],
          ),
        ],
      ),
    );
  }

  static const _tabNames = ['today', 'topics', 'cards', 'stories', 'words'];

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
      ],
    );
  }
}

class _PlanStep {
  const _PlanStep({
    required this.id,
    required this.icon,
    required this.title,
    required this.detail,
    required this.done,
    required this.start,
  });
  final String id;
  final IconData icon;
  final String title;
  final String detail;
  final bool done;
  final Future<void> Function() start;
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.step});
  final _PlanStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: ValueKey('plan-${step.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: step.done ? scheme.primary : scheme.primaryContainer,
          foregroundColor: step.done
              ? scheme.onPrimary
              : scheme.onPrimaryContainer,
          child: Icon(step.done ? Icons.check_rounded : step.icon),
        ),
        title: Text(
          step.title,
          style: theme.textTheme.titleSmall?.copyWith(
            decoration: step.done ? TextDecoration.lineThrough : null,
            color: step.done ? scheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: Text(step.detail),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: step.start,
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
          'Your plan for today is below: short real-life sentences, Jyutping '
          'over every new character, fading as you learn it.';
    } else if (due > 0) {
      headline = '$due ${due == 1 ? 'character' : 'characters'} to review';
      detail = 'Start with them, then something new. Your plan is below.';
    } else {
      headline = 'All caught up';
      detail = 'Nothing is due. Carry on with the next step below.';
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
    'swearing': Icons.sentiment_very_dissatisfied_rounded,
  };
  for (final e in byKeyword.entries) {
    if (id.contains(e.key)) return e.value;
  }
  return Icons.menu_book_rounded;
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    this.step,
    this.next = false,
    required this.scenario,
    required this.total,
    required this.met,
    required this.onTap,
  });

  /// Position on the beginner path (null: not on the path).
  final int? step;

  /// The recommended next topic.
  final bool next;
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
      margin: EdgeInsets.zero,
      shape: next
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
                    child: Icon(_topicIcon(scenario.id), size: 18),
                  ),
                  const Spacer(),
                  if (next)
                    Container(
                      key: const ValueKey('up-next-chip'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Up next',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    )
                  else if (step != null)
                    Text(
                      'Step $step',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: Text(
                  scenario.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 5,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$met / $total characters',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
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
    final lv = readingLevel(known);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Level ${lv.level}',
                key: const ValueKey('reading-level'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: lv.need == 0 ? 1 : lv.have / lv.need,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                lv.need == 0 ? 'top level' : '${lv.have}/${lv.need}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text.rich(
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
        ],
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
