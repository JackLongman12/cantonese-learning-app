/// What the learner finds hard, from the event log: sounds they mix up when reading
/// aloud, characters they keep needing help with, and how the week went. Shown on
/// Today and turned into a "fix weak spots" step.
library;

import '../events/event.dart';
import 'item_state.dart';

const _initials = [
  'gw',
  'kw',
  'ng',
  'b',
  'p',
  'm',
  'f',
  'd',
  't',
  'n',
  'l',
  'g',
  'k',
  'h',
  'w',
  'z',
  'c',
  's',
  'j',
];

/// 'nei5' -> (initial: 'n', final: 'ei', tone: '5'); syllabic 'm4', 'ng5' have no final.
({String initial, String rhyme, String tone})? splitJyutping(String syllable) {
  final m = RegExp(r'^([a-z]+)([1-6])$').firstMatch(syllable);
  if (m == null) return null;
  final body = m.group(1)!;
  if (body == 'm' || body == 'ng') {
    return (initial: '', rhyme: body, tone: m.group(2)!);
  }
  final ini = _initials.firstWhere((i) => body.startsWith(i), orElse: () => '');
  return (initial: ini, rhyme: body.substring(ini.length), tone: m.group(2)!);
}

/// One kind of mix-up: "n → l" (start of the syllable), "eoi → ui" (ending), "tone 3 → 6".
class SoundMixup {
  SoundMixup(this.kind, this.expected, this.heard);
  final String kind; // start | ending | tone
  final String expected;
  final String heard;
  int count = 0;
  final examples = <String>{}; // 'nei5 → lei5'

  String get label =>
      kind == 'tone' ? 'tone $expected → $heard' : '$expected → $heard';
}

/// The learner's most frequent mix-ups in read-aloud attempts, most frequent first.
List<SoundMixup> weakSounds(Iterable<Event> events, {int top = 4}) {
  final byKey = <String, SoundMixup>{};
  void add(String kind, String e, String h, String example) {
    final key = '$kind:$e:$h';
    final m = byKey.putIfAbsent(
      key,
      () => SoundMixup(kind, e.isEmpty ? '∅' : e, h.isEmpty ? '∅' : h),
    );
    m.count++;
    if (m.examples.length < 3) m.examples.add(example);
  }

  for (final ev in events) {
    if (ev.type != 'speech.attempt') continue;
    for (final t in (ev.payload['per_token'] as List? ?? const [])) {
      if (t is! Map) continue;
      final v = t['v'];
      if (v != 'wrong' && v != 'tone') continue;
      final e = splitJyutping('${t['expected']}');
      final h = splitJyutping('${t['heard']}');
      if (e == null || h == null) continue;
      final ex = '${t['expected']} → ${t['heard']}';
      if (e.initial != h.initial) add('start', e.initial, h.initial, ex);
      if (e.rhyme != h.rhyme) add('ending', e.rhyme, h.rhyme, ex);
      if (e.tone != h.tone) add('tone', e.tone, h.tone, ex);
    }
  }
  final list = byKey.values.where((m) => m.count >= 2).toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return list.take(top).toList();
}

/// Characters with the most lapses (needed the reading again after learning it).
List<ItemState> weakCharacters(
  Iterable<ItemState> states,
  String lang, {
  int top = 8,
}) {
  final list =
      states
          .where((s) => s.itemId.startsWith('cr:$lang:') && s.lapses > 0)
          .toList()
        ..sort(
          (a, b) => b.lapses != a.lapses
              ? b.lapses.compareTo(a.lapses)
              : (a.stability ?? 0).compareTo(b.stability ?? 0),
        );
  return list.take(top).toList();
}

/// What the last seven days gave you: characters met for the first time and sentences
/// read. Deliberately no per-day record or streak: progress, not attendance.
({int newChars, int sentences}) weekProgress(
  Iterable<Event> events,
  DateTime nowUtc,
) {
  final since = nowUtc.subtract(const Duration(days: 7));
  final introduced = <String>{};
  var sentences = 0;
  for (final e in events) {
    if (e.tsUtc.isBefore(since)) continue;
    if (e.type == 'review.applied' && e.payload['signal'] == 'introduced') {
      if (e.payload['item_id'] case final String id) introduced.add(id);
    } else if (e.type == 'item.done' && e.payload['skipped'] != true) {
      sentences++;
    }
  }
  return (newChars: introduced.length, sentences: sentences);
}
