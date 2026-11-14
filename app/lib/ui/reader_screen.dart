/// Reads a set of sentences one at a time. Every action is logged; grades are derived
/// from what the learner did, not asked for.
library;

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
  int _audioPlays = 0;
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
    _s.logger.log('session.start', {
      'mode': widget.mode,
      'scenario_id': ?widget.scenarioId,
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
    if (t.itemId == null || _revealedTokens.contains(tokenIndex)) return;
    HapticFeedback.selectionClick();
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
      _toast('No audio for this sentence yet');
      return;
    }
    try {
      await _s.playAudio(path);
    } on Object catch (e) {
      if (mounted) _toast('Could not play audio: $e');
    }
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
      _s.logger.log('session.end', {
        'reason': 'done',
        'items_done': _queue.length,
      });
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index++;
      _present();
    });
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
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) => _body(context, wide: c.maxWidth > 700),
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
                        if (!s.reviewed) ...[
                          const SizedBox(width: 6),
                          const _Tag(
                            icon: Icons.edit_note_rounded,
                            text: 'Draft',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
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
                          fontSize: wide ? 44 : 34,
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
                    const SizedBox(height: 16),
                    _MeaningPanel(
                      open: _showTranslation,
                      en: s.en,
                      notes: s.notes,
                      onToggle: _toggleMeaning,
                    ),
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
  });

  final bool isLast;
  final VoidCallback onListen;
  final VoidCallback onSlow;
  final VoidCallback onSkip;
  final VoidCallback onNext;
  final bool showShortcuts;

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
                  'Keys: Enter next · L listen · S slow · M meaning',
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
    final cmn = lang == 'cmn';
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
                  child: Text(
                    cmn ? '行' : '行',
                    style: chineseStyle(lang, fontSize: 30),
                  ),
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
            row(
              cmn ? 'xíng' : 'haang4',
              'New',
              'The full reading is shown. Just read along.',
            ),
            row(
              cmn ? 'ˊ' : '4',
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
