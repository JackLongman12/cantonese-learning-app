import 'package:duk/engine/word_book.dart';
import 'package:duk/events/event.dart';
import 'package:flutter_test/flutter_test.dart';

var _n = 0;
Event ev(String type, Map<String, Object?> payload, {int minute = 0}) => Event(
  id: 'e${_n++}',
  tsUtc: DateTime.utc(2026, 11, 15, 10, minute),
  tzOffsetMin: 480,
  monoMs: 0,
  deviceId: 'd',
  deviceKind: 'android',
  sessionId: 's',
  appVersion: 't',
  contentVersion: 'c',
  type: type,
  payload: payload,
);

void main() {
  test('save and remove replay from the log, newest first', () {
    final book = WordBook.replay([
      ev('word.save', {
        'text': '銀行',
        'lang': 'yue',
        'en': 'bank',
        'context': '行路去銀行',
      }, minute: 1),
      ev('word.save', {
        'text': '埋單',
        'lang': 'yue',
        'en': 'the bill',
      }, minute: 2),
      ev('word.remove', {'text': '埋單', 'lang': 'yue'}, minute: 4),
    ]);
    expect(book.words('yue').map((w) => w.text), ['銀行']);
    expect(book.words('yue').single.context, '行路去銀行');
    expect(book.contains('yue', '埋單'), isFalse);
  });

  test('the same event twice is applied once', () {
    final book = WordBook();
    final e = ev('word.save', {'text': '銀行', 'lang': 'yue'});
    book
      ..apply(e)
      ..apply(ev('word.remove', {'text': '銀行', 'lang': 'yue'}, minute: 1))
      ..apply(e);
    expect(book.words('yue'), isEmpty);
  });

  test('highlights take the longest saved word without overlaps', () {
    final book = WordBook.replay([
      ev('word.save', {'text': '銀', 'lang': 'yue'}),
      ev('word.save', {'text': '銀行', 'lang': 'yue'}),
      ev('word.save', {'text': '行路', 'lang': 'yue'}),
    ]);
    expect(book.highlights('yue', '行路去銀行'), [(0, 2), (3, 5)]);
  });

  test('struggled words go on the practice list until practised twice', () {
    final book = WordBook.replay([
      ev('word.flag', {'text': '銀行', 'lang': 'yue', 'reason': 'read'}, minute: 1),
      ev('word.flag', {'text': '銀行', 'lang': 'yue', 'reason': 'say'}, minute: 2),
      ev('word.flag', {'text': '巴士', 'lang': 'yue', 'reason': 'say'}, minute: 3),
      ev('word.practice', {'text': '巴士', 'lang': 'yue', 'ok': true}, minute: 4),
      ev('word.practice', {'text': '巴士', 'lang': 'yue', 'ok': false}, minute: 5),
      ev('word.practice', {'text': '銀行', 'lang': 'yue', 'ok': true}, minute: 6),
      ev('word.practice', {'text': '銀行', 'lang': 'yue', 'ok': true}, minute: 7),
    ]);
    // 銀行 cleared by two in a row; 巴士's streak was broken
    expect(book.practice('yue').map((w) => w.text), ['巴士']);
    expect(book.practice('yue').single.misses, 2);
    expect(book.needsPractice('yue', '銀行'), isFalse);
  });
}
