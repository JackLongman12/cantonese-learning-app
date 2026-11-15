/// "My words": every word the learner saved while reading, with its meaning, the
/// sentence it came from and that sentence's translation. Practise reads those
/// sentences again, so words are always met in context.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/word_book.dart';
import '../platform/sfx.dart';
import 'practice_words_screen.dart';
import 'reader_screen.dart';
import 'ruby_text.dart';
import 'word_sheet.dart';

class WordsScreen extends StatefulWidget {
  const WordsScreen({super.key, required this.services, required this.lang});
  final AppServices services;
  final String lang;

  @override
  State<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen> {
  AppServices get _s => widget.services;
  String get _lang => widget.lang;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _practise(List<SavedWord> words) async {
    final ids = {for (final w in words) ?w.sentenceId}.toList();
    final lines = _s.content.sentencesByIds(ids);
    if (lines.isEmpty) return;
    _s.logger.log('nav.screen', {'screen': 'reader', 'mode': 'my_words'});
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          services: _s,
          title: 'My words',
          sentences: lines,
          lang: _lang,
          mode: 'my_words',
          ordered: true,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _remove(SavedWord w) {
    _s.logger.log('word.remove', {'text': w.text, 'lang': w.lang});
    _s.sound(Sfx.tap);
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Removed ${w.text}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              _s.logger.log('word.save', {
                'text': w.text,
                'lang': w.lang,
                'reading': ?w.reading,
                'en': ?w.en,
                'sentence_id': ?w.sentenceId,
                'context': ?w.context,
                'context_en': ?w.contextEn,
              });
              if (mounted) setState(() {});
            },
          ),
        ),
      );
  }

  Future<void> _play(String text) async {
    final path = _s.content.audioPath(_lang, text);
    if (path != null) await _s.playAudio(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final words = _s.words.words(_lang);
    final q = _search.text.trim();
    final query = _lang == 'yue' ? _s.content.toTraditional(q) : q;
    final results = query.isEmpty
        ? const <DictEntry>[]
        : _s.content.lookup(query, _lang);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (_s.words.practice(_lang) case final practice
                when practice.isNotEmpty) ...[
              Card(
                key: const ValueKey('practice-card'),
                margin: EdgeInsets.zero,
                color: scheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${practice.length} ${practice.length == 1 ? 'word' : 'words'} to practise',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Added by themselves when you needed the reading or said them wrong.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final w in practice.take(12))
                            Chip(
                              label: Text(
                                w.text,
                                style: chineseStyle(_lang, fontSize: 16),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        key: const ValueKey('practise-flagged'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: () async {
                          _s.sound(Sfx.tap);
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PracticeWordsScreen(
                                services: _s,
                                words: practice.take(10).toList(),
                              ),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.record_voice_over_rounded),
                        label: const Text('Practise them'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text('My words', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Long-press any character while reading to look it up. '
              'Saved words are highlighted wherever they appear.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('word-search'),
              controller: _search,
              style: chineseStyle(_lang, fontSize: 16),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Look up a word (type or paste Chinese)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            for (final e in results.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.trad, style: chineseStyle(_lang, fontSize: 22)),
                subtitle: Text('${showReading(_lang, e.jyutping)}\n${e.en}'),
                isThreeLine: true,
              ),
            if (query.isNotEmpty && results.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No entry for $query.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            if (words.isNotEmpty)
              FilledButton.icon(
                key: const ValueKey('practise-words'),
                onPressed: () => _practise(words),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('Read their sentences again (${words.length})'),
              ),
            const SizedBox(height: 12),
            if (words.isEmpty)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.bookmarks_outlined,
                        size: 40,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No saved words yet',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'While reading, long-press a character, then tap the bookmark.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            for (final w in words)
              Card(
                key: ValueKey('my-word-${w.text}'),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.end,
                              spacing: 10,
                              children: [
                                InkWell(
                                  key: ValueKey('say-${w.text}'),
                                  onTap: () =>
                                      sayOrExplain(context, _s, w.text, _lang),
                                  child: Text(
                                    w.text,
                                    style: chineseStyle(_lang, fontSize: 26),
                                  ),
                                ),
                                if (w.reading != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      showReading(_lang, w.reading!),
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(color: scheme.primary),
                                    ),
                                  ),
                              ],
                            ),
                            if (w.en != null && w.en!.isNotEmpty)
                              Text(w.en!, style: theme.textTheme.bodyMedium),
                            if (w.context != null) ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () => _play(w.context!),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.volume_up_rounded,
                                      size: 16,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        w.context!,
                                        style: chineseStyle(
                                          _lang,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (w.contextEn != null)
                                Text(
                                  w.contextEn!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.bookmark_remove_outlined),
                        onPressed: () => _remove(w),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
