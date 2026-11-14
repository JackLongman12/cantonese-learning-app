/// Adds readings to any text on the device (pasted, photographed), using the compact
/// lexicon the pipeline ships in content.db: per-character defaults plus the words whose
/// reading differs from them. Mirrors pipeline/duk/annotate.py tokenisation.
library;

class LexChar {
  const LexChar(this.reading, this.readings);
  final String reading;

  /// How many readings the character has; >1 means context could change it.
  final int readings;
}

class AnnotatedToken {
  const AnnotatedToken(
    this.surface,
    this.kind, {
    this.reading,
    this.uncertain = false,
  });

  final String surface;

  /// han | latin | punct | space
  final String kind;
  final String? reading;

  /// The character has several readings and no dictionary word settled which one.
  final bool uncertain;

  String? itemId(String lang) =>
      kind == 'han' && reading != null ? 'cr:$lang:$surface:$reading' : null;
}

bool isHan(int cp) =>
    (cp >= 0x4E00 && cp <= 0x9FFF) ||
    (cp >= 0x3400 && cp <= 0x4DBF) ||
    (cp >= 0xF900 && cp <= 0xFAFF) ||
    (cp >= 0x20000 && cp <= 0x323AF) ||
    cp == 0x3007;

bool _isAsciiAlnum(int cp) =>
    (cp >= 0x30 && cp <= 0x39) ||
    (cp >= 0x41 && cp <= 0x5A) ||
    (cp >= 0x61 && cp <= 0x7A);

bool _isDigit(int cp) => cp >= 0x30 && cp <= 0x39;

bool _isSpace(int cp) =>
    cp == 0x20 || cp == 0x09 || cp == 0x0A || cp == 0x0D || cp == 0x3000;

/// Splits text into tokens: one per Han character, one per ASCII alphanumeric run
/// (with decimal points inside numbers), one per other character.
List<AnnotatedToken> tokenize(String text) {
  final cps = text.runes.toList();
  final out = <AnnotatedToken>[];
  var i = 0;
  while (i < cps.length) {
    final cp = cps[i];
    if (isHan(cp)) {
      out.add(AnnotatedToken(String.fromCharCode(cp), 'han'));
      i++;
    } else if (_isAsciiAlnum(cp)) {
      var j = i + 1;
      while (j < cps.length &&
          (_isAsciiAlnum(cps[j]) ||
              ((cps[j] == 0x2E || cps[j] == 0x2C) &&
                  j + 1 < cps.length &&
                  _isDigit(cps[j + 1]) &&
                  _isDigit(cps[j - 1])))) {
        j++;
      }
      out.add(AnnotatedToken(String.fromCharCodes(cps.sublist(i, j)), 'latin'));
      i = j;
    } else {
      out.add(
        AnnotatedToken(
          String.fromCharCode(cp),
          _isSpace(cp) ? 'space' : 'punct',
        ),
      );
      i++;
    }
  }
  return out;
}

class Annotator {
  Annotator({required this.chars, required this.words, this.maxWord = 6});

  final Map<String, LexChar> chars;

  /// word -> space-separated readings, one per character
  final Map<String, String> words;
  final int maxWord;

  List<AnnotatedToken> annotate(String text) {
    final tokens = tokenize(text);
    final out = <AnnotatedToken>[];
    var i = 0;
    while (i < tokens.length) {
      final t = tokens[i];
      if (t.kind != 'han') {
        out.add(t);
        i++;
        continue;
      }
      // longest dictionary word starting here, over consecutive Han tokens
      var matched = 0;
      List<String>? readings;
      for (var len = maxWord; len >= 2; len--) {
        if (i + len > tokens.length) continue;
        final span = tokens.sublist(i, i + len);
        if (span.any((x) => x.kind != 'han')) continue;
        final w = words[span.map((x) => x.surface).join()];
        if (w != null) {
          matched = len;
          readings = w.split(' ');
          break;
        }
      }
      if (matched > 0) {
        for (var k = 0; k < matched; k++) {
          out.add(
            AnnotatedToken(tokens[i + k].surface, 'han', reading: readings![k]),
          );
        }
        i += matched;
      } else {
        final c = chars[t.surface];
        out.add(
          AnnotatedToken(
            t.surface,
            'han',
            reading: c?.reading,
            uncertain: c == null || c.readings > 1,
          ),
        );
        i++;
      }
    }
    return out;
  }
}
