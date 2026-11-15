// Renders the README banner (docs/banner.png): the round logo and words on the left, the
// app's Home screen on the right. Uses the real logo and the real Home preview, so run
// the screen previews first:
//   flutter test --update-goldens --tags golden test/ui/screen_preview_test.dart
//   flutter test --update-goldens --tags golden test/ui/banner_test.dart
@Tags(['golden'])
library;

import 'dart:io';

import 'package:duk/ui/logo.dart';
import 'package:duk/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

void main() {
  testWidgets('readme banner', (t) async {
    await loadFont('NotoSansHK', 'assets/fonts/NotoSansHK.ttf');
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1600, 800);
    addTearDown(t.view.reset);

    final Uint8List shot = File(
      'test/ui/goldens/preview_phone_home_day2.png',
    ).readAsBytesSync();
    final image = MemoryImage(shot);

    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dukTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            return RepaintBoundary(
              key: const ValueKey('banner'),
              child: Container(
                width: 1600,
                height: 800,
                color: Palette.cream,
                padding: const EdgeInsets.fromLTRB(120, 0, 140, 0),
                child: Row(
                  children: [
                    // left: the round logo and the words
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // the icon in a round mask
                          const ClipOval(
                            child: DuckLogo(size: 168, tile: true),
                          ),
                          const SizedBox(height: 36),
                          Text(
                            'DuckLearn',
                            style: theme.textTheme.displayMedium?.copyWith(
                              fontSize: 92,
                              fontWeight: FontWeight.w700,
                              color: Palette.bark,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'A beginner-friendly app\nfor learning Cantonese.',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 38,
                              fontWeight: FontWeight.w400,
                              color: Palette.barkSoft,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Real Macau and Hong Kong sentences · Jyutping help that fades as you learn',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                              color: Palette.terraDeep,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // right: the app itself, in a simple phone frame
                    Container(
                      width: 330,
                      height: 680,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Palette.bark,
                        borderRadius: BorderRadius.circular(48),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(38),
                        child: Image(image: image, fit: BoxFit.cover),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await t.runAsync(() async {
      final el = t.element(find.byType(Image));
      await precacheImage(image, el);
    });
    await t.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('banner')),
      matchesGoldenFile('../../../docs/banner.png'),
    );
  });
}
