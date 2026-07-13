import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class CyberAlertDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final Color borderColor;
  final Color titleColor;

  const CyberAlertDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.borderColor = AppColors.accentSecondary,
    this.titleColor = AppColors.accentSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor.withValues(alpha: 0.5),
            width: 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 8),
                  child: const SizedBox(height: 1),
                ),
              ),
              Positioned.fill(
                child: Container(
                  color: AppColors.background.withValues(alpha: 0.10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DefaultTextStyle(
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      child: content,
                    ),
                    const SizedBox(height: 24),
                    if (actions.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
