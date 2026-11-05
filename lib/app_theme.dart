import 'package:flutter/material.dart';

import 'data/sample_data.dart';

const appFontFamily = 'AtkinsonHyperlegible';

abstract final class AppColors {
  static const ink = Color(0xFF111111);
  static const inkSoft = Color(0xFF444444);
  static const outline = Color(0xFF767676);
  static const divider = Color(0xFFD4D4D4);
  static const mapBackground = Color(0xFFE8E8E8);
  static const stale = Color(0xFF595959);

  static const normal = Color(0xFF1F6B3F);
  static const waspada = Color(0xFFF2B60C);
  static const awas = Color(0xFFA91F1A);
}

extension MonitoringStatusColors on MonitoringStatus {
  Color get background => switch (this) {
    MonitoringStatus.normal => AppColors.normal,
    MonitoringStatus.waspada => AppColors.waspada,
    MonitoringStatus.awas => AppColors.awas,
    MonitoringStatus.noData => AppColors.stale,
  };

  Color get foreground =>
      this == MonitoringStatus.waspada ? AppColors.ink : Colors.white;
}

ThemeData buildAppTheme() {
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );

  return ThemeData(
    colorScheme: const ColorScheme.light(
      primary: AppColors.ink,
      onPrimary: Colors.white,
      secondary: AppColors.ink,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.ink,
      outline: AppColors.outline,
      error: AppColors.awas,
    ),
    scaffoldBackgroundColor: Colors.white,
    fontFamily: appFontFamily,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
      headlineSmall: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 18, height: 1.35),
      bodyMedium: TextStyle(fontSize: 18, height: 1.35),
      labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: appFontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: AppColors.ink,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.ink, width: 1.5),
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: appFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
  );
}
