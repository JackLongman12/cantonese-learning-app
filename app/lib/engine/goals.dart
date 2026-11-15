/// Learning goals: what the learner wants to be able to do in Macau and Hong Kong.
/// A goal moves its topics to the front of the path (in their usual easy-first order)
/// and points Today's "Learn" and "Speak" at them. Nothing is locked: other topics stay
/// open and follow after. The goal can be changed any time (Today or Settings).
library;

class Goal {
  const Goal(this.id, this.title, this.detail, this.topics);
  final String id;
  final String title;
  final String detail;

  /// Topic ids containing any of these go first.
  final List<String> topics;
}

const goals = [
  Goal(
    'around',
    'Get around',
    'Buses, taxis, the MTR, directions, signs, sightseeing',
    ['getting-around', 'signs', 'tourism'],
  ),
  Goal('food', 'Eat out and shop', 'Ordering, menus, paying, markets, prices', [
    'food',
    'shopping',
    'numbers',
  ]),
  Goal('daily', 'Daily life', 'Home, health, weather, paperwork, your phone', [
    'daily',
    'home',
    'health',
    'weather',
    'gov',
    'messaging',
  ]),
  Goal('work', 'Work', 'Colleagues, messages, offices and forms', [
    'work',
    'messaging',
    'gov',
    'numbers',
  ]),
  Goal('social', 'Make friends', 'Chatting, slang, messages, stories', [
    'chat',
    'messaging',
    'swearing',
  ]),
  Goal(
    'all',
    'A bit of everything',
    'The usual path, easiest topics first',
    [],
  ),
];

Goal goalById(String? id) =>
    goals.firstWhere((g) => g.id == id, orElse: () => goals.last);

/// [path] (easiest first) with the goal's topics moved to the front, keeping order.
List<String> orderForGoal(List<String> path, Goal goal) {
  bool fits(String id) => goal.topics.any(id.contains);
  return [
    for (final id in path)
      if (fits(id)) id,
    for (final id in path)
      if (!fits(id)) id,
  ];
}

/// Whether a topic belongs to the goal (for "Learn" and "Speak" on Today).
bool inGoal(String topicId, Goal goal) =>
    goal.topics.isEmpty || goal.topics.any(topicId.contains);
