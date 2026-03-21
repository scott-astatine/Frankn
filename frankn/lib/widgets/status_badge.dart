import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class StatusBadge extends StatelessWidget {
  final SignalConnectionState state;
  const StatusBadge({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Color color;
    String text;
    switch (state) {
      case SignalConnectionState.connected:
        color = AppColors.matrixGreen;
        text = l10n.linked;
        break;
      case SignalConnectionState.connecting:
        color = AppColors.cyberYellow;
        text = l10n.syncing;
        break;
      case SignalConnectionState.failed:
        color = AppColors.errorRed;
        text = l10n.error;
        break;
      default:
        color = AppColors.textGrey;
        text = l10n.offline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1A1F),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
