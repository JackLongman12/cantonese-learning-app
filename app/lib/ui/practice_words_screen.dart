/// Practise the words the app noticed you struggled with. Each word appears without
/// Jyutping, inside the sentence it came from; you read it aloud and the mic grades
/// you (or, without a mic, you check the reading and say whether you got it). Two
/// correct in a row takes a word off the list.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../engine/pronunciation.dart';
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
  });
  final AppServices services;
  final List<PracticeWord> words;

  @override
  State<PracticeWordsScreen> createState() => _PracticeWordsScreenState();
}

class _PracticeWordsScreenState extends State<PracticeWordsScreen> {
  AppServices get _s => widget.services;
  int _index = 0;
  bool _shown = false;
  List<CharScore>? _scores;
  int? _percent;
  int _right = 0;

  PracticeWord get _w => widget.words[_index];

  List<String> get _expected =>
      (_w.reading ??
              _s.content
                  .annotator('yue')
                  .annotate(_w.text)
                  .map((t) => t.reading ?? '')
                  .join(' '))
          .split(' ')
          .where((r) => r.isNotEmpty)
          .toList();

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
    setState(() {
      _index++;
      _shown = false;
      _scores = null;
      _percent = null;
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
                        Text(
                          'Read this word aloud',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            _w.text,
                            key: const ValueKey('practice-word'),
                            style: chineseStyle('yue', fontSize: 56),
                          ),
                        ),
                        if (_shown || _scores != null)
                          Center(
                            child: Text(
                              _expected.join(' '),
                              key: const ValueKey('practice-reading'),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        if (_w.context case final c?) ...[
                          const SizedBox(height: 20),
                          _Context(text: c, word: _w.text),
                          if (_shown && _w.contextEn != null)
                            Text(
                              _w.contextEn!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                        if (_scores != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _scores!.isEmpty
                                ? 'That is how it reads. It stays on your list.'
                                : _percent! >= 85
                                ? 'Right! ($_percent%)'
                                : 'Not quite ($_percent%): '
                                      '${_scores!.where((c) => c.isError).map((c) => "you said ${c.heard ?? '–'}, it's ${c.expected}").join('; ')}',
                            key: const ValueKey('practice-result'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: _percent! >= 85
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
                    child: _scores != null || (_shown && _s.speech == null)
                        ? _shown && _scores == null
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        key: const ValueKey('self-wrong'),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 56),
                                        ),
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
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(0, 56),
                                        ),
                                        onPressed: () {
                                          _record(true);
                                          _next();
                                        },
                                        child: const Text('I read it'),
                                      ),
                                    ),
                                  ],
                                )
                              : FilledButton(
                                  key: const ValueKey('practice-next'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 56),
                                  ),
                                  onPressed: _next,
                                  child: const Text('Next'),
                                )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              MicCheck(
                                services: _s,
                                expected: _expected,
                                label: 'Read it aloud',
                                onResult: (scores, pct) {
                                  _record(pct >= 85);
                                  setState(() {
                                    _scores = scores;
                                    _percent = pct;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: () => sayOrExplain(
                                        context,
                                        _s,
                                        _w.text,
                                        'yue',
                                      ),
                                      icon: const Icon(Icons.volume_up_rounded),
                                      label: const Text('Hear it'),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextButton(
                                      key: const ValueKey('practice-show'),
                                      onPressed: () {
                                        // looking it up counts as not reading it
                                        if (_s.speech != null) _record(false);
                                        setState(() => _shown = true);
                                        if (_s.speech != null) {
                                          _scores = const [];
                                          _percent = 0;
                                        }
                                      },
                                      child: const Text('Show reading'),
                                    ),
                                  ),
                                ],
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

/// The sentence the word came from, with the word marked.
class _Context extends StatelessWidget {
  const _Context({required this.text, required this.word});
  final String text;
  final String word;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = text.indexOf(word);
    final base = chineseStyle('yue', fontSize: 20, color: scheme.onSurface);
    if (i < 0) return Text(text, style: base);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: text.substring(0, i)),
          TextSpan(
            text: word,
            style: base.copyWith(
              backgroundColor: scheme.tertiaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: text.substring(i + word.length)),
        ],
      ),
    );
  }
}
