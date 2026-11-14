/// Text from a photo or screenshot. Android uses ML Kit's on-device Chinese model;
/// Windows uses the built-in Windows OCR (needs a Chinese OCR language installed);
/// macOS is not wired yet.
library;

import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

class OcrResult {
  const OcrResult.text(this.text) : error = null;
  const OcrResult.error(this.error) : text = '';
  final String text;

  /// Human-readable reason when no text could be read.
  final String? error;
}

/// Windows OCR inserts spaces between CJK characters; drop them, keep other spacing.
String tidyOcrText(String raw) => raw
    .replaceAllMapped(
      RegExp(r'(?<=[　-鿿豈-﫿＀-￯])[ \t]+(?=[　-鿿豈-﫿＀-￯])'),
      (_) => '',
    )
    .trim();

class OcrService {
  bool get canUseCamera => Platform.isAndroid || Platform.isIOS;
  bool get supported => Platform.isAndroid || Platform.isWindows;

  Future<String?> pickImage({required bool camera}) async {
    final file = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2400,
    );
    return file?.path;
  }

  Future<OcrResult> recognise(String imagePath) async {
    if (Platform.isAndroid || Platform.isIOS) return _mlKit(imagePath);
    if (Platform.isWindows) return _windows(imagePath);
    return const OcrResult.error(
      'Photo reading is not available on this device yet.',
    );
  }

  Future<OcrResult> _mlKit(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final r = await recognizer.processImage(InputImage.fromFilePath(path));
      final text = tidyOcrText(r.blocks.map((b) => b.text).join('\n'));
      return text.isEmpty
          ? const OcrResult.error('No text found in the picture.')
          : OcrResult.text(text);
    } on Object catch (e) {
      return OcrResult.error('Could not read the picture: $e');
    } finally {
      await recognizer.close();
    }
  }

  Future<OcrResult> _windows(String path) async {
    final script = File(p.join(Directory.systemTemp.path, 'ducklearn_ocr.ps1'));
    await script.writeAsString(_windowsScript);
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
      path,
    ], stdoutEncoding: const SystemEncoding());
    final out = (r.stdout as String).trim();
    if (r.exitCode == 3) {
      return const OcrResult.error(
        'Windows has no Chinese OCR installed. Add it in Settings > Time & language > '
        'Language & region > Add a language > Chinese (Traditional, Hong Kong SAR), '
        'with "Optical character recognition" ticked. Then try again.',
      );
    }
    if (r.exitCode != 0) {
      return OcrResult.error('Could not read the picture: ${r.stderr}');
    }
    final text = tidyOcrText(out);
    return text.isEmpty
        ? const OcrResult.error('No text found in the picture.')
        : OcrResult.text(text);
  }
}

/// Runs Windows.Media.Ocr from PowerShell and writes UTF-8 text to stdout.
/// Exit 3 = no Chinese OCR language installed.
const _windowsScript = r'''
param([string]$Path)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$type) {
  $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result
}
$langs = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages |
  Where-Object { $_.LanguageTag -like 'zh*' } |
  Sort-Object { if ($_.LanguageTag -match 'Hant|HK|TW') { 0 } else { 1 } }
if (-not $langs) { exit 3 }
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage(@($langs)[0])
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
$result.Lines | ForEach-Object { $_.Text }
''';
