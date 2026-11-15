/// A mic button that checks you said something right: records (stops by itself when
/// you finish), recognises on the device, and compares the Jyutping heard with the
/// Jyutping expected. Used by word practice and flashcards.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../engine/pronunciation.dart';
import '../platform/sfx.dart';
import '../platform/speech.dart';
import '../platform/storage.dart';
import 'reader_screen.dart' show ModelDownloadDialog, soundAccuracy;

/// Readings heard in recognised text (Traditional, han characters only).
List<String> heardReadings(AppServices s, String heardText) => s.content
    .annotator('yue')
    .annotate(s.content.toTraditional(heardText))
    .where((t) => t.kind == 'han' && t.reading != null)
    .map((t) => t.reading!)
    .toList();

/// After a missed attempt: your recording, then the native audio, so you hear the
/// difference. The recording is a temp file, deleted straight after. Attempts at or
/// above [passPercent] are never kept.
Future<void> playComparison(
  AppServices s,
  Float32List samples,
  String? nativeText,
) async {
  final file = File(recordingPath(Directory.systemTemp));
  try {
    file.writeAsBytesSync(writeWav16(samples));
    await s.playFile?.call(file.path);
    final path = nativeText == null
        ? null
        : s.content.audioPath('yue', nativeText);
    if (path != null) await s.playAudio(path);
  } on Object {
    // playback failed: nothing to keep anyway
  } finally {
    if (file.existsSync()) file.deleteSync();
  }
}

/// Two silent recordings in a row: a hint (silence is never scored as wrong).
void noteSilence(BuildContext context, AppServices s, {required bool heard}) {
  if (heard) {
    s.speechSilences = 0;
    return;
  }
  s.speechSilences++;
  if (s.speechSilences < 2) return;
  s.speechSilences = 0;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text(
          "Didn't hear anything. Tap the mic and speak up a little.",
        ),
      ),
    );
}

class MicCheck extends StatefulWidget {
  const MicCheck({
    super.key,
    required this.services,
    required this.expected,
    required this.onResult,
    this.label = 'Say it',
    this.autoStart = false,
    this.nativeText,
  });
  final AppServices services;

  /// Start listening as soon as it appears (unless the mic is paused or not set up).
  final bool autoStart;

  /// The text whose recorded audio is played after a miss, for comparison.
  final String? nativeText;

  /// Jyutping per character, in order.
  final List<String> expected;
  final void Function(List<CharScore> scores, int percent) onResult;
  final String label;

  @override
  State<MicCheck> createState() => _MicCheckState();
}

enum _State { idle, recording, scoring }

class _MicCheckState extends State<MicCheck> {
  _State _state = _State.idle;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart && _s.speech?.installed == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _state == _State.idle) _tap();
      });
    }
  }

  @override
  void dispose() {
    if (_state == _State.recording) _s.speech?.stopRecording().ignore();
    super.dispose();
  }

  Future<void> _tap() async {
    final eng = _s.speech;
    if (eng == null || _state == _State.scoring) return;
    if (_state == _State.recording) return _stop(eng);
    if (!eng.installed) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ModelDownloadDialog(engine: eng),
      );
      if (ok != true || !mounted) return;
    }
    if (!await eng.canRecord()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DuckLearn needs the microphone to check you.'),
          ),
        );
      }
      return;
    }
    _s.sound(Sfx.mic);
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await eng.startRecording(
      onFinished: () {
        if (mounted && _state == _State.recording) _stop(eng);
      },
      maxLength: Duration(milliseconds: 3000 + widget.expected.length * 700),
    );
    if (mounted) setState(() => _state = _State.recording);
  }

  Future<void> _stop(SpeechEngine eng) async {
    setState(() => _state = _State.scoring);
    final samples = await eng.stopRecording();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    noteSilence(context, _s, heard: eng.heardSpeech);
    if (!eng.heardSpeech) {
      setState(() => _state = _State.idle);
      return;
    }
    final heard = heardReadings(_s, eng.recognise(samples, lang: 'yue'));
    final score = scoreAttempt(widget.expected, heard);
    final pct = soundAccuracy(score.chars);
    _s.logger.log('speech.attempt', {
      'engine': 'sensevoice-int8',
      'score': score.ratio,
      'per_token': [
        for (final c in score.chars)
          {'expected': c.expected, 'heard': c.heard, 'v': c.verdict.name},
      ],
    });
    _s.sound(pct >= passPercent ? Sfx.good : Sfx.tryAgain);
    if (mounted) setState(() => _state = _State.idle);
    widget.onResult(score.chars, pct);
    if (pct < passPercent) await playComparison(_s, samples, widget.nativeText);
  }

  @override
  Widget build(BuildContext context) {
    if (_s.speech == null ||
        !(Platform.isAndroid || Platform.isWindows || Platform.isMacOS)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final recording = _state == _State.recording;
    return FilledButton.tonalIcon(
      key: const ValueKey('mic-check'),
      onPressed: _state == _State.scoring ? null : _tap,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        backgroundColor: recording ? scheme.errorContainer : null,
      ),
      icon: _state == _State.scoring
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
      label: Text(recording ? 'Listening… tap to stop' : widget.label),
    );
  }
}
