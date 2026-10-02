import 'package:flutter/material.dart';

const kAccent = Color(0xFFE5484D);
const kBackground = Color(0xFF0D0E12);
const kSurface = Color(0xFF16181F);
const kSurfaceHigh = Color(0xFF1F222B);
const kOutline = Color(0xFF2B2F3A);
const kTextDim = Color(0xFF9AA0AE);

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: kAccent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: kAccent,
        onPrimary: Colors.white,
        surface: kBackground,
        surfaceContainerLowest: kBackground,
        surfaceContainerLow: kSurface,
        surfaceContainer: kSurface,
        surfaceContainerHigh: kSurfaceHigh,
        surfaceContainerHighest: kSurfaceHigh,
        outline: kOutline,
        outlineVariant: kOutline,
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBackground,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: kBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kOutline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceHigh,
      hintStyle: const TextStyle(color: kTextDim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kAccent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: Colors.white,
        side: const BorderSide(color: kOutline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kSurfaceHigh,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(color: kOutline, space: 1),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 3,
      activeTrackColor: kAccent,
      inactiveTrackColor: Colors.white24,
      thumbColor: kAccent,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
  );
}

/// Stable colour for a person's name.
Color colorForUser(String id) {
  const palette = [
    Color(0xFFFF8A80),
    Color(0xFFFFB74D),
    Color(0xFFFFF176),
    Color(0xFFA5D6A7),
    Color(0xFF80DEEA),
    Color(0xFF90CAF9),
    Color(0xFFB39DDB),
    Color(0xFFF48FB1),
  ];
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}
