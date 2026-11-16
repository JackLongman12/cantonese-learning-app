import 'dart:io';

import 'package:duk/platform/character_pictures.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'downloads missing pictures once, skips non-images and failures',
    () async {
      final dir = Directory.systemTemp.createTempSync('pics');
      addTearDown(() => dir.deleteSync(recursive: true));
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        return switch (r.url.path) {
          '/a.png' => http.Response.bytes([0x89, 0x50, 0x4E, 0x47, 1, 2], 200),
          '/html' => http.Response('<html>', 200),
          _ => http.Response('gone', 404),
        };
      });
      final pics = CharacterPictures(dir, client: client);
      final urls = {
        '伙計': 'https://x.test/a.png',
        '司機': 'https://x.test/html',
        '醫生': 'https://x.test/missing',
      };
      expect(await pics.fetchMissing(urls), 1);
      expect(pics.fileFor('伙計').existsSync(), isTrue);
      expect(pics.fileFor('伙計').path, endsWith('4f19-8a08.png'));
      expect(pics.fileFor('司機').existsSync(), isFalse);
      calls = 0;
      expect(await pics.fetchMissing(urls), 0);
      expect(calls, 2, reason: 'the saved one is not fetched again');
    },
  );
}
