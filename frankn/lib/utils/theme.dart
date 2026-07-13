import 'package:flutter/material.dart';

class ColorPalette {
  // Backgrounds
  static const Color voidBlack = Color(0xFF050505);
  static const Color deepSpace = Color(0xFF0B0D17);
  static const Color panelGrey = Color(0xFF1A1A2E);

  // Neon Accents
  static const Color neonCyan = Color(0xFF00F3FF);
  static const Color neonPink = Color(0xFFFF00FF);
  static const Color cyberYellow = Color(0xFFFFEE00);
  static const Color matrixGreen = Color(0xFF00FF41);
  static const Color neonRed = Color(0xeecc203A);

  // Markdown Theme Colors
  static const Color indigoAccent = Color(0xFF6366F1);
  static const Color indigoLight = Color(0xFF818CF8);
  static const Color fuchsiaAccent = Color(0xccbe4899);
  static const Color fuchsiaAccentLight = Color(0xFFEC4899);

  // Neo / Chat Theme Colors
  static const Color backgroundNeo = Color(0xFF09090B);
  static const Color darkZincNeo = Color(0xFF18181B);
  static const Color zincNeo = Color(0xFF71717A);
  static const Color cyanNeo = Color(0xFF06B6D4);
  static const Color fuchsiaNeo = Color(0xFFD946EF);
  static const Color matrixGreenNeo = Color(0xFF10B981);

  // Functional Colors
  static const Color errorRed = Color(0xFFFF2A2A);
  static const Color textWhite = Color(0xFFE0E0E0);
  static const Color textGrey = Color(0xFFAAAAAA);
}

class AppColors {
  // Global Layout Colors
  static const Color background = ColorPalette.voidBlack;
  static const Color surface = ColorPalette.deepSpace;
  static const Color surfaceSecondary = ColorPalette.panelGrey;

  // Semantic Accent Colors
  static const Color accentPrimary = ColorPalette.fuchsiaAccent;
  static const Color accentSecondary = ColorPalette.fuchsiaAccentLight;
  static const Color accentWarning = ColorPalette.cyberYellow;
  static const Color accentSuccess = ColorPalette.matrixGreen;
  static const Color accentDanger = ColorPalette.neonRed;
  static const Color accentError = ColorPalette.errorRed;

  // Typography Colors
  static const Color textPrimary = ColorPalette.textWhite;
  static const Color textSecondary = ColorPalette.textGrey;

  // Component-Specific Mappings: Markdown Viewer
  static const Color markdownPrimary = ColorPalette.fuchsiaAccent;
  static const Color markdownPrimaryLight = ColorPalette.fuchsiaAccentLight;
  static const Color markdownAccent = ColorPalette.indigoLight;
  static const Color markdownBg = ColorPalette.voidBlack;
  static const Color markdownCodeBg = Colors.transparent;
  static const Color markdownSurface = ColorPalette.deepSpace;
  static const Color markdownBorder = ColorPalette.indigoAccent;

  // Component-Specific Mappings: Chat Bubbles (Dohee Chat)
  static final Color chatUserBubbleBg = ColorPalette.neonCyan.withValues(
    alpha: 0.1,
  );
  static const Color chatAiBubbleBg = ColorPalette.panelGrey;
  static const Color chatBubbleBorder = ColorPalette.neonCyan;

  // Component-Specific Mappings: Neo / Chat Interface
  static const Color neoBackground = ColorPalette.backgroundNeo;
  static const Color neoDarkZinc = ColorPalette.darkZincNeo;
  static const Color neoZinc = ColorPalette.zincNeo;
  static const Color neoCyan = ColorPalette.cyanNeo;
  static const Color neoFuchsia = ColorPalette.fuchsiaNeo;
  static const Color neoMatrixGreen = ColorPalette.matrixGreenNeo;
}

class NeoColors {
  static const background = AppColors.neoBackground;
  static const darkZinc = AppColors.neoDarkZinc;
  static const zinc = AppColors.neoZinc;
  static const cyan = AppColors.neoCyan;
  static const fuchsia = AppColors.neoFuchsia;
  static const matrixGreen = AppColors.neoMatrixGreen;
}

class CyberTheme {
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,

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
          color: AppColors.accentPrimary,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textPrimary),
        // Use labelSmall for data labels
        labelSmall: TextStyle(
          fontFamily: 'JetBrainsMonoNerdFont',
          letterSpacing: 1,
          fontSize: 10,
        ),
      ),

      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentPrimary, // Default Status
        secondary: AppColors.accentSecondary, // Media Active
        surface: AppColors.surfaceSecondary,
        error: AppColors.accentError, // Destructive/Kill
        onSurface: AppColors.textPrimary,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
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
