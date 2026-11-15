import 'dart:io';

import 'package:duk/platform/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cleans old audio caches and recordings, keeps everything else', () {
    final temp = Directory.systemTemp.createTempSync('duk_storage');
    addTearDown(() => temp.deleteSync(recursive: true));
    final oldCache = Directory(
      '${temp.path}/0f8fad5b-d9cb-469f-a165-70867728950e',
    )..createSync();
    File('${oldCache.path}/a.mp3').writeAsBytesSync(List.filled(1000, 1));
    File('${temp.path}/ducklearn_mine_3.wav')
        .writeAsBytesSync(List.filled(500, 1));
    File(recordingPath(temp)).writeAsBytesSync(List.filled(200, 1));
    final current = Directory('${temp.path}/$audioCacheId')..createSync();
    File('${current.path}/b.mp3').writeAsBytesSync(List.filled(300, 1));
    final other = File('${temp.path}/something_else.txt')
      ..writeAsStringSync('keep');

    expect(cleanTemp(temp), 1700);
    expect(oldCache.existsSync(), isFalse);
    expect(current.existsSync(), isTrue); // this launch's cache stays
    expect(other.existsSync(), isTrue);

    expect(cleanTemp(temp, includeAudioCache: true), 300);
    expect(current.existsSync(), isFalse);
    expect(formatBytes(1500000), '1.5 MB');
  });
}
