import 'dart:io';

import 'package:duk/platform/word_photos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(100, 0)];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('photos'));
  tearDown(() => dir.deleteSync(recursive: true));

  WordPhotos make(Future<http.Response> Function(http.Request) handler) =>
      WordPhotos(dir, client: MockClient(handler));

  test('follows Commons redirects to the image and keeps it', () async {
    var calls = 0;
    final photos = make((r) async {
      calls++;
      if (r.url.host == 'commons.wikimedia.org') {
        return http.Response(
          '',
          302,
          headers: {'location': 'https://upload.wikimedia.org/x/Bus.jpg'},
        );
      }
      return http.Response.bytes(_jpeg, 200);
    });
    final f = await photos.get('Bus.jpg');
    expect(f, isNotNull);
    expect(f!.readAsBytesSync(), _jpeg);
    // a second showing reads the file, no download
    expect(await photos.get('Bus.jpg'), isNotNull);
    expect(calls, 2);
  });

  test('a redirect away from Wikimedia is refused', () async {
    final photos = make(
      (r) async => http.Response(
        '',
        302,
        headers: {'location': 'https://evil.example/x.jpg'},
      ),
    );
    expect(await photos.get('Bus.jpg'), isNull);
  });

  test('oversized files and non-images are refused', () async {
    final big = make(
      (r) async => http.Response.bytes([
        ..._jpeg,
        ...List.filled(WordPhotos.maxBytes, 0),
      ], 200),
    );
    expect(await big.get('Big.jpg'), isNull);
    final html = make((r) async => http.Response('<html>', 200));
    expect(await html.get('Page.jpg'), isNull);
  });

  test('file names never escape the folder', () {
    final photos = WordPhotos(dir);
    final f = photos.fileFor('../../etc/passwd');
    expect(f.parent.path, dir.path);
  });
}
