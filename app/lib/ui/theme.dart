/// DuckLearn look: warm and calm. Cream paper, oat tiles, one soft terracotta accent for
/// the thing that matters on a screen, muted sage for "done", and yolk yellow for the
/// ducks. Plain Noto Sans everywhere (readable first). Older names stay as aliases.
library;

import 'package:material_ui/material_ui.dart';

abstract final class Palette {
  // warm terracotta (light)
  static const cream = Color(0xFFF7F2EA);
  static const oat = Color(0xFFEEE6D9);
  static const terra = Color(0xFFB5725A);
  static const terraSoft = Color(0xFFF2E3D7);
  static const terraDeep = Color(0xFF8A4F3A);
  static const bark = Color(0xFF3F3731);
  static const barkSoft = Color(0xFF7D7166);
  static const line = Color(0xFFE2D8C9);
  static const sage = Color(0xFFE3E7D9);
  static const sageDeep = Color(0xFF5F6F4F);
  static const yolk = Color(0xFFEFCB7E);
  static const yolkDeep = Color(0xFFE2B65F);
  static const shell = Color(0xFFFBF7F0);
  static const blush = Color(0xFFEDA98F);
  static const mama = Color(0xFFF7F1E7);

  // dark
  static const night = Color(0xFF2B2623);
  static const nightRaised = Color(0xFF36302B);
  static const terraLight = Color(0xFFC98E72);
  static const terraNight = Color(0xFF47372E);
  static const terraPale = Color(0xFFE7B9A2);
  static const paperText = Color(0xFFEFE6DA);
  static const paperTextSoft = Color(0xFFB4A897);
  static const lineNight = Color(0xFF463E37);

  // the app icon's own colors (logo, older mascot): unchanged so the icon stays the same
  static const cinnabar = Color(0xFFC23B22);
  static const cinnabarDeep = Color(0xFF9E2A16);
  static const ink = Color(0xFF1E1A17);
  static const inkSoft = Color(0xFF5A524B);
  static const paper = Color(0xFFF6F0E4);
  static const paperDeep = Color(0xFFECE3D1);
  static const jade = Color(0xFF2F6F62);
  static const gold = Color(0xFFB8892B);
  static const cinnabarLight = Color(0xFFE0654D);
}

/// Kept for older callers; headings now use the reading font.
const brushFont = 'NotoSansHK';

ThemeData dukTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: Palette.terra,
    brightness: brightness,
  );
  final scheme = base.copyWith(
    primary: dark ? Palette.terraLight : Palette.terra,
    onPrimary: dark ? Palette.night : const Color(0xFFFFF9F2),
    primaryContainer: dark ? Palette.terraNight : Palette.terraSoft,
    onPrimaryContainer: dark ? Palette.terraPale : Palette.terraDeep,
    secondary: dark ? const Color(0xFFBCC9A8) : Palette.sageDeep,
    secondaryContainer: dark ? const Color(0xFF363C30) : Palette.sage,
    onSecondaryContainer: dark ? const Color(0xFFBCC9A8) : Palette.sageDeep,
    tertiary: dark ? const Color(0xFFC9A866) : Palette.yolkDeep,
    tertiaryContainer: dark ? const Color(0xFF4A3F28) : const Color(0xFFF6E6C2),
    onTertiaryContainer: dark
        ? const Color(0xFFEBD6A6)
        : const Color(0xFF6B5320),
    error: dark ? const Color(0xFFE29A86) : const Color(0xFFB0533F),
    surface: dark ? Palette.night : Palette.cream,
    onSurface: dark ? Palette.paperText : Palette.bark,
    onSurfaceVariant: dark ? Palette.paperTextSoft : Palette.barkSoft,
    surfaceContainerLowest: dark ? Palette.night : Palette.shell,
    surfaceContainerLow: dark ? Palette.nightRaised : Palette.oat,
    surfaceContainer: dark ? Palette.nightRaised : Palette.oat,
    surfaceContainerHigh: dark
        ? const Color(0xFF3D3631)
        : const Color(0xFFE8DECF),
    surfaceContainerHighest: dark ? const Color(0xFF443C36) : Palette.line,
    outline: dark ? const Color(0xFF7D7367) : const Color(0xFFA89B8C),
    outlineVariant: dark ? Palette.lineNight : Palette.line,
  );
  final t = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'NotoSansHK',
    scaffoldBackgroundColor: scheme.surface,
  );
  TextStyle? head(TextStyle? s) => s?.copyWith(fontWeight: FontWeight.w600);
  return t.copyWith(
    textTheme: t.textTheme.copyWith(
      displaySmall: head(t.textTheme.displaySmall),
      headlineMedium: head(t.textTheme.headlineMedium),
      headlineSmall: head(t.textTheme.headlineSmall),
      titleLarge: head(t.textTheme.titleLarge),
      titleMedium: head(t.textTheme.titleMedium),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: head(t.textTheme.titleLarge)
          ?.copyWith(color: scheme.onSurface),
    ),
    // flat tiles: no borders, no shadows
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(
          fontFamily: 'NotoSansHK',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
