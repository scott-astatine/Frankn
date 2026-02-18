import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class CyberCard extends StatelessWidget {
  final Widget child;
  const CyberCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.panelGrey.withValues(alpha: .9),
        border: Border.all(color: AppColors.neonCyan.withValues(alpha: .5)),
        borderRadius: BorderRadiusGeometry.all(Radius.circular(8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonCyan.withValues(alpha: .1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}
