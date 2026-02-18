import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class SshStatusBar extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback onExit;

  const SshStatusBar({
    super.key,
    required this.isConnected,
    required this.isConnecting,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onExit,
            child: const Row(
              children: [
                Icon(Icons.chevron_left, color: AppColors.neonCyan, size: 14),
                Text(
                  "EXIT",
                  style: TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Icon(
            Icons.circle,
            color: isConnected ? AppColors.matrixGreen : AppColors.errorRed,
            size: 6,
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? "UPLINK_STABLE" : "OFFLINE",
            style: const TextStyle(
              fontSize: 8,
              color: AppColors.textGrey,
              fontFamily: 'Courier',
            ),
          ),
          const Spacer(),
          if (isConnecting)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1,
                color: AppColors.neonCyan,
              ),
            ),
          const SizedBox(width: 8),
          const Text(
            "FRANKN_SHELL_v1.0",
            style: TextStyle(
              fontSize: 8,
              color: AppColors.textGrey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
