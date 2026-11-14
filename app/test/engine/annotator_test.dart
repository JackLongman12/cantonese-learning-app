import 'dart:io';

import 'package:duk/data/content_db.dart';
import 'package:duk/engine/annotator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = Annotator(
    chars: {
      '我': const LexChar('ngo5', 1),
      '去': const LexChar('heoi3', 2),
      '銀': const LexChar('ngan4', 1),
      '行': const LexChar('hang4', 9),
      '路': const LexChar('lou6', 3),
    },
    words: {'銀行': 'ngan4 hong4', '行路': 'haang4 lou6'},
  );

  test('words beat character defaults, longest first', () {
    final t = a.annotate('我去銀行，行路去。');
    expect(t.map((x) => x.reading).toList(), [
      'ngo5',
      'heoi3',
      'ngan4',
      'hong4',
      null,
      'haang4',
      'lou6',
      'heoi3',
      null, //
    ]);
    expect(t[2].uncertain, isFalse); // settled by a word
    expect(t[1].uncertain, isTrue); // 去 has two readings, no word around it
    expect(t[0].itemId('yue'), 'cr:yue:我:ngo5');
  });

  test(
    'tokens rebuild the text, including Latin, numbers and astral characters',
    () {
      const text = 'MOP 25.5蚊，好平！𠮶個';
      final t = a.annotate(text);
      expect(t.map((x) => x.surface).join(), text);
      expect(t.firstWhere((x) => x.surface == '25.5').kind, 'latin');
      expect(t.firstWhere((x) => x.surface == '𠮶').kind, 'han');
      expect(t.firstWhere((x) => x.surface == '𠮶').reading, isNull);
    },
  );

  final dbPath = 'assets/content/content.db';
  test('shipped lexicon agrees with the pipeline on reviewed content', () {
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final yue = db.annotator('yue');
    // context readings the pipeline settled; the device must reproduce them
    String r(String s) =>
        yue.annotate(s).map((x) => x.reading ?? '·').join(' ');
    expect(r('我去銀行'), 'ngo5 heoi3 ngan4 hong4');
    expect(r('唔該，埋單。'), 'm4 goi1 · maai4 daan1 ·');
    expect(r('呢個幾多錢呀？'), 'ni1 go3 gei2 do1 cin2 aa3 ·');
    final cmn = db.annotator('cmn');
    expect(cmn.annotate('银行').map((x) => x.reading).join(' '), 'yin2 hang2');
    expect(cmn.annotate('音乐').map((x) => x.reading).join(' '), 'yin1 yue4');

    // every sentence: device readings match pipeline readings for most characters
    var same = 0, total = 0;
    for (final sc in db.scenarios('yue')) {
      for (final s in db.sentences(sc.id, 'yue')) {
        final mine = yue.annotate(s.text);
        for (var i = 0; i < s.tokens.length; i++) {
          if (s.tokens[i].kind != 'han') continue;
          total++;
          if (mine[i].reading == s.tokens[i].reading) same++;
        }
      }
    }
    expect(same / total, greaterThan(0.97), reason: '$same of $total');
  }, skip: File(dbPath).existsSync() ? false : 'run the pipeline first');
}
