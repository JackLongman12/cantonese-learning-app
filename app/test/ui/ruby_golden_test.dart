// Renders real sentences with the bundled fonts to an image, so glyph variants, ruby
// alignment and wrapping can be checked by eye: test/ui/goldens/ruby.png
// Regenerate with: flutter test --update-goldens test/ui/ruby_golden_test.dart
@Tags(['golden'])
library;

import 'dart:io';

import 'package:duk/engine/scaffold.dart';
import 'package:duk/ui/ruby_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

List<RubyToken> toks(
  String text,
  List<String?> readings,
  List<ScaffoldLevel> levels,
) => [
  for (var i = 0; i < text.length; i++)
    RubyToken(
      surface: text[i],
      kind: readings[i] == null ? 'punct' : 'han',
      reading: readings[i],
      level: levels[i % levels.length],
    ),
];

void main() {
  testWidgets('ruby rendering', (t) async {
    await loadFont('NotoSansHK', 'assets/fonts/NotoSansHK.ttf');
    await loadFont('NotoSansSC', 'assets/fonts/NotoSansSC.ttf');
    await t.binding.setSurfaceSize(const Size(560, 620));
    addTearDown(() => t.binding.setSurfaceSize(null));
    const full = [ScaffoldLevel.full];
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF00695C)),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 28,
              children: [
                RubyText(
                  lang: 'yue',
                  tokens: toks('唔該，去關閘要搭幾號巴士？', [
                    'm4',
                    'goi1',
                    null,
                    'heoi3',
                    'gwaan1',
                    'zaap6',
                    'jiu3',
                    'daap3',
                    'gei2',
                    'hou6',
                    'baa1',
                    'si2',
                    null,
                  ], full),
                ),
                RubyText(
                  lang: 'yue',
                  tokens: toks(
                    '我去銀行，行路去。',
                    [
                      'ngo5',
                      'heoi3',
                      'ngan4',
                      'hong4',
                      null,
                      'haang4',
                      'lou6',
                      'heoi3',
                      null,
                    ],
                    const [
                      ScaffoldLevel.none,
                      ScaffoldLevel.tap,
                      ScaffoldLevel.hint,
                      ScaffoldLevel.full,
                    ],
                  ),
                ),
                RubyText(
                  lang: 'cmn',
                  tokens: toks('请问，去关闸要坐几路公交车？', [
                    'qing3',
                    'wen4',
                    null,
                    'qu4',
                    'guan1',
                    'zha2',
                    'yao4',
                    'zuo4',
                    'ji3',
                    'lu4',
                    'gong1',
                    'jiao1',
                    'che1',
                    null,
                  ], full),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/ruby.png'),
    );
  });
}
