/// Newcomer practice beyond single words (2026-11-17, content/practice.yaml):
/// - Listen: hear what people say back and pick what it means.
/// - Tones: hear one of a set of characters that differ only by tone, in different voices.
/// - Sentences: put a word into a frame (＿喺邊？) and say it.
/// - A Jyutping guide, and one real-world challenge at a time on Home.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/pronunciation.dart' show passPercent;
import '../platform/sfx.dart';
import 'finish.dart';
import 'mic_check.dart';
import 'ruby_text.dart' show chineseStyle;
import 'situations.dart' show wordWithReading;
import 'word_picture.dart';

List<String> _readings(CardRow c) => [
  for (final t in c.tokens)
    if (t.reading != null) t.reading!,
];

// ---------------------------------------------------------------- Listen (replies)

/// Replies to practice: missed ones first, then unheard, then the rest; [situations]
/// limits them (empty = all).
List<PracticeRow> listenRound(AppServices s, Set<String> situations) {
  final log = s.practiceLog;
  final all = [
    for (final r in s.content.practice('reply'))
      if (situations.isEmpty || situations.contains(r.group)) r,
  ];
  if (all.isEmpty) return const [];
  final rnd = s.variety;
  int rank(PracticeRow r) => log.repliesMissed.contains(r.id)
      ? 0
      : log.repliesHeard.contains(r.id)
      ? 2
      : 1;
  final shuffled = [...all]..shuffle(rnd);
  shuffled.sort((a, b) => rank(a).compareTo(rank(b)));
  return shuffled.take(8).toList();
}

class ListenDrillScreen extends StatefulWidget {
  const ListenDrillScreen({
    super.key,
    required this.services,
    required this.title,
    this.situations = const {},
  });
  final AppServices services;
  final String title;
  final Set<String> situations;

  @override
  State<ListenDrillScreen> createState() => _ListenDrillScreenState();
}

class _ListenDrillScreenState extends State<ListenDrillScreen> {
  AppServices get _s => widget.services;
  late List<PracticeRow> _items = listenRound(_s, widget.situations);
  int _index = 0;
  int _right = 0;
  int? _picked;
  bool _slowUsed = false;
  late List<String> _options = _optionsFor(0);

  PracticeRow get _item => _items[_index];

  List<String> _optionsFor(int i) {
    if (i >= _items.length) return const [];
    final item = _items[i];
    final pool = [
      for (final r in _s.content.practice('reply'))
        if (r.group == item.group && r.en != item.en) r.en,
    ]..shuffle(_s.variety);
    if (pool.length < 3) {
      pool.addAll(
        [
          for (final r in _s.content.practice('reply'))
            if (r.group != item.group && !pool.contains(r.en)) r.en,
        ]..shuffle(_s.variety),
      );
    }
    return [item.en, ...pool.take(3)]..shuffle(_s.variety);
  }

  @override
  void initState() {
    super.initState();
    if (_items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  Future<void> _play({bool slow = false}) async {
    if (slow) _slowUsed = true;
    await _s.saySentence(_item.card.zh, slow: slow);
  }

  void _pick(int i) {
    if (_picked != null) return;
    final ok = _options[i] == _item.en;
    setState(() {
      _picked = i;
      if (ok) _right++;
    });
    _s.logPractice('listen.answer', {
      'id': _item.id,
      'correct': ok,
      'slow': _slowUsed,
    });
  }

  void _next() {
    _s.silence();
    setState(() {
      _index++;
      _picked = null;
      _slowUsed = false;
      _options = _optionsFor(_index);
    });
    if (_index < _items.length) {
      _s.sound(Sfx.next);
      _play();
    } else {
      _s.sound(Sfx.finish);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _index >= _items.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [closeToHome(context)],
        bottom: duckBar(_items.isEmpty ? 1 : _index / _items.length),
      ),
      body: SafeArea(
        child: _items.isEmpty
            ? const Center(child: Text('No replies to practice here yet.'))
            : done
            ? FinishView(
                services: _s,
                title: 'You understood $_right of ${_items.length}',
                subtitle: 'Missed ones come back first next time.',
                onKeepGoing: () => setState(() {
                  _items = listenRound(_s, widget.situations);
                  _index = 0;
                  _right = 0;
                  _options = _optionsFor(0);
                  _play();
                }),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Text(
                    'What did they say?',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        key: const ValueKey('listen-play'),
                        onPressed: _play,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 56),
                        ),
                        icon: const Icon(Icons.volume_up_rounded),
                        label: const Text('Play again'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        key: const ValueKey('listen-slow'),
                        onPressed: () => _play(slow: true),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 56),
                        ),
                        icon: const Icon(Icons.slow_motion_video_rounded),
                        label: const Text('Slow'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  for (var i = 0; i < _options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _Option(
                        key: ValueKey('listen-option-$i'),
                        label: _options[i],
                        state: _picked == null
                            ? _OptionState.open
                            : _options[i] == _item.en
                            ? _OptionState.right
                            : _picked == i
                            ? _OptionState.wrong
                            : _OptionState.closed,
                        onTap: () => _pick(i),
                      ),
                    ),
                  if (_picked != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      color: scheme.surfaceContainerLow,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _play,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              wordWithReading(_item.card.tokens, size: 28),
                              const SizedBox(height: 6),
                              Text(
                                _item.en,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('listen-next'),
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      child: const Text('Next'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

enum _OptionState { open, right, wrong, closed }

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.label,
    required this.state,
    required this.onTap,
    this.child,
  });
  final String label;
  final _OptionState state;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, icon) = switch (state) {
      _OptionState.right => (
        scheme.primaryContainer,
        Icons.check_circle_rounded,
      ),
      _OptionState.wrong => (scheme.errorContainer, Icons.cancel_rounded),
      _ => (scheme.surfaceContainerLow, null),
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child:
                    child ??
                    Text(label, style: Theme.of(context).textTheme.bodyLarge),
              ),
              if (icon != null) Icon(icon),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Tones (ear training)

/// Tone sets in content order: (id, title, members).
List<(String, String, List<PracticeRow>)> toneSets(AppServices s) {
  final sets = <String, List<PracticeRow>>{};
  for (final r in s.content.practice('tone')) {
    (sets[r.group] ??= []).add(r);
  }
  return [for (final e in sets.entries) (e.key, e.value.first.extra, e.value)];
}

class ToneDrillScreen extends StatefulWidget {
  const ToneDrillScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<ToneDrillScreen> createState() => _ToneDrillScreenState();
}

class _ToneDrillScreenState extends State<ToneDrillScreen> {
  AppServices get _s => widget.services;
  static const rounds = 10;
  late final _sets = {for (final t in toneSets(_s)) t.$1: t};
  late List<(String, PracticeRow)> _plan = _makePlan();
  int _index = 0;
  int _right = 0;
  PracticeRow? _picked;

  /// Three sets to work on (never tried, then weakest), members in random order.
  List<(String, PracticeRow)> _makePlan() {
    final order = _s.practiceLog.toneOrder(_sets.keys.toList());
    final focus = order.take(3).toList();
    if (focus.isEmpty) return const [];
    final rnd = _s.variety;
    return [
      for (var i = 0; i < rounds; i++)
        () {
          final set = focus[i % focus.length];
          final members = _sets[set]!.$3;
          return (set, members[rnd.nextInt(members.length)]);
        }(),
    ];
  }

  /// The recorded voices, plus the phone's voice when one is installed: each round
  /// uses the next, so the learner hears the tones from more than one speaker.
  Future<void> _say(PracticeRow r) async {
    final paths = _s.content.audioPaths(r.card.zh);
    final useCount = paths.length + (_s.voice != null ? 1 : 0);
    if (useCount == 0) return;
    final which = _index % useCount;
    if (which < paths.length) {
      await _s.playAudio(paths[which]);
    } else if (!(await _s.voice!.say(r.card.zh)) && paths.isNotEmpty) {
      await _s.playAudio(paths.first);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_plan.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _say(_plan[0].$2));
    }
  }

  void _pick(PracticeRow r) {
    if (_picked != null) {
      _say(r); // after answering, any of them can be heard to compare
      return;
    }
    final (set, target) = _plan[_index];
    final ok = r.id == target.id;
    setState(() {
      _picked = r;
      if (ok) _right++;
    });
    _s.logPractice('tone.answer', {
      'set': set,
      'played': target.card.zh,
      'picked': r.card.zh,
      'correct': ok,
      'voice': _index,
    });
  }

  void _next() {
    _s.silence();
    setState(() {
      _index++;
      _picked = null;
    });
    if (_index < _plan.length) {
      _s.sound(Sfx.next);
      _say(_plan[_index].$2);
    } else {
      _s.sound(Sfx.finish);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _index >= _plan.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hear the tones'),
        actions: [closeToHome(context)],
        bottom: duckBar(_plan.isEmpty ? 1 : _index / _plan.length),
      ),
      body: SafeArea(
        child: _plan.isEmpty
            ? const Center(child: Text('No tone sets yet.'))
            : done
            ? FinishView(
                services: _s,
                title: 'You heard $_right of ${_plan.length} right',
                subtitle: 'The sets you mix up most come back first.',
                onKeepGoing: () => setState(() {
                  _plan = _makePlan();
                  _index = 0;
                  _right = 0;
                  _say(_plan[0].$2);
                }),
              )
            : () {
                final (set, target) = _plan[_index];
                final members = _sets[set]!.$3;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Text(
                      _sets[set]!.$2,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Which one did you hear?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('tone-play'),
                        onPressed: () => _say(target),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 56),
                        ),
                        icon: const Icon(Icons.volume_up_rounded),
                        label: const Text('Play again'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final m in members)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _Option(
                          key: ValueKey('tone-option-${m.card.zh}'),
                          label: m.en,
                          state: _picked == null
                              ? _OptionState.open
                              : m.id == target.id
                              ? _OptionState.right
                              : _picked!.id == m.id
                              ? _OptionState.wrong
                              : _OptionState.closed,
                          onTap: () => _pick(m),
                          child: Row(
                            children: [
                              Text(
                                m.card.zh,
                                style: chineseStyle('yue', fontSize: 30),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                _readings(m.card).join(' '),
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  m.en,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_picked != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tap any of them to hear it.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const ValueKey('tone-next'),
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        child: const Text('Next'),
                      ),
                    ],
                  ],
                );
              }(),
      ),
    );
  }
}

// ---------------------------------------------------------------- Sentences (frames)

/// The word that fills a frame sentence (`frame:<frame>:<word>`).
String frameWord(PracticeRow r) => r.id.substring(r.id.lastIndexOf(':') + 1);

List<PracticeRow> frameRound(AppServices s) {
  final all = [...s.content.practice('frame')]..shuffle(s.variety);
  final said = s.practiceLog.framesSaid;
  all.sort(
    (a, b) => (said.contains(a.id) ? 1 : 0) - (said.contains(b.id) ? 1 : 0),
  );
  return all.take(8).toList();
}

class FrameDrillScreen extends StatefulWidget {
  const FrameDrillScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<FrameDrillScreen> createState() => _FrameDrillScreenState();
}

class _FrameDrillScreenState extends State<FrameDrillScreen> {
  AppServices get _s => widget.services;
  late List<PracticeRow> _items = frameRound(_s);
  int _index = 0;
  int _right = 0;
  bool _revealed = false;
  int? _micPct;

  PracticeRow get _item => _items[_index];

  void _reveal() {
    setState(() => _revealed = true);
    unawaited(_s.saySentence(_item.card.zh));
  }

  void _grade(bool ok, String via) {
    _s.logPractice('frame.say', {'id': _item.id, 'ok': ok, 'via': via});
    if (ok) _right++;
    _s.silence();
    setState(() {
      _index++;
      _revealed = false;
      _micPct = null;
    });
    _s.sound(_index < _items.length ? Sfx.next : Sfx.finish);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _index >= _items.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Build a sentence'),
        actions: [closeToHome(context)],
        bottom: duckBar(_items.isEmpty ? 1 : _index / _items.length),
      ),
      body: SafeArea(
        child: _items.isEmpty
            ? const Center(child: Text('No sentences yet.'))
            : done
            ? FinishView(
                services: _s,
                title: 'You said $_right of ${_items.length}',
                subtitle:
                    'Swap in any word you know: the frame stays the same.',
                onKeepGoing: () => setState(() {
                  _items = frameRound(_s);
                  _index = 0;
                  _right = 0;
                }),
              )
            : () {
                final word = frameWord(_item);
                final wordCard = _s.content.wordCard(word);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Text(
                      'Say it in Cantonese:',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '"${_item.en}"',
                      key: const ValueKey('frame-english'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      color: scheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Text(
                              'The pattern',
                              style: theme.textTheme.labelMedium,
                            ),
                            Text(
                              _item.extra,
                              style: chineseStyle('yue', fontSize: 28),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'The word',
                              style: theme.textTheme.labelMedium,
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _s.sayWord(word, 'yue'),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (wordCard != null) ...[
                                    WordPicture(
                                      services: _s,
                                      cardId: wordCard.id,
                                      size: 40,
                                    ),
                                    const SizedBox(width: 10),
                                    wordWithReading(wordCard.tokens),
                                    const SizedBox(width: 10),
                                    Text(
                                      wordCard.alt,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ] else
                                    Text(
                                      word,
                                      style: chineseStyle('yue', fontSize: 26),
                                    ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.volume_up_outlined,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_revealed) ...[
                      if (_s.speech != null)
                        Center(
                          child: MicCheck(
                            key: ValueKey('frame-mic-$_index'),
                            services: _s,
                            nativeText: _item.card.zh,
                            expected: _readings(_item.card),
                            onResult: (_, pct) {
                              setState(() => _micPct = pct);
                              _reveal();
                            },
                          ),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        key: const ValueKey('frame-show'),
                        onPressed: _reveal,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        child: const Text('Show me'),
                      ),
                    ] else ...[
                      Card(
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _s.saySentence(_item.card.zh),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                wordWithReading(_item.card.tokens, size: 30),
                                if (_micPct case final pct?)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      pct >= passPercent
                                          ? 'Sounded right ($pct%)'
                                          : 'Not quite ($pct%). Listen and try again next time.',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const ValueKey('frame-again'),
                              onPressed: () => _grade(false, _via),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 52),
                              ),
                              child: const Text('Not yet'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              key: const ValueKey('frame-got-it'),
                              onPressed: () => _grade(true, _via),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 52),
                              ),
                              child: const Text('I said it'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              }(),
      ),
    );
  }

  String get _via => _micPct == null ? 'self' : 'mic';
}

// ---------------------------------------------------------------- Jyutping guide

/// How to read the Jyutping above each word: the letters that don't sound like English,
/// and the six tones. Every example is a word in the app with its dictionary reading.
class JyutpingGuideScreen extends StatelessWidget {
  const JyutpingGuideScreen({super.key, required this.services});
  final AppServices services;

  static const _letters = [
    ('j', 'Like English "y" in "yes".', '要'),
    ('z', 'Between English "j" and "ts".', '走冰'),
    ('c', 'Like "ch" or "ts", with a puff of air.', '車費'),
    ('ng', 'The "ng" of "sing", even at the start of a word.', '牙'),
    ('m', 'On its own, a whole syllable: hum it.', '唔該'),
    ('aa / a', 'aa is long, as in "father"; a is short, as in "but".', '買'),
    ('eo / oe', 'Rounded lips, like French "eu".', '水'),
    ('yu', 'Say "ee" with rounded lips, like French "u".', '落雨'),
    ('-p -t -k', 'Closed off at the end, not released: no puff of air.', '八達通'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = toneSets(s).where((t) => t.$1 == 'tones-si').firstOrNull;
    const toneShape = [
      'high, level',
      'rising from mid',
      'mid, level',
      'low, falling',
      'rising from low',
      'low, level',
    ];
    Widget example(String zh) {
      final c = s.content.wordCard(zh);
      if (c == null) return const SizedBox.shrink();
      return InkWell(
        onTap: () => s.sayWord(c.zh, 'yue'),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              wordWithReading(c.tokens, size: 22),
              const SizedBox(width: 6),
              Icon(Icons.volume_up_outlined, size: 18, color: scheme.primary),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reading Jyutping')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'The small letters above each word are Jyutping: how the word sounds, '
              'then a number for its tone. Most letters sound as in English; these don\'t.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            for (final (letters, how, zh) in _letters)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(
                          letters,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(how, style: theme.textTheme.bodyMedium),
                      ),
                      example(zh),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('The six tones', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'The number at the end is the tone. Same letters, different tone, '
              'different word: tap each to hear it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            if (tones != null)
              for (final (i, m) in tones.$3.indexed)
                ListTile(
                  key: ValueKey('guide-tone-$i'),
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    m.card.zh,
                    style: chineseStyle('yue', fontSize: 30),
                  ),
                  title: Text(
                    '${_readings(m.card).join(' ')}  ·  ${m.en}',
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(() {
                    final r = _readings(m.card).firstOrNull ?? '';
                    final t = int.tryParse(r.isEmpty ? '' : r[r.length - 1]);
                    return t != null && t >= 1 && t <= 6
                        ? 'Tone $t: ${toneShape[t - 1]}'
                        : '';
                  }()),
                  trailing: const Icon(Icons.volume_up_outlined),
                  onTap: () => s.sayWord(m.card.zh, 'yue'),
                ),
            const SizedBox(height: 8),
            Text(
              'Tones 4, 5 and 6 are the low ones. Many speakers say 2 and 5, or 3 and 6, '
              'close together; context usually tells them apart.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Real-world challenge

/// One small thing to do for real, on Home: the words to use and an "I did it" button.
/// No streaks: done ones just stop showing.
class ChallengeCard extends StatefulWidget {
  const ChallengeCard({super.key, required this.services});
  final AppServices services;

  @override
  State<ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends State<ChallengeCard> {
  AppServices get _s => widget.services;
  int _skip = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = _s.content.practice('challenge');
    final open = [
      for (final c in all)
        if (!_s.practiceLog.challengesDone.contains(c.id)) c,
    ];
    if (open.isEmpty) return const SizedBox.shrink();
    final c = open[_skip % open.length];
    final doneCount = all.length - open.length;
    return Card(
      key: const ValueKey('challenge-card'),
      margin: EdgeInsets.zero,
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Try it for real',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (doneCount > 0)
                  Text('$doneCount done', style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(c.en, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _s.saySentence(c.card.zh),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    wordWithReading(c.card.tokens, size: 24),
                    const SizedBox(width: 8),
                    const Icon(Icons.volume_up_outlined, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('challenge-another'),
                    onPressed: open.length < 2
                        ? null
                        : () => setState(() => _skip++),
                    child: const Text('Another'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('challenge-done'),
                    onPressed: () {
                      _s.logPractice('challenge.done', {'id': c.id});
                      setState(() {});
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('I did it'),
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
