import 'package:duk/engine/pictures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pictures come from keywords in the meaning, specific first', () {
    expect(pictureForMeaning('An iced milk tea, please.'), '🧋');
    expect(pictureForMeaning('Which bus goes to the Border Gate?'), '🚌');
    expect(pictureForMeaning('I have a fever.'), '🤒');
    expect(pictureForMeaning('Is this minibus going to Mong Kok?'), '🚐');
    // whole words only: "cart" is not "car", "teacher" is not "tea"
    expect(pictureForMeaning('The teacher is here.'), isNull);
    expect(pictureForMeaning('Hmm.'), isNull);
  });
}
