import 'package:duk/engine/path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final items = {
    'hard': {'a', 'x', 'y'},
    'easy': {'a', 'b', 'c'},
    'mid': {'a', 'b', 'z'},
  };
  final freq = {'a': 50, 'b': 30, 'c': 25, 'x': 1, 'y': 2, 'z': 3};

  test('topics with common characters come first', () {
    expect(orderTopics(items, freq), ['easy', 'mid', 'hard']);
  });

  test('up next is the first topic not mostly met', () {
    final path = orderTopics(items, freq);
    expect(upNext(path, items, (i) => {'a', 'b', 'c'}.contains(i)), 'mid');
    expect(upNext(path, items, (_) => true), isNull);
  });

  test('levels', () {
    expect(readingLevel(0), (level: 1, have: 0, need: 25));
    expect(readingLevel(30), (level: 2, have: 5, need: 50));
    expect(readingLevel(5000).level, 10);
    expect(readingLevel(5000).need, 0);
  });
}
