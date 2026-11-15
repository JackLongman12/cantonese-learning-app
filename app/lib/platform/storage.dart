/// What DuckLearn keeps on the device, and cleaning up what it does not need.
///
/// Kept: progress (events), settings, the content database copy, the speech model (if
/// downloaded). Junk: the audio player's copies of played clips from earlier launches,
/// old read-aloud recordings, update installers. Only the latest recording is kept, for
/// "Play mine", and it is deleted on the next start.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Folder name the audio player uses for its copies of clips (fixed, so it is reused
/// across launches instead of a new random folder each time).
const audioCacheId = 'ducklearn_audio';

/// The one file read-aloud writes your voice to (overwritten each attempt).
String recordingPath(Directory temp) => p.join(temp.path, 'ducklearn_mine.wav');

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Removes junk from the temp folder. Returns bytes freed.
int cleanTemp(Directory temp, {bool includeAudioCache = false}) {
  var freed = 0;
  if (!temp.existsSync()) return 0;
  for (final e in temp.listSync()) {
    final name = p.basename(e.path);
    final junk =
        // audio player copies from earlier launches (random folder names)
        (e is Directory && _uuid.hasMatch(name)) ||
        (includeAudioCache && e is Directory && name == audioCacheId) ||
        // read-aloud recordings
        (e is File &&
            name.startsWith('ducklearn_mine') &&
            name.endsWith('.wav'));
    if (!junk) continue;
    try {
      freed += sizeOf(e);
      e.deleteSync(recursive: true);
    } on Object {
      // in use: next time
    }
  }
  return freed;
}

int sizeOf(FileSystemEntity e) {
  try {
    if (e is File) return e.lengthSync();
    if (e is Directory) {
      var n = 0;
      for (final f in e.listSync(recursive: true, followLinks: false)) {
        if (f is File) n += f.lengthSync();
      }
      return n;
    }
  } on Object {
    // unreadable: count as nothing
  }
  return 0;
}

String formatBytes(int b) => b >= 1000000
    ? '${(b / 1000000).toStringAsFixed(b >= 10000000 ? 0 : 1)} MB'
    : '${(b / 1000).round()} KB';
