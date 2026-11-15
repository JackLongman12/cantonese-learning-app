/// On-device speech recognition for the read-aloud check: SenseVoice (Cantonese,
/// Mandarin, English) through sherpa-onnx, recorded with the `record` package.
/// Nothing leaves the device. The 240 MB model is downloaded once, on first use.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import '../engine/end_of_speech.dart';

const _hf =
    'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main';
const modelBytes = 239233841;
const _files = {'model.int8.onnx': modelBytes, 'tokens.txt': 315894};

class SpeechEngine {
  SpeechEngine(this.modelDir);

  /// Holds model.int8.onnx and tokens.txt.
  final Directory modelDir;

  so.OfflineRecognizer? _recognizer;
  String? _lang;
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;

  /// Runs before each recording starts (the app stops any audio playing).
  Future<void> Function()? beforeRecording;
  final _pcm = BytesBuilder(copy: false);

  static const sampleRate = 16000;

  bool get installed => _files.entries.every((e) {
    final f = File(p.join(modelDir.path, e.key));
    return f.existsSync() && f.lengthSync() == e.value;
  });

  /// Downloads the model; [progress] gets 0..1. Writes to temp files first so an
  /// interrupted download never leaves a broken model behind.
  Future<void> install({void Function(double)? progress}) async {
    modelDir.createSync(recursive: true);
    final total = _files.values.fold(0, (a, b) => a + b);
    var done = 0;
    final client = http.Client();
    try {
      for (final e in _files.entries) {
        final target = File(p.join(modelDir.path, e.key));
        if (target.existsSync() && target.lengthSync() == e.value) {
          done += e.value;
          continue;
        }
        final part = File('${target.path}.part');
        final resp = await client.send(
          http.Request('GET', Uri.parse('$_hf/${e.key}')),
        );
        if (resp.statusCode != 200) {
          throw HttpException('HTTP ${resp.statusCode} for ${e.key}');
        }
        final sink = part.openWrite();
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          done += chunk.length;
          progress?.call(done / total);
        }
        await sink.close();
        if (part.lengthSync() != e.value) {
          throw const HttpException('Incomplete download');
        }
        part.renameSync(target.path);
      }
    } finally {
      client.close();
    }
  }

  void _load(String lang) {
    if (_recognizer != null && _lang == lang) return;
    _recognizer?.free();
    so.initBindings();
    _recognizer = so.OfflineRecognizer(
      so.OfflineRecognizerConfig(
        model: so.OfflineModelConfig(
          senseVoice: so.OfflineSenseVoiceModelConfig(
            model: p.join(modelDir.path, 'model.int8.onnx'),
            language: 'yue',
          ),
          tokens: p.join(modelDir.path, 'tokens.txt'),
          numThreads: 2,
        ),
      ),
    );
    _lang = lang;
  }

  /// Text heard in 16 kHz mono float samples.
  String recognise(Float32List samples, {required String lang}) {
    _load(lang);
    final r = _recognizer!;
    final stream = r.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      r.decode(stream);
      return r.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  Future<bool> canRecord() => _recorder.hasPermission();

  EndOfSpeech? _end;

  /// Whether the last recording had any speech in it (silence: the learner may be
  /// unable to speak right now, so it should not be scored as wrong).
  bool get heardSpeech => _end?.heardSpeech ?? false;

  /// Starts recording. [onFinished] fires once, when the learner stops speaking
  /// (see [EndOfSpeech]); [maxLength] caps very long sentences.
  Future<void> startRecording({
    void Function()? onFinished,
    Duration maxLength = const Duration(seconds: 20),
  }) async {
    await beforeRecording?.call();
    _pcm.clear();
    final end = EndOfSpeech(sampleRate: sampleRate, maxLength: maxLength);
    _end = end;
    var fired = false;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        noiseSuppress: true,
      ),
    );
    _sub = stream.listen((chunk) {
      _pcm.add(chunk);
      if (!fired && end.add(pcm16ToFloat(chunk))) {
        fired = true;
        onFinished?.call();
      }
    });
  }

  /// A recording is running.
  bool get recording => _sub != null;

  /// Stops a running recording and throws it away (leaving a screen).
  Future<void> cancel() async {
    if (!recording) return;
    await stopRecording();
  }

  /// Stops and returns the recording as float samples in [-1, 1].
  Future<Float32List> stopRecording() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;
    return pcm16ToFloat(_pcm.takeBytes());
  }

  void dispose() {
    _recognizer?.free();
    _recorder.dispose();
  }
}

/// 16-bit PCM mono WAV, for playing the learner's own recording back.
Uint8List writeWav16(
  Float32List samples, {
  int sampleRate = SpeechEngine.sampleRate,
}) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}

Float32List pcm16ToFloat(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final out = Float32List(bytes.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Minimal reader for 16-bit PCM mono WAV files (tests and fixtures).
Float32List readWav16(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  var off = 12;
  while (off + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(off, off + 4));
    final size = d.getUint32(off + 4, Endian.little);
    if (id == 'data') {
      return pcm16ToFloat(bytes.sublist(off + 8, off + 8 + size));
    }
    off += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('No data chunk in WAV');
}
