/// Stamps and records events. The UI calls [log]; nothing else writes events.
library;

import 'package:ulid/ulid.dart';

import 'event.dart';
import 'event_store.dart';

typedef Clock = DateTime Function();

class EventLogger {
  EventLogger({
    required this.store,
    required this.deviceId,
    required this.deviceKind,
    required this.appVersion,
    required this.contentVersion,
    Clock? clock,
    String Function()? newId,
    this.idleAfter = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? (() => Ulid().toString()) {
    startSession();
  }

  final EventStore store;
  final String deviceId;
  final String deviceKind;
  final String appVersion;
  final String contentVersion;
  final Duration idleAfter;
  final Clock _clock;
  final String Function() _newId;
  final List<void Function(Event)> _listeners = [];

  late String _sessionId;
  late DateTime _sessionStart;
  DateTime? _lastInput;
  int _idleMs = 0;

  String get sessionId => _sessionId;
  DateTime now() => _clock();

  void addListener(void Function(Event) l) => _listeners.add(l);

  void startSession() {
    _sessionId = _newId();
    _sessionStart = _clock();
    _lastInput = null;
    _idleMs = 0;
  }

  /// Call on every user input. Gaps longer than [idleAfter] are counted as idle and
  /// excluded from [activeMsSince].
  void touch() {
    final now = _clock();
    final last = _lastInput;
    if (last != null) {
      final gap = now.difference(last);
      if (gap > idleAfter) {
        _idleMs += gap.inMilliseconds;
        _write('idle.end', {'idle_ms': gap.inMilliseconds}, now);
      }
    }
    _lastInput = now;
  }

  ActiveMark mark() => ActiveMark(_clock(), _idleMs);

  /// Milliseconds of non-idle time since [mark].
  int activeMsSince(ActiveMark mark) {
    final now = _clock();
    final wall = now.difference(mark.at).inMilliseconds;
    var idle = _idleMs - mark.idleMs;
    final last = _lastInput;
    if (last != null && now.difference(last) > idleAfter) {
      idle += now.difference(last).inMilliseconds;
    }
    return (wall - idle).clamp(0, wall);
  }

  Event log(String type, [Map<String, Object?> payload = const {}]) =>
      _write(type, payload, _clock());

  Event _write(String type, Map<String, Object?> payload, DateTime now) {
    final e = Event(
      id: _newId(),
      tsUtc: now.toUtc(),
      tzOffsetMin: now.timeZoneOffset.inMinutes,
      monoMs: now.difference(_sessionStart).inMilliseconds,
      deviceId: deviceId,
      deviceKind: deviceKind,
      sessionId: _sessionId,
      appVersion: appVersion,
      contentVersion: contentVersion,
      type: type,
      payload: payload,
    );
    store.append(e);
    for (final l in _listeners) {
      l(e);
    }
    return e;
  }
}

class ActiveMark {
  const ActiveMark(this.at, this.idleMs);
  final DateTime at;
  final int idleMs;
}
