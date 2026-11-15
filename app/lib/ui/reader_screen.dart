/// Reads a set of sentences one at a time. Every action is logged; grades are derived
/// from what the learner did, not asked for.
library;

import 'voice_picker.dart';
import '../engine/pictures.dart';

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/scaffold.dart';
import '../engine/signals.dart';
import '../events/event_logger.dart';
import 'ruby_text.dart';
import 'visual_novel.dart';
import 'mic_check.dart' show noteSilence, playComparison;
import 'critters.dart';
import 'finish.dart';
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
    this.focus = const {},
    this.onComplete,
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

  /// Weak characters to work on even if not due yet (Review).
  final Set<String> focus;

  /// Called once when the last sentence is finished (Today's plan ticks a step).
  final VoidCallback? onComplete;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late List<SentenceRow> _queue;
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
  final Set<String> _practiced = {};
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
      _queue = _pickMore();
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

  late final Set<String> _recent = _s.recentSentences();

  /// The next batch: chosen by the planner, never repeating a sentence already shown.
  List<SentenceRow> _pickMore({int extraNew = 0}) {
    final seen = {for (final q in _queueOrEmpty) q.id};
    final pool = [
      for (final s in widget.sentences)
        if (!seen.contains(s.id)) s,
    ];
    final picks = _s.planner.plan(
      candidates: [for (final s in pool) s.toCandidate()],
      learner: _s.learner,
      now: _s.logger.now(),
      count: widget.count ?? pool.length,
      maxNew: widget.maxNew + extraNew,
      // different sentences each session, same characters reinforced
      recentlySeen: _recent,
      focus: widget.focus,
      random: _s.variety,
      jitter: AppServices.plannerJitter,
    );
    final byId = {for (final s in pool) s.id: s};
    for (final p in picks) {
      _why[p.candidate.id] = p.reasons;
    }
    return [for (final p in picks) byId[p.candidate.id]!];
  }

  List<SentenceRow> get _queueOrEmpty {
    try {
      return _queue;
    } on Error {
      return const [];
    }
  }

  /// "Keep going": another batch, no cap. Only for planner-picked sessions.
  bool get _canKeepGoing =>
      !(widget.conversation || widget.story || widget.ordered);

  void _keepGoing() {
    // the same mix if possible; otherwise allow a few more new characters
    var more = _pickMore();
    if (more.isEmpty) more = _pickMore(extraNew: 8);
    if (more.isEmpty) {
      // last resort: unseen sentences with the fewest new characters
      final seen = {for (final q in _queue) q.id};
      int newIn(SentenceRow r) =>
          r.itemIds.where((id) => _s.learner.stateOf(id).isNew).length;
      more = [
        for (final r in widget.sentences)
          if (!seen.contains(r.id)) r,
      ]..sort((a, b) => newIn(a).compareTo(newIn(b)));
      more = more.take(widget.count ?? 8).toList();
    }
    if (more.isEmpty) return;
    _s.logger.log('session.more', {'added': more.length});
    setState(() {
      final at = _queue.length;
      _queue = [..._queue, ...more];
      _finished = false;
      _index = at;
      _present();
    });
  }

  bool _completed = false;

  void _complete() {
    if (_completed) return;
    _completed = true;
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    // leaving early still counts once a few sentences were read: no pressure to finish
    if (!_finished && _read >= 3) _complete();
    if (_mic == _Mic.recording) _s.speech?.cancel();
    super.dispose();
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
    if (!_choosing) {
      final shown = _index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _index != shown) return;
        if (widget.autoplay) _play(slow: false, auto: true);
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
    if (widget.autoplay) _play(slow: false, auto: true);
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
    final available = await _s.canSay(_sentence.text);
    if (!mounted) return;
    if (!auto) _audioPlays++;
    _s.logger.log('item.audio', {
      'exposure_id': _exposureId,
      'scope': 'sentence',
      'rate': slow ? 'slow' : 'normal',
      'nth': _audioPlays,
      'available': available,
      if (auto) 'auto': true,
    });
    if (!available) {
      if (auto) return;
      _toast('No audio for this sentence yet');
      return;
    }
    final shownAt = _exposure;
    try {
      await _s.saySentence(_sentence.text, slow: slow);
      // the meaning appears once the line has been heard (setting, on by default)
      if (mounted && !_showTranslation && _exposure == shownAt && !_finished) {
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
      if (!mounted) return;
      noteSilence(context, _s, heard: eng.heardSpeech);
      if (!eng.heardSpeech) {
        setState(() => _mic = _Mic.idle);
        return;
      }
      // let the spinner paint before the (sub-second) recognition runs
      await Future<void>.delayed(const Duration(milliseconds: 16));
      _scoreSpeech(eng.recognise(samples, lang: widget.lang));
      if (mounted) {
        setState(() {
          _mic = _Mic.idle;
          _showTranslation = true; // you tried: the meaning is yours to check
        });
      }
      // below the pass mark: hear yours, then the native; the recording is not kept
      if (soundAccuracy(_speech.values.toList()) < passPercent) {
        await playComparison(_s, samples, _sentence.text);
      }
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
    _s.sound(
      soundAccuracy(score.chars) >= passPercent ? Sfx.good : Sfx.tryAgain,
    );
    // words said wrong go on the practice list
    final seenWords = <int>{};
    for (final e in byToken.entries.where((e) => e.value.isMiss)) {
      if (seenWords.add(s.wordRange(e.key).$1)) flagWord(_s, s, e.key, 'say');
    }
    setState(() {
      _speech = byToken;
      // A mispronounced character is a reading lapse, exactly like tapping to reveal.
      for (final e in byToken.entries.where((e) => e.value.isMiss)) {
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
      _practiced.add(o.itemId);
      if (o.signal == Signal.introduced) _introduced.add(o.itemId);
      if (o.signal == Signal.reveal) _lapsed.add(o.itemId);
    }
    if (outcomes.isNotEmpty) _read++;
    // words on the practice list read right here, without help: that counts as a practice
    if (!skipped) {
      final offs = tokenOffsets(_sentence.tokens);
      for (final w in _s.words.practice(widget.lang)) {
        final at = _sentence.text.indexOf(w.text);
        if (at < 0) continue;
        final end = at + w.text.length;
        final inside = [
          for (var k = 0; k < _sentence.tokens.length; k++)
            if (offs[k] >= at && offs[k] < end) k,
        ];
        final clean = inside.every(
          (k) => !_revealedTokens.contains(k) && !(_speech[k]?.isMiss ?? false),
        );
        if (clean) {
          _s.logger.log('word.practice', {
            'text': w.text,
            'lang': w.lang,
            'ok': true,
          });
        }
      }
    }
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
    _s.silence(); // nothing from this sentence keeps playing over the next
    _finishCurrent(skipped: skipped);
    if (_index + 1 >= _queue.length) {
      _s.prefs.resume = null;
      _s.logger.log('session.end', {
        'reason': 'done',
        'items_done': _queue.length,
      });
      _s.sound(Sfx.finish);
      _complete();
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
        services: _s,
        title: widget.title,
        read: _read,
        practiced: _practiced.length,
        introduced: _introduced.length,
        checked: _lapsed.length,
        onKeepGoing: _canKeepGoing ? _keepGoing : null,
        newChars: [
          for (final id in _introduced)
            if (id.split(':') case [_, _, final ch, final r]) (ch, r),
        ],
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
            leading: closeToHome(context),
            title: Text(widget.title),
            actions: [
              VoiceButton(_s),
              IconButton(
                tooltip: 'How reading help works',
                onPressed: _showHelp,
                icon: const Icon(Icons.help_outline_rounded),
              ),
            ],
            bottom: duckBar(_index / _queue.length),
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
                        // a picture of what the sentence is about
                        if (pictureForMeaning(s.en) case final pic?)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              pic,
                              key: const ValueKey('sentence-picture'),
                              style: const TextStyle(fontSize: 40),
                            ),
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
              slowNext: _audioPlays.isOdd,
              onListen: () async {
                await _play(slow: _audioPlays.isOdd);
                if (mounted) setState(() {});
              },
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
    required this.slowNext,
    required this.onSkip,
    required this.onNext,
    required this.showShortcuts,
    this.mic,
    this.onMic,
  });

  final bool isLast;
  final VoidCallback onListen;

  /// The next tap plays it slower (every second tap).
  final bool slowNext;
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
                // one button, no holding: tap to listen, tap again for slower
                FilledButton.tonalIcon(
                  key: const ValueKey('listen'),
                  onPressed: mic == _Mic.recording ? null : onListen,
                  icon: const Icon(Icons.volume_up_rounded),
                  label: Text(slowNext ? 'Slower' : 'Listen'),
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
                const SizedBox(width: 8),
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
            row('', 'Known', 'No help. Tap a word if you ever need to check.'),
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
            const Chick(mood: ChickMood.sleepy, size: 110),
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
    required this.services,
    required this.title,
    required this.read,
    required this.practiced,
    required this.introduced,
    required this.checked,
    this.newChars = const [],
    this.onKeepGoing,
  });

  final AppServices services;

  /// More of the same, if wanted. Stopping is just as fine.
  final VoidCallback? onKeepGoing;

  /// Characters met for the first time: (character, Jyutping).
  final List<(String, String)> newChars;
  final String title;
  final int read;
  final int practiced;
  final int introduced;
  final int checked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget stat(String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.titleLarge),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
      body: SafeArea(
        child: FinishView(
          services: services,
          // read it all without help: proud, with stars
          mood: checked == 0 && read > 0 ? ChickMood.proud : ChickMood.happy,
          title: checked == 0 ? 'All read without help' : 'Nice reading',
          subtitle: checked == 0
              ? null
              : 'The $checked ${checked == 1 ? 'character' : 'characters'} you checked will come back sooner.',
          onKeepGoing: onKeepGoing,
          children: [
            const SizedBox(height: 16),
            Row(
              children: [
                stat('$read', 'sentences read'),
                const SizedBox(width: 8),
                stat('$introduced', 'new characters'),
                const SizedBox(width: 8),
                stat('$practiced', 'practiced'),
              ],
            ),
            if (newChars.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                key: const ValueKey('new-chars'),
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final (ch, r) in newChars.take(16))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r, style: theme.textTheme.labelSmall),
                          Text(ch, style: chineseStyle('yue', fontSize: 20)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _Mic { idle, recording, scoring }

/// "4 of 5 right · 1 tone off" plus what was said instead.
/// Share of characters whose sound was right (tone slips forgiven).
int soundAccuracy(List<CharScore> scores) => lenientAccuracy(scores);

class _AccuracyBadge extends StatelessWidget {
  const _AccuracyBadge({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = percent >= passPercent;
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
