import 'package:duk/engine/reading_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readings are shown as Jyutping', () {
    expect(displayReading('yue', 'hong4'), 'hong4');
  });

  test('tone hints', () {
    expect(displayToneHint('yue', 'hong4'), '4');
    expect(displayToneHint('yue', 'sik6'), '6');
    expect(displayToneHint('yue', 'MOP'), '');
  });
}
