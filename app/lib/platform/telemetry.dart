/// Anonymous usage and crash reports, sent to the DuckLearn Cloudflare Worker
/// (`worker/`, docs/TELEMETRY.md) only when the learner said yes.
///
/// Usage: the event log is the queue. Shared events (events/telemetry_filter.dart) are
/// read from this device's JSONL files and sent in batches; a small cursor file records
/// how many lines of each file went out, so nothing is sent twice and nothing is lost
/// when the phone is offline. Crashes: written to a file first, sent on the next upload.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ulid/ulid.dart';

import '../app_services.dart';
import '../data/prefs.dart';
import '../events/event.dart';
import '../events/telemetry_filter.dart';

/// The Worker. Not a secret: it only accepts well-formed, size-limited batches.
const telemetryUrl = String.fromEnvironment(
  'TELEMETRY_URL',
  defaultValue: 'https://ducklearn-telemetry.lp-reports.workers.dev',
);

/// Events per request; the Worker refuses more.
const telemetryBatch = 400;

class Telemetry {
  Telemetry({
    required this.prefs,
    required this.eventDir,
    required this.stateDir,
    required this.appVersion,
    http.Client? client,
    this.url = telemetryUrl,
  }) : _client = client ?? http.Client();

  final Prefs prefs;

  /// This device's event files (`<events>/<deviceId>/`).
  final Directory eventDir;

  /// Where the cursor and unsent crash reports live.
  final Directory stateDir;
  final String appVersion;
  final String url;
  final http.Client _client;
  bool _busy = false;

  File get _cursorFile => File('${stateDir.path}/telemetry_cursor.json');
  Directory get _crashDir => Directory('${stateDir.path}/crashes');

  bool get enabled => prefs.shareData == true && prefs.telemetryId != null;

  Map<String, int> _readCursor() {
    try {
      return (jsonDecode(_cursorFile.readAsStringSync()) as Map)
          .cast<String, int>();
    } on Object {
      return {};
    }
  }

  void _writeCursor(Map<String, int> c) {
    stateDir.createSync(recursive: true);
    _cursorFile.writeAsStringSync(jsonEncode(c));
  }

  List<File> _eventFiles() {
    if (!eventDir.existsSync()) return const [];
    return eventDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  String _name(File f) => f.uri.pathSegments.last;

  /// Marks everything logged so far as already handled: used when sharing is turned
  /// back on, so nothing from the time it was off is sent.
  void skipToEnd() {
    _writeCursor({
      for (final f in _eventFiles())
        _name(f): const LineSplitter().convert(f.readAsStringSync()).length,
    });
  }

  /// Sends what is new. Safe to call often; does nothing while sharing is off, while
  /// another upload runs, or without a connection (it tries again next time).
  Future<int> upload() async {
    if (!enabled || _busy) return 0;
    _busy = true;
    var sent = 0;
    try {
      await _sendCrashes();
      final cursor = _readCursor();
      for (final f in _eventFiles()) {
        // cheap check first: a file that has not grown since the last upload is skipped
        // without being read (frequent uploads cost almost nothing when idle)
        final size = f.lengthSync();
        if (cursor['${_name(f)}#bytes'] == size) continue;
        final lines = const LineSplitter().convert(f.readAsStringSync());
        var at = cursor[_name(f)] ?? 0;
        while (at < lines.length) {
          final end = (at + telemetryBatch * 3).clamp(0, lines.length);
          final batch = <Map<String, Object?>>[];
          var k = at;
          for (; k < end && batch.length < telemetryBatch; k++) {
            final e = Event.tryParseLine(lines[k]);
            final out = e == null ? null : shareable(e, prefs.telemetryId!);
            if (out != null) batch.add(out);
          }
          if (batch.isNotEmpty) {
            final r = await _client
                .post(
                  Uri.parse('$url/v1/events'),
                  headers: {'content-type': 'application/json'},
                  body: jsonEncode({'events': batch}),
                )
                .timeout(const Duration(seconds: 30));
            if (r.statusCode != 200) return sent;
            sent += batch.length;
          }
          at = k;
          cursor[_name(f)] = at;
          _writeCursor(cursor);
        }
        cursor['${_name(f)}#bytes'] = size;
        _writeCursor(cursor);
      }
    } on Object {
      // offline or the Worker is down: the cursor kept what went out
    } finally {
      _busy = false;
    }
    return sent;
  }

  /// Keeps a crash for the next upload (a crash may be the last thing the app does).
  void recordCrash(
    Object error,
    StackTrace? stack, {
    String where = 'flutter',
  }) {
    try {
      _crashDir.createSync(recursive: true);
      File(
        '${_crashDir.path}/${Ulid()}.json',
      ).writeAsStringSync(jsonEncode(crashReport(error, stack, where: where)));
    } on Object {
      // nowhere to write: nothing more to do
    }
    if (enabled) unawaited(upload());
  }

  Map<String, Object?> crashReport(
    Object error,
    StackTrace? stack, {
    required String where,
  }) => {
    'ts_utc': DateTime.now().toUtc().toIso8601String(),
    'app_version': appVersion,
    'device_kind': Platform.operatingSystem,
    'os_version': _cut(Platform.operatingSystemVersion, 120),
    'where': where,
    'error_type': error.runtimeType.toString(),
    'message': _cut(redactCrashText(error.toString()), 600),
    'stack': _cut(redactCrashText(stack?.toString() ?? ''), 6000),
  };

  Future<void> _sendCrashes() async {
    if (!_crashDir.existsSync()) return;
    for (final f in _crashDir.listSync().whereType<File>()) {
      Map<String, Object?> report;
      try {
        report = (jsonDecode(f.readAsStringSync()) as Map)
            .cast<String, Object?>();
      } on Object {
        f.deleteSync();
        continue;
      }
      final r = await _client
          .post(
            Uri.parse('$url/v1/crash'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({...report, 'install_id': prefs.telemetryId}),
          )
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return;
      f.deleteSync();
    }
  }

  /// Unsent crash reports are dropped when sharing is turned off.
  void forgetCrashes() {
    if (_crashDir.existsSync()) _crashDir.deleteSync(recursive: true);
  }
}

String _cut(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// Turns sharing on or off (onboarding, Settings, the one-time question on Home).
/// On: a new random id; the first time ever, the history so far is sent too, after
/// that only what is logged from now on. Off: nothing more is sent.
void setSharing(AppServices s, bool on) {
  final p = s.prefs;
  final was = p.shareData;
  if (on) {
    final firstTime = !p.sharedBefore;
    p.telemetryId = Ulid().toString();
    p.sharedBefore = true;
    if (!firstTime) s.telemetry?.skipToEnd();
  } else {
    p.telemetryId = null;
    s.telemetry?.forgetCrashes();
  }
  p.shareData = on;
  s.logger.log('settings.change', {'key': 'share_data', 'from': was, 'to': on});
  if (on) unawaited(s.telemetry?.upload());
}

/// While the app is open, sends what is new every [every]; stops in the background.
/// No background jobs or wake-ups: a closed app costs no battery, and the last events
/// go out when the app is put away (on pause). An idle check reads only file sizes.
class TelemetrySchedule {
  TelemetrySchedule(this.telemetry, {this.every = const Duration(minutes: 2)});
  final Telemetry telemetry;
  final Duration every;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(telemetry.upload()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
