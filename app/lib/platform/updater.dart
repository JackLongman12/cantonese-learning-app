/// Auto-update from GitHub Releases (public repo, no token needed).
///
/// Releases are tagged `b<build number>` and carry assets named
///   DuckLearn-android-arm64.apk, DuckLearn-android-arm32.apk, DuckLearn-windows-x64.zip
/// (see tool/release.sh). The app compares the release's build number with its own and,
/// if newer, downloads the right asset and hands it to the platform installer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

const githubRepo = 'JackLongman12/cantonese-learning-app';

class UpdateInfo {
  const UpdateInfo({
    required this.build,
    required this.version,
    required this.assetUrl,
    required this.assetSize,
    required this.notes,
  });
  final int build;
  final String version;
  final String assetUrl;
  final int assetSize;
  final String notes;
}

/// Which release asset this device needs, or null where updates aren't supported.
String? assetNameFor({required String os, required String dartVersion}) {
  if (os == 'android') {
    return dartVersion.contains('android_arm64') || dartVersion.contains('x64')
        ? 'DuckLearn-android-arm64.apk'
        : 'DuckLearn-android-arm32.apk';
  }
  if (os == 'windows') return 'DuckLearn-windows-x64.zip';
  return null; // macOS later
}

/// Parses `GET /repos/{repo}/releases/latest`. Returns null if it is not newer.
UpdateInfo? parseRelease(
  Map<String, Object?> json, {
  required int currentBuild,
  required String asset,
}) {
  final tag = json['tag_name'] as String? ?? '';
  final build = int.tryParse(tag.replaceFirst(RegExp('^b'), ''));
  if (build == null || build <= currentBuild) return null;
  for (final a
      in (json['assets'] as List? ?? const []).cast<Map<String, Object?>>()) {
    if (a['name'] == asset) {
      return UpdateInfo(
        build: build,
        version: json['name'] as String? ?? tag,
        assetUrl: a['browser_download_url'] as String,
        assetSize: (a['size'] as num?)?.toInt() ?? 0,
        notes: json['body'] as String? ?? '',
      );
    }
  }
  return null;
}

class Updater {
  Updater({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _channel = MethodChannel('ducklearn/update');

  int? _currentBuild;

  Future<int> currentBuild() async => _currentBuild ??=
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  /// Null when up to date, unsupported, offline, or a local dev build (build number 1).
  Future<UpdateInfo?> check() async {
    final asset = assetNameFor(
      os: Platform.operatingSystem,
      dartVersion: Platform.version,
    );
    if (asset == null) return null;
    final current = await currentBuild();
    if (current <= 1) {
      return null; // `flutter run` builds: never nag during development
    }
    try {
      final r = await _client
          .get(
            Uri.parse(
              'https://api.github.com/repos/$githubRepo/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return parseRelease(
        (jsonDecode(r.body) as Map).cast<String, Object?>(),
        currentBuild: current,
        asset: asset,
      );
    } on Object {
      return null; // offline etc.: try again next launch
    }
  }

  /// Downloads the asset into [dir] and returns its path.
  Future<String> download(
    UpdateInfo u,
    Directory dir, {
    void Function(double)? progress,
  }) async {
    dir.createSync(recursive: true);
    final target = File(
      p.join(dir.path, Uri.parse(u.assetUrl).pathSegments.last),
    );
    final part = File('${target.path}.part');
    final resp = await _client.send(http.Request('GET', Uri.parse(u.assetUrl)));
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    final total = resp.contentLength ?? u.assetSize;
    var done = 0;
    final sink = part.openWrite();
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      done += chunk.length;
      if (total > 0) progress?.call(done / total);
    }
    await sink.close();
    if (total > 0 && part.lengthSync() != total) {
      throw const HttpException('Incomplete download');
    }
    if (target.existsSync()) target.deleteSync();
    part.renameSync(target.path);
    return target.path;
  }

  /// Android: opens the system installer. Windows: swaps the files and restarts.
  Future<void> install(String path) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('installApk', {'path': path});
    } else if (Platform.isWindows) {
      final installDir = File(Platform.resolvedExecutable).parent.path;
      final script = File(
        p.join(File(path).parent.path, 'ducklearn_update.ps1'),
      )..writeAsStringSync(windowsUpdateScript);
      await Process.start('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '-Zip',
        path,
        '-Dir',
        installDir,
        '-Exe',
        Platform.resolvedExecutable,
        '-WaitPid',
        '$pid',
      ], mode: ProcessStartMode.detached);
      exit(0);
    }
  }
}

/// Waits for the app to exit, unpacks the new build over the install folder, restarts it.
/// App data lives in %APPDATA%, not the install folder, so progress is untouched.
const windowsUpdateScript = r'''
param([string]$Zip, [string]$Dir, [string]$Exe, [int]$WaitPid)
$ErrorActionPreference = 'Stop'
try { Wait-Process -Id $WaitPid -Timeout 60 } catch {}
$tmp = Join-Path $env:TEMP ("ducklearn_update_" + [guid]::NewGuid())
Expand-Archive -Path $Zip -DestinationPath $tmp -Force
$src = Get-ChildItem $tmp -Recurse -Filter 'duk.exe' | Select-Object -First 1
Copy-Item -Path (Join-Path $src.DirectoryName '*') -Destination $Dir -Recurse -Force
Remove-Item $tmp -Recurse -Force
Start-Process -FilePath $Exe
''';
