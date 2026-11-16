import 'package:duk/platform/updater.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> release(String tag, List<String> assets) => {
  'tag_name': tag,
  'name': '0.$tag',
  'body': 'notes',
  'assets': [
    for (final a in assets)
      {
        'name': a,
        'browser_download_url':
            'https://github.com/o/r/releases/download/b1/$a',
        'size': 100,
      },
  ],
};

void main() {
  test('picks the asset for the device', () {
    expect(
      assetNameFor(os: 'android', dartVersion: '3.14 on "android_arm64"'),
      'DuckLearn-android-arm64.apk',
    );
    expect(
      assetNameFor(os: 'windows', dartVersion: ''),
      'DuckLearn-windows-x64.zip',
    );
    expect(assetNameFor(os: 'macos', dartVersion: ''), isNull);
  });

  test('only newer builds with the right asset count as updates', () {
    const apk = 'DuckLearn-android-arm64.apk';
    final r = release('b42', [apk, 'DuckLearn-windows-x64.zip']);
    expect(parseRelease(r, currentBuild: 41, asset: apk)?.build, 42);
    expect(
      parseRelease(r, currentBuild: 41, asset: apk)?.assetUrl,
      'https://github.com/o/r/releases/download/b1/$apk',
    );
    expect(parseRelease(r, currentBuild: 42, asset: apk), isNull); // same build
    expect(parseRelease(r, currentBuild: 50, asset: apk), isNull); // older
    expect(
      parseRelease(release('b43', ['other.zip']), currentBuild: 1, asset: apk),
      isNull,
    );
    expect(
      parseRelease(release('nightly', [apk]), currentBuild: 1, asset: apk),
      isNull,
    );
  });

  test(
    'tags use the Android versionCode, so installed split builds see updates',
    () {
      const apk = 'DuckLearn-android-arm64.apk';
      // build 21 installs as versionCode 2021 (arm64 split); release b2022 is newer
      expect(normaliseBuild(2021), 2021);
      expect(
        normaliseBuild(21),
        2021,
      ); // plain build numbers (Windows) line up too
      final r = release('b2022', [apk]);
      expect(
        parseRelease(r, currentBuild: normaliseBuild(2021), asset: apk)?.build,
        2022,
      );
      // the old scheme's tag (b21) is correctly not newer than 2021
      expect(
        parseRelease(release('b21', [apk]), currentBuild: 2021, asset: apk),
        isNull,
      );
    },
  );

  test('downloads only come from GitHub over HTTPS, with safe names', () {
    expect(
      trustedAssetUrl('https://github.com/o/r/releases/download/b1/a.apk'),
      isTrue,
    );
    expect(trustedAssetUrl('https://objects.githubusercontent.com/x'), isTrue);
    expect(trustedAssetUrl('http://github.com/a.apk'), isFalse);
    expect(trustedAssetUrl('https://github.com.evil.example/a.apk'), isFalse);
    expect(trustedAssetUrl('https://evil.example/a.apk'), isFalse);
    expect(safeFileName('DuckLearn-android-arm64.apk'), isNotNull);
    expect(safeFileName('..'), isNull);
    expect(safeFileName('.hidden'), isNull);
    expect(safeFileName('a/b.apk'), isNull);
  });

  test('a release from somewhere else is ignored; the digest is kept', () {
    Map<String, Object?> rel(String url, [String? digest]) => {
      'tag_name': 'b2100',
      'assets': [
        {
          'name': 'DuckLearn-android-arm64.apk',
          'browser_download_url': url,
          'size': 1,
          'digest': ?digest,
        },
      ],
    };
    const asset = 'DuckLearn-android-arm64.apk';
    expect(
      parseRelease(
        rel('https://evil.example/$asset'),
        currentBuild: 1,
        asset: asset,
      ),
      isNull,
    );
    final ok = parseRelease(
      rel(
        'https://github.com/o/r/releases/download/b2100/$asset',
        'sha256:ABC',
      ),
      currentBuild: 1,
      asset: asset,
    )!;
    expect(ok.sha256, 'abc');
  });
}
