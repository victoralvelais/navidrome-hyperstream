import 'package:flutter/material.dart';

/// Keep the visual palette here so restyling does not touch playback code.
ThemeData hyperstreamTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xfffa365a),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xffff526f) : const Color(0xffd92048),
        onPrimary: Colors.white,
        onSurface: dark ? const Color(0xfff5f5f7) : const Color(0xff151518),
        onSurfaceVariant: dark
            ? const Color(0xffb9bbc5)
            : const Color(0xff656570),
        surface: dark ? const Color(0xff08080a) : const Color(0xfff7f7fa),
        surfaceContainer: dark ? const Color(0xff141416) : Colors.white,
        surfaceContainerHighest: dark
            ? const Color(0xff303036)
            : const Color(0xffeeedf1),
      );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -.35,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 17,
        letterSpacing: -.35,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 15,
        letterSpacing: -.2,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(letterSpacing: -.15),
      labelMedium: base.textTheme.labelMedium?.copyWith(letterSpacing: 0),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: base.textTheme.bodyLarge?.copyWith(
        color: scheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -.35,
      ),
      subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        fontSize: 14,
        letterSpacing: -.15,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    sliderTheme: const SliderThemeData(trackHeight: 3),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .5),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}
