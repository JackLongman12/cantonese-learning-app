import 'package:duk/engine/pronunciation.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> v(AttemptScore s) => [for (final c in s.chars) c.verdict.name];

void main() {
  test('all correct', () {
    final s = scoreAttempt(
      ['ngo5', 'soeng2', 'maai5', 'syu1'],
      ['ngo5', 'soeng2', 'maai5', 'syu1'],
    );
    expect(v(s), ['ok', 'ok', 'ok', 'ok']);
    expect(s.ratio, 1);
  });

  test('a wrong tone is reported as a tone error with what was heard', () {
    // 買 maai5 (buy) read as 賣 maai6 (sell)
    final s = scoreAttempt(
      ['ngo5', 'soeng2', 'maai5', 'syu1'],
      ['ngo5', 'soeng2', 'maai6', 'syu1'],
    );
    expect(v(s), ['ok', 'ok', 'tone', 'ok']);
    expect(s.chars[2].heard, 'maai6');
  });

  test(
    'a different syllable is wrong; dropped and extra syllables keep alignment',
    () {
      final s = scoreAttempt(
        ['m4', 'goi1', 'maai4', 'daan1'],
        [
          'm4',
          'goi1',
          'aa3',
          'maai4',
          'bei2',
        ], // extra particle, last syllable wrong
      );
      expect(v(s), ['ok', 'ok', 'ok', 'wrong']);
      final dropped = scoreAttempt(
        ['heoi3', 'gwaan1', 'zaap6'],
        ['heoi3', 'zaap6'],
      );
      expect(v(dropped), ['ok', 'missed', 'ok']);
    },
  );

  test('lazy sounds are accepted (n/l, dropped ng-, gw/g before o)', () {
    final s = scoreAttempt(['nei5', 'ngo5', 'gwok3'], ['lei5', 'o5', 'gok3']);
    expect(v(s), ['ok', 'ok', 'ok']);
  });

  test('nothing heard', () {
    expect(v(scoreAttempt(['ngo5', 'hai6'], [])), ['missed', 'missed']);
  });
}
