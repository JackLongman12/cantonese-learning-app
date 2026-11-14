/// What the learner knows. State is a pure function of the event log:
/// `LearnerModel.replay(events)` always reproduces it (docs/DESIGN.md section 4.2).
library;

import '../events/event.dart';
import 'item_state.dart';
import 'memory.dart';

class LearnerModel {
  LearnerModel(this.memory);

  final Memory memory;
  final Map<String, ItemState> _states = {};
  final Set<String> _seenEvents = {};
  DateTime? _latest;

  /// True once an event older than one already applied has arrived (typically merged in
  /// from another device). Memory updates depend on order, so the state must then be
  /// rebuilt with [replay] before it is trusted again.
  bool get needsReplay => _needsReplay;
  bool _needsReplay = false;

  ItemState stateOf(String itemId) =>
      _states[itemId] ?? ItemState(itemId: itemId);

  Iterable<ItemState> get known => _states.values;

  /// Applies one event. Safe to call twice with the same event (sync can deliver
  /// duplicates) and with event types this version does not know.
  void apply(Event e) {
    if (!_seenEvents.add(e.id)) return;
    if (e.type != 'review.applied') return;
    final latest = _latest;
    if (latest != null && e.tsUtc.isBefore(latest)) _needsReplay = true;
    if (latest == null || e.tsUtc.isAfter(latest)) _latest = e.tsUtc;
    final itemId = e.payload['item_id'];
    final grade = e.payload['grade'];
    if (itemId is! String || grade is! String) return;
    final Grade g;
    try {
      g = Grade.parse(grade);
    } on StateError {
      return;
    }
    _states[itemId] = memory.review(stateOf(itemId), g, e.tsUtc);
  }

  /// Rebuilds state from scratch. Events may arrive unordered and duplicated (several
  /// devices, several files); they are applied in (time, id) order exactly once.
  static LearnerModel replay(Iterable<Event> events, Memory memory) {
    final sorted = events.toList()
      ..sort((a, b) {
        final c = a.tsUtc.compareTo(b.tsUtc);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final model = LearnerModel(memory);
    sorted.forEach(model.apply);
    return model;
  }

  Map<String, ItemState> snapshot() => Map.unmodifiable(_states);
}
