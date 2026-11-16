import 'package:duk/engine/practice_log.dart';
import 'package:duk/events/event.dart';
import 'package:flutter_test/flutter_test.dart';

var _n = 0;
Event ev(String type, Map<String, Object?> payload) => Event(
  id: 'e${_n++}',
  tsUtc: DateTime.utc(2026, 11, 17, 10),
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
  test('challenges, replies and frames replay from the log', () {
    final log = PracticeLog.replay([
      ev('challenge.done', {'id': 'ch-noice'}),
      ev('listen.answer', {'id': 'rep:a', 'correct': false}),
      ev('listen.answer', {'id': 'rep:b', 'correct': false}),
      ev('listen.answer', {'id': 'rep:b', 'correct': true}),
      ev('frame.say', {'id': 'frame:x', 'ok': false}),
      ev('frame.say', {'id': 'frame:y', 'ok': true}),
      ev('unknown.type', {'id': 'zzz'}),
    ]);
    expect(log.challengesDone, {'ch-noice'});
    expect(log.repliesMissed, {'rep:a'});
    expect(log.repliesHeard, {'rep:a', 'rep:b'});
    expect(log.framesSaid, {'frame:y'});
  });

  test('tone scores keep the last answers and order weakest first', () {
    final log = PracticeLog.replay([
      for (var i = 0; i < 12; i++)
        ev('tone.answer', {'set': 'tones-si', 'correct': i >= 2}),
      ev('tone.answer', {'set': 'tones-ma', 'correct': false}),
    ]);
    // the two early misses fell out of the window of ten
    expect(log.toneScore('tones-si'), 1.0);
    expect(log.toneScore('tones-ma'), 0.0);
    expect(log.toneScore('tones-ji'), isNull);
    expect(log.toneOrder(['tones-si', 'tones-ma', 'tones-ji']), [
      'tones-ji',
      'tones-ma',
      'tones-si',
    ]);
  });
}
