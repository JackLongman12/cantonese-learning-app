// Runs the real on-device recogniser (sherpa-onnx + SenseVoice) on two recordings:
// 我想買書 read correctly, and with 買 maai5 replaced by 睇 tai2.
//   flutter test integration_test/speech_test.dart -d windows
// Uses the model already downloaded to ../data/models (pipeline dev copy); skipped
// if it is not there.
import 'dart:io';

import 'package:duk/data/content_db.dart';
import 'package:duk/engine/pronunciation.dart';
import 'package:duk/platform/speech.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Directory? _devModel() {
  final models = Directory('../data/models');
  if (!models.existsSync()) return null;
  for (final d in models.listSync().whereType<Directory>()) {
    if (d.path.contains('sense-voice') &&
        File('${d.path}/model.int8.onnx').existsSync()) {
      return d;
    }
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final model = _devModel();

  testWidgets('read-aloud scoring with the real model', (t) async {
    final engine = SpeechEngine(model!);
    final dir = Directory.systemTemp.createTempSync('duk_speech');
    final bytes = await rootBundle.load('assets/content/content.db');
    final dbFile = File('${dir.path}/content.db')
      ..writeAsBytesSync(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    final db = ContentDb.open(dbFile.path);
    final yue = db.annotator('yue');
    final expected = yue.annotate('我想買書').map((x) => x.reading!).toList();
    expect(expected, ['ngo5', 'soeng2', 'maai5', 'syu1']);

    AttemptScore run(String fixture) {
      final wav = File('integration_test/fixtures/$fixture.wav')
          .readAsBytesSync();
      final heard = engine.recognise(readWav16(wav), lang: 'yue');
      final readings = yue
          .annotate(db.toTraditional(heard))
          .where((x) => x.kind == 'han' && x.reading != null)
          .map((x) => x.reading!)
          .toList();
      // ignore: avoid_print
      print('$fixture heard "$heard" -> $readings');
      return scoreAttempt(expected, readings);
    }

    final good = run('buy_correct');
    expect(good.chars.map((c) => c.verdict), everyElement(Verdict.ok));

    // A different syllable (睇 tai2 instead of 買 maai5) is caught.
    final bad = run('buy_said_look');
    expect(bad.chars[2].verdict, Verdict.wrong);
    expect(bad.chars[2].heard, 'tai2');
    expect(
      [bad.chars[0], bad.chars[1], bad.chars[3]].map((c) => c.verdict),
      everyElement(Verdict.ok),
    );
    // Known limit: a tone slip that makes another real word (賣 maai6 for 買 maai5)
    // is "corrected" by the recogniser, which is why tones are checked by ear.
    engine.dispose();
    db.close();
  }, skip: model == null);
}
