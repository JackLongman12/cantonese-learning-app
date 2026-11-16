import 'dart:convert';
import 'dart:io';

import 'package:duk/data/prefs.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/platform/telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;
  late EventLogger logger;
  late Prefs prefs;
  final posts = <(String, Map<String, Object?>)>[];
  var online = true;

  Telemetry make() => Telemetry(
    prefs: prefs,
    eventDir: Directory('${dir.path}/events/dev1'),
    stateDir: dir,
    appVersion: 'b2070',
    url: 'https://worker.test',
    client: MockClient((r) async {
      if (!online) throw const SocketException('offline');
      posts.add((r.url.path, (jsonDecode(r.body) as Map).cast()));
      return http.Response('{"ok":true}', 200);
    }),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('telemetry');
    logger = EventLogger(
      store: JsonlEventStore(Directory('${dir.path}/events'), 'dev1'),
      deviceId: 'dev1',
      deviceKind: 'android',
      appVersion: 'b2070',
      contentVersion: 'c1',
    );
    prefs = Prefs.memory();
    posts.clear();
    online = true;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('nothing is sent until the learner agrees', () async {
    logger.log('app.open', {});
    expect(await make().upload(), 0);
    expect(posts, isEmpty);
  });

  test('sends shared events once, without the device id', () async {
    prefs
      ..shareData = true
      ..telemetryId = 'tid';
    logger.log('app.open', {});
    logger.log('idle.end', {'idle_ms': 30000}); // not shared
    logger.log('word.save', {'text': '私人', 'lang': 'yue'});
    final t = make();
    expect(await t.upload(), 2);
    final events = posts.single.$2['events']! as List;
    expect(posts.single.$1, '/v1/events');
    expect([for (final e in events) (e as Map)['type']], ['app.open', 'word.save']);
    expect(jsonEncode(events), isNot(contains('dev1')));
    expect(jsonEncode(events), isNot(contains('私人')));
    // nothing new: nothing sent
    expect(await t.upload(), 0);
    logger.log('session.start', {});
    expect(await t.upload(), 1);
  });

  test('offline keeps everything for the next try', () async {
    prefs
      ..shareData = true
      ..telemetryId = 'tid';
    logger.log('app.open', {});
    online = false;
    final t = make();
    expect(await t.upload(), 0);
    online = true;
    expect(await t.upload(), 1);
  });

  test('turning sharing back on skips what happened while it was off', () async {
    logger.log('app.open', {});
    final t = make()..skipToEnd();
    prefs
      ..shareData = true
      ..telemetryId = 'tid';
    logger.log('session.start', {});
    expect(await t.upload(), 1);
    expect(((posts.single.$2['events']! as List).single as Map)['type'], 'session.start');
  });

  test('a crash is kept and sent with the next upload', () async {
    final t = make();
    t.recordCrash(StateError('boom'), StackTrace.current);
    expect(posts, isEmpty); // not agreed yet
    prefs
      ..shareData = true
      ..telemetryId = 'tid';
    await t.upload();
    final crash = posts.firstWhere((p) => p.$1 == '/v1/crash').$2;
    expect(crash['error_type'], 'StateError');
    expect(crash['install_id'], 'tid');
    expect(crash['app_version'], 'b2070');
    posts.clear();
    await t.upload();
    expect(posts.where((p) => p.$1 == '/v1/crash'), isEmpty);
  });
}
