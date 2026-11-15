/// Practise the words the app noticed you struggled with, in the sentence they came
/// from: in Cantonese the context decides the reading and the meaning. The sentence
/// shows with its usual help, the practised word is highlighted with its Jyutping
/// hidden, and the meaning of the sentence is there to lean on. Read the whole
/// sentence aloud; the mic grades the practised word. Without a mic, check the reading
/// and say whether you got it. Two right in a row takes a word off the list.
library;

import '../engine/pictures.dart';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/pronunciation.dart';
import '../engine/scaffold.dart';
import '../engine/word_book.dart';
import '../platform/sfx.dart';
import 'mic_check.dart';
import 'ruby_text.dart';
import 'word_sheet.dart';

class PracticeWordsScreen extends StatefulWidget {
  const PracticeWordsScreen({
    super.key,
    required this.services,
    required this.words,
    this.onComplete,
  });
  final AppServices services;
  final List<PracticeWord> words;

  /// Called once when the last word is done.
  final VoidCallback? onComplete;

  @override
  State<PracticeWordsScreen> createState() => _PracticeWordsScreenState();
}

class _PracticeWordsScreenState extends State<PracticeWordsScreen> {
  AppServices get _s => widget.services;
  int _index = 0;
  bool _shown = false;
  List<CharScore>? _scores;
  bool? _ok;
  int _right = 0;

  PracticeWord get _w => widget.words[_index];

  /// The sentence the word came from, or the word alone (cards have no sentence).
  late SentenceRow _ctx = _contextFor(_w);

  SentenceRow _contextFor(PracticeWord w) {
    final id = w.sentenceId;
    final found = id == null
        ? const <SentenceRow>[]
        : _s.content.sentencesByIds([id]);
    if (found.isNotEmpty) return found.first;
    final tokens = _s.content.annotator('yue').annotate(w.context ?? w.text);
    return SentenceRow(
      id: 'practice:${w.text}',
      pairId: '',
      lang: 'yue',
      text: w.context ?? w.text,
      en: w.contextEn ?? '',
      register: 'spoken',
      region: 'both',
      notes: '',
      reviewed: false,
      tokens: [
        for (final t in tokens)
          TokenRow(t.surface, t.kind, t.reading, null, false),
      ],
    );
  }

  /// Token range of the practised word inside the sentence.
  (int, int) get _range {
    final i = _ctx.text.indexOf(_w.text);
    if (i < 0) return (0, _ctx.tokens.length);
    var off = 0, a = -1, b = -1;
    for (var k = 0; k < _ctx.tokens.length; k++) {
      if (off == i) a = k;
      off += _ctx.tokens[k].surface.length;
      if (off == i + _w.text.length) {
        b = k + 1;
        break;
      }
    }
    return a < 0 || b < 0 ? (0, _ctx.tokens.length) : (a, b);
  }

  /// Readings of every character in the sentence, in order (what the mic expects).
  List<String> get _sentenceReadings => [
    for (final t in _ctx.tokens)
      if (t.kind == 'han' && t.reading != null) t.reading!,
  ];

  /// Which entries of [_sentenceReadings] belong to the practised word.
  Set<int> get _wordPositions {
    final (a, b) = _range;
    final out = <int>{};
    var n = 0;
    for (var k = 0; k < _ctx.tokens.length; k++) {
      final t = _ctx.tokens[k];
      if (t.kind != 'han' || t.reading == null) continue;
      if (k >= a && k < b) out.add(n);
      n++;
    }
    return out;
  }

  void _record(bool ok) {
    _s.logger.log('word.practice', {
      'text': _w.text,
      'lang': _w.lang,
      'ok': ok,
    });
    if (ok) _right++;
  }

  void _next() {
    _s.sound(Sfx.next);
    if (_index + 1 >= widget.words.length) widget.onComplete?.call();
    setState(() {
      _index++;
      _shown = false;
      _scores = null;
      _ok = null;
      if (_index < widget.words.length) _ctx = _contextFor(_w);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _index >= widget.words.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practise words'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: widget.words.isEmpty ? 1 : _index / widget.words.length,
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: done
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_right of ${widget.words.length} right',
                        key: const ValueKey('practice-done'),
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Words come off the list after two right in a row.',
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Read the sentence aloud. Focus on ',
                              ),
                              TextSpan(
                                text: _w.text,
                                style: chineseStyle(
                                  'yue',
                                  fontSize: 18,
                                  color: scheme.primary,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Builder(
                              builder: (_) {
                                final (a, b) = _range;
                                return RubyText(
                                  key: const ValueKey('practice-sentence'),
                                  lang: 'yue',
                                  fontSize: 32 * _s.prefs.textScale,
                                  wordOf: _ctx.wordOf,
                                  tokens: [
                                    for (var k = 0; k < _ctx.tokens.length; k++)
                                      RubyToken(
                                        surface: _ctx.tokens[k].surface,
                                        kind: _ctx.tokens[k].kind,
                                        reading: _ctx.tokens[k].reading,
                                        // the practised word: no help until you check
                                        level:
                                            k >= a &&
                                                k < b &&
                                                !_shown &&
                                                _scores == null
                                            ? ScaffoldLevel.tap
                                            : ScaffoldLevel.full,
                                        saved: k >= a && k < b,
                                        mark: k >= a && k < b && _scores != null
                                            ? (_ok!
                                                  ? SpeechMark.ok
                                                  : SpeechMark.wrong)
                                            : null,
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        if (pictureForMeaning(_ctx.en) case final pic?)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Center(
                              child: Text(
                                pic,
                                style: const TextStyle(fontSize: 48),
                              ),
                            ),
                          ),
                        if (_ctx.en.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            _ctx.en,
                            key: const ValueKey('practice-meaning'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (_scores != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _scores!.isEmpty
                                ? 'That is how it reads. It stays on your list.'
                                : _ok!
                                ? 'Right!'
                                : 'Not quite: ${[for (final i in _wordPositions)
                                    if (i < _scores!.length && _scores![i].isMiss) "you said ${_scores![i].heard ?? '–'}, it's ${_scores![i].expected}"].join('; ')}',
                            key: const ValueKey('practice-result'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: _ok == true
                                  ? scheme.primary
                                  : scheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // actions at the bottom, in reach of the thumb
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: _bottom(context),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _bottom(BuildContext context) {
    if (_scores != null) {
      return FilledButton(
        key: const ValueKey('practice-next'),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
        onPressed: _next,
        child: const Text('Next'),
      );
    }
    if (_shown) {
      // no mic: say whether you read it
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('self-wrong'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: () {
                _record(false);
                _next();
              },
              child: const Text('Not yet'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const ValueKey('self-right'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: () {
                _record(true);
                _next();
              },
              child: const Text('I read it'),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MicCheck(
          key: ValueKey('practice-mic-$_index'),
          services: _s,
          nativeText: _ctx.text,
          expected: _sentenceReadings,
          label: 'Read the sentence aloud',
          onResult: (scores, _) {
            final positions = _wordPositions;
            final ok =
                positions.isNotEmpty &&
                positions.every((i) => i < scores.length && !scores[i].isMiss);
            _record(ok);
            setState(() {
              _scores = scores;
              _ok = ok;
            });
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () {
                  final path = _s.content.audioPath('yue', _ctx.text);
                  path != null
                      ? _s.playAudio(path)
                      : sayOrExplain(context, _s, _w.text, 'yue');
                },
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('Hear it'),
              ),
            ),
            Expanded(
              child: TextButton(
                key: const ValueKey('practice-show'),
                onPressed: () {
                  if (_s.speech != null) {
                    // looking it up counts as not reading it
                    _record(false);
                    setState(() {
                      _scores = const [];
                      _ok = false;
                    });
                  } else {
                    setState(() => _shown = true);
                  }
                },
                child: const Text('Show reading'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
