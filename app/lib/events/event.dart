/// Event envelope, schema v1 (docs/EVENTS_SCHEMA.md). Events are immutable; unknown
/// types and fields are carried through untouched so devices on different app versions
/// can share one log.
library;

import 'dart:convert';

const int eventSchemaVersion = 1;

class Event {
  const Event({
    required this.id,
    required this.tsUtc,
    required this.tzOffsetMin,
    required this.monoMs,
    required this.deviceId,
    required this.deviceKind,
    required this.sessionId,
    required this.appVersion,
    required this.contentVersion,
    required this.type,
    this.payload = const {},
    this.schemaV = eventSchemaVersion,
  });

  final String id;
  final DateTime tsUtc;
  final int tzOffsetMin;
  final int monoMs;
  final String deviceId;
  final String deviceKind;
  final String sessionId;
  final String appVersion;
  final String contentVersion;
  final int schemaV;
  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'id': id,
    'ts_utc': tsUtc.toUtc().toIso8601String(),
    'tz_offset_min': tzOffsetMin,
    'mono_ms': monoMs,
    'device_id': deviceId,
    'device_kind': deviceKind,
    'session_id': sessionId,
    'app_version': appVersion,
    'content_version': contentVersion,
    'schema_v': schemaV,
    'type': type,
    'payload': payload,
  };

  String toLine() => jsonEncode(toJson());

  static Event fromJson(Map<String, Object?> j) => Event(
    id: j['id'] as String,
    tsUtc: DateTime.parse(j['ts_utc'] as String).toUtc(),
    tzOffsetMin: (j['tz_offset_min'] as num?)?.toInt() ?? 0,
    monoMs: (j['mono_ms'] as num?)?.toInt() ?? 0,
    deviceId: j['device_id'] as String? ?? '',
    deviceKind: j['device_kind'] as String? ?? '',
    sessionId: j['session_id'] as String? ?? '',
    appVersion: j['app_version'] as String? ?? '',
    contentVersion: j['content_version'] as String? ?? '',
    schemaV: (j['schema_v'] as num?)?.toInt() ?? 1,
    type: j['type'] as String,
    payload: (j['payload'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  /// Returns null for a corrupt line (e.g. a write cut short by a crash) instead of
  /// throwing, so one bad line never blocks a replay.
  static Event? tryParseLine(String line) {
    if (line.trim().isEmpty) return null;
    try {
      return fromJson((jsonDecode(line) as Map).cast<String, Object?>());
    } on Object {
      return null;
    }
  }
}
