/// Long-press a character: the words around it, with readings and meanings, and a
/// bookmark to keep the word (with its sentence) in "My words".
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/reading_format.dart';
import '../platform/sfx.dart';
import 'ruby_text.dart';

/// Character offsets of each token in its sentence.
List<int> tokenOffsets(List<TokenRow> tokens) {
  final out = <int>[];
  var off = 0;
  for (final t in tokens) {
    out.add(off);
    off += t.surface.length;
  }
  return out;
}

/// Readings of the sentence's own tokens for a character range (context-correct for
/// polyphones), or null if any character has none.
String? rangeReading(List<TokenRow> tokens, int start, int end) {
  final offs = tokenOffsets(tokens);
  final parts = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final a = offs[i], b = a + tokens[i].surface.length;
    if (b <= start || a >= end) continue;
    final r = tokens[i].reading;
    if (tokens[i].kind != 'han') continue;
    if (r == null) return null;
    parts.add(r);
  }
  return parts.isEmpty ? null : parts.join(' ');
}

/// Puts the word around token [i] on the practice list ([reason]: 'read' when its
/// reading had to be revealed, 'say' when read-aloud heard it wrong).
void flagWord(AppServices s, SentenceRow sentence, int i, String reason) {
  final (a, b) = sentence.wordRange(i);
  final text = [for (var k = a; k < b; k++) sentence.tokens[k].surface].join();
  if (text.isEmpty || sentence.tokens[i].kind != 'han') return;
  final offs = tokenOffsets(sentence.tokens);
  final cs = offs[a];
  final ce = b < offs.length ? offs[b] : sentence.text.length;
  s.logger.log('word.flag', {
    'text': text,
    'lang': sentence.lang,
    'reason': reason,
    'reading': ?rangeReading(sentence.tokens, cs, ce),
    'sentence_id': sentence.id,
    'context': sentence.text,
    'context_en': sentence.en,
  });
}

const noVoiceMessage =
    'No Cantonese voice on this device. Install "Cantonese (Hong Kong)" '
    'under Settings > Text-to-speech (Speech services by Google).';

/// Says [word]; shows how to install a voice when none is available.
Future<void> sayOrExplain(
  BuildContext context,
  AppServices s,
  String word,
  String lang,
) async {
  if (!await s.sayWord(word, lang) && context.mounted && !s.voiceNoticeShown) {
    s.voiceNoticeShown = true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(noVoiceMessage),
        ),
      );
  }
}

String showReading(String lang, String reading) =>
    reading.split(' ').map((r) => displayReading(lang, r)).join(' ');

/// Opens the lookup for token [tokenIndex] of [sentence].
Future<void> showWordLookup(
  BuildContext context, {
  required AppServices services,
  required String lang,
  required SentenceRow sentence,
  required int tokenIndex,
}) {
  final offs = tokenOffsets(sentence.tokens);
  final pos = offs[tokenIndex];
  final found = services.content.wordsAt(sentence.text, pos, lang);
  // the word this sentence actually uses goes first (行 in 銀行 is hong4, not hang4)
  final (ws, we) = sentence.wordRange(tokenIndex);
  final cs = offs[ws];
  final ce = we < offs.length ? offs[we] : sentence.text.length;
  final ctx = found.indexWhere((f) => f.start == cs && f.end == ce);
  if (ctx > 0) found.insert(0, found.removeAt(ctx));
  services.logger.log('reader.lookup', {
    'char': sentence.tokens[tokenIndex].surface,
    'in_sentence': sentence.id,
    'words_found': found.length,
  });
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => WordLookupSheet(
      services: services,
      lang: lang,
      sentence: sentence,
      found: found,
      char: sentence.tokens[tokenIndex].surface,
    ),
  );
}

class WordLookupSheet extends StatefulWidget {
  const WordLookupSheet({
    super.key,
    required this.services,
    required this.lang,
    required this.sentence,
    required this.found,
    required this.char,
  });
  final AppServices services;
  final String lang;
  final SentenceRow sentence;
  final List<({int start, int end, List<DictEntry> entries})> found;
  final String char;

  @override
  State<WordLookupSheet> createState() => _WordLookupSheetState();
}

class _WordLookupSheetState extends State<WordLookupSheet> {
  AppServices get _s => widget.services;

  void _toggle(String word, String? reading, String en) {
    final saved = _s.words.contains(widget.lang, word);
    _s.sound(saved ? Sfx.tap : Sfx.save);
    if (saved) {
      _s.logger.log('word.remove', {'text': word, 'lang': widget.lang});
    } else {
      _s.logger.log('word.save', {
        'text': word,
        'lang': widget.lang,
        'reading': ?reading,
        'en': en,
        'sentence_id': widget.sentence.id,
        'context': widget.sentence.text,
        'context_en': widget.sentence.en,
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = widget.lang;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            if (widget.found.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No dictionary entry for ${widget.char}.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            for (final f in widget.found) ...[
              _WordCard(
                key: ValueKey(
                  'lookup-${widget.sentence.text.substring(f.start, f.end)}',
                ),
                lang: lang,
                word: widget.sentence.text.substring(f.start, f.end),
                reading:
                    rangeReading(widget.sentence.tokens, f.start, f.end) ??
                    f.entries.first.jyutping,
                entries: f.entries,
                saved: _s.words.contains(
                  lang,
                  widget.sentence.text.substring(f.start, f.end),
                ),
                onToggle: (word, reading, en) => _toggle(word, reading, en),
                onSpeak: (word) => sayOrExplain(context, _s, word, lang),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              'From: ${widget.sentence.en}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Meanings: CC-Canto and CC-CEDICT (CC BY-SA).',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({
    super.key,
    required this.lang,
    required this.word,
    required this.reading,
    required this.entries,
    required this.saved,
    required this.onToggle,
    required this.onSpeak,
  });
  final String lang;
  final String word;
  final String reading;
  final List<DictEntry> entries;
  final bool saved;
  final void Function(String word, String? reading, String en) onToggle;
  final void Function(String word) onSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final en = entries.map((e) => e.en).toSet().take(3).toList();
    return Card(
      margin: EdgeInsets.zero,
      color: saved ? scheme.tertiaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    key: ValueKey('say-$word'),
                    onTap: () => onSpeak(word),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(word, style: chineseStyle(lang, fontSize: 28)),
                        const SizedBox(width: 8),
                        Icon(Icons.volume_up_rounded, color: scheme.primary),
                      ],
                    ),
                  ),
                  if (reading.isNotEmpty)
                    Text(
                      showReading(lang, reading),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  const SizedBox(height: 4),
                  for (final m in en)
                    Text('• $m', style: theme.textTheme.bodyMedium),
                  if (entries.first.source == 'cccanto')
                    Text(
                      'Cantonese usage',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.tertiary,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('save-$word'),
              tooltip: saved ? 'Remove from My words' : 'Save to My words',
              icon: Icon(
                saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
              ),
              color: scheme.primary,
              onPressed: () => onToggle(
                word,
                reading.isEmpty ? null : reading,
                en.join('; '),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
