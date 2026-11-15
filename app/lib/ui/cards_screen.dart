/// Flashcards of real Macau and Hong Kong names (streets, LRT and MTR stations), from
/// OpenStreetMap. The front is the sign as written, with the same fading Jyutping as
/// everywhere else; the back gives the full reading, the Portuguese/English name on the
/// sign, and the audio.
library;

import '../engine/pictures.dart';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/deck_planner.dart';
import '../engine/item_state.dart';
import '../engine/pronunciation.dart';
import '../engine/scaffold.dart';
import '../events/event_logger.dart';
import '../platform/sfx.dart';
import 'mic_check.dart';
import 'ruby_text.dart';
import 'tiles.dart';
import 'word_sheet.dart';

/// Deck tiles for the Topics tab (Cantonese only: these are Cantonese names).
class DeckSection extends StatelessWidget {
  const DeckSection({
    super.key,
    required this.services,
    required this.onChanged,
  });
  final AppServices services;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decks = services.content.decks();
    if (decks.isEmpty) return const SizedBox.shrink();
    final now = services.logger.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Flashcards', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Cantonese dishes with photos, and real street and station names '
          'from the map.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (dueCards(services, decks) case final due when due.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilledButton.icon(
              key: const ValueKey('review-due-cards'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              onPressed: () async {
                services.sound(Sfx.tap);
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CardSessionScreen(
                      services: services,
                      deck: const DeckRow('due', 'Cards due', 'both', '', 0),
                      cards: due.take(20).toList(),
                    ),
                  ),
                );
                onChanged();
              },
              icon: const Icon(Icons.style_rounded),
              label: Text(
                'Review ${due.length} due ${due.length == 1 ? 'card' : 'cards'}',
              ),
            ),
          ),
        TileGrid(
          children: [
            for (final d in decks)
              _DeckTile(
                deck: d,
                progress: deckProgress(
                  [for (final c in services.content.cards(d.id)) c.id],
                  services.learner.stateOf,
                  now,
                ),
                onTap: () async {
                  services.sound(Sfx.tap);
                  services.logger.log('nav.screen', {
                    'screen': 'deck',
                    'deck_id': d.id,
                  });
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CardSessionScreen(services: services, deck: d),
                    ),
                  );
                  onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Cards from every deck whose review is due now, most overdue first.
List<CardRow> dueCards(AppServices s, List<DeckRow> decks) {
  final now = s.logger.now();
  final due = <(CardRow, DateTime)>[];
  for (final d in decks) {
    for (final c in s.content.cards(d.id)) {
      final st = s.learner.stateOf(c.id);
      if (!st.isNew && st.due != null && !st.due!.isAfter(now)) {
        due.add((c, st.due!));
      }
    }
  }
  due.sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final d in due) d.$1];
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.deck,
    required this.progress,
    required this.onTap,
  });
  final DeckRow deck;
  final ({int learned, int due}) progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppTile(
    key: ValueKey('deck-${deck.id}'),
    icon: deck.id == 'food'
        ? Icons.restaurant_rounded
        : deck.id.contains('streets')
        ? Icons.signpost_rounded
        : Icons.train_rounded,
    title: deck.title,
    subtitle: '${progress.learned} of ${deck.count} seen',
    badge: progress.due > 0 ? '${progress.due} due' : null,
    progress: deck.count == 0 ? 0 : progress.learned / deck.count,
    onTap: onTap,
  );
}

class CardSessionScreen extends StatefulWidget {
  const CardSessionScreen({
    super.key,
    required this.services,
    required this.deck,
    this.cards,
    this.onComplete,
  });
  final AppServices services;
  final DeckRow deck;

  /// Cards to study instead of the deck's own (e.g. everything due, across decks).
  final List<CardRow>? cards;

  /// Called once when the session is finished.
  final VoidCallback? onComplete;

  @override
  State<CardSessionScreen> createState() => _CardSessionScreenState();
}

class _CardSessionScreenState extends State<CardSessionScreen> {
  AppServices get _s => widget.services;
  late final List<CardRow> _all =
      widget.cards ?? _s.content.cards(widget.deck.id);

  /// How often each card came back this session ("couldn't read it" -> again soon).
  final _requeued = <String, int>{};

  /// Read-aloud result for the current card.
  List<CharScore>? _micScores;
  int? _micPct;
  late List<CardRow> _queue;
  int _index = 0;
  bool _flipped = false;
  late ActiveMark _mark;
  Map<String, ScaffoldLevel> _levels = const {};
  final _revealed = <String>{};
  final _revealedTokens = <int>{};
  int _known = 0, _again = 0;
  late final _patterns = _s.content.streetPatterns(widget.deck.region);

  CardRow get _card => _queue[_index];

  @override
  void initState() {
    super.initState();
    final byId = {for (final c in _all) c.id: c};
    _queue = [
      for (final id in pickCards(
        deckOrder: [for (final c in _all) c.id],
        stateOf: _s.learner.stateOf,
        now: _s.logger.now(),
      ))
        byId[id]!,
    ];
    _s.logger.log('session.start', {
      'mode': 'deck',
      'deck_id': widget.deck.id,
      'lang': 'yue',
      'planned_items': _queue.length,
    });
    if (_queue.isNotEmpty) _present();
  }

  void _present() {
    final now = _s.logger.now();
    _levels = {
      for (final id in _card.itemIds)
        id: _s.scaffold.levelFor(_s.learner.stateOf(id), _s.memory, now),
    };
    _flipped = false;
    _micScores = null;
    _micPct = null;
    _revealed.clear();
    _revealedTokens.clear();
    _mark = _s.logger.mark();
    _s.logger.log('item.shown', {
      'exposure_id': '${_s.logger.sessionId}-card-$_index',
      'card_id': _card.id,
      'lang': 'yue',
      'item_ids': _levels.keys.toList(),
      'scaffold': [for (final l in _levels.values) l.name],
      'pos_in_session': _index,
    });
  }

  void _reveal(int i) {
    final t = _card.tokens[i];
    if (t.itemId == null || _revealedTokens.contains(i)) return;
    HapticFeedback.selectionClick();
    _s.sound(Sfx.reveal);
    setState(() {
      _revealedTokens.add(i);
      _revealed.add(t.itemId!);
    });
  }

  Future<void> _play() async {
    final path = _s.content.audioPath('yue', _card.zh);
    if (path != null) await _s.playAudio(path);
  }

  void _flip() {
    _s.sound(Sfx.tap);
    setState(() => _flipped = true);
    if (_s.prefs.autoPlay) _play();
  }

  /// "Got it" or "Again": the card itself is graded, and each character too, so street
  /// names count towards reading everywhere else.
  void _grade(bool gotIt) {
    final exposure = '${_s.logger.sessionId}-card-$_index';
    final outcomes = _s.signals.outcomes(
      shown: _levels,
      revealed: gotIt ? _revealed : _levels.keys.toSet(),
      activeMs: _s.logger.activeMsSince(_mark),
    );
    for (final o in outcomes) {
      _s.logger.log('review.applied', {
        'exposure_id': exposure,
        'item_id': o.itemId,
        'grade': o.grade.name,
        'signal': o.signal.name,
        's_before': _s.learner.stateOf(o.itemId).stability,
      });
    }
    _s.logger.log('review.applied', {
      'exposure_id': exposure,
      'item_id': _card.id,
      'grade': gotIt ? Grade.good.name : Grade.again.name,
      'signal': 'explicit',
      's_before': _s.learner.stateOf(_card.id).stability,
    });
    gotIt ? _known++ : _again++;
    if (!gotIt) {
      _s.logger.log('word.flag', {
        'text': _card.zh,
        'lang': 'yue',
        'reason': _micPct != null ? 'say' : 'read',
        'reading': [
          for (final t in _card.tokens)
            if (t.reading != null) t.reading!,
        ].join(' '),
        'context': _card.zh,
        'context_en': _card.alt,
      });
      final n = _requeued[_card.id] ?? 0;
      if (n < 2) {
        _requeued[_card.id] = n + 1;
        final at = (_index + 4).clamp(0, _queue.length);
        _queue.insert(at, _card);
      }
    }
    if (_index + 1 >= _queue.length) {
      _s.logger.log('session.end', {
        'reason': 'done',
        'items_done': _queue.length,
      });
      _s.sound(Sfx.finish);
      _complete();
      setState(() => _index++);
      return;
    }
    _s.sound(gotIt ? Sfx.next : Sfx.tryAgain);
    setState(() {
      _index++;
      _present();
    });
  }

  @override
  void dispose() {
    if (_known + _again >= 3) _complete();
    super.dispose();
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
    final done = _index >= _queue.length;
    return Scaffold(
      bottomNavigationBar: done || _queue.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _flipped
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const ValueKey('again'),
                              onPressed: () => _grade(false),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 56),
                              ),
                              child: const Text("Couldn't read it"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              key: const ValueKey('got-it'),
                              onPressed: () => _grade(true),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 56),
                              ),
                              child: const Text('Read it'),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: MicCheck(
                              key: ValueKey('mic-${_card.id}-$_index'),
                              services: _s,
                              nativeText: _card.zh,
                              expected: [
                                for (final t in _card.tokens)
                                  if (t.reading != null) t.reading!,
                              ],
                              onResult: (scores, pct) {
                                final at = _index;
                                setState(() {
                                  _micScores = scores;
                                  _micPct = pct;
                                });
                                _flip();
                                // said right: counts as read, move on by itself
                                // around half wrong: counts as not read
                                if (pct <= failPercent) {
                                  Future<void>.delayed(
                                    const Duration(milliseconds: 1600),
                                    () {
                                      if (mounted && _index == at && _flipped) {
                                        _grade(false);
                                      }
                                    },
                                  );
                                }
                                if (pct >= passPercent) {
                                  Future<void>.delayed(
                                    const Duration(milliseconds: 1400),
                                    () {
                                      if (mounted && _index == at && _flipped) {
                                        _grade(true);
                                      }
                                    },
                                  );
                                }
                              },
                            ),
                          ),
                          if (_s.speech != null) const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              key: const ValueKey('flip'),
                              onPressed: _flip,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 56),
                              ),
                              child: const Text('Check'),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
      appBar: AppBar(
        title: Text(widget.deck.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: _queue.isEmpty ? 1 : _index / _queue.length,
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _queue.isEmpty
                ? const _Message('Nothing due in this deck. Come back later.')
                : done
                ? _Message(
                    '$_known known · $_again to see again soon',
                    key: const ValueKey('deck-done'),
                    action: FilledButton(
                      key: const ValueKey('done'),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // the dish's photo, so the word and the food stick together
                      // no photo: a picture for the kind of card
                      if (_card.image == null)
                        Center(
                          child: Text(
                            widget.deck.id.contains('streets')
                                ? '🛣️'
                                : widget.deck.id == 'food'
                                ? (pictureForMeaning(_card.alt) ?? '🍽️')
                                : widget.deck.id == 'due'
                                ? (pictureForMeaning(_card.alt) ?? '🗂️')
                                : '🚉',
                            style: const TextStyle(fontSize: 56),
                          ),
                        ),
                      if (_card.image case final img?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: Image.asset(
                                'assets/cards/$img',
                                key: const ValueKey('card-photo'),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 36,
                            horizontal: 16,
                          ),
                          child: Center(
                            child: RubyText(
                              lang: 'yue',
                              fontSize: 44 * _s.prefs.textScale,
                              tokens: [
                                for (var i = 0; i < _card.tokens.length; i++)
                                  RubyToken(
                                    surface: _card.tokens[i].surface,
                                    kind: _card.tokens[i].kind,
                                    reading: _card.tokens[i].reading,
                                    level: _flipped
                                        ? ScaffoldLevel.full
                                        : _levels[_card.tokens[i].itemId] ??
                                              ScaffoldLevel.full,
                                    revealed:
                                        !_flipped &&
                                        _revealedTokens.contains(i),
                                    flagged: _card.tokens[i].flagged,
                                  ),
                              ],
                              onReveal: _flipped ? null : _reveal,
                              onSpeak: (i) => _flipped
                                  ? _play()
                                  : sayOrExplain(
                                      context,
                                      _s,
                                      _card.tokens[i].surface,
                                      'yue',
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_flipped) ...[
                        Text(
                          'Read it aloud, or in your head and check.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ] else ...[
                        if (_micPct case final pct?)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              pct >= passPercent
                                  ? 'You said it right ($pct%)'
                                  : pct <= failPercent
                                  ? "Couldn't read it ($pct%): ${_micScores!.where((c) => c.isMiss).map((c) => "${c.heard ?? '–'} → ${c.expected}").join(', ')}"
                                  : 'Close ($pct%), you decide: ${_micScores!.where((c) => c.isMiss).map((c) => "${c.heard ?? '–'} → ${c.expected}").join(', ')}',
                              key: const ValueKey('card-mic-result'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: pct >= passPercent
                                    ? scheme.primary
                                    : scheme.error,
                              ),
                            ),
                          ),
                        if (_card.alt.isNotEmpty)
                          Text(
                            _card.alt,
                            key: const ValueKey('card-alt'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                        if (_card.credit.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _card.credit,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (_card.note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _card.note,
                              textAlign: TextAlign.center,
                              style: chineseStyle(
                                'yue',
                                fontSize: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (_hint() case final h?)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              h,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.tertiary,
                              ),
                            ),
                          ),
                        if (_card.flagged)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'A reading here is not confirmed yet (orange).',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed: _play,
                            icon: const Icon(Icons.volume_up_rounded),
                            label: const Text('Listen'),
                          ),
                        ),
                        Center(
                          child: TextButton.icon(
                            onPressed: () => _lookup(context),
                            icon: const Icon(Icons.translate_rounded),
                            label: const Text('Word meanings'),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// "大馬路 is usually Avenida (79 of 81 on the map)", for street cards.
  String? _hint() {
    if (!widget.deck.id.contains('streets')) return null;
    for (final p in _patterns) {
      if (_card.zh.endsWith(p.zh)) {
        return '${p.zh} is usually “${p.word}” (${p.n} of ${p.total} on the map)';
      }
    }
    return null;
  }

  void _lookup(BuildContext context) {
    final c = _card;
    showWordLookup(
      context,
      services: _s,
      lang: 'yue',
      sentence: SentenceRow(
        id: c.id,
        pairId: c.id,
        lang: 'yue',
        text: c.zh,
        en: c.alt,
        register: 'written',
        region: widget.deck.region,
        notes: '',
        reviewed: false,
        tokens: c.tokens,
      ),
      tokenIndex: c.tokens.indexWhere((t) => t.kind == 'han'),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {super.key, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}
