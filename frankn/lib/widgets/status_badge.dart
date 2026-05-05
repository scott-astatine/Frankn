import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class StatusBadge extends StatelessWidget {
  final SignalConnectionState state;
  const StatusBadge({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (state) {
      case SignalConnectionState.connected:
        color = AppColors.matrixGreen;
        break;
      case SignalConnectionState.connecting:
        color = AppColors.cyberYellow;
        break;
      case SignalConnectionState.failed:
        color = AppColors.errorRed;
        break;
      default:
        color = AppColors.textGrey;
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 4,
            spreadRadius: 1,
          )
        ],
      ),
    );
  }
}
