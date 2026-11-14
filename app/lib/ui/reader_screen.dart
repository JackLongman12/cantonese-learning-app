/// Reads one scenario sentence by sentence. Every action is logged; grades are derived
/// from what the learner did, not asked for.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/scaffold.dart';
import '../engine/signals.dart';
import '../events/event_logger.dart';
import 'ruby_text.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.services,
    required this.scenario,
    required this.lang,
  });

  final AppServices services;
  final ScenarioRow scenario;
  final String lang;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final List<SentenceRow> _queue;
  final Map<String, List<String>> _why = {};
  int _index = 0;
  int _exposure = 0;

  // state of the sentence on screen
  late Map<String, ScaffoldLevel> _levels;
  final Set<String> _revealed = {};
  final Set<int> _revealedTokens = {};
  bool _showTranslation = false;
  int _audioPlays = 0;
  late ActiveMark _mark;

  AppServices get _s => widget.services;
  SentenceRow get _sentence => _queue[_index];

  @override
  void initState() {
    super.initState();
    final all = _s.content.sentences(widget.scenario.id, widget.lang);
    final picks = _s.planner.plan(
      candidates: [for (final s in all) s.toCandidate()],
      learner: _s.learner,
      now: _s.logger.now(),
      count: all.length,
      maxNew: 12,
    );
    final byId = {for (final s in all) s.id: s};
    _queue = [for (final p in picks) byId[p.candidate.id]!];
    for (final p in picks) {
      _why[p.candidate.id] = p.reasons;
    }
    _s.logger.log('session.start', {
      'mode': 'reader',
      'scenario_id': widget.scenario.id,
      'lang': widget.lang,
      'planned_items': _queue.length,
    });
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
    _exposure++;
    _mark = _s.logger.mark();
    _s.logger.touch();
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

  String get _exposureId => '${_s.logger.sessionId}-$_exposure';

  void _reveal(int tokenIndex) {
    final t = _sentence.tokens[tokenIndex];
    if (t.itemId == null) return;
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

  Future<void> _play({required bool slow}) async {
    _s.logger.touch();
    final path = _s.content.audioPath(widget.lang, _sentence.text, slow: slow);
    _audioPlays++;
    _s.logger.log('item.audio', {
      'exposure_id': _exposureId,
      'scope': 'sentence',
      'rate': slow ? 'slow' : 'normal',
      'nth': _audioPlays,
      'available': path != null,
    });
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audio for this sentence yet')),
      );
      return;
    }
    try {
      await _s.playAudio(path);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not play audio: $e')));
    }
  }

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
    _finishCurrent(skipped: skipped);
    if (_index + 1 >= _queue.length) {
      _s.logger.log('session.end', {
        'reason': 'done',
        'items_done': _queue.length,
      });
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _index++;
      _present();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.scenario.title)),
        body: const Center(child: Text('Nothing to read here right now.')),
      );
    }
    final s = _sentence;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scenario.title),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${_index + 1} / ${_queue.length}'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RubyText(
                        lang: widget.lang,
                        onReveal: _reveal,
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
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (_showTranslation) ...[
                        Text(s.en, style: theme.textTheme.titleMedium),
                        if (s.notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(s.notes, style: theme.textTheme.bodyMedium),
                        ],
                      ],
                      if (!s.reviewed) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Not checked by you yet',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _play(slow: false),
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Listen'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _play(slow: true),
                    icon: const Icon(Icons.slow_motion_video),
                    label: const Text('Slow'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _s.logger.touch();
                      if (!_showTranslation) {
                        _s.logger.log('item.reveal', {
                          'exposure_id': _exposureId,
                          'what': 'translation',
                          'latency_ms': _s.logger.activeMsSince(_mark),
                        });
                      }
                      setState(() => _showTranslation = !_showTranslation);
                    },
                    icon: const Icon(Icons.translate),
                    label: Text(_showTranslation ? 'Hide meaning' : 'Meaning'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _next(skipped: true),
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('next'),
                    onPressed: _next,
                    child: Text(
                      _index + 1 >= _queue.length ? 'Finish' : 'Next',
                    ),
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
