/// A mic button that checks you said something right: records (stops by itself when
/// you finish), recognises on the device, and compares the Jyutping heard with the
/// Jyutping expected. Used by word practice and flashcards.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../engine/pronunciation.dart';
import '../platform/sfx.dart';
import '../platform/speech.dart';
import 'reader_screen.dart' show ModelDownloadDialog, soundAccuracy;

/// Readings heard in recognised text (Traditional, han characters only).
List<String> heardReadings(AppServices s, String heardText) => s.content
    .annotator('yue')
    .annotate(s.content.toTraditional(heardText))
    .where((t) => t.kind == 'han' && t.reading != null)
    .map((t) => t.reading!)
    .toList();

class MicCheck extends StatefulWidget {
  const MicCheck({
    super.key,
    required this.services,
    required this.expected,
    required this.onResult,
    this.label = 'Say it',
  });
  final AppServices services;

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
