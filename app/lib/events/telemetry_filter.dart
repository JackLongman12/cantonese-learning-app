/// Which events leave the device, and in what form, when the learner agreed to share
/// anonymous usage data (docs/TELEMETRY.md). Pure Dart so it is unit-tested.
///
/// Rules:
/// - Only the event types in [sharedTypes]. Everything else stays on the device.
/// - Never anything the learner typed, pasted or said: payload keys in [_dropKeys] are
///   removed (words saved from pasted text, the words a recogniser heard).
/// - The device id is replaced with the install's telemetry id (random, separate from
///   the device id, reset by turning sharing off and on).
library;

import 'event.dart';

const sharedTypes = {
  'app.open',
  'session.start',
  'session.end',
  'session.more',
  'item.shown',
  'item.check',
  'item.reveal',
  'item.audio',
  'item.done',
  'review.applied',
  'speech.attempt',
  'conv.choice',
  'nav.screen',
  'plan.step',
  'settings.change',
  'reader.open',
  'reader.lookup',
  'word.save',
  'word.remove',
  'word.flag',
  'word.practice',
  'experiment.assigned',
  'onboarding.done',
  'app.crash',
};

/// Free text that could be the learner's own (pasted, typed or spoken).
const _dropKeys = {'text', 'en', 'reading', 'per_token', 'heard', 'said', 'query'};

/// The event as it is uploaded, or null when it is not shared.
Map<String, Object?>? shareable(Event e, String telemetryId) {
  if (!sharedTypes.contains(e.type)) return null;
  final payload = <String, Object?>{
    for (final kv in e.payload.entries)
      if (!_dropKeys.contains(kv.key)) kv.key: kv.value,
  };
  // a character looked up in pasted text is the learner's text; in a lesson it is ours
  if (e.type == 'reader.lookup' && payload['in_sentence'] == null) {
    payload.remove('item_id');
    payload.remove('char');
  }
  return {
    'id': e.id,
    'ts_utc': e.tsUtc.toUtc().toIso8601String(),
    'tz_offset_min': e.tzOffsetMin,
    'install_id': telemetryId,
    'device_kind': e.deviceKind,
    'session_id': e.sessionId,
    'app_version': e.appVersion,
    'content_version': e.contentVersion,
    'type': e.type,
    'payload': payload,
  };
}
