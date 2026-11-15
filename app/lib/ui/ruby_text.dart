/// Chinese text with a reading above each character, at a per-character help level.
///
/// Readings are aligned by token index, never by string position. Punctuation is glued to
/// its neighbour so a line never starts with "，" or ends with "「".
library;

import 'package:material_ui/material_ui.dart';

import '../engine/reading_format.dart';
import '../engine/scaffold.dart';

enum SpeechMark { ok, tone, wrong, missed }

class RubyToken {
  const RubyToken({
    required this.surface,
    required this.kind,
    this.reading,
    this.level = ScaffoldLevel.full,
    this.revealed = false,
    this.flagged = false,
    this.mark,
    this.saved = false,
  });

  final String surface;

  /// han | latin | punct | space (as written by the pipeline)
  final String kind;
  final String? reading;
  final ScaffoldLevel level;

  /// The learner asked to see this reading during the current exposure.
  final bool revealed;

  /// The reading has not been confirmed by a human yet.
  final bool flagged;

  /// Read-aloud result for this character, shown as a coloured underline.
  final SpeechMark? mark;

  /// Part of a word in the learner's "My words": drawn on a soft highlight.
  final bool saved;

  bool get isHan => kind == 'han';
}

/// Text style for a language: the regional font and locale decide which glyph variant of a
/// shared code point is drawn (docs/DESIGN.md section 5, rule 2).
TextStyle chineseStyle(String lang, {required double fontSize, Color? color}) =>
    TextStyle(
      fontFamily: 'NotoSansHK',
      locale: const Locale('zh', 'HK'),
      fontSize: fontSize,
      height: 1.15,
      color: color,
    );

const _opening = '「『（《〈【“‘([';

class RubyText extends StatelessWidget {
  const RubyText({
    super.key,
    required this.tokens,
    required this.lang,
    this.fontSize = 34,
    this.onReveal,
    this.onLookup,
    this.onSpeak,
    this.wordOf,
  });

  final List<RubyToken> tokens;
  final String lang;
  final double fontSize;

  /// Called with the token index when the learner asks for a hidden reading.
  final void Function(int index)? onReveal;

  /// Long-press: look the word up (meaning, save to My words). Falls back to reveal.
  final void Function(int index)? onLookup;

  /// Tap: say the word this character belongs to. A hidden reading is revealed too
  /// (hearing it gives the reading away, so it counts like a reveal).
  final void Function(int index)? onSpeak;

  /// Word number per token (tokens of one word share it). When set, each word is
  /// underlined as one unit, like Duolingo, so 銀行 reads as one word, 帶 遮 as two.
  final List<int>? wordOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rubySize = fontSize * 0.36;

    Widget glyph(RubyToken t, int i) {
      final base = Text(
        t.surface,
        style: chineseStyle(lang, fontSize: fontSize),
      );
      final String ruby;
      Color rubyColor = scheme.onSurfaceVariant;
      if (!t.isHan || t.reading == null) {
        ruby = '';
      } else if (t.revealed) {
        ruby = displayReading(lang, t.reading!);
        rubyColor = scheme.error;
      } else {
        ruby = switch (t.level) {
          ScaffoldLevel.full => displayReading(lang, t.reading!),
          ScaffoldLevel.hint => displayToneHint(lang, t.reading!),
          ScaffoldLevel.tap || ScaffoldLevel.none => '',
        };
        if (t.flagged) rubyColor = scheme.tertiary;
      }
      final canTap =
          t.isHan &&
          t.reading != null &&
          !t.revealed &&
          (t.level == ScaffoldLevel.hint || t.level == ScaffoldLevel.tap);
      final canLongPress =
          t.isHan && (onLookup != null || (t.reading != null && !t.revealed));
      final column = Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.isHan ? fontSize * 0.07 : 0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: rubySize * 1.5,
              child: Text(
                ruby,
                key: ValueKey('ruby-$i'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  // Same family as the characters: it carries Latin glyphs too, so readings
                  // look identical on every platform.
                  fontFamily: 'NotoSansHK',
                  fontSize: rubySize,
                  color: rubyColor,
                  height: 1.2,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: t.mark == null ? 2 : 4,
                    color: switch (t.mark) {
                      SpeechMark.ok => const Color(0xFF2F6F62),
                      SpeechMark.tone => const Color(0xFFB8892B),
                      SpeechMark.wrong => scheme.error,
                      SpeechMark.missed => scheme.outline,
                      null =>
                        t.isHan && !t.revealed && t.level == ScaffoldLevel.tap
                            ? scheme.outlineVariant
                            : Colors.transparent,
                    },
                  ),
                ),
              ),
              child: t.saved
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: base,
                    )
                  : base,
            ),
          ],
        ),
      );
      final hidden =
          t.isHan &&
          t.reading != null &&
          !t.revealed &&
          t.level != ScaffoldLevel.full;
      if (!canLongPress ||
          (onReveal == null && onLookup == null && onSpeak == null)) {
        return column;
      }
      return Semantics(
        label: t.surface,
        hint: onSpeak != null
            ? 'Tap to hear it, long-press for the meaning'
            : canTap
            ? 'Tap to show the reading'
            : onLookup != null
            ? 'Long-press for the meaning'
            : 'Long-press to show the reading',
        child: GestureDetector(
          key: ValueKey('cell-$i'),
          behavior: HitTestBehavior.opaque,
          onTap: onSpeak != null && t.isHan
              ? () {
                  if (hidden) onReveal?.call(i);
                  onSpeak!(i);
                }
              : canTap && onReveal != null
              ? () => onReveal!(i)
              : null,
          onLongPress: onLookup != null || onReveal != null
              ? () => (onLookup ?? onReveal)!(i)
              : null,
          child: column,
        ),
      );
    }

    // Group tokens into words: [opening punct][word glyphs][closing punct].
    final groups = <_Group>[];
    var pendingOpen = <Widget>[];
    int? lastWord;
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.kind == 'space') {
        groups.add(_Group(space: fontSize * 0.3));
        lastWord = null;
        continue;
      }
      final g = glyph(t, i);
      if (t.kind == 'punct') {
        if (_opening.contains(t.surface)) {
          pendingOpen.add(g);
        } else if (groups.isNotEmpty && groups.last.space == null) {
          groups.last.trail.add(g);
        } else {
          groups.add(_Group()..trail.add(g));
        }
        lastWord = null;
        continue;
      }
      final w = wordOf != null && i < wordOf!.length ? wordOf![i] : null;
      final last = groups.isEmpty ? null : groups.last;
      if (w != null &&
          w == lastWord &&
          last != null &&
          last.trail.isEmpty &&
          pendingOpen.isEmpty) {
        last.word.add(g);
      } else {
        groups.add(
          _Group(underline: wordOf != null && t.isHan)
            ..lead.addAll(pendingOpen)
            ..word.add(g),
        );
        pendingOpen = [];
      }
      lastWord = w;
    }
    if (pendingOpen.isNotEmpty) groups.add(_Group()..lead.addAll(pendingOpen));

    final line = scheme.outlineVariant;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      runSpacing: fontSize * 0.25,
      children: [
        for (final g in groups)
          if (g.space != null)
            SizedBox(width: g.space)
          else
            _Cell([
              ...g.lead,
              if (g.word.isNotEmpty)
                g.underline
                    ? Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: fontSize * 0.05,
                        ),
                        padding: const EdgeInsets.only(bottom: 3),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: line, width: 2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: g.word,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: g.word,
                      ),
              ...g.trail,
            ]),
      ],
    );
  }
}

class _Group {
  _Group({this.space, this.underline = false});
  final double? space;
  final bool underline;
  final lead = <Widget>[];
  final word = <Widget>[];
  final trail = <Widget>[];
}

/// A character with the punctuation glued to it; wraps as one unit.
class _Cell extends StatelessWidget {
  const _Cell(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: children,
  );
}
