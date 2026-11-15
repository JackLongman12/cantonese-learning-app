/// "Read anything": paste or share real text (a menu, a sign, a chat) and get
/// readings over only the characters this learner doesn't know yet.
library;

import 'voice_picker.dart';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../engine/annotator.dart';
import '../engine/scaffold.dart';
import 'critters.dart';
import 'ruby_text.dart';
import 'word_sheet.dart';

class PasteReaderScreen extends StatefulWidget {
  const PasteReaderScreen({
    super.key,
    required this.services,
    required this.lang,
    this.initialText,
    this.source = 'paste',
  });

  final AppServices services;
  final String lang;

  /// Text to read straight away (shared from another app, or the clipboard).
  final String? initialText;
  final String source;

  @override
  State<PasteReaderScreen> createState() => _PasteReaderScreenState();
}

class _PasteReaderScreenState extends State<PasteReaderScreen> {
  final _input = TextEditingController();
  List<AnnotatedToken> _tokens = const [];
  Map<String, ScaffoldLevel> _levels = const {};
  final Set<int> _revealed = {};
  bool _editing = true;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    final text = widget.initialText?.trim() ?? '';
    if (text.isNotEmpty) {
      _input.text = text;
      _read(text, source: widget.source, initial: true);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _read(String text, {required String source, bool initial = false}) {
    final tokens = _s.content.annotator(widget.lang).annotate(text);
    final now = _s.logger.now();
    final levels = <String, ScaffoldLevel>{};
    for (final t in tokens) {
      final id = t.itemId(widget.lang);
      if (id != null) {
        levels[id] = _s.scaffold.levelFor(
          _s.learner.stateOf(id),
          _s.memory,
          now,
        );
      }
    }
    final han = tokens.where((t) => t.kind == 'han').length;
    final unknown = tokens.where((t) {
      final id = t.itemId(widget.lang);
      return t.kind == 'han' &&
          (id == null || levels[id] == ScaffoldLevel.full);
    }).length;
    // Never log the text itself: lengths and ratios only (EVENTS_SCHEMA rule 6).
    _s.logger.log('reader.open', {
      'source': source,
      'lang': widget.lang,
      'chars': han,
      'unknown_ratio': han == 0 ? 0 : unknown / han,
    });
    void apply() {
      _tokens = tokens;
      _levels = levels;
      _revealed.clear();
      _editing = false;
    }

    initial ? apply() : setState(apply);
  }

  void _reveal(int i) {
    final t = _tokens[i];
    final id = t.itemId(widget.lang);
    if (id == null || _revealed.contains(i)) return;
    HapticFeedback.selectionClick();
    _s.logger.log('reader.lookup', {
      'item_id': id,
      'level': _levels[id]?.name,
      'uncertain': t.uncertain,
    });
    // Forgetting a character the learner had been studying is a lapse, as in the reader.
    final st = _s.learner.stateOf(id);
    if (!st.isNew) {
      _s.logger.log('review.applied', {
        'item_id': id,
        'grade': 'again',
        'signal': 'reveal',
        'source': 'free_reader',
      });
    }
    setState(() => _revealed.add(i));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _toast('The clipboard has no text.');
      return;
    }
    _input.text = text;
    _read(text, source: 'paste');
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Read anything'),
        actions: [
          VoiceButton(_s),
          if (!_editing)
            IconButton(
              tooltip: 'Edit text',
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _editing ? _editor(context) : _reader(context),
          ),
        ),
      ),
    );
  }

  Widget _editor(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Chick(mood: ChickMood.innocent, size: 72),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Paste anything you want to read: a menu, a sign, a form, a message. '
                'On Android you can also Share text to DuckLearn from any app. '
                'Readings appear only over characters you don\'t know yet.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('paste-input'),
          controller: _input,
          minLines: 5,
          maxLines: 12,
          style: chineseStyle(widget.lang, fontSize: 20),
          decoration: const InputDecoration(
            hintText: '貼上中文…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('read-text'),
              onPressed: () {
                final text = _input.text.trim();
                if (text.isNotEmpty) _read(text, source: 'typed');
              },
              icon: const Icon(Icons.menu_book_rounded),
              label: const Text('Read'),
            ),
            OutlinedButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Paste'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _reader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final han = [
      for (final t in _tokens)
        if (t.kind == 'han') t,
    ];
    final readable = han.where((t) {
      final id = t.itemId(widget.lang);
      final l = id == null ? null : _levels[id];
      return l == ScaffoldLevel.none || l == ScaffoldLevel.tap;
    }).length;
    final uncertain = han.where((t) => t.uncertain).length;
    // split into lines so paragraphs keep their shape
    final lines = <List<int>>[[]];
    for (var i = 0; i < _tokens.length; i++) {
      if (_tokens[i].surface == '\n') {
        lines.add([]);
      } else {
        lines.last.add(i);
      }
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Text(
                  han.isEmpty
                      ? '–'
                      : '${(100 * readable / han.length).round()}%',
                  key: const ValueKey('coverage'),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'of these ${han.length} characters you already read without help. '
                    'Tap any you can\'t read.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  if (line.isEmpty)
                    const SizedBox(height: 12)
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RubyText(
                        lang: widget.lang,
                        fontSize: 28,
                        onReveal: (k) => _reveal(line[k]),
                        onSpeak: (k) {
                          final text = line
                              .map((i) => _tokens[i].surface)
                              .join();
                          var pos = 0;
                          for (var j = 0; j < k; j++) {
                            pos += _tokens[line[j]].surface.length;
                          }
                          final found = _s.content.wordsAt(
                            text,
                            pos,
                            widget.lang,
                          );
                          final word = found.isEmpty
                              ? _tokens[line[k]].surface
                              : text.substring(
                                  found.first.start,
                                  found.first.end,
                                );
                          sayOrExplain(context, _s, word, widget.lang);
                        },
                        tokens: [
                          for (final i in line)
                            RubyToken(
                              surface: _tokens[i].surface,
                              kind: _tokens[i].kind,
                              reading: _tokens[i].reading,
                              level:
                                  _levels[_tokens[i].itemId(widget.lang)] ??
                                  ScaffoldLevel.full,
                              revealed: _revealed.contains(i),
                              flagged: _tokens[i].uncertain,
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        if (uncertain > 0) ...[
          const SizedBox(height: 10),
          Text(
            'Readings in gold are a best guess: those characters have more than one '
            'reading and the dictionary could not tell which one from context.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
