/// Speak: rapid, back-to-back speaking practice. A sentence appears, the mic starts
/// by itself, stops when you finish, and you get a quick tick or a correction, then the
/// next one. As much speaking as possible, no tapping in between, nothing flashy.
///
/// Two ways: "Read it" (read the Chinese aloud; Jyutping fades as usual) and "Repeat
/// after me" (hear it first, then say it; for when you cannot read it yet).
/// Speaking counts as reading: characters said right are reviewed like a sentence read
/// without help, and words said wrong go on the practice list.
library;

import 'voice_picker.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/pictures.dart';
import '../engine/pronunciation.dart';
import '../engine/scaffold.dart';
import '../platform/sfx.dart';
import 'critters.dart';
import 'finish.dart';
import 'mic_check.dart' show heardReadings, noteSilence, playComparison;
import 'reader_screen.dart' show ModelDownloadDialog;
import 'ruby_text.dart';
import 'word_sheet.dart';

enum SpeakMode { read, repeat }

enum _Phase { ready, listening, thinking, right, wrong, done }

class SpeakDrillScreen extends StatefulWidget {
  const SpeakDrillScreen({
    super.key,
    required this.services,
    required this.title,
    required this.sentences,
    this.mode = SpeakMode.read,
    this.onComplete,
  });
  final AppServices services;
  final String title;
  final List<SentenceRow> sentences;
  final SpeakMode mode;
  final VoidCallback? onComplete;

  @override
  State<SpeakDrillScreen> createState() => _SpeakDrillScreenState();
}

class _SpeakDrillScreenState extends State<SpeakDrillScreen> {
  AppServices get _s => widget.services;
  late SpeakMode _mode = widget.mode;
  int _index = 0;
  _Phase _phase = _Phase.ready;

  /// This line is finished: its meaning shows and Next moves on (never by itself).
  bool _lineDone = false;
  bool _retried = false;
  int _right = 0;
  Map<int, CharScore> _marks = const {};
  Map<String, ScaffoldLevel> _levels = const {};
  int _percent = 0;

  SentenceRow get _line => widget.sentences[_index];

  /// A speech engine exists on this device (the mic is used only when tapped).
  bool get _hasMic => _s.speech != null;

  @override
  void initState() {
    super.initState();
    _s.logger.log('session.start', {
      'mode': 'speak',
      'lang': 'yue',
      'planned_items': widget.sentences.length,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    if (_index >= 3) _complete();
    _s.speech?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    final eng = _s.speech;
    if (eng != null && !eng.installed) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ModelDownloadDialog(engine: eng),
      );
      if (ok != true || !mounted) return;
    }
    if (eng != null && !await eng.canRecord()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'DuckLearn needs the microphone for speaking practice.',
            ),
          ),
        );
      }
      return;
    }
    unawaited(_present());
  }

  /// Show the line; in "repeat" mode play it first; then listen.
  Future<void> _present() async {
    if (!mounted || widget.sentences.isEmpty) return;
    final now = _s.logger.now();
    setState(() {
      _phase = _Phase.ready;
      _lineDone = false;
      _marks = const {};
      _levels = {
        for (final id in _line.itemIds)
          id: _mode == SpeakMode.repeat
              ? ScaffoldLevel.full
              : _s.scaffold.levelFor(_s.learner.stateOf(id), _s.memory, now),
      };
    });
    // "repeat" mode and retries hear it first; otherwise you read it first
    if (_mode == SpeakMode.repeat || _retried) await _playNative();
    // the mic waits for a tap (no automatic listening)
    if (mounted) setState(() {});
  }

  Future<void> _playNative() async {
    await _s.saySentence(_line.text);
  }

  Future<void> _listen() async {
    final eng = _s.speech;
    if (eng == null) return; // no mic: self-paced (buttons below)
    _s.sound(Sfx.mic);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final shown = _index;
    await eng.startRecording(
      onFinished: () {
        if (mounted && _phase == _Phase.listening && _index == shown) _score();
      },
      maxLength: Duration(
        milliseconds:
            3500 + _line.tokens.where((t) => t.kind == 'han').length * 650,
      ),
    );
    if (mounted) setState(() => _phase = _Phase.listening);
  }

  Future<void> _score() async {
    final eng = _s.speech!;
    setState(() => _phase = _Phase.thinking);
    final samples = await eng.stopRecording();
    if (!mounted) return;
    noteSilence(context, _s, heard: eng.heardSpeech);
    if (!eng.heardSpeech) {
      // nothing said: not marked wrong; tap the mic to try again
      setState(() => _phase = _Phase.ready);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final idx = [
      for (var i = 0; i < _line.tokens.length; i++)
        if (_line.tokens[i].kind == 'han' && _line.tokens[i].reading != null) i,
    ];
    final score = scoreAttempt([
      for (final i in idx) _line.tokens[i].reading!,
    ], heardReadings(_s, eng.recognise(samples, lang: 'yue')));
    final pct = lenientAccuracy(score.chars);
    _s.logger.log('speech.attempt', {
      'engine': 'sensevoice-int8',
      'mode': 'speak-${_mode.name}',
      'sentence_id': _line.id,
      'score': score.ratio,
      'per_token': [
        for (final c in score.chars)
          {'expected': c.expected, 'heard': c.heard, 'v': c.verdict.name},
      ],
    });
    final marks = {for (var k = 0; k < idx.length; k++) idx[k]: score.chars[k]};
    final ok = pct >= passPercent;
    _s.sound(ok ? Sfx.good : Sfx.tryAgain);
    if (!mounted) return;
    setState(() {
      _marks = marks;
      _percent = pct;
      _phase = ok ? _Phase.right : _Phase.wrong;
    });
    if (ok || _retried) {
      // done with this line: show what it means; you press Next
      _finishLine(marks);
      setState(() => _lineDone = true);
    } else {
      // one more go: hear yours, then the native, then tap to say it again
      _retried = true;
      await playComparison(_s, samples, null);
      await _playNative();
      if (mounted) setState(() => _phase = _Phase.ready);
    }
  }

  /// Reviews for the characters (said right = read without help; missed = lapse) and
  /// missed words to the practice list.
  void _finishLine(Map<int, CharScore> marks) {
    final missed = <String>{
      for (final e in marks.entries)
        if (e.value.isMiss && _line.tokens[e.key].itemId != null)
          _line.tokens[e.key].itemId!,
    };
    final outcomes = _s.signals.outcomes(
      shown: _levels,
      revealed: missed,
      // speaking a line takes a few seconds per character: never "too fast"
      activeMs: 4000 * _levels.length,
    );
    for (final o in outcomes) {
      _s.logger.log('review.applied', {
        'item_id': o.itemId,
        'grade': o.grade.name,
        'signal': o.signal.name,
        's_before': _s.learner.stateOf(o.itemId).stability,
      });
    }
    final seen = <int>{};
    for (final e in marks.entries.where((e) => e.value.isMiss)) {
      if (seen.add(_line.wordRange(e.key).$1)) {
        flagWord(_s, _line, e.key, 'say');
      }
    }
    if (marks.values.every((c) => !c.isMiss)) _right++;
    _s.logger.log('item.done', {'mode': 'speak', 'skipped': false});
  }

  void _advance() {
    _retried = false;
    if (_index + 1 >= widget.sentences.length) {
      _s.logger.log('session.end', {
        'reason': 'done',
        'items_done': widget.sentences.length,
      });
      _s.sound(Sfx.finish);
      _complete();
      setState(() => _phase = _Phase.done);
      return;
    }
    setState(() => _index++);
    unawaited(_present());
  }

  bool _completed = false;

  void _complete() {
    if (_completed) return;
    _completed = true;
    widget.onComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_phase == _Phase.done) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: FinishView(
            services: _s,
            mood: _right == widget.sentences.length
                ? ChickMood.proud
                : ChickMood.happy,
            title: '$_right of ${widget.sentences.length} said right',
            titleKey: const ValueKey('speak-done'),
            subtitle: _right == widget.sentences.length
                ? null
                : 'Words you missed are on your practice list.',
          ),
        ),
      );
    }
    final pic = pictureForMeaning(_line.en);
    final (label, color) = switch (_phase) {
      _Phase.listening => ('Listening… say it', scheme.primary),
      _Phase.thinking => ('Checking…', scheme.onSurfaceVariant),
      _Phase.right => ('Right ($_percent%)', scheme.primary),
      _Phase.wrong => (
        _retried && _marks.isNotEmpty
            ? 'Listen, then once more'
            : 'Not quite ($_percent%)',
        scheme.error,
      ),
      _ => (
        _mode == SpeakMode.repeat
            ? 'Listen, then tap the mic and say it'
            : 'Tap the mic and read it aloud',
        scheme.onSurfaceVariant,
      ),
    };
    return Scaffold(
      appBar: AppBar(
        leading: closeToHome(context),
        title: Text(widget.title),
        actions: [VoiceButton(_s)],
        bottom: duckBar(
          widget.sentences.isEmpty ? 1 : _index / widget.sentences.length,
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  SegmentedButton<SpeakMode>(
                    key: const ValueKey('speak-mode'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: SpeakMode.read,
                        icon: Icon(Icons.menu_book_rounded),
                        label: Text('Read it'),
                      ),
                      ButtonSegment(
                        value: SpeakMode.repeat,
                        icon: Icon(Icons.hearing_rounded),
                        label: Text('Repeat after me'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) {
                      final from = _mode;
                      setState(() => _mode = v.first);
                      _s.logger.log('settings.change', {
                        'key': 'speak_mode',
                        'from': from.name,
                        'to': _mode.name,
                      });
                      // show this line again in the new mode
                      if (_phase == _Phase.ready && !_lineDone) {
                        unawaited(_present());
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _mode == SpeakMode.read
                        ? 'Read the line yourself; no audio first.'
                        : 'Hear the line first, then say it back.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (pic != null)
                    Center(
                      child: Text(pic, style: const TextStyle(fontSize: 48)),
                    ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: RubyText(
                        key: ValueKey('speak-line-$_index'),
                        lang: 'yue',
                        fontSize: 34 * _s.prefs.textScale,
                        wordOf: _line.wordOf,
                        tokens: [
                          for (var i = 0; i < _line.tokens.length; i++)
                            RubyToken(
                              surface: _line.tokens[i].surface,
                              kind: _line.tokens[i].kind,
                              reading: _line.tokens[i].reading,
                              // after a miss, show the readings to copy
                              level: _phase == _Phase.wrong
                                  ? ScaffoldLevel.full
                                  : _levels[_line.tokens[i].itemId] ??
                                        ScaffoldLevel.full,
                              mark: switch (_marks[i]?.verdict) {
                                Verdict.ok || Verdict.tone => SpeechMark.ok,
                                Verdict.wrong => SpeechMark.wrong,
                                Verdict.missed => SpeechMark.missed,
                                null => null,
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // the meaning comes after you have said it
                  if (_lineDone)
                    Text(
                      _line.en,
                      key: const ValueKey('speak-meaning'),
                      style: theme.textTheme.bodyLarge,
                    ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // a missed line: a puzzled chick, not a telling-off
                      if (_phase == _Phase.wrong)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Chick(mood: ChickMood.confused, size: 44),
                        ),
                      if (_phase == _Phase.right)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Chick(mood: ChickMood.happy, size: 44),
                        ),
                      Flexible(
                        child: Text(
                          label,
                          key: const ValueKey('speak-status'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_phase == _Phase.listening)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Center(child: Icon(Icons.mic_rounded, size: 48)),
                    ),
                ],
              ),
            ),
            // controls in thumb reach; with a mic, the loop runs by itself
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Hear it',
                    onPressed: _phase == _Phase.listening ? null : _playNative,
                    icon: const Icon(Icons.volume_up_rounded),
                  ),
                  const SizedBox(width: 8),
                  if (_hasMic)
                    IconButton.filled(
                      key: const ValueKey('speak-mic'),
                      tooltip: _phase == _Phase.listening ? 'Stop' : 'Speak',
                      iconSize: 32,
                      onPressed: _phase == _Phase.thinking || _lineDone
                          ? null
                          : _phase == _Phase.listening
                          ? _score
                          : _listen,
                      icon: Icon(
                        _phase == _Phase.listening
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _lineDone
                        ? FilledButton(
                            key: const ValueKey('speak-next'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 52),
                            ),
                            onPressed: () {
                              _s.silence();
                              _s.sound(Sfx.next);
                              _advance();
                            },
                            child: const Text('Next'),
                          )
                        : _hasMic
                        ? OutlinedButton(
                            key: const ValueKey('speak-skip'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 52),
                            ),
                            onPressed: () {
                              if (_phase == _Phase.listening) {
                                _s.speech?.stopRecording().ignore();
                              }
                              _s.silence();
                              _advance();
                            },
                            child: const Text('Skip'),
                          )
                        : FilledButton(
                            // no mic: say it aloud yourself, then see the meaning
                            key: const ValueKey('speak-said'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 52),
                            ),
                            onPressed: () {
                              _finishLine(const {});
                              setState(() => _lineDone = true);
                            },
                            child: const Text('Said it'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short lines for speaking (2-12 characters), chosen like a reading session: due
/// characters first, a few new ones.
List<SentenceRow> pickSpeakLines(
  AppServices s,
  List<SentenceRow> pool, {
  int count = 10,
  // new characters are fine to say: Jyutping sits on top of them
  int maxNew = 20,
}) {
  final short = [
    for (final l in pool)
      if (l.tokens.where((t) => t.kind == 'han').length case final n
          when n >= 2 && n <= 12)
        l,
  ];
  final picks = s.planner.plan(
    candidates: [for (final l in short) l.toCandidate()],
    learner: s.learner,
    now: s.logger.now(),
    count: count,
    maxNew: maxNew,
    recentlySeen: s.recentSentences(),
    random: s.variety,
    jitter: AppServices.plannerJitter,
  );
  final byId = {for (final l in short) l.id: l};
  return [for (final p in picks) byId[p.candidate.id]!];
}
