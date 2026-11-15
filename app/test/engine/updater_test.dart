import 'package:duk/platform/updater.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> release(String tag, List<String> assets) => {
  'tag_name': tag,
  'name': '0.$tag',
  'body': 'notes',
  'assets': [
    for (final a in assets)
      {'name': a, 'browser_download_url': 'https://x/$a', 'size': 100},
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
      'https://x/$apk',
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
}
