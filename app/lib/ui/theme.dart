/// DuckLearn look: ink on rice paper, a cinnabar seal for the one thing that matters on a
/// screen, calligraphy (LXGW WenKai TC) for headings, plain Noto Sans for everything the
/// learner has to read precisely.
library;

import 'package:material_ui/material_ui.dart';

abstract final class Palette {
  static const cinnabar = Color(0xFFC23B22); // 朱
  static const cinnabarDeep = Color(0xFF9E2A16);
  static const ink = Color(0xFF1E1A17); // 墨
  static const inkSoft = Color(0xFF5A524B);
  static const paper = Color(0xFFF6F0E4); // 宣紙
  static const paperDeep = Color(0xFFECE3D1);
  static const jade = Color(0xFF2F6F62); // 青
  static const gold = Color(0xFFB8892B); // 金

  static const night = Color(0xFF171412);
  static const nightRaised = Color(0xFF221E1B);
  static const paperText = Color(0xFFEFE7D6);
  static const cinnabarLight = Color(0xFFE0654D);
}

const brushFont = 'LXGWWenKaiTC';

ThemeData dukTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: Palette.cinnabar,
    brightness: brightness,
  );
  final scheme = base.copyWith(
    primary: dark ? Palette.cinnabarLight : Palette.cinnabar,
    onPrimary: dark ? Palette.night : Palette.paper,
    primaryContainer: dark ? const Color(0xFF4A1E15) : const Color(0xFFF3DCD3),
    onPrimaryContainer: dark ? const Color(0xFFFFDAD1) : Palette.cinnabarDeep,
    secondary: Palette.jade,
    secondaryContainer: dark
        ? const Color(0xFF1F3A34)
        : const Color(0xFFDCEAE5),
    onSecondaryContainer: dark
        ? const Color(0xFFBFE3D8)
        : const Color(0xFF173A33),
    tertiary: Palette.gold,
    surface: dark ? Palette.night : Palette.paper,
    onSurface: dark ? Palette.paperText : Palette.ink,
    onSurfaceVariant: dark ? const Color(0xFFB9AE9E) : Palette.inkSoft,
    surfaceContainerLowest: dark ? Palette.night : const Color(0xFFFBF7EF),
    surfaceContainerLow: dark ? Palette.nightRaised : const Color(0xFFFBF7EF),
    surfaceContainer: dark ? Palette.nightRaised : const Color(0xFFF1E9DA),
    surfaceContainerHigh: dark ? const Color(0xFF2B2622) : Palette.paperDeep,
    surfaceContainerHighest: dark
        ? const Color(0xFF35302B)
        : const Color(0xFFE4D9C4),
    outline: dark ? const Color(0xFF7D7367) : const Color(0xFF9C9182),
    outlineVariant: dark ? const Color(0xFF3D3732) : const Color(0xFFDCD1BE),
  );
  final t = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'NotoSansHK',
    scaffoldBackgroundColor: scheme.surface,
  );
  TextStyle? brush(TextStyle? s, {FontWeight w = FontWeight.w700}) =>
      s?.copyWith(fontFamily: brushFont, fontWeight: w, letterSpacing: 0.5);
  return t.copyWith(
    textTheme: t.textTheme.copyWith(
      displaySmall: brush(t.textTheme.displaySmall),
      headlineMedium: brush(t.textTheme.headlineMedium),
      headlineSmall: brush(t.textTheme.headlineSmall),
      titleLarge: brush(t.textTheme.titleLarge),
      titleMedium: brush(t.textTheme.titleMedium),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: brush(t.textTheme.titleLarge)
          ?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(
          fontFamily: 'NotoSansHK',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.onSurface,
        selectedForegroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
