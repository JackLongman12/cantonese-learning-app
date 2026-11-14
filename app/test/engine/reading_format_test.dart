import 'package:duk/engine/reading_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('numbered pinyin becomes tone-marked pinyin', () {
    const cases = {
      'qing3': 'qǐng',
      'wen4': 'wèn',
      'guan1': 'guān',
      'zha2': 'zhá',
      'jiao1': 'jiāo', // a takes the mark
      'xie4': 'xiè', // e takes the mark
      'gou3': 'gǒu', // ou -> o
      'liu2': 'liú', // otherwise the last vowel
      'gui4': 'guì',
      'duo1': 'duō',
      'lv4': 'lǜ', // v is ü
      'nü3': 'nǚ',
      'lüe4': 'lüè',
      'de5': 'de', // neutral tone: no mark
      'er2': 'ér',
      'ng2': 'ng', // no vowel to mark
    };
    cases.forEach((numbered, marked) {
      expect(pinyinWithToneMarks(numbered), marked, reason: numbered);
    });
    expect(pinyinWithToneMarks('MOP'), 'MOP');
  });

  test('Cantonese stays Jyutping, Mandarin shows Pinyin', () {
    expect(displayReading('yue', 'hong4'), 'hong4');
    expect(displayReading('cmn', 'hang2'), 'háng');
  });

  test('tone hints', () {
    expect(displayToneHint('yue', 'hong4'), '4');
    expect(displayToneHint('yue', 'sik6'), '6');
    expect(displayToneHint('cmn', 'hang2'), 'ˊ');
    expect(displayToneHint('cmn', 'de5'), '·');
    expect(displayToneHint('yue', 'MOP'), '');
  });
}
