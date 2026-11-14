import 'package:duk/engine/scaffold.dart';
import 'package:duk/ui/ruby_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {double width = 400}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(width: width, child: child),
  ),
);

String rubyAt(WidgetTester t, int i) =>
    t.widget<Text>(find.byKey(ValueKey('ruby-$i'))).data ?? '';

void main() {
  const tokens = [
    RubyToken(
      surface: '銀',
      kind: 'han',
      reading: 'ngan4',
      level: ScaffoldLevel.full,
    ),
    RubyToken(
      surface: '行',
      kind: 'han',
      reading: 'hong4',
      level: ScaffoldLevel.hint,
    ),
    RubyToken(surface: '，', kind: 'punct'),
    RubyToken(
      surface: '行',
      kind: 'han',
      reading: 'haang4',
      level: ScaffoldLevel.tap,
    ),
    RubyToken(
      surface: '路',
      kind: 'han',
      reading: 'lou6',
      level: ScaffoldLevel.none,
    ),
    RubyToken(surface: 'MOP', kind: 'latin'),
  ];

  testWidgets('each level shows exactly the help it should', (t) async {
    await t.pumpWidget(host(const RubyText(tokens: tokens, lang: 'yue')));
    expect(rubyAt(t, 0), 'ngan4');
    expect(rubyAt(t, 1), '4');
    expect(rubyAt(t, 3), '');
    expect(rubyAt(t, 4), '');
    expect(rubyAt(t, 5), '');
    expect(find.text('haang4'), findsNothing);
  });

  testWidgets('tap reveals tap/hint levels; mastered needs a long-press', (
    t,
  ) async {
    final revealed = <int>[];
    await t.pumpWidget(
      host(RubyText(tokens: tokens, lang: 'yue', onReveal: revealed.add)),
    );
    await t.tap(find.byKey(const ValueKey('cell-3')));
    await t.tap(find.byKey(const ValueKey('cell-1')));
    await t.tap(
      find.byKey(const ValueKey('cell-4')),
    ); // mastered: a tap does nothing
    await t.tap(
      find.byKey(const ValueKey('cell-0')),
    ); // already shown: nothing to reveal
    expect(revealed, [3, 1]);
    await t.longPress(find.byKey(const ValueKey('cell-4')));
    expect(revealed, [3, 1, 4]);
    expect(
      find.byKey(const ValueKey('cell-2')),
      findsNothing,
    ); // punctuation is inert
  });

  testWidgets('a revealed token shows its full reading', (t) async {
    await t.pumpWidget(
      host(
        const RubyText(
          lang: 'yue',
          tokens: [
            RubyToken(
              surface: '行',
              kind: 'han',
              reading: 'haang4',
              level: ScaffoldLevel.tap,
              revealed: true,
            ),
          ],
        ),
      ),
    );
    expect(rubyAt(t, 0), 'haang4');
  });

  test('Chinese text uses the Hong Kong font and locale', () {
    final style = chineseStyle('yue', fontSize: 10);
    expect(style.fontFamily, 'NotoSansHK');
    expect(style.locale, const Locale('zh', 'HK'));
  });

  testWidgets(
    'wraps long text without overflow and never starts a line with punctuation',
    (t) async {
      final long = [
        for (var i = 0; i < 40; i++) ...[
          const RubyToken(surface: '長', kind: 'han', reading: 'coeng4'),
          if (i % 4 == 3) const RubyToken(surface: '，', kind: 'punct'),
        ],
      ];
      await t.pumpWidget(
        host(
          SingleChildScrollView(
            child: RubyText(tokens: long, lang: 'yue'),
          ),
          width: 300,
        ),
      );
      expect(t.takeException(), isNull);
      final commas = find.text('，');
      expect(commas, findsNWidgets(10));
      for (final e in commas.evaluate()) {
        final box = e.renderObject! as RenderBox;
        expect(box.localToGlobal(Offset.zero).dx, greaterThan(1));
      }
    },
  );
}
