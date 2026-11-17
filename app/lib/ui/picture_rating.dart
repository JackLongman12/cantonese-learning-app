/// TEMPORARY developer tool (owner, 2026-11-17): rate the word pictures the pipeline was
/// not sure about (`doubt: true` in content/pictures.yaml), one tap each: Bad, OK (fits,
/// a better one would be welcome) or Good.
/// Ratings are events (`picture.rate`); with usage sharing on they reach the developer,
/// and `duk pictures ratings` applies them. A Bad picture stops showing on this device.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/practice_log.dart';
import 'situations.dart' show wordWithReading;
import 'word_picture.dart';

/// Doubtful pictures in situation order, with their cards.
List<(CardRow, WordPictureRow)> doubtfulPictures(AppServices s) {
  final pics = s.content.wordPictures();
  return [
    for (final sit in s.content.situations())
      for (final c in s.content.cards(sit.deck.id))
        if (pics[c.id] case final pic? when pic.doubt) (c, pic),
  ];
}

/// How many doubtful pictures have no rating yet.
int picturesToRate(AppServices s) => doubtfulPictures(s)
    .where(
      (e) => !s.practiceLog.pictureRatings.containsKey(
        PracticeLog.pictureKey(e.$1.id, e.$2.ref),
      ),
    )
    .length;

class PictureRatingScreen extends StatefulWidget {
  const PictureRatingScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<PictureRatingScreen> createState() => _PictureRatingScreenState();
}

class _PictureRatingScreenState extends State<PictureRatingScreen> {
  AppServices get _s => widget.services;
  late final List<(CardRow, WordPictureRow)> _all = doubtfulPictures(_s);

  /// Where we are in [_all]; starts at the first one without a rating.
  late int _index = _firstOpen(0);

  int _firstOpen(int from) {
    for (var i = from; i < _all.length; i++) {
      if (!_s.practiceLog.pictureRatings.containsKey(_key(i))) return i;
    }
    return _all.length;
  }

  String _key(int i) => PracticeLog.pictureKey(_all[i].$1.id, _all[i].$2.ref);

  /// [rating] is `good`, `ok` or `bad`; `good` stays in the payload (OK keeps the
  /// picture too) so older readers of the event still work.
  void _rate(String rating) {
    final (card, pic) = _all[_index];
    _s.logPractice('picture.rate', {
      'card_id': card.id,
      'kind': pic.kind,
      'ref': pic.ref,
      'rating': rating,
      'good': rating != 'bad',
    });
    setState(() => _index = _firstOpen(_index + 1));
    if (_index >= _all.length) unawaited(_s.telemetry?.upload());
  }

  @override
  void dispose() {
    // send what was rated so far, even if not finished
    unawaited(_s.telemetry?.upload());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rated = _all
        .where(
          (e) => _s.practiceLog.pictureRatings.containsKey(
            PracticeLog.pictureKey(e.$1.id, e.$2.ref),
          ),
        )
        .length;
    final done = _index >= _all.length;
    final sharing = _s.prefs.shareData == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate pictures'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$rated / ${_all.length}',
                key: const ValueKey('rate-count'),
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!sharing)
              Container(
                color: scheme.errorContainer,
                padding: const EdgeInsets.all(12),
                child: const Text(
                  'Usage sharing is off, so your ratings stay on this phone. Turn on '
                  '"Share anonymous usage" in Settings to send them.',
                ),
              ),
            Expanded(
              child: done
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _all.isEmpty
                              ? 'No pictures to rate.'
                              : 'All rated. Thank you!',
                          key: const ValueKey('rate-done'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    )
                  : () {
                      final (card, pic) = _all[_index];
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        children: [
                          Text(
                            'Does the picture fit the word?',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: WordPicture(
                              key: ValueKey('rate-pic-${card.id}'),
                              services: _s,
                              cardId: card.id,
                              size: 180,
                              evenIfRatedBad: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(child: wordWithReading(card.tokens, size: 30)),
                          const SizedBox(height: 4),
                          Text(
                            card.alt,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            pic.kind == 'photo' ? 'Photo' : 'Icon',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      );
                    }(),
            ),
            if (!done)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('rate-bad'),
                        onPressed: () => _rate('bad'),
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                          minimumSize: const Size(0, 72),
                        ),
                        icon: const Icon(Icons.thumb_down_rounded),
                        label: const Text('Bad'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        key: const ValueKey('rate-ok'),
                        onPressed: () => _rate('ok'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 72),
                        ),
                        child: const Text('OK'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('rate-good'),
                        onPressed: () => _rate('good'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 72),
                        ),
                        icon: const Icon(Icons.thumb_up_rounded),
                        label: const Text('Good'),
                      ),
                    ),
                  ],
                ),
              ),
            if (_index > 0)
              TextButton(
                key: const ValueKey('rate-back'),
                onPressed: () => setState(() => _index--),
                child: const Text('Back (change the last one)'),
              ),
          ],
        ),
      ),
    );
  }
}
