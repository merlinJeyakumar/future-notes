import 'package:flutter/material.dart';

/// Centralized color definitions for the app's design system.
/// Provides both light and dark mode color palettes.
class AppColors {
  // Dark mode colors
  static const darkBackground = Color(0xFF1A202C);
  static const darkSurface = Color(0xFF2D3748);
  static const darkSurfaceVariant = Color(0xFF1E293B);
  static const darkSidebar = Color(0xFF161E2D);
  static const darkPrimary = Color(0xFF60A5FA);
  static const darkAccent = Color(0xFF48BB78);
  static const darkTextPrimary = Color(0xFFE2E8F0);
  static const darkTextSecondary = Color(0xFFA0AEC0);
  static const darkSubtleGray = Color(0xFF94A3B8);
  static const darkDivider = Color(0xFF4A5568);
  static const darkBorder = Color(0xFF334155);

  // Light mode colors
  static const lightBackground = Color(0xFFF7FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVariant = Color(0xFFF1F5F9);
  static const lightSidebar = Color(0xFFEDF2F7);
  static const lightPrimary = Color(0xFF2563A6);
  static const lightAccent = Color(0xFF38A169);
  static const lightTextPrimary = Color(0xFF1A202C);
  static const lightTextSecondary = Color(0xFF4A5568);
  static const lightSubtleGray = Color(0xFF526175);
  static const lightDivider = Color(0xFFE2E8F0);
  static const lightBorder = Color(0xFFCBD5E0);
}

/// Extension on ThemeData to provide easy access to custom app colors.
extension AppThemeExtension on ThemeData {
  /// Returns the appropriate colors based on brightness
  bool get isDark => brightness == Brightness.dark;

  Color get appBackground =>
      isDark ? AppColors.darkBackground : AppColors.lightBackground;
  Color get appSurface =>
      isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get appSurfaceVariant =>
      isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant;
  Color get appSidebar =>
      isDark ? AppColors.darkSidebar : AppColors.lightSidebar;
  Color get appPrimary =>
      isDark ? AppColors.darkPrimary : AppColors.lightPrimary;
  Color get appAccent => isDark ? AppColors.darkAccent : AppColors.lightAccent;
  Color get appTextPrimary =>
      isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get appTextSecondary =>
      isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get appSubtleGray =>
      isDark ? AppColors.darkSubtleGray : AppColors.lightSubtleGray;
  Color get appDivider =>
      isDark ? AppColors.darkDivider : AppColors.lightDivider;
  Color get appBorder => isDark ? AppColors.darkBorder : AppColors.lightBorder;
}

/// Main theme configuration class
class AppTheme {
  static ThemeData get darkTheme {
    final base = ThemeData.dark();
    return base.copyWith(
      // Resolve Material's size geometry before scaling inherited color styles.
      textTheme: base.typography.englishLike
          .merge(base.textTheme)
          .apply(fontSizeFactor: .7776),
      primaryTextTheme: base.typography.englishLike
          .merge(base.primaryTextTheme)
          .apply(fontSizeFactor: .7776),
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkPrimary,
        secondary: AppColors.darkAccent,
        surface: AppColors.darkSurface,
        onPrimary: AppColors.darkBackground,
        onSecondary: Colors.white,
        onSurface: AppColors.darkTextPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSidebar,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.darkDivider,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkPrimary),
        ),
        hintStyle: const TextStyle(color: AppColors.darkSubtleGray),
        labelStyle: const TextStyle(color: AppColors.darkSubtleGray),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkTextSecondary,
          side: const BorderSide(color: AppColors.darkBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.darkPrimary),
      ),
      iconTheme: const IconThemeData(color: AppColors.darkTextSecondary),
      listTileTheme: const ListTileThemeData(
        textColor: AppColors.darkTextPrimary,
        iconColor: AppColors.darkTextSecondary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkSurface,
        contentTextStyle: const TextStyle(color: AppColors.darkTextPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData.light();
    return base.copyWith(
      textTheme: base.typography.englishLike
          .merge(base.textTheme)
          .apply(fontSizeFactor: .7776),
      primaryTextTheme: base.typography.englishLike
          .merge(base.primaryTextTheme)
          .apply(fontSizeFactor: .7776),
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightPrimary,
        secondary: AppColors.lightAccent,
        surface: AppColors.lightSurface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.lightTextPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSidebar,
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.lightBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightDivider,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightPrimary),
        ),
        hintStyle: const TextStyle(color: AppColors.lightSubtleGray),
        labelStyle: const TextStyle(color: AppColors.lightSubtleGray),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.lightPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightTextSecondary,
          side: const BorderSide(color: AppColors.lightBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.lightPrimary),
      ),
      iconTheme: const IconThemeData(color: AppColors.lightTextSecondary),
      listTileTheme: const ListTileThemeData(
        textColor: AppColors.lightTextPrimary,
        iconColor: AppColors.lightTextSecondary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.lightSurface,
        contentTextStyle: const TextStyle(color: AppColors.lightTextPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
