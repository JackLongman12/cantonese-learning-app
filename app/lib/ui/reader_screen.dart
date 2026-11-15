/// Reads a set of sentences one at a time. Every action is logged; grades are derived
/// from what the learner did, not asked for.
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/scaffold.dart';
import '../engine/signals.dart';
import '../events/event_logger.dart';
import 'mascot.dart';
import 'ruby_text.dart';
import 'visual_novel.dart';
import 'word_sheet.dart';
import '../engine/pronunciation.dart';
import '../platform/sfx.dart';
import '../platform/speech.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.services,
    required this.title,
    required this.sentences,
    required this.lang,
    this.mode = 'topic',
    this.scenarioId,
    this.count,
    this.maxNew = 12,
    this.conversation = false,
    this.story = false,
    this.autoplay = false,
    this.ordered = false,
    this.startAt = 0,
  });

  final AppServices services;
  final String title;

  /// Candidates; the planner picks and orders what is actually shown.
  final List<SentenceRow> sentences;
  final String lang;
  final String mode;
  final String? scenarioId;

  /// Sentences in the session (null = as many as the planner finds useful).
  final int? count;
  final int maxNew;

  /// Read [sentences] in the given order as a conversation (no planner).
  final bool conversation;

  /// Read [sentences] in order as a story: earlier lines stay as plain paragraphs.
  final bool story;

  /// Read along: play each line's audio as it appears.
  final bool autoplay;

  /// Keep [sentences] in the given order (resuming), starting at [startAt].
  final bool ordered;
  final int startAt;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final List<SentenceRow> _queue;
  final Map<String, List<String>> _why = {};
  int _index = 0;
  int _exposure = 0;
  bool _finished = false;

  // state of the sentence on screen
  late Map<String, ScaffoldLevel> _levels;
  final Set<String> _revealed = {};
  final Set<int> _revealedTokens = {};
  bool _showTranslation = false;

  /// Learner's turn in a conversation: pick the line before seeing it.
  bool _choosing = false;
  List<String> _options = const [];
  final _wrongPicks = <String>{};
  int _audioPlays = 0;
  Map<int, CharScore> _speech = const {};
  String? _myRecording;
  _Mic _mic = _Mic.idle;
  late ActiveMark _mark;

  // session totals for the summary
  final Set<String> _practised = {};
  final Set<String> _introduced = {};
  final Set<String> _lapsed = {};
  int _read = 0;

  AppServices get _s => widget.services;
  SentenceRow get _sentence => _queue[_index];

  @override
  void initState() {
    super.initState();
    if (widget.conversation || widget.story || widget.ordered) {
      _queue = [...widget.sentences];
    } else {
      final picks = _s.planner.plan(
        candidates: [for (final s in widget.sentences) s.toCandidate()],
        learner: _s.learner,
        now: _s.logger.now(),
        count: widget.count ?? widget.sentences.length,
        maxNew: widget.maxNew,
      );
      final byId = {for (final s in widget.sentences) s.id: s};
      _queue = [for (final p in picks) byId[p.candidate.id]!];
      for (final p in picks) {
        _why[p.candidate.id] = p.reasons;
      }
    }
    _s.logger.log('session.start', {
      'mode': widget.mode,
      'scenario_id': ?widget.scenarioId,
      'lang': widget.lang,
      'planned_items': _queue.length,
    });
    _index = widget.startAt.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
    if (_queue.isNotEmpty) _present();
  }

  void _present() {
    final now = _s.logger.now();
    _levels = {
      for (final id in _sentence.itemIds)
        id: _s.scaffold.levelFor(_s.learner.stateOf(id), _s.memory, now),
    };
    _revealed.clear();
    _revealedTokens.clear();
    _showTranslation = false;
    _audioPlays = 0;
    _speech = const {};
    _myRecording = null;
    _exposure++;
    _mark = _s.logger.mark();
    _s.logger.touch();
    // remember where we are, so an interrupted session can be resumed from home
    _s.prefs.resume = {
      'title': widget.title,
      'lang': widget.lang,
      'mode': widget.mode,
      'ids': [for (final q in _queue) q.id],
      'index': _index,
      'conversation': widget.conversation,
      'story': widget.story,
    };
    _wrongPicks.clear();
    _options = _choicesFor(_sentence);
    _choosing = _options.length >= 2;
    if (!_choosing && (widget.autoplay || _s.prefs.autoPlay)) {
      final shown = _index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _index == shown) _play(slow: false, auto: true);
      });
    }
    _s.logger.log('item.shown', {
      'exposure_id': _exposureId,
      'sentence_id': _sentence.id,
      'lang': widget.lang,
      'item_ids': _levels.keys.toList(),
      'scaffold': [for (final l in _levels.values) l.name],
      'planner': {'reasons': _why[_sentence.id] ?? const []},
      'pos_in_session': _index,
    });
  }

  /// The line to say plus two lines you say in other conversations of this topic,
  /// shuffled the same way each time.
  List<String> _choicesFor(SentenceRow s) {
    if (!widget.conversation || !_isLearner(s) || widget.scenarioId == null) {
      return const [];
    }
    final others = _s.content
        .learnerLines(widget.scenarioId!, exceptDialogue: s.dialogue)
        .where((t) => t != s.text)
        .toSet()
        .toList();
    if (others.length < 2) return const [];
    final rnd = Random(s.id.hashCode);
    others.shuffle(rnd);
    return [s.text, others[0], others[1]]..shuffle(rnd);
  }

  void _pick(String text) {
    final ok = text == _sentence.text;
    _s.logger.log('conv.choice', {
      'exposure_id': _exposureId,
      'sentence_id': _sentence.id,
      'correct': ok,
      'tries': _wrongPicks.length + 1,
    });
    if (!ok) {
      _s.sound(Sfx.tryAgain);
      setState(() => _wrongPicks.add(text));
      return;
    }
    _s.sound(Sfx.good);
    setState(() => _choosing = false);
    if (widget.autoplay || _s.prefs.autoPlay) _play(slow: false, auto: true);
  }

  /// Who stands opposite you on the stage: the current speaker, or the last one who spoke.
  String _otherSpeaker() {
    for (var k = _index; k >= 0; k--) {
      if (!_isLearner(_queue[k])) return _queue[k].speaker ?? '';
    }
    for (final l in _queue) {
      if (!_isLearner(l)) return l.speaker ?? '';
    }
    return '';
  }

  /// In conversations the learner is 你; everyone else is the other side.
  bool _isLearner(SentenceRow r) => r.speaker == '你';

  String get _exposureId => '${_s.logger.sessionId}-$_exposure';

  void _reveal(int tokenIndex) {
    final t = _sentence.tokens[tokenIndex];
    if (t.itemId == null || _revealedTokens.contains(tokenIndex)) return;
    HapticFeedback.selectionClick();
    _s.sound(Sfx.reveal);
    _s.logger.touch();
    _s.logger.log('item.reveal', {
      'exposure_id': _exposureId,
      'item_id': t.itemId,
      'token_idx': tokenIndex,
      'what': 'reading',
      'latency_ms': _s.logger.activeMsSince(_mark),
    });
    setState(() {
      _revealedTokens.add(tokenIndex);
      _revealed.add(t.itemId!);
    });
  }

  void _toggleMeaning() {
    _s.sound(Sfx.tap);
    _s.logger.touch();
    if (!_showTranslation) {
      _s.logger.log('item.reveal', {
        'exposure_id': _exposureId,
        'what': 'translation',
        'latency_ms': _s.logger.activeMsSince(_mark),
      });
    }
    setState(() => _showTranslation = !_showTranslation);
  }

  Future<void> _play({required bool slow, bool auto = false}) async {
    if (!auto) _s.logger.touch();
    final path = _s.content.audioPath(widget.lang, _sentence.text);
    if (!auto) _audioPlays++;
    _s.logger.log('item.audio', {
      'exposure_id': _exposureId,
      'scope': 'sentence',
      'rate': slow ? 'slow' : 'normal',
      'nth': _audioPlays,
      'available': path != null,
      if (auto) 'auto': true,
    });
    if (path == null) {
      if (auto) return;
      _toast('No audio for this sentence yet');
      return;
    }
    final shownAt = _exposure;
    try {
      await (slow ? (_s.playAudioSlow ?? _s.playAudio) : _s.playAudio)(path);
      // the meaning appears once the line has been heard (setting, on by default)
      if (mounted &&
          _s.prefs.autoMeaning &&
          !_showTranslation &&
          _exposure == shownAt &&
          !_finished) {
        _s.logger.log('item.reveal', {
          'exposure_id': _exposureId,
          'what': 'translation',
          'auto': true,
        });
        setState(() => _showTranslation = true);
      }
    } on Object catch (e) {
      // automatic playback fails quietly; a tap on Listen says what went wrong
      if (mounted && !auto) _toast('Could not play audio: $e');
    }
  }

  Future<void> _readAloud() async {
    final eng = _s.speech;
    if (eng == null || _mic == _Mic.scoring) return;
    _s.logger.touch();
    if (_mic == _Mic.recording) {
      setState(() => _mic = _Mic.scoring);
      final samples = await eng.stopRecording();
      final wav = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}ducklearn_mine_$_exposure.wav',
      )..writeAsBytesSync(writeWav16(samples));
      _myRecording = wav.path;
      // let the spinner paint before the (sub-second) recognition runs
      await Future<void>.delayed(const Duration(milliseconds: 16));
      _scoreSpeech(eng.recognise(samples, lang: widget.lang));
      if (mounted) setState(() => _mic = _Mic.idle);
      return;
    }
    if (!eng.installed) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ModelDownloadDialog(engine: eng),
      );
      if (ok != true || !mounted) return;
    }
    if (!await eng.canRecord()) {
      _toast('DuckLearn needs the microphone to check your reading.');
      return;
    }
    final syllables = _sentence.tokens.where((t) => t.kind == 'han').length;
    final started = _exposure;
    _s.sound(Sfx.mic);
    // let the start sound finish so it isn't recorded
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await eng.startRecording(
      // stop by itself when the learner finishes the sentence
      onFinished: () {
        if (mounted && _mic == _Mic.recording && _exposure == started) {
          _readAloud();
        }
      },
      maxLength: Duration(milliseconds: 4000 + syllables * 700),
    );
    if (mounted) setState(() => _mic = _Mic.recording);
  }

  /// Compares the readings heard with the readings expected, character by character.
  void scoreSpeechForTest(String heardText) => _scoreSpeech(heardText);

  void _scoreSpeech(String heardText) {
    final s = _sentence;
    final heard = _s.content
        .annotator(widget.lang)
        .annotate(
          widget.lang == 'yue'
              ? _s.content.toTraditional(heardText)
              : heardText,
        )
        .where((t) => t.kind == 'han' && t.reading != null)
        .map((t) => t.reading!)
        .toList();
    final idx = [
      for (var i = 0; i < s.tokens.length; i++)
        if (s.tokens[i].kind == 'han' && s.tokens[i].reading != null) i,
    ];
    final score = scoreAttempt([
      for (final i in idx) s.tokens[i].reading!,
    ], heard);
    final byToken = {
      for (var k = 0; k < idx.length; k++) idx[k]: score.chars[k],
    };
    _s.logger.log('speech.attempt', {
      'exposure_id': _exposureId,
      'engine': 'sensevoice-int8',
      'score': score.ratio,
      'per_token': [
        for (final c in score.chars)
          {'expected': c.expected, 'heard': c.heard, 'v': c.verdict.name},
      ],
    });
    _s.sound(soundAccuracy(score.chars) >= 85 ? Sfx.good : Sfx.tryAgain);
    // words said wrong go on the practice list
    final seenWords = <int>{};
    for (final e in byToken.entries.where((e) => e.value.isError)) {
      if (seenWords.add(s.wordRange(e.key).$1)) flagWord(_s, s, e.key, 'say');
    }
    setState(() {
      _speech = byToken;
      // A mispronounced character is a reading lapse, exactly like tapping to reveal.
      for (final e in byToken.entries.where((e) => e.value.isError)) {
        final id = s.tokens[e.key].itemId;
        if (id != null) {
          _revealed.add(id);
          _revealedTokens.add(e.key);
        }
      }
    });
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );

  /// Closes the current exposure: derive grades, log them, move on.
  void _finishCurrent({required bool skipped}) {
    _s.logger.touch();
    final activeMs = _s.logger.activeMsSince(_mark);
    final List<ItemOutcome> outcomes = skipped
        ? const []
        : _s.signals.outcomes(
            shown: _levels,
            revealed: _revealed,
            activeMs: activeMs,
          );
    for (final o in outcomes) {
      final before = _s.learner.stateOf(o.itemId);
      _s.logger.log('review.applied', {
        'exposure_id': _exposureId,
        'item_id': o.itemId,
        'grade': o.grade.name,
        'signal': o.signal.name,
        's_before': before.stability,
      });
      _practised.add(o.itemId);
      if (o.signal == Signal.introduced) _introduced.add(o.itemId);
      if (o.signal == Signal.reveal) _lapsed.add(o.itemId);
    }
    if (outcomes.isNotEmpty) _read++;
    // characters you had to reveal: their words go on the practice list
    if (!skipped) {
      final seen = <int>{};
      for (final i in _revealedTokens) {
        final w = _sentence.wordRange(i).$1;
        if (seen.add(w)) flagWord(_s, _sentence, i, 'read');
      }
    }
    _s.logger.log('item.done', {
      'exposure_id': _exposureId,
      'active_ms': activeMs,
      'reveals': _revealed.length,
      'audio_plays': _audioPlays,
      'skipped': skipped || outcomes.isEmpty,
    });
  }

  void _next({bool skipped = false}) {
    if (_finished) return;
    _finishCurrent(skipped: skipped);
    if (_index + 1 >= _queue.length) {
      _s.prefs.resume = null;
      _s.logger.log('session.end', {
        'reason': 'done',
        'items_done': _queue.length,
      });
      _s.sound(Sfx.finish);
      setState(() => _finished = true);
      return;
    }
    _s.sound(Sfx.next);
    setState(() {
      _index++;
      _present();
    });
  }

  /// Says the dictionary word around token [i] (or the character alone).
  Future<void> _speakWord(int i) async {
    final s = _sentence;
    // the word as segmented in this sentence (context), not just the longest match
    final (a, b) = s.wordRange(i);
    final word = [for (var k = a; k < b; k++) s.tokens[k].surface].join();
    _s.logger.log('item.audio', {
      'exposure_id': _exposureId,
      'scope': 'word',
      'rate': 'normal',
      'text': word,
    });
    if (!await _s.sayWord(word, widget.lang) &&
        mounted &&
        !_s.voiceNoticeShown) {
      _s.voiceNoticeShown = true;
      _toast(noVoiceMessage);
    }
  }

  /// Token indexes that fall inside a saved word ("My words").
  Set<int> _savedTokens(SentenceRow s) {
    final ranges = _s.words.highlights(widget.lang, s.text);
    if (ranges.isEmpty) return const {};
    final offs = tokenOffsets(s.tokens);
    return {
      for (var i = 0; i < s.tokens.length; i++)
        if (ranges.any(
          (r) => offs[i] < r.$2 && offs[i] + s.tokens[i].surface.length > r.$1,
        ))
          i,
    };
  }

  void _showHelp() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _HelpSheet(lang: widget.lang),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const _EmptyState(),
      );
    }
    if (_finished) {
      return _SummaryScreen(
        title: widget.title,
        read: _read,
        practised: _practised.length,
        introduced: _introduced.length,
        checked: _lapsed.length,
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _next,
        const SingleActivator(LogicalKeyboardKey.space): _next,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.keyL): () =>
            _play(slow: false),
        const SingleActivator(LogicalKeyboardKey.keyS): () => _play(slow: true),
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMeaning,
        const SingleActivator(LogicalKeyboardKey.keyR): _readAloud,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            actions: [
              IconButton(
                tooltip: 'How reading help works',
                onPressed: _showHelp,
                icon: const Icon(Icons.help_outline_rounded),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearProgressIndicator(
                value: _index / _queue.length,
                minHeight: 4,
              ),
            ),
          ),
          // Swipe left for the next sentence: one-thumb reading on a phone.
          body: GestureDetector(
            key: const ValueKey('swipe-area'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -400) _next();
            },
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, c) => _body(context, wide: c.maxWidth > 700),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, {required bool wide}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = _sentence;
    final savedChars = _savedTokens(s);
    final levels = _levels.values.toSet();
    final hint =
        levels.contains(ScaffoldLevel.tap) ||
            levels.contains(ScaffoldLevel.hint)
        ? 'Read it in your head. Tap any character you can\'t read to see it.'
        : levels.contains(ScaffoldLevel.full)
        ? 'New characters have Jyutping on top. Read along, then tap Listen.'
        : 'No help needed here. Read it, then move on.';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_index + 1} of ${_queue.length}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (s.register == 'written')
                          const _Tag(
                            icon: Icons.signpost_outlined,
                            text: 'Written Chinese',
                          ),
                      ],
                    ),
                    if (widget.story && _index > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          [for (var k = 0; k < _index; k++) _queue[k].text]
                              .join(),
                          key: const ValueKey('story-so-far'),
                          style: chineseStyle(
                            widget.lang,
                            fontSize: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ).copyWith(height: 1.7),
                        ),
                      ),
                    if (widget.conversation) ...[
                      const SizedBox(height: 8),
                      ConversationStage(
                        other: _otherSpeaker(),
                        youSpeaking: _isLearner(s),
                        // Irasutoya's terms rule out aggressive uses
                        showPictures: widget.scenarioId != 'scn-swearing',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (!_isLearner(s))
                            NamePlate(speaker: s.speaker ?? '', mine: false),
                          const Spacer(),
                          if (_index > 0)
                            IconButton(
                              key: const ValueKey('backlog'),
                              tooltip: 'Earlier lines',
                              icon: const Icon(Icons.history_rounded),
                              onPressed: () => showBacklog(
                                context,
                                _queue.sublist(0, _index),
                              ),
                            ),
                          if (_isLearner(s))
                            const NamePlate(speaker: '你', mine: true),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_choosing)
                      ChoicePanel(
                        key: const ValueKey('choices'),
                        options: _options,
                        wrong: _wrongPicks,
                        prompt: _index > 0 ? _queue[_index - 1].en : null,
                        onPick: _pick,
                      )
                    else ...[
                      Card(
                        margin: EdgeInsets.zero,
                        color: widget.conversation
                            ? speakerColors(scheme, mine: _isLearner(s)).bg
                            : null,
                        shape: widget.conversation
                            ? RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  width: 2,
                                  color: speakerColors(
                                    scheme,
                                    mine: _isLearner(s),
                                  ).edge,
                                ),
                              )
                            : null,
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                            20,
                            wide ? 28 : 20,
                            20,
                            wide ? 32 : 24,
                          ),
                          child: RubyText(
                            lang: widget.lang,
                            onReveal: _reveal,
                            onSpeak: _speakWord,
                            wordOf: s.wordOf,
                            onLookup: (i) {
                              _reveal(i);
                              showWordLookup(
                                context,
                                services: _s,
                                lang: widget.lang,
                                sentence: _sentence,
                                tokenIndex: i,
                              ).then((_) {
                                if (mounted) setState(() {});
                              });
                            },
                            fontSize: (wide ? 44 : 34) * _s.prefs.textScale,
                            tokens: [
                              for (var i = 0; i < s.tokens.length; i++)
                                RubyToken(
                                  surface: s.tokens[i].surface,
                                  kind: s.tokens[i].kind,
                                  reading: s.tokens[i].reading,
                                  level:
                                      _levels[s.tokens[i].itemId] ??
                                      ScaffoldLevel.full,
                                  revealed: _revealedTokens.contains(i),
                                  flagged: s.tokens[i].flagged,
                                  saved: savedChars.contains(i),
                                  mark: switch (_speech[i]?.verdict) {
                                    Verdict.ok => SpeechMark.ok,
                                    Verdict.tone => SpeechMark.tone,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.touch_app_outlined,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              hint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_speech.isNotEmpty)
                        _SpeechResult(
                          scores: _speech.values.toList(),
                          onPlayMine:
                              _myRecording == null || _s.playFile == null
                              ? null
                              : () {
                                  _s.logger.log('item.audio', {
                                    'exposure_id': _exposureId,
                                    'scope': 'own_recording',
                                  });
                                  _s.playFile!(_myRecording!);
                                },
                          onPlayNative: () => _play(slow: false),
                        ),
                      const SizedBox(height: 16),
                      _MeaningPanel(
                        open: _showTranslation,
                        en: s.en,
                        notes: s.notes,
                        onToggle: _toggleMeaning,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _BottomBar(
              isLast: _index + 1 >= _queue.length,
              onListen: () => _play(slow: false),
              onSlow: () => _play(slow: true),
              onSkip: () => _next(skipped: true),
              onNext: _next,
              mic: _s.speech == null ? null : _mic,
              onMic: _readAloud,
              // keyboard hints only where there is a keyboard
              showShortcuts:
                  wide &&
                  const {
                    TargetPlatform.windows,
                    TargetPlatform.macOS,
                    TargetPlatform.linux,
                  }.contains(defaultTargetPlatform),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MeaningPanel extends StatelessWidget {
  const _MeaningPanel({
    required this.open,
    required this.en,
    required this.notes,
    required this.onToggle,
  });

  final bool open;
  final String en;
  final String notes;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: open ? scheme.secondaryContainer : null,
      child: InkWell(
        key: const ValueKey('meaning'),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.translate_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    open ? 'Meaning' : 'Show meaning',
                    style: theme.textTheme.labelLarge,
                  ),
                  const Spacer(),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (open) ...[
                const SizedBox(height: 10),
                Text(en, style: theme.textTheme.titleMedium),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(notes, style: theme.textTheme.bodyMedium),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isLast,
    required this.onListen,
    required this.onSlow,
    required this.onSkip,
    required this.onNext,
    required this.showShortcuts,
    this.mic,
    this.onMic,
  });

  final bool isLast;
  final VoidCallback onListen;
  final VoidCallback onSlow;
  final VoidCallback onSkip;
  final VoidCallback onNext;
  final bool showShortcuts;
  final _Mic? mic;
  final VoidCallback? onMic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: onListen,
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text('Listen'),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Listen slowly',
                  onPressed: onSlow,
                  icon: const Icon(Icons.slow_motion_video_rounded),
                ),
                if (mic != null) ...[
                  const SizedBox(width: 4),
                  mic == _Mic.recording
                      ? IconButton.filled(
                          key: const ValueKey('mic'),
                          tooltip: 'Stop and check',
                          onPressed: onMic,
                          icon: const Icon(Icons.stop_rounded),
                        )
                      : IconButton.outlined(
                          key: const ValueKey('mic'),
                          tooltip: 'Read aloud and check',
                          onPressed: mic == _Mic.scoring ? null : onMic,
                          icon: mic == _Mic.scoring
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.mic_rounded),
                        ),
                ],
                const SizedBox(width: 4),
                TextButton(onPressed: onSkip, child: const Text('Skip')),
                const SizedBox(width: 4),
                // takes the remaining width, so the bar fits small phones
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('next'),
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: Icon(
                      isLast
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                    label: Text(isLast ? 'Finish' : 'Next'),
                  ),
                ),
              ],
            ),
            if (showShortcuts)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Keys: Enter next · L listen · S slow · R read aloud · M meaning',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(
      String example,
      String label,
      String body, {
      bool underline = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Column(
              children: [
                Text(example, style: theme.textTheme.labelSmall),
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: underline
                            ? theme.colorScheme.outlineVariant
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text('行', style: chineseStyle(lang, fontSize: 30)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleSmall),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How the reading help fades',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            row('haang4', 'New', 'The full reading is shown. Just read along.'),
            row(
              '4',
              'Learning',
              'Only the tone is shown. Tap if you need the rest.',
            ),
            row(
              '',
              'Testing',
              'Faint underline: try to read it. Tap only if you\'re stuck.',
              underline: true,
            ),
            row('', 'Known', 'No help. Long-press if you ever need to check.'),
            const SizedBox(height: 4),
            Text(
              'Tapping is fine: it tells the app which characters to bring back sooner. '
              'Each character fades on its own schedule.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DuckMascot(size: 110, mood: DuckMood.sleepy),
            const SizedBox(height: 12),
            Text(
              'Nothing to read here right now',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Everything in this topic is fresh in your memory. Try another topic or come back later.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryScreen extends StatelessWidget {
  const _SummaryScreen({
    required this.title,
    required this.read,
    required this.practised,
    required this.introduced,
    required this.checked,
  });

  final String title;
  final int read;
  final int practised;
  final int introduced;
  final int checked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String value, String label) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DuckMascot(size: 130, mood: DuckMood.cheer),
                  const SizedBox(height: 12),
                  Text('Nice paddling!', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    checked == 0
                        ? 'You read everything without checking. Nice.'
                        : 'The $checked ${checked == 1 ? 'character' : 'characters'} you checked will come back sooner.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      stat('$read', 'sentences read'),
                      const SizedBox(width: 8),
                      stat('$introduced', 'new characters'),
                      const SizedBox(width: 8),
                      stat('$practised', 'characters practised'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey('done'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(200, 52),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Mic { idle, recording, scoring }

/// "4 of 5 right · 1 tone off" plus what was said instead.
/// Share of characters whose sound was right; a heard tone slip counts half.
/// Tones the recogniser "corrects" silently can't be seen, so this measures sounds.
int soundAccuracy(List<CharScore> scores) {
  if (scores.isEmpty) return 0;
  var pts = 0.0;
  for (final c in scores) {
    if (c.verdict == Verdict.ok) pts += 1;
    if (c.verdict == Verdict.tone) pts += 0.5;
  }
  return (100 * pts / scores.length).round();
}

class _AccuracyBadge extends StatelessWidget {
  const _AccuracyBadge({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = percent >= 85;
    final mid = percent >= 60;
    final bg = good
        ? scheme.primaryContainer
        : mid
        ? scheme.tertiaryContainer
        : scheme.errorContainer;
    final fg = good
        ? scheme.onPrimaryContainer
        : mid
        ? scheme.onTertiaryContainer
        : scheme.onErrorContainer;
    return Container(
      key: const ValueKey('speech-accuracy'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$percent%',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: fg, fontWeight: FontWeight.w700),
          ),
          Text(
            'sounds',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _SpeechResult extends StatelessWidget {
  const _SpeechResult({
    required this.scores,
    this.onPlayMine,
    this.onPlayNative,
  });
  final List<CharScore> scores;
  final VoidCallback? onPlayMine;
  final VoidCallback? onPlayNative;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = scores.where((c) => c.verdict == Verdict.ok).length;
    final tones = scores.where((c) => c.verdict == Verdict.tone).length;
    final wrong = scores.where((c) => c.verdict == Verdict.wrong).length;
    final missed = scores.where((c) => c.verdict == Verdict.missed).length;
    final parts = [
      '$ok of ${scores.length} right',
      if (tones > 0) '$tones tone${tones == 1 ? '' : 's'} off',
      if (wrong > 0) '$wrong different sound${wrong == 1 ? '' : 's'}',
      if (missed > 0) '$missed not heard',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AccuracyBadge(percent: soundAccuracy(scores)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      parts.join(' · '),
                      key: const ValueKey('speech-result'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final c in scores.where((c) => c.isError).take(4))
                Text(
                  "You said ${c.heard}, it's ${c.expected}",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (ok == scores.length)
                Text('Every sound right.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              // Recognition hears sounds well but can "correct" a wrong tone into another
              // real word (賣 heard as 買), so tones are left to the learner's own ear.
              Text(
                'Tones: listen to yours, then the native audio.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  if (onPlayMine != null)
                    OutlinedButton.icon(
                      key: const ValueKey('play-mine'),
                      onPressed: onPlayMine,
                      icon: const Icon(Icons.record_voice_over_rounded),
                      label: const Text('Play mine'),
                    ),
                  if (onPlayNative != null)
                    OutlinedButton.icon(
                      onPressed: onPlayNative,
                      icon: const Icon(Icons.volume_up_rounded),
                      label: const Text('Native'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModelDownloadDialog extends StatefulWidget {
  const ModelDownloadDialog({super.key, required this.engine});
  final SpeechEngine engine;

  @override
  State<ModelDownloadDialog> createState() => ModelDownloadDialogState();
}

class ModelDownloadDialogState extends State<ModelDownloadDialog> {
  double? _progress;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await widget.engine.install(
        progress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null && _error == null;
    return AlertDialog(
      title: const Text('Check your reading aloud'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "DuckLearn listens on this device and checks every character's sound and "
            'tone. It needs a one-time download of the speech model '
            '(${modelBytes ~/ 1000000} MB). Nothing you say leaves the device.',
          ),
          if (_progress != null) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 6),
            Text('${(100 * _progress!).round()}%'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              'Download failed: $_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: busy ? null : _download,
          child: Text(_error == null ? 'Download' : 'Try again'),
        ),
      ],
    );
  }
}
