import 'package:flutter/material.dart';
import 'theme.dart';

/// Admin-only styling layered on top of the shared SARAP theme, so the
/// existing admin pages look cleaner without touching their code: white
/// page headers with a hairline border, branded tabs, coral switches and
/// solid floating buttons. Buttons keep the shared theme (full width) so
/// existing forms lay out exactly as before.
class AdminTheme {
  static ThemeData light() {
    final base = AppTheme.light();
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.border,
        labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.border),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        extendedTextStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.navy,
      ),
    );
  }
} 