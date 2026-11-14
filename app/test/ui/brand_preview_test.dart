// Renders the DuckLearn logo and the mascot stages/moods for review, and writes the
// 1024px app-icon sources used by flutter_launcher_icons:
//   flutter test --update-goldens --tags golden test/ui/brand_preview_test.dart
@Tags(['golden'])
library;

import 'dart:io';

import 'package:duk/ui/logo.dart';
import 'package:duk/ui/mascot.dart';
import 'package:duk/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(p).readAsBytesSync())),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await loadFont(brushFont, [
      'assets/fonts/LXGWWenKaiTC-Regular.ttf',
      'assets/fonts/LXGWWenKaiTC-Bold.ttf',
    ]);
  });

  Widget plain(Widget child, {Color bg = Colors.transparent}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: bg,
      child: Center(child: child),
    ),
  );

  testWidgets('app icon sources', (t) async {
    // 1024 logical px at dpr 1 -> 1024 px files
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1024, 1024);
    addTearDown(t.view.reset);
    await t.pumpWidget(plain(const DuckLogo(size: 1024, tile: true)));
    await expectLater(
      find.byType(DuckLogo),
      matchesGoldenFile('../../assets/icon/app_icon.png'),
    );
    // Android adaptive foreground: full-bleed face; the launcher applies its own mask
    await t.pumpWidget(plain(const DuckLogo(size: 1024, tile: false)));
    await expectLater(
      find.byType(DuckLogo),
      matchesGoldenFile('../../assets/icon/app_icon_fg.png'),
    );
  });

  testWidgets('brand sheet', (t) async {
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(1600, 900);
    addTearDown(t.view.reset);
    await t.pumpWidget(
      plain(
        bg: Palette.paper,
        Wrap(
          spacing: 28,
          runSpacing: 20,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const DuckLogo(size: 150, tile: true),
            const DuckLogo(size: 64),
            for (final st in DuckStage.values) DuckMascot(size: 120, stage: st),
            const DuckMascot(size: 120, mood: DuckMood.cheer),
            const DuckMascot(size: 120, mood: DuckMood.sleepy),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/brand.png'),
    );
  });
}
