/// How a stored reading is shown to the learner.
///
/// Readings are stored in one plain form per language (Jyutping `hong4`, numbered Pinyin
/// `qing3`) so item ids stay stable. Cantonese is displayed as Jyutping; Mandarin is
/// displayed as standard Hanyu Pinyin with tone marks (`qǐng`).
library;

const _marks = {
  'a': 'āáǎà',
  'e': 'ēéěè',
  'i': 'īíǐì',
  'o': 'ōóǒò',
  'u': 'ūúǔù',
  'ü': 'ǖǘǚǜ',
};

/// `qing3` -> `qǐng`, `lv4` -> `lǜ`, `de5` -> `de`. Anything unexpected is returned as is.
String pinyinWithToneMarks(String numbered) {
  final m = RegExp(r'^([a-zü]+)([1-5])$').firstMatch(numbered.toLowerCase());
  if (m == null) return numbered;
  final syllable = m.group(1)!.replaceAll('v', 'ü');
  final tone = int.parse(m.group(2)!);
  if (tone == 5) return syllable;

  // Standard placement: a or e takes the mark; in "ou" the o does; otherwise the last vowel.
  int index;
  if (syllable.contains('a')) {
    index = syllable.indexOf('a');
  } else if (syllable.contains('e')) {
    index = syllable.indexOf('e');
  } else if (syllable.contains('ou')) {
    index = syllable.indexOf('o');
  } else {
    index = syllable.lastIndexOf(RegExp('[iouü]'));
  }
  if (index < 0) return syllable; // syllabic consonant such as "ng" or "m"
  final marked = _marks[syllable[index]]![tone - 1];
  return syllable.replaceRange(index, index + 1, marked);
}

/// Full reading as shown above a character.
String displayReading(String lang, String reading) =>
    lang == 'cmn' ? pinyinWithToneMarks(reading) : reading;

/// Tone-only hint: the tone number for Jyutping, the tone mark shape for Pinyin.
String displayToneHint(String lang, String reading) {
  final m = RegExp(r'[1-6]$').firstMatch(reading);
  if (m == null) return '';
  final tone = m.group(0)!;
  if (lang != 'cmn') return tone;
  return const {'1': 'ˉ', '2': 'ˊ', '3': 'ˇ', '4': 'ˋ', '5': '·'}[tone] ?? '';
}
