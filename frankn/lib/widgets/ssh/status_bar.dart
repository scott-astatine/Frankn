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
      height: 32, // Slightly taller for the solid button look
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
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
          const SizedBox(width: 16),
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
          const Spacer(),
          GestureDetector(
            onTap: onExit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: const BoxDecoration(
                color: AppColors.errorRed,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "EXIT",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.close, color: Colors.black, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
