import 'package:flutter/material.dart';

import 'data/sample_data.dart';

const appFontFamily = 'PlusJakartaSans';

abstract final class AppColors {
  static const ink = Color(0xFF111111);
  static const inkSoft = Color(0xFF555555);
  static const border = Color(0xFFD4D4D4);
  static const divider = Color(0xFFE6E6E6);
  static const page = Color(0xFFEFEFEF);
  static const panel = Color(0xFFF7F7F7);
  static const iconTile = Color(0xFFF1F1F1);
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
  return ThemeData(
    colorScheme: const ColorScheme.light(
      primary: AppColors.ink,
      onPrimary: Colors.white,
      secondary: AppColors.ink,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.ink,
      outline: AppColors.border,
      error: AppColors.awas,
    ),
    scaffoldBackgroundColor: AppColors.page,
    fontFamily: appFontFamily,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 14, height: 1.35),
      bodyMedium: TextStyle(fontSize: 12, height: 1.35),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        textStyle: const TextStyle(
          fontFamily: appFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        foregroundColor: AppColors.ink,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        textStyle: const TextStyle(
          fontFamily: appFontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}
