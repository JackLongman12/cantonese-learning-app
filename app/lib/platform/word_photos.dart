/// Photos for newcomer words (2026-11-17): downloaded from Wikimedia Commons on the phone
/// when first shown, never bundled, kept in a cache folder. Downloads are untrusted: HTTPS
/// only, Wikimedia hosts only (redirects included; thumbnails come from
/// thumb.wikimedia.org since 2026, before that upload.wikimedia.org), at most [maxBytes], JPEG or PNG only.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

class WordPhotos {
  WordPhotos(this.dir, {http.Client? client})
    : _client = client; // ignore: prefer_initializing_formals

  final Directory dir;
  final http.Client? _client;
  final _pending = <String, Future<File?>>{};

  static const _userAgent =
      'DuckLearn/1.0 (https://github.com/JackLongman12/cantonese-learning-app)';

  static const maxBytes = 400 * 1024;
  static const width = 320;

  /// Where a photo is kept: a safe name from the file's characters.
  File fileFor(String commonsFile) {
    final safe = commonsFile.runes.map((r) => r.toRadixString(16)).join('-');
    final name = safe.length > 120 ? safe.substring(0, 120) : safe;
    return File('${dir.path}/$name.img');
  }

  /// The photo's thumbnail link on Commons (resolves to upload.wikimedia.org).
  static Uri urlFor(String commonsFile) => Uri.https(
    'commons.wikimedia.org',
    '/wiki/Special:FilePath/$commonsFile',
    {'width': '$width'},
  );

  static const _hosts = {
    'commons.wikimedia.org',
    'upload.wikimedia.org',
    'thumb.wikimedia.org',
  };

  static bool _trusted(Uri u) => u.scheme == 'https' && _hosts.contains(u.host);

  /// The photo on disk, downloading it first if needed; null if it can't be had (offline:
  /// the next showing tries again).
  Future<File?> get(String commonsFile) {
    final f = fileFor(commonsFile);
    if (f.existsSync()) return Future.value(f);
    return _pending[commonsFile] ??= _download(commonsFile, f).whenComplete(() {
      // a block, not `=>`: remove() returns this very future, and waiting on it hangs
      _pending.remove(commonsFile);
    });
  }

  Future<File?> _download(String commonsFile, File out) async {
    final client = _client ?? http.Client();
    try {
      var uri = urlFor(commonsFile);
      http.StreamedResponse? r;
      // follow redirects by hand so every hop is checked
      for (var hop = 0; hop < 4; hop++) {
        if (!_trusted(uri)) return null;
        final req = http.Request('GET', uri)
          ..followRedirects = false
          // Wikimedia asks apps to name themselves
          ..headers['user-agent'] = _userAgent;
        r = await client.send(req).timeout(const Duration(seconds: 20));
        final loc = r.headers['location'];
        if (r.statusCode >= 300 && r.statusCode < 400 && loc != null) {
          uri = uri.resolve(loc);
          await r.stream.drain<void>();
          continue;
        }
        break;
      }
      if (r == null || r.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in r.stream.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) return null;
      }
      if (!_isImage(bytes)) return null;
      dir.createSync(recursive: true);
      final part = File('${out.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(out.path);
      return out;
    } on Object {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  static bool _isImage(List<int> b) =>
      (b.length > 4 &&
          b[0] == 0x89 &&
          b[1] == 0x50 &&
          b[2] == 0x4E &&
          b[3] == 0x47) ||
      (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF);
}
