import 'package:flutter/material.dart';
import 'utils.dart';

class CyberTheme {
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.voidBlack,
      primaryColor: AppColors.neonCyan,

      // Typography: Monospaced for that terminal feel
      fontFamily: 'Courier',

      // Global Text Theme - Bolder for readability
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textWhite,
        ),
        bodyLarge: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textWhite,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.neonCyan,
        ),
      ),

      colorScheme: const ColorScheme.dark(
        primary: AppColors.neonCyan,
        secondary: AppColors.neonPink,
        surface: AppColors.panelGrey,
        error: AppColors.errorRed,
        onPrimary: AppColors.voidBlack,
        onSurface: AppColors.textWhite,
      ),

      // App Bar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.voidBlack,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.neonCyan,
          fontFamily: 'Courier',
          fontWeight: FontWeight.bold,
          fontSize: 20,
          letterSpacing: 1.5,
        ),
        iconTheme: IconThemeData(color: AppColors.neonCyan),
      ),

      // Card Theme (Glass-like panels)
      // Using CardThemeData as requested for your specific Flutter environment
      cardTheme: CardThemeData(
        color: AppColors.panelGrey.withValues(alpha: 0.8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          side: const BorderSide(color: AppColors.neonCyan, width: 1),
        ),
        elevation: 10,
        shadowColor: AppColors.neonCyan.withValues(alpha: 0.3),
      ),

      // Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.neonCyan.withValues(alpha: 0.1),
          foregroundColor: AppColors.neonCyan,
          side: const BorderSide(color: AppColors.neonCyan),
          shape: const BeveledRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
