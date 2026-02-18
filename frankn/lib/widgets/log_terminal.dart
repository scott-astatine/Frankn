import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class LogTerminal extends StatelessWidget {
  final List<String> logs;
  final VoidCallback onToggleExpand;
  final VoidCallback onMinimize;
  final VoidCallback onFullscreen;
  final bool isExpanded;
  final bool isMinimized;

  const LogTerminal({
    super.key,
    required this.logs,
    required this.onToggleExpand,
    required this.onMinimize,
    required this.onFullscreen,
    this.isExpanded = false,
    this.isMinimized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.voidBlack.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: AppColors.neonCyan.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonCyan.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                color: AppColors.neonCyan.withValues(alpha: 0.05),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.terminal,
                          color: AppColors.matrixGreen,
                          size: 12,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "TERMINAL_OUT // ${isMinimized ? 'MIN' : 'ACT'}",
                          style: const TextStyle(
                            color: AppColors.neonCyan,
                            fontSize: 8,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildHeaderBtn(
                          isMinimized
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          onMinimize,
                        ),
                        _buildHeaderBtn(Icons.unfold_more, onToggleExpand),
                        _buildHeaderBtn(Icons.fullscreen, onFullscreen),
                      ],
                    ),
                  ],
                ),
              ),

              // Log List (Hide if minimized)
              if (!isMinimized)
                SizedBox(
                  height: 1000, // Large enough to fill available space
                  child: SelectionArea(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: _buildRichLogLine(logs[index]),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBtn(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(
        icon,
        color: AppColors.neonCyan.withValues(alpha: 0.6),
        size: 16,
      ),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildRichLogLine(String log) {
    log = log.toLowerCase();
    Color textColor = AppColors.matrixGreen;

    if (log.contains("error") || log.contains("failed")) {
      textColor = AppColors.errorRed;
    } else if (log.contains("warn") || log.contains("debug")) {
      textColor = AppColors.cyberYellow;
    } else if (log.contains("host")) {
      textColor = AppColors.neonPink;
    } else if (log.contains("success") || log.contains("granted")) {
      textColor = AppColors.neonCyan;
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: log.startsWith(">") ? "> " : "",
            style: const TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: log.startsWith(">") ? log.substring(2) : log,
            style: TextStyle(
              color: textColor,
              fontFamily: 'Courier',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
