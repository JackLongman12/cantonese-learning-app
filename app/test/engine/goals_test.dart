import 'package:duk/engine/goals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const path = [
    'scn-mo-getting-around',
    'scn-mo-messaging',
    'scn-mo-numbers',
    'scn-cantonese-food',
    'scn-mo-food-and-money',
    'scn-hk-getting-around',
  ];

  test('the goal\'s topics go first, the rest keep their order', () {
    expect(orderForGoal(path, goalById('food')), [
      'scn-mo-numbers',
      'scn-cantonese-food',
      'scn-mo-food-and-money',
      'scn-mo-getting-around',
      'scn-mo-messaging',
      'scn-hk-getting-around',
    ]);
    expect(orderForGoal(path, goalById('all')), path);
  });

  test('unknown or missing goal means a bit of everything', () {
    expect(goalById(null).id, 'all');
    expect(inGoal('scn-mo-work', goalById('all')), isTrue);
    expect(inGoal('scn-mo-work', goalById('food')), isFalse);
  });
}
