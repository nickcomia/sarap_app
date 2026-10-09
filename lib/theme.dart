import 'package:flutter/material.dart';

/// Colors and text styles lifted from the "User Design Interface" mockups
/// in the SARAP capstone manuscript (Figures 7-16): a warm coral/orange
/// primary color, dark navy headings, soft off-white backgrounds, and
/// generously rounded cards & buttons.
class AppColors {
  static const Color primary = Color(0xFFFF6B4A); // coral / orange
  static const Color primaryDark = Color(0xFFE85A3A);
  static const Color secondary = Color(0xFF2ECC91); // fresh green (BMI badge, match %)
  static const Color navy = Color(0xFF1F2A44); // headings / dark text
  static const Color background = Color(0xFFF7F7FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color chipBg = Color(0xFFF1F1F5);
  static const Color chipSelectedBg = Color(0xFFFFE7DF);
  static const Color muted = Color(0xFF8A8FA3);
  static const Color border = Color(0xFFE7E7EE);
  static const Color danger = Color(0xFFE8544E);
}

class AppColorsDark {
  static const Color primary = Color(0xFFFF7A5C);
  static const Color primaryDark = Color(0xFFFF6B4A);
  static const Color secondary = Color(0xFF3EE0A0);
  static const Color textPrimary = Color(0xFFF3F4F8);
  static const Color background = Color(0xFF12141C);
  static const Color card = Color(0xFF1B1E2A);
  static const Color chipBg = Color(0xFF232636);
  static const Color chipSelectedBg = Color(0xFF3A2A28);
  static const Color muted = Color(0xFF9098AC);
  static const Color border = Color(0xFF2A2E3D);
  static const Color danger = Color(0xFFFF6B6B);
}

/// Resolves the correct color for the current theme (light or dark) from
/// a BuildContext — use this instead of AppColors.* directly in any widget
/// that needs to look correct in both modes.
class AppColorsOf {
  final BuildContext context;
  AppColorsOf(this.context);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get primary => _isDark ? AppColorsDark.primary : AppColors.primary;
  Color get primaryDark => _isDark ? AppColorsDark.primaryDark : AppColors.primaryDark;
  Color get secondary => _isDark ? AppColorsDark.secondary : AppColors.secondary;
  Color get navy => _isDark ? AppColorsDark.textPrimary : AppColors.navy;
  Color get background => _isDark ? AppColorsDark.background : AppColors.background;
  Color get card => _isDark ? AppColorsDark.card : AppColors.card;
  Color get chipBg => _isDark ? AppColorsDark.chipBg : AppColors.chipBg;
  Color get chipSelectedBg => _isDark ? AppColorsDark.chipSelectedBg : AppColors.chipSelectedBg;
  Color get muted => _isDark ? AppColorsDark.muted : AppColors.muted;
  Color get border => _isDark ? AppColorsDark.border : AppColors.border;
  Color get danger => _isDark ? AppColorsDark.danger : AppColors.danger;
}

/// Shorthand: AppColorsOf(context).card instead of the long form above.
extension AppColorsContext on BuildContext {
  AppColorsOf get colors => AppColorsOf(this);
}

/// Consistent spacing scale — use these instead of one-off SizedBox heights
/// so vertical rhythm matches across every screen.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double xxl = 40;
}

/// Consistent corner radii — match the rounded style already used on
/// buttons and inputs so cards, sheets, and dialogs feel like one system.
class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 16;
  static const double xl = 22;
}

/// Soft, layered shadows for a modern elevated look — replaces flat
/// 1px borders with subtle depth.
class AppShadows {
  static List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.navy.withValues(alpha: 0.06),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
  static List<BoxShadow> soft = [
    BoxShadow(
      color: AppColors.navy.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
  static List<BoxShadow> floating = [
    BoxShadow(
      color: AppColors.navy.withValues(alpha: 0.12),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}

/// Reusable gradients for hero sections, badges, and accents.
class AppGradients {
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryDark],
  );
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A3A5C), AppColors.navy],
  );
  static const LinearGradient secondary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34D399), AppColors.secondary],
  );
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
          height: 1.2,
        ),
        headlineSmall: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
        bodyLarge: const TextStyle(fontSize: 15, color: AppColors.navy),
        bodyMedium: const TextStyle(fontSize: 13.5, color: AppColors.muted),
        labelLarge: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.border, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.chipBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
        hintStyle: const TextStyle(color: AppColors.muted),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.chipBg,
        selectedColor: AppColors.chipSelectedBg,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide.none,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
        contentTextStyle: const TextStyle(fontSize: 14, color: AppColors.muted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.navy, size: 22),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.border,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.15),
        trackHeight: 5,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.muted,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColorsDark.primary,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AppColorsDark.background,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppColorsDark.textPrimary,
          height: 1.2,
        ),
        headlineSmall: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: AppColorsDark.textPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColorsDark.textPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColorsDark.textPrimary,
        ),
        bodyLarge: const TextStyle(fontSize: 15, color: AppColorsDark.textPrimary),
        bodyMedium: const TextStyle(fontSize: 13.5, color: AppColorsDark.muted),
        labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColorsDark.background,
        foregroundColor: AppColorsDark.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColorsDark.textPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorsDark.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColorsDark.textPrimary,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColorsDark.border, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColorsDark.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColorsDark.chipBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColorsDark.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColorsDark.danger, width: 1.4),
        ),
        hintStyle: const TextStyle(color: AppColorsDark.muted),
      ),
      cardTheme: CardThemeData(
        color: AppColorsDark.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColorsDark.border, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColorsDark.border,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColorsDark.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColorsDark.textPrimary,
        ),
        contentTextStyle: const TextStyle(fontSize: 14, color: AppColorsDark.muted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColorsDark.card,
        contentTextStyle: const TextStyle(color: AppColorsDark.textPrimary, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      iconTheme: const IconThemeData(color: AppColorsDark.textPrimary, size: 22),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColorsDark.primary,
        inactiveTrackColor: AppColorsDark.border,
        thumbColor: AppColorsDark.primary,
        overlayColor: AppColorsDark.primary.withValues(alpha: 0.15),
        trackHeight: 5,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColorsDark.card,
        selectedItemColor: AppColorsDark.primary,
        unselectedItemColor: AppColorsDark.muted,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}