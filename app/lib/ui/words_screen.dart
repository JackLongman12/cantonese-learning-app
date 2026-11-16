/// "Train": the practice page. Speak, practice your words (read again in the sentence
/// they came from), read your own text, the reading skills, and every word you saved.
/// Everything is a tile, so one thing is easy to spot.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import 'finish.dart' show pushOnce;
import '../engine/word_book.dart';
import '../platform/sfx.dart';
import 'paste_reader_screen.dart';
import 'practice_words_screen.dart';
import 'ruby_text.dart';
import 'tiles.dart';
import 'word_sheet.dart';

class WordsScreen extends StatefulWidget {
  const WordsScreen({
    super.key,
    required this.services,
    required this.lang,
    this.onSpeak,
    this.skills = const [],
  });
  final AppServices services;
  final String lang;

  /// Opens the speaking drill.
  final VoidCallback? onSpeak;

  /// Reading-skill tiles (built by the home screen).
  final List<Widget> skills;

  @override
  State<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen> {
  AppServices get _s => widget.services;
  String get _lang => widget.lang;

  /// Flagged words first, then saved ones not already flagged, as practice items.
  List<PracticeWord> _practiceList(List<SavedWord> saved) {
    final flagged = _s.words.practice(_lang);
    final have = {for (final w in flagged) w.text};
    return [
      ...flagged,
      for (final w in saved)
        if (!have.contains(w.text))
          PracticeWord(
            text: w.text,
            lang: w.lang,
            flaggedAt: w.savedAt,
            reading: w.reading,
            sentenceId: w.sentenceId,
            context: w.context,
            contextEn: w.contextEn,
          ),
    ];
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
    await _s.saySentence(text);
  }

  Future<void> _push(Widget screen) async {
    _s.sound(Sfx.tap);
    await pushOnce(context, MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final words = _s.words.words(_lang);
    final practice = _practiceList(words);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            TileGrid(
              children: [
                if (widget.onSpeak != null)
                  AppTile(
                    key: const ValueKey('practice-speak'),
                    icon: Icons.record_voice_over_rounded,
                    title: 'Speak',
                    subtitle: '10 lines, tap the mic',
                    highlight: true,
                    onTap: widget.onSpeak!,
                  ),
                if (practice.isNotEmpty)
                  AppTile(
                    key: const ValueKey('practice-flagged'),
                    icon: Icons.bookmark_added_rounded,
                    title: 'My words',
                    subtitle: 'Read them in their sentence',
                    badge: '${practice.length}',
                    onTap: () => _push(
                      PracticeWordsScreen(
                        services: _s,
                        words: practice.take(10).toList(),
                      ),
                    ),
                  ),
                AppTile(
                  key: const ValueKey('open-free-reader'),
                  icon: Icons.chrome_reader_mode_rounded,
                  title: 'Your own text',
                  subtitle: 'Paste a message, menu or sign',
                  onTap: () =>
                      _push(PasteReaderScreen(services: _s, lang: _lang)),
                ),
              ],
            ),
            if (widget.skills.isNotEmpty) ...[
              heading('Reading skills'),
              TileGrid(children: widget.skills),
            ],
            heading('Saved words'),
            if (words.isEmpty)
              Text(
                'While reading, tap a word, then tap the bookmark.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              TileGrid(
                children: [
                  for (final w in words)
                    _WordTile(
                      key: ValueKey('my-word-${w.text}'),
                      word: w,
                      lang: _lang,
                      onTap: () => sayOrExplain(context, _s, w.text, _lang),
                      onContext: w.context == null
                          ? null
                          : () => _play(w.context!),
                      onRemove: () => _remove(w),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// One saved word: the word, its reading and meaning. Tap to hear or look it up.
class _WordTile extends StatelessWidget {
  const _WordTile({
    super.key,
    required this.word,
    required this.lang,
    required this.onTap,
    required this.onRemove,
    this.onContext,
  });
  final SavedWord word;
  final String lang;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('say-${word.text}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 0, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      word.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: chineseStyle(lang, fontSize: 26),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.bookmark_remove_outlined, size: 20),
                    onPressed: onRemove,
                  ),
                ],
              ),
              if (word.reading != null)
                Text(
                  showReading(lang, word.reading!),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              if (word.en != null && word.en!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    word.en!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (onContext != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onContext,
                  icon: const Icon(Icons.volume_up_rounded, size: 16),
                  label: const Text('Its sentence'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
