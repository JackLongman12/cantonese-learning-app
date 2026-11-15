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
import '../engine/adaptive.dart';
import '../engine/path.dart';
import '../engine/weak_spots.dart';
import 'cards_screen.dart';
import 'logo.dart';
import 'mascot.dart';
import 'paste_reader_screen.dart';
import 'reader_screen.dart';
import 'practice_screens.dart';
import 'skills.dart';
import '../platform/home_widget_sync.dart';
import '../platform/sfx.dart';
import 'settings_screen.dart';
import 'speak_drill_screen.dart';
import 'stories_screen.dart';
import 'topic_screen.dart';
import 'word_sheet.dart';
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
  String _topicFilter = 'All';

  /// Topic groups for the filter chips (matched against topic ids).
  static const _topicGroups = <String, List<String>?>{
    'All': null,
    'Getting around': ['getting-around', 'tourism'],
    'Food': ['food'],
    'Daily life': [
      'home',
      'shopping',
      'health',
      'weather',
      'numbers',
      'messaging',
      'signs',
    ],
    'Work & papers': ['gov', 'work'],
    'People & culture': ['chat', 'swearing'],
  };
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
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
      unawaited(_refreshReminders());
      // reopening the app from the background counts as opening it
      final last = _lastUpdateCheck;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 30)) {
        _checkUpdate();
      }
    }
  }

  DateTime? _lastUpdateCheck;

  Future<void> _checkUpdate() async {
    final u = _s.updater;
    if (u == null) return;
    _lastUpdateCheck = DateTime.now();
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
    _insights = null;
    if (mounted) setState(() {});
  }

  ({
    int newChars,
    int sentences,
    List<SoundMixup> sounds,
    List<ItemState> chars,
    SessionPlan session,
    ({int? readingPct, int? speakingPct}) accuracy,
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
    );
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
    _insights = null;
    if (mounted) setState(() {});
    await _offerReminder();
    unawaited(_refreshReminders());
  }

  /// Read anything today? (a reminder is then skipped for today)
  bool get _readToday {
    final now = _s.logger.now().toLocal();
    return _s.learner.known.any((x) {
      final l = x.lastReview?.toLocal();
      return l != null &&
          l.year == now.year &&
          l.month == now.month &&
          l.day == now.day;
    });
  }

  /// Keeps the next reminders in step with today's reading (called on open/return).
  Future<void> _refreshReminders() async {
    final r = _s.reminders;
    final m = _s.prefs.reminderMinute;
    if (r == null || !_s.prefs.reminderOn || m == null) return;
    await r.scheduleDaily(m, readToday: _readToday);
  }

  /// Reminder on/off and time, from the bell on Today.
  Future<void> _reminderSheet() async {
    final r = _s.reminders!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final m = _s.prefs.reminderMinute ?? 20 * 60;
          final clock =
              '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    key: const ValueKey('reminder-toggle'),
                    title: const Text('Gentle reminder'),
                    subtitle: const Text(
                      'Only on days you have not read yet. It stops by itself if '
                      'you take a break.',
                    ),
                    value: _s.prefs.reminderOn,
                    onChanged: (on) async {
                      if (on && !await r.requestPermission()) return;
                      _s.prefs.reminderOn = on;
                      _s.prefs.reminderMinute ??= m;
                      on ? await _refreshReminders() : await r.cancel();
                      _s.logger.log('settings.change', {
                        'key': 'reminder',
                        'from': !on,
                        'to': on,
                      });
                      set(() {});
                      if (mounted) setState(() {});
                    },
                  ),
                  ListTile(
                    title: const Text('Time'),
                    trailing: Text(clock),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
                      );
                      if (t == null) return;
                      _s.prefs.reminderMinute = t.hour * 60 + t.minute;
                      await _refreshReminders();
                      set(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Once, after the first session: a daily nudge at this time of day (opt-in).
  Future<void> _offerReminder() async {
    final r = _s.reminders;
    if (r == null || _s.prefs.reminderOffered || _s.prefs.reminderOn) return;
    if (_s.learner.known.isEmpty || !mounted) return;
    _s.prefs.reminderOffered = true;
    final now = TimeOfDay.now();
    final minute = now.hour * 60 + now.minute;
    final clock =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('A little every day?'),
        content: Text(
          'Reading a few sentences daily works far better than a lot once a week. '
          'Want a quiet reminder at $clock each day? You can change it in Settings.',
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
      ..reminderMinute = minute;
    await r.scheduleDaily(minute, readToday: true);
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
    final overview = _overview();
    final practiseWords = _s.words.practice(_lang);
    final cardsDue = _lang == 'yue'
        ? dueCards(_s, _s.content.decks())
        : const <CardRow>[];
    final reviewCount = due + overview.chars.length + practiseWords.length;
    final plan = <_PlanStep>[
      // Review: due characters, weak spots and words to practise in one session of
      // sentences, then any flashcards that are due.
      if (reviewCount > 0 || cardsDue.isNotEmpty || done.contains('review'))
        _PlanStep(
          id: 'review',
          icon: Icons.history_edu_rounded,
          title: 'Review',
          detail: [
            if (due > 0) '$due due',
            if (overview.chars.isNotEmpty) '${overview.chars.length} weak',
            if (practiseWords.isNotEmpty) '${practiseWords.length} words',
            if (cardsDue.isNotEmpty) '${cardsDue.length} cards',
          ].join(' · '),
          done: done.contains('review'),
          start: () async {
            final focus = {for (final c in overview.chars) c.itemId};
            final wordSentences = {
              for (final w in practiseWords) ?w.sentenceId,
            };
            final all = _s.content.allSentences(_lang);
            final weakLines = [
              for (final x in all)
                if (wordSentences.contains(x.id) ||
                    x.itemIds.any(focus.contains))
                  x,
            ];
            if (due > 0 || weakLines.isNotEmpty) {
              await _open(
                title: 'Review',
                // weak spots and flagged words first, then whatever is due
                sentences: [
                  ...weakLines,
                  ...all.where((x) => !weakLines.contains(x)),
                ],
                mode: 'review',
                count: overview.session.count,
                maxNew: 0,
                onComplete: () => finished('review'),
              );
            }
            if (cardsDue.isNotEmpty && mounted) {
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
          detail: 'New sentences from the next topic on your path.',
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
        title: 'Speak 10 sentences',
        detail: 'Read each line aloud; the mic checks you, line after line.',
        done: done.contains('speak'),
        start: () => _push(
          SpeakDrillScreen(
            services: _s,
            title: 'Speak',
            mode: SpeakMode.read,
            sentences: pickSpeakLines(
              _s,
              met < 20 && nextTopic != null
                  ? _s.content.sentences(nextTopic.id, _lang)
                  : _s.content.allSentences(_lang),
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
        const SizedBox(height: 20),
        if (_update case final u?)
          UpdateBanner(
            info: u,
            onLater: () => setState(() => _update = null),
            onUpdate: () => runUpdate(context, _s, u),
          ),
        _TodayCard(
          due: due,
          known: learned,
          isFirstTime: met == 0,
          hasContent: scenarios.isNotEmpty,
          onQuack: () => _s.sound(Sfx.quack),
          onStart: startDaily,
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
        const SizedBox(height: 16),
        _WeekCard(newChars: overview.newChars, sentences: overview.sentences),
        if (overview.sounds.isNotEmpty ||
            overview.chars.isNotEmpty ||
            overview.accuracy.readingPct != null) ...[
          const SizedBox(height: 12),
          _WeakSpotsCard(
            readingPct: overview.accuracy.readingPct,
            speakingPct: overview.accuracy.speakingPct,
            wordsToPractise: practiseWords.length,
            cardsDue: cardsDue.length,
            sounds: overview.sounds,
            chars: overview.chars,
            onChar: (c) => sayOrExplain(context, _s, c, _lang),
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
      ]),
      page([
        Text('Topics', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          'Everything is open. Steps are only a suggested order for beginners.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        // filter by kind of situation: fewer tiles to scan at once
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in _topicGroups.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: ValueKey('topic-filter-$c'),
                    label: Text(c),
                    selected: _topicFilter == c,
                    showCheckmark: false,
                    onSelected: (_) {
                      _s.sound(Sfx.tap);
                      setState(() => _topicFilter = c);
                    },
                  ),
                ),
            ],
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
            final group = _topicGroups[_topicFilter];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (step, sc) in _pathOrder(
                  scenarios,
                  itemsByScenario,
                ).indexed)
                  if (group == null || group.any((g) => sc.id.contains(g)))
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
        const SizedBox(height: 24),
      ]),
      page([
        Text('Practice', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Short skills that make reading easier, and flashcards.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          key: const ValueKey('practice-speak'),
          margin: EdgeInsets.zero,
          color: theme.colorScheme.primaryContainer,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: const Icon(Icons.record_voice_over_rounded, size: 32),
            title: Text('Speak', style: theme.textTheme.titleMedium),
            subtitle: const Text(
              'Rapid speaking: 10 lines, the mic runs by itself. '
              'Switch between reading and repeating after the audio.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _push(
              SpeakDrillScreen(
                services: _s,
                title: 'Speak',
                sentences: pickSpeakLines(_s, _s.content.allSentences(_lang)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Reading skills', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 10) / 2;
            final skills = <Widget>[
              _SkillTile(
                key: const ValueKey('open-families'),
                icon: Icons.hub_rounded,
                title: 'Sound families',
                subtitle: '青 → 清 晴 請',
                onTap: () =>
                    _push(SoundFamiliesScreen(services: _s, lang: _lang)),
              ),
              _SkillTile(
                key: const ValueKey('open-spoken-written'),
                icon: Icons.compare_arrows_rounded,
                title: 'Spoken vs written',
                subtitle: '佢係 · 他是',
                onTap: () => _push(const SpokenWrittenScreen()),
              ),
              ...extraSkillTiles(context, _s, _push),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final t in skills) SizedBox(width: w, child: t)],
            );
          },
        ),
        const SizedBox(height: 24),
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
                label: 'Practice',
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

/// What the week gave you. No daily dots or streaks: they turn learning into
/// attendance and push quick, poor sessions just to keep a record going.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.newChars, required this.sentences});
  final int newChars;
  final int sentences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget stat(String value, String label) => Expanded(
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
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Card(
      key: const ValueKey('week-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This week', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                stat('$newChars', 'new characters'),
                stat('$sentences', 'sentences read'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What you find hard: sounds you mix up reading aloud, characters you keep needing.
class _WeakSpotsCard extends StatelessWidget {
  const _WeakSpotsCard({
    required this.readingPct,
    required this.speakingPct,
    required this.wordsToPractise,
    required this.cardsDue,
    required this.sounds,
    required this.chars,
    required this.onChar,
  });
  final int? readingPct;
  final int? speakingPct;
  final int wordsToPractise;
  final int cardsDue;
  final List<SoundMixup> sounds;
  final List<ItemState> chars;
  final ValueChanged<String> onChar;

  static String _explain(SoundMixup m) => switch (m.kind) {
    'tone' => 'tone ${m.expected} said as ${m.heard}',
    'start' => 'starts with ${m.expected}, said as ${m.heard}',
    _ => 'ends in ${m.expected}, said as ${m.heard}',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const ValueKey('weak-spots'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How you are doing this week',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Metric(
                  key: const ValueKey('metric-reading'),
                  value: readingPct == null ? '–' : '$readingPct%',
                  label: 'read without help',
                ),
                _Metric(
                  key: const ValueKey('metric-speaking'),
                  value: speakingPct == null ? '–' : '$speakingPct%',
                  label: 'sounds said right',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Metric(value: '${chars.length}', label: 'weak characters'),
                _Metric(value: '$wordsToPractise', label: 'words to practise'),
                _Metric(value: '$cardsDue', label: 'cards due'),
              ],
            ),
            const SizedBox(height: 4),
            if (chars.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Characters you keep needing help with (tap to hear):',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
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
            ],
            if (sounds.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Sounds you mix up when reading aloud:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              for (final m in sounds)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• ${_explain(m)} (${m.count}×), e.g. ${m.examples.first}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
            ],
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
    this.onQuack,
  });

  final VoidCallback? onQuack;

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
