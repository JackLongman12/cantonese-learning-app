/// Start screen: one obvious action ("Start today's reading"), progress you can see,
/// and topics with how far along each one is.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/item_state.dart';
import '../engine/adaptive.dart';
import '../engine/goals.dart';
import '../engine/path.dart';
import '../engine/weak_spots.dart';
import 'cards_screen.dart';
import 'goal_picker.dart';
import 'paste_reader_screen.dart';
import 'reader_screen.dart';
import 'reminder_sync.dart';
import 'practice_screens.dart';
import 'progress_view.dart';
import 'skills.dart';
import '../platform/sfx.dart';
import 'settings_screen.dart';
import 'speak_drill_screen.dart';
import 'stories_screen.dart';
import 'critters.dart';
import 'finish.dart';
import 'tiles.dart';
import 'topic_screen.dart';
import 'word_sheet.dart';
import 'words_screen.dart';
import 'update_ui.dart';
import '../platform/updater.dart';
import 'ruby_text.dart';

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

  /// Topic groups for the filter chips (matched against topic ids).
  /// Topics grouped by kind of situation, in this order. A topic goes in the first
  /// group whose keyword is in its id; anything unmatched lands in "More".
  static const _topicGroups = <(String, List<String>)>[
    ('The basics', ['numbers', 'signs', 'variants']),
    ('Getting around', ['getting-around', 'tourism']),
    ('Food and shopping', ['food', 'shopping']),
    ('Home and health', ['home', 'daily', 'health', 'weather']),
    ('Errands and work', ['gov', 'work']),
    ('People and chat', ['chat', 'messaging', 'swearing']),
  ];
  StreamSubscription<String>? _shareSub;
  UpdateInfo? _update;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shareSub = _s.shares.incoming.listen(
      (t) => _openReader(t, source: 'share'),
    );
    // while the app is open, look again now and then (a release can land any time)
    _updateTimer = Timer.periodic(const Duration(minutes: 20), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _checkUpdate();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(_checkUpdate());
      final launch = await _s.shares.takeLaunchText();
      if (launch != null && mounted) {
        await _openReader(launch, source: 'share');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshReminders());
      // reopening the app from the background counts as opening it: check every
      // time (only a quick request; at most once every two minutes)
      final last = _lastUpdateCheck;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 2)) {
        _checkUpdate();
      }
    }
  }

  DateTime? _lastUpdateCheck;
  Timer? _updateTimer;

  /// The build already offered in a dialog this run (asked once; the banner stays).
  int? _offeredBuild;

  Future<void> _checkUpdate() async {
    final u = _s.updater;
    if (u == null) return;
    _lastUpdateCheck = DateTime.now();
    final info = await u.check();
    _s.logger.log('update.check', {'channel': 'release', 'found': info?.build});
    if (!mounted || info == null) return;
    setState(() => _update = info);
    _offerUpdate();
  }

  /// Asks once per new build, on whichever tab is open; during an exercise it waits
  /// until you are back on the home screen.
  void _offerUpdate() {
    final info = _update;
    if (info == null || info.build == _offeredBuild || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _offeredBuild = info.build;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('update-offer'),
        title: Text('Update available · ${info.version}'),
        content: Text(
          'A new DuckLearn is ready (${(info.assetSize / 1e6).round()} MB). '
          'Your progress stays as it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              runUpdate(context, _s, info);
            },
            child: const Text('Update now'),
          ),
        ],
      ),
    );
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

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    _insights = null;
    if (mounted) setState(() {});
    _offerUpdate();
  }

  ({
    int newChars,
    int sentences,
    List<SoundMixup> sounds,
    List<ItemState> chars,
    SessionPlan session,
    ({int? readingPct, int? speakingPct}) accuracy,
    ({
      PeriodStats thisWeek,
      PeriodStats lastWeek,
      PeriodStats? firstWeek,
      List<int> metByWeek,
    })
    time,
  })?
  _insights;

  /// Week activity and weak spots, from the event log (cached until an exercise ends).
  ({
    int newChars,
    int sentences,
    List<SoundMixup> sounds,
    List<ItemState> chars,
    SessionPlan session,
    ({int? readingPct, int? speakingPct}) accuracy,
    ({
      PeriodStats thisWeek,
      PeriodStats lastWeek,
      PeriodStats? firstWeek,
      List<int> metByWeek,
    })
    time,
  })
  _overview() {
    if (_insights case final i?) return i;
    final events = _s.logger.store.readAll().toList();
    final w = weekProgress(events, _s.logger.now().toUtc());
    return _insights = (
      newChars: w.newChars,
      sentences: w.sentences,
      sounds: weakSounds(events),
      chars: weakCharacters(_s.learner.known, _lang),
      session: adaptSession(events, _s.logger.now().toUtc()),
      accuracy: weekAccuracy(events, _s.logger.now().toUtc()),
      time: progressOverTime(events, _s.logger.now().toUtc()),
    );
  }

  Future<void> _openTopic(ScenarioRow sc, {bool practice = false}) async {
    _s.prefs.setLastTopic(_lang, sc.id);
    _s.logger.log('nav.screen', {
      'screen': practice ? 'reader' : 'topic',
      'scenario_id': sc.id,
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => practice
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
    _insights = null;
    if (mounted) setState(() {});
    _offerUpdate();
    await _offerReminder();
    unawaited(_refreshReminders());
  }

  /// Keeps the next reminders in step with today's reading (called on open/return).
  Future<void> _refreshReminders() => syncReminders(_s);

  /// Reminder on/off and time, from the bell on Today.
  Future<void> _reminderSheet() async {
    final r = _s.reminders!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  key: const ValueKey('reminder-toggle'),
                  title: const Text('Gentle reminder'),
                  subtitle: Text(
                    '${reminderLabel(_s)}. Only on days you have not read '
                    'yet; it stops by itself if you take a break.',
                  ),
                  value: _s.prefs.reminderOn,
                  onChanged: (on) async {
                    if (on && !await r.requestPermission()) return;
                    _s.prefs.reminderOn = on;
                    await syncReminders(_s);
                    _s.logger.log('settings.change', {
                      'key': 'reminder',
                      'from': !on,
                      'to': on,
                    });
                    set(() {});
                    if (mounted) setState(() {});
                  },
                ),
                if (_s.prefs.reminderOn)
                  ...reminderTimeTiles(ctx, _s, (from, to) {
                    _s.logger.log('settings.change', {
                      'key': 'reminder_minute',
                      'from': from,
                      'to': to,
                    });
                    set(() {});
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Once, after the first session: a daily nudge, smart-timed (opt-in).
  Future<void> _offerReminder() async {
    final r = _s.reminders;
    if (r == null || _s.prefs.reminderOffered || _s.prefs.reminderOn) return;
    if (_s.learner.known.isEmpty || !mounted) return;
    _s.prefs.reminderOffered = true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('A little every day?'),
        content: const Text(
          'Reading a few sentences daily works far better than a lot once a '
          'week. Want a quiet reminder? It learns when you usually read and '
          'skips days you already did. You can set a fixed time in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No thanks'),
          ),
          FilledButton(
            key: const ValueKey('reminder-yes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remind me'),
          ),
        ],
      ),
    );
    if (yes != true || !await r.requestPermission()) return;
    _s.prefs
      ..reminderOn = true
      ..reminderMinute = null; // smart
    await syncReminders(_s);
    _s.logger.log('settings.change', {
      'key': 'reminder',
      'from': false,
      'to': true,
    });
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
    final base = [
      ...order,
      if (byId.containsKey('scn-swearing')) 'scn-swearing',
    ];
    // your goal's topics first; everything else follows in the usual order
    return [
      for (final id in orderForGoal(base, goalById(_s.prefs.goal))) byId[id]!,
    ];
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
    Set<String> focus = const {},
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
          focus: focus,
          onComplete: onComplete,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Today's plan as last built (the finish screens ask what comes next).
  List<_PlanStep> _lastPlan = const [];
  String _lastDay = '';

  _PlanStep? get _nextUndone {
    final done = _s.prefs.planDone(_lastDay);
    return _lastPlan.where((p) => !done.contains(p.id)).firstOrNull;
  }

  /// Back to Home, rebuild, then do [then] (from a finish screen anywhere).
  void _fromAnywhere(void Function() then) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) then();
    });
  }

  Future<void> _openTool(String id) async {
    _s.sound(Sfx.tap);
    _s.logger.log('nav.screen', {'screen': 'tool-$id', 'source': 'tools'});
    switch (id) {
      case 'topics':
        setState(() => _tab = 1);
      case 'stories':
        setState(() => _tab = 2);
      case 'cards':
        await _push(
          _ToolPage(
            title: 'Flashcards',
            children: [
              DeckSection(services: _s, onChanged: () => setState(() {})),
            ],
          ),
        );
      case 'speak':
        await _push(
          SpeakDrillScreen(
            services: _s,
            title: 'Speak',
            sentences: pickSpeakLines(_s, _s.content.allSentences(_lang)),
          ),
        );
      case 'words':
        await _push(
          Scaffold(
            appBar: AppBar(title: const Text('My words')),
            body: SafeArea(
              child: WordsScreen(services: _s, lang: _lang),
            ),
          ),
        );
      case 'skills':
        await _push(
          _ToolPage(
            title: 'Reading skills',
            children: [
              Builder(
                builder: (context) => TileGrid(
                  children: [
                    AppTile(
                      key: const ValueKey('open-families'),
                      icon: Icons.hub_rounded,
                      title: 'Sound families',
                      subtitle: '青 → 清 晴 請',
                      subtitleStyle: chineseStyle('yue', fontSize: 14),
                      onTap: () =>
                          _push(SoundFamiliesScreen(services: _s, lang: _lang)),
                    ),
                    AppTile(
                      key: const ValueKey('open-spoken-written'),
                      icon: Icons.compare_arrows_rounded,
                      title: 'Spoken vs written',
                      subtitle: '佢係 · 他是',
                      subtitleStyle: chineseStyle('yue', fontSize: 14),
                      onTap: () => _push(const SpokenWrittenScreen()),
                    ),
                    ...extraSkillTiles(context, _s, _push),
                  ],
                ),
              ),
            ],
          ),
        );
    }
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
    // learned: met and then read again without help (moves the level from day one;
    // "known well" below is the slower three-week measure)
    final learned = states
        .where((x) => x.reps >= 2 && (x.stability ?? 0) >= 1)
        .length;
    final totalChars = itemsByScenario.values.expand((x) => x).toSet().length;
    final path = _pathOrder(scenarios, itemsByScenario);
    final upNextId = upNext(
      [for (final sc in path) sc.id],
      itemsByScenario,
      (id) => !_s.learner.stateOf(id).isNew,
    );

    Widget page(List<Widget> children, {bool still = false}) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ScrollConfiguration(
          // Home fits on one screen: no stretch or bounce that makes it feel like a
          // scrolling page. It still scrolls when it really doesn't fit (small phone,
          // large text).
          behavior: ScrollConfiguration.of(context)
              .copyWith(overscroll: !still),
          child: ListView(
            physics: still ? const ClampingScrollPhysics() : null,
            padding: EdgeInsets.fromLTRB(20, 16, 20, still ? 12 : 32),
            children: children,
          ),
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
    final goal = goalById(_s.prefs.goal);
    final overview = _overview();
    final practiceWords = _s.words.practice(_lang);
    final cardsDue = _lang == 'yue'
        ? dueCards(_s, _s.content.decks())
        : const <CardRow>[];
    final reviewCount = due + overview.chars.length + practiceWords.length;
    final plan = <_PlanStep>[
      // Review: due characters, weak spots and words to practice in one session of
      // sentences. Due flashcards only when there are no sentences to review (one
      // screen per step, so Back leaves the whole review; cards also show on the
      // Cards tile).
      if (reviewCount > 0 || cardsDue.isNotEmpty || done.contains('review'))
        _PlanStep(
          id: 'review',
          icon: Icons.history_edu_rounded,
          title: 'Review',
          detail: [
            if (due > 0) '$due due',
            if (overview.chars.isNotEmpty) '${overview.chars.length} weak',
            if (practiceWords.isNotEmpty) '${practiceWords.length} words',
            if (reviewCount == 0 && cardsDue.isNotEmpty)
              '${cardsDue.length} cards',
          ].join(' · '),
          done: done.contains('review'),
          start: () async {
            final focus = {for (final c in overview.chars) c.itemId};
            final wordSentences = {
              for (final w in practiceWords) ?w.sentenceId,
            };
            final all = _s.content.allSentences(_lang);
            final weakLines = [
              for (final x in all)
                if (wordSentences.contains(x.id) ||
                    x.itemIds.any(focus.contains))
                  x,
            ];
            if (due > 0 || weakLines.isNotEmpty) {
              return _open(
                title: 'Review',
                // weak spots and flagged words first, then whatever is due
                sentences: [
                  ...weakLines,
                  ...all.where((x) => !weakLines.contains(x)),
                ],
                mode: 'review',
                count: overview.session.count,
                maxNew: 0,
                focus: focus,
                onComplete: () => finished('review'),
              );
            }
            if (cardsDue.isNotEmpty) {
              await _push(
                CardSessionScreen(
                  services: _s,
                  deck: const DeckRow('due', 'Cards due', 'both', '', 0),
                  cards: cardsDue.take(20).toList(),
                  onComplete: () => finished('review'),
                ),
              );
            }
          },
        ),
      if (nextTopic != null)
        _PlanStep(
          id: 'learn',
          icon: Icons.flag_rounded,
          title: 'Learn: ${nextTopic.title}',
          detail: goal.id == 'all'
              ? 'New sentences, next on your path'
              : 'Next for your goal: ${goal.title.toLowerCase()}.',
          done: done.contains('learn'),
          start: () {
            _s.prefs.setLastTopic(_lang, nextTopic.id);
            return _open(
              title: nextTopic.title,
              sentences: _s.content.sentences(nextTopic.id, _lang),
              mode: 'path',
              scenarioId: nextTopic.id,
              // a first session is short: finish it, feel the win, come back
              count: met == 0 ? 5 : overview.session.count,
              maxNew: met == 0 ? 4 : overview.session.maxNew,
              onComplete: () => finished('learn'),
            );
          },
        ),
      _PlanStep(
        id: 'speak',
        icon: Icons.record_voice_over_rounded,
        title: 'Speak',
        detail: '10 lines, tap the mic and say them',
        done: done.contains('speak'),
        start: () => _push(
          SpeakDrillScreen(
            services: _s,
            title: 'Speak',
            mode: SpeakMode.read,
            sentences: pickSpeakLines(
              _s,
              // lines from your goal's topics (all topics for "a bit of everything")
              [
                for (final sc in scenarios)
                  if (inGoal(sc.id, goal) && sc.id != 'scn-swearing')
                    ..._s.content.sentences(sc.id, _lang),
              ],
            ),
            onComplete: () => finished('speak'),
          ),
        ),
      ),
    ];
    // learn something before speaking it; the rest after
    const order = ['review', 'learn', 'speak'];
    plan.sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
    final nextStep = plan.where((x) => !x.done).firstOrNull;
    _lastPlan = plan;
    _lastDay = day;
    _s.home = HomeLink(
      next: () {
        final n = _nextUndone;
        if (n == null) return null;
        return (title: n.title, number: _lastPlan.indexOf(n) + 1);
      },
      startNext: () => _fromAnywhere(() => _nextUndone?.start()),
      openTool: (id) => _fromAnywhere(() => _openTool(id)),
    );

    void startDaily() => _open(
      title: met == 0 ? 'First steps' : "Today's reading",
      sentences: _s.content.allSentences(_lang),
      mode: 'daily',
      count: overview.session.count,
      maxNew: overview.session.maxNew,
    );

    final pages = <Widget>[
      page([
        _header(theme),
        const SizedBox(height: 8),
        if (_update case final u?)
          UpdateBanner(
            info: u,
            onLater: () => setState(() => _update = null),
            onUpdate: () => runUpdate(context, _s, u),
          ),
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
        if (_s.prefs.goal == null)
          Card(
            key: const ValueKey('goal-ask'),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'What do you want Cantonese for?',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your plan will start with those topics.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  GoalList(
                    selected: null,
                    onPick: (g) => setState(() => setGoal(_s, g)),
                  ),
                ],
              ),
            ),
          )
        else
          Row(
            key: const ValueKey('goal-row'),
            children: [
              Chick(
                mood: nextStep == null && plan.isNotEmpty
                    ? ChickMood.sleepy
                    : ChickMood.innocent,
                size: 64,
                sway: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nextStep == null && plan.isNotEmpty
                      ? 'All done today'
                      : 'Goal: ${goal.title}',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                key: const ValueKey('goal-change'),
                onPressed: () async {
                  if (await pickGoal(context, _s)) setState(() {});
                },
                child: const Text('Change'),
              ),
            ],
          ),
        const SizedBox(height: 8),
        for (final (i, step) in plan.indexed)
          _PlanTile(step: step, number: i + 1, current: step == nextStep),
        const SizedBox(height: 14),
        Text(
          'Or pick something',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ToolGrid(
          onTap: _openTool,
          // Topics and Stories are tabs; the rest as four big tiles
          hide: const {'topics', 'stories'},
          columns: 2,
          badges: {
            if (cardsDue.isNotEmpty) 'cards': '${cardsDue.length} due',
            if (practiceWords.isNotEmpty) 'words': '${practiceWords.length}',
          },
        ),
      ], still: true),
      page([
        Text('Topics', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          'Everything is open. "Up next" is the suggested next topic.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (scenarios.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No content yet.', textAlign: TextAlign.center),
          ),
        // grouped by kind of situation, each group in path order
        for (final (name, list) in _groupTopics(
          _pathOrder(scenarios, itemsByScenario),
        )) ...[
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 10),
            child: Text(
              name,
              key: ValueKey('topic-group-$name'),
              style: theme.textTheme.titleMedium,
            ),
          ),
          TileGrid(
            children: [
              for (final sc in list)
                _TopicTile(
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
            ],
          ),
        ],
        const SizedBox(height: 24),
      ]),
      StoriesScreen(key: ValueKey('stories-$_lang'), services: _s, lang: _lang),
      page([
        ProgressView(
          met: met,
          learned: learned,
          readablePct: totalChars == 0
              ? null
              : (100 * solid / totalChars).round(),
          thisWeek: overview.time.thisWeek,
          lastWeek: overview.time.lastWeek,
          firstWeek: overview.time.firstWeek,
          metByWeek: overview.time.metByWeek,
          chars: overview.chars,
          sounds: overview.sounds,
          wordsToPractice: practiceWords.length,
          cardsDue: cardsDue.length,
          onChar: (c) => sayOrExplain(context, _s, c, _lang),
          onReview: plan.where((p) => p.id == 'review').firstOrNull?.start,
          onWords: () => _openTool('words'),
          onCards: () => _openTool('cards'),
          onSpeak: () => _openTool('speak'),
        ),
      ]),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // a duckling joins mama for every step finished today
                    DuckFamily(ducklings: plan.where((p) => p.done).length),
                    SizedBox(
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
                                    : 'Start: ${nextStep.title}')
                              : 'Read more',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
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
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                key: ValueKey('tab-topics'),
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map_rounded),
                label: 'Topics',
              ),
              NavigationDestination(
                key: ValueKey('tab-stories'),
                icon: Icon(Icons.auto_stories_outlined),
                selectedIcon: Icon(Icons.auto_stories_rounded),
                label: 'Stories',
              ),
              NavigationDestination(
                key: ValueKey('tab-progress'),
                icon: Icon(Icons.insert_chart_outlined_rounded),
                selectedIcon: Icon(Icons.insert_chart_rounded),
                label: 'Progress',
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<(String, List<ScenarioRow>)> _groupTopics(List<ScenarioRow> ordered) {
    final groups = {for (final (n, _) in _topicGroups) n: <ScenarioRow>[]};
    final more = <ScenarioRow>[];
    for (final sc in ordered) {
      final g = _topicGroups.where((g) => g.$2.any(sc.id.contains)).firstOrNull;
      (g == null ? more : groups[g.$1]!).add(sc);
    }
    return [
      for (final e in groups.entries)
        if (e.value.isNotEmpty) (e.key, e.value),
      if (more.isNotEmpty) ('More', more),
    ];
  }

  static const _tabNames = ['today', 'topics', 'stories', 'progress'];

  Widget _header(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Today',
            style: theme.textTheme.titleLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_s.reminders != null)
          IconButton(
            key: const ValueKey('reminder-bell'),
            tooltip: 'Reminder',
            onPressed: _reminderSheet,
            icon: Icon(
              _s.prefs.reminderOn
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
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
  const _PlanTile({
    required this.step,
    required this.number,
    required this.current,
  });
  final _PlanStep step;
  final int number;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = current ? scheme.onPrimaryContainer : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: current ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('plan-${step.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: step.start,
          // every plan tile the same height, done or not
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                EggMarker(number: number, current: current, done: step.done),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: step.done ? scheme.onSurfaceVariant : fg,
                        ),
                      ),
                      if (!step.done && step.detail.isNotEmpty)
                        Text(
                          step.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: fg ?? scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (current) Icon(Icons.play_arrow_rounded, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain page for a tool opened from Home (flashcards, skills).
class _ToolPage extends StatelessWidget {
  const _ToolPage({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: children,
          ),
        ),
      ),
    ),
  );
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
    'daily': Icons.location_city_rounded,
    'variants': Icons.swap_horiz_rounded,
  };
  for (final e in byKeyword.entries) {
    if (id.contains(e.key)) return e.value;
  }
  return Icons.menu_book_rounded;
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    this.next = false,
    required this.scenario,
    required this.total,
    required this.met,
    required this.onTap,
  });

  /// Position on the beginner path (null: not on the path).

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
