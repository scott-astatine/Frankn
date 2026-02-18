import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class StatusBadge extends StatelessWidget {
  final SignalConnectionState state;
  const StatusBadge({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    switch (state) {
      case SignalConnectionState.connected:
        color = AppColors.matrixGreen;
        text = "LINKED";
        break;
      case SignalConnectionState.connecting:
        color = AppColors.cyberYellow;
        text = "SYNCING";
        break;
      case SignalConnectionState.failed:
        color = AppColors.errorRed;
        text = "ERROR";
        break;
      default:
        color = AppColors.textGrey;
        text = "OFFLINE";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
