/// Conversation pictures (Irasutoya illustrations) are downloaded on the device the
/// first time the app runs, never shipped inside it: their terms allow using the
/// pictures but not redistributing the files (content/characters.yaml).
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// File name for a speaker: code points in hex (伙計 -> 4f19-8a08.png).
String characterFileName(String role) =>
    '${role.runes.map((r) => r.toRadixString(16)).join('-')}.png';

class CharacterPictures {
  CharacterPictures(this.dir, {http.Client? client})
    : _client = client; // ignore: prefer_initializing_formals

  /// Where the pictures live (app support folder / characters).
  final Directory dir;
  final http.Client? _client;

  File fileFor(String role) => File(p.join(dir.path, characterFileName(role)));

  /// Downloads every picture not on disk yet. Returns how many were saved. Failures
  /// (offline, a moved link) are skipped quietly: the stage draws an initial instead,
  /// and the next launch tries again.
  Future<int> fetchMissing(Map<String, String> urls) async {
    var saved = 0;
    final client = _client ?? http.Client();
    try {
      dir.createSync(recursive: true);
      for (final MapEntry(key: role, value: url) in urls.entries) {
        final out = fileFor(role);
        if (out.existsSync()) continue;
        try {
          final r = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 30));
          if (r.statusCode != 200 || !_isImage(r.bodyBytes)) continue;
          final part = File('${out.path}.part');
          await part.writeAsBytes(r.bodyBytes, flush: true);
          await part.rename(out.path);
          saved++;
        } on Object {
          // try again next launch
        }
      }
    } finally {
      if (_client == null) client.close();
    }
    return saved;
  }

  /// PNG or JPEG only: downloads are untrusted data.
  static bool _isImage(List<int> b) =>
      (b.length > 4 &&
          b[0] == 0x89 &&
          b[1] == 0x50 &&
          b[2] == 0x4E &&
          b[3] == 0x47) ||
      (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF);
}
