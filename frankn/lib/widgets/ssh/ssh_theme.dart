import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:frankn/utils/utils.dart';

class SshTheme {
  static final terminalTheme = TerminalTheme(
    cursor: AppColors.neonCyan,
    selection: AppColors.neonCyan.withValues(alpha: 0.3),
    foreground: AppColors.textWhite,
    background: Colors.transparent,
    black: const Color(0xFF000000),
    red: AppColors.errorRed,
    green: AppColors.matrixGreen,
    yellow: AppColors.cyberYellow,
    blue: const Color(0xFF0066FF),
    magenta: AppColors.neonPink,
    cyan: AppColors.neonCyan,
    white: const Color(0xFFFFFFFF),
    brightBlack: const Color(0xFF666666),
    brightRed: const Color(0xFFFF3333),
    brightGreen: const Color(0xFF33FF33),
    brightYellow: const Color(0xFFFFFF33),
    brightBlue: const Color(0xFF33CCFF),
    brightMagenta: const Color(0xFFFF66FF),
    brightCyan: const Color(0xFF66FFFF),
    brightWhite: const Color(0xFFFFFFFF),
    searchHitBackground: AppColors.cyberYellow,
    searchHitBackgroundCurrent: AppColors.neonPink,
    searchHitForeground: AppColors.voidBlack,
  );
}
