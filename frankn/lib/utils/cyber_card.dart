import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class CyberCard extends StatelessWidget {
  final Widget child;
  final Color? borderColor;
  final Color? bgColor;
  final String? label;

  const CyberCard({
    super.key,
    required this.child,
    this.borderColor,
    this.label,
    this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color:
            bgColor ??
            AppColors.surface.withValues(alpha: 0.3), // Deep deck grey
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.05),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16), // Rounded as per design
      ),
      child: child,
    );
  }
}
