import 'package:flutter/material.dart';
import 'utils.dart';

class CyberTheme {
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.voidBlack,

      // UI Font: Noto Sans KR for better Korean support, fallback to Inter/Sans-Serif
      fontFamily: 'Noto Sans KR',

      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
          color: Colors.white,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.neonCyan,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textWhite),
        // Use labelSmall for data labels
        labelSmall: TextStyle(
          fontFamily: 'JetBrainsMonoNerdFont',
          letterSpacing: 1,
          fontSize: 10,
        ),
      ),

      colorScheme: const ColorScheme.dark(
        primary: AppColors.neonCyan, // Default Status
        secondary: AppColors.neonPink, // Media Active
        surface: AppColors.panelGrey,
        error: AppColors.errorRed, // Destructive/Kill
        onSurface: AppColors.textWhite,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.voidBlack,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
