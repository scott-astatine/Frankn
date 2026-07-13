import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class GlassyHeader extends StatelessWidget {
  final bool innerBoxIsScrolled;
  final Widget child;
  final double height;
  final Color accentColor;

  const GlassyHeader({
    super.key,
    required this.innerBoxIsScrolled,
    required this.child,
    this.height = 64.0,
    this.accentColor = AppColors.neonCyan,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: innerBoxIsScrolled
                ? AppColors.deepSpace.withValues(alpha: 0.6)
                : AppColors.deepSpace.withValues(alpha: 0.9),
            border: Border(
              bottom: BorderSide(
                color: innerBoxIsScrolled
                    ? Colors.transparent
                    : accentColor.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.only(top: 18, left: 8, right: 8),
          child: child,
        ),
      ),
    );
  }
}
