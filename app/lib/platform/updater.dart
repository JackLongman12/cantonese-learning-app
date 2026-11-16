/// Auto-update from GitHub Releases (public repo, no token needed).
///
/// Releases are tagged `b<Android versionCode>` (2000 + build: `--split-per-abi` adds
/// 2000 for arm64) and carry assets named
///   DuckLearn-android-arm64.apk (and DuckLearn-windows-x64.zip once Windows releases resume)
/// (see tool/release.sh). The app compares the release's build number with its own and,
/// if newer, downloads the right asset and hands it to the platform installer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
    this.sha256,
  });
  final int build;
  final String version;
  final String assetUrl;
  final int assetSize;
  final String notes;

  /// The asset's SHA-256 from GitHub (`digest: "sha256:..."`), checked after download.
  final String? sha256;
}

/// Release downloads only come from GitHub over HTTPS (the API's own links), so a bad
/// API answer can never point the updater somewhere else.
bool trustedAssetUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https') return false;
  return u.host == 'github.com' || u.host.endsWith('.githubusercontent.com');
}

/// A safe file name for a download: letters, digits, dot, dash, underscore; never a
/// path or a hidden file.
String? safeFileName(String name) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$').hasMatch(name) ? name : null;

/// Android split builds report 2000 + build (arm64); plain build numbers are shifted to match.
int normaliseBuild(int n) => n >= 1000 ? n : 2000 + n;

/// Which release asset this device needs, or null where updates aren't supported.
String? assetNameFor({required String os, required String dartVersion}) {
  if (os == 'android') return 'DuckLearn-android-arm64.apk'; // arm64 only
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
      final url = a['browser_download_url'] as String? ?? '';
      if (!trustedAssetUrl(url)) return null;
      final digest = a['digest'] as String? ?? '';
      return UpdateInfo(
        sha256: digest.startsWith('sha256:')
            ? digest.substring(7).toLowerCase()
            : null,
        build: build,
        version: json['name'] as String? ?? tag,
        assetUrl: url,
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

  /// Why the last [check] found nothing, when it was not "up to date".
  String? lastError;

  /// Comparable with release tags: Android reports the arm64 versionCode (2000 + build);
  /// other platforms report the plain build number, so it is shifted the same way.
  Future<int> currentBuild() async {
    if (_currentBuild != null) return _currentBuild!;
    final n = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    return _currentBuild = normaliseBuild(n);
  }

  /// Null when up to date, unsupported, offline, or a local dev build (build number 1).
  Future<UpdateInfo?> check() async {
    final asset = assetNameFor(
      os: Platform.operatingSystem,
      dartVersion: Platform.version,
    );
    lastError = null;
    if (asset == null) return null;
    final current = await currentBuild();
    if (current <= 2001) {
      return null; // `flutter run` builds: never nag during development
    }
    try {
      final r = await _client
          .get(
            Uri.parse(
              'https://api.github.com/repos/$githubRepo/releases/latest',
            ),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'DuckLearn',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        lastError = 'GitHub answered ${r.statusCode}';
        return null;
      }
      return parseRelease(
        (jsonDecode(r.body) as Map).cast<String, Object?>(),
        currentBuild: current,
        asset: asset,
      );
    } on Object catch (e) {
      lastError = e is TimeoutException
          ? 'No answer from GitHub (offline?)'
          : '$e';
      return null; // try again next launch
    }
  }

  /// Update downloads live in their own folder under the temp dir, so they can be
  /// wiped without touching anything else.
  static Directory updatesDir(Directory temp) =>
      Directory(p.join(temp.path, 'ducklearn_updates'));

  /// Removes leftovers of earlier updates: installers, half downloads, the Windows
  /// script and unpack folders. Progress, settings and the speech model live in the
  /// app support folder and are never touched.
  static void cleanUp(Directory temp) {
    try {
      final dir = updatesDir(temp);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      if (!temp.existsSync()) return;
      for (final e in temp.listSync()) {
        final name = p.basename(e.path);
        if (name.startsWith('ducklearn_update') ||
            (name.startsWith('DuckLearn-') &&
                (name.endsWith('.apk') ||
                    name.endsWith('.zip') ||
                    name.endsWith('.part')))) {
          e.deleteSync(recursive: true);
        }
      }
    } on Object {
      // a file still in use (Windows) is cleaned next launch
    }
  }

  /// Downloads the asset into [dir] and returns its path.
  Future<String> download(
    UpdateInfo u,
    Directory dir, {
    void Function(double)? progress,
  }) async {
    if (!trustedAssetUrl(u.assetUrl)) {
      throw const HttpException('Untrusted download link');
    }
    final name = safeFileName(Uri.parse(u.assetUrl).pathSegments.last);
    if (name == null) throw const HttpException('Unexpected file name');
    dir.createSync(recursive: true);
    final target = File(p.join(dir.path, name));
    final part = File('${target.path}.part');
    final resp = await _client.send(http.Request('GET', Uri.parse(u.assetUrl)));
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    final total = resp.contentLength ?? u.assetSize;
    var done = 0;
    final sink = part.openWrite();
    final hashOut = _DigestSink();
    final hasher = sha256.startChunkedConversion(hashOut);
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      hasher.add(chunk);
      done += chunk.length;
      if (total > 0) progress?.call(done / total);
    }
    await sink.close();
    hasher.close();
    if (total > 0 && part.lengthSync() != total) {
      part.deleteSync();
      throw const HttpException('Incomplete download');
    }
    // the file must be exactly the one GitHub published
    if (u.sha256 != null && hashOut.value.toString() != u.sha256) {
      part.deleteSync();
      throw const HttpException('Download does not match its checksum');
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
Remove-Item $Zip -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $Exe
''';

/// Collects the digest from a chunked SHA-256 conversion.
class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
