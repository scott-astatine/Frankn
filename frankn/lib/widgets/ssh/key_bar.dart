import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class SshKeyBar extends StatelessWidget {
  final ModState ctrlState;
  final ModState altState;
  final ModState shiftState;
  final VoidCallback onToggleCtrl;
  final VoidCallback onLockCtrl;
  final VoidCallback onToggleAlt;
  final VoidCallback onLockAlt;
  final VoidCallback onToggleShift;
  final VoidCallback onLockShift;
  final Function(String) onSendRaw;

  const SshKeyBar({
    super.key,
    required this.ctrlState,
    required this.altState,
    required this.shiftState,
    required this.onToggleCtrl,
    required this.onLockCtrl,
    required this.onToggleAlt,
    required this.onLockAlt,
    required this.onToggleShift,
    required this.onLockShift,
    required this.onSendRaw,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _buildKeyBtn("TAB", "\t"),
          _buildKeyBtn("ESC", "\x1b"),
          _buildModifierBtn("CTRL", ctrlState, onToggleCtrl, onLockCtrl),
          _buildModifierBtn("ALT", altState, onToggleAlt, onLockAlt),
          _buildModifierBtn("SHIFT", shiftState, onToggleShift, onLockShift),
          _buildKeyBtn("INS", "\x1b[2~"),
          _buildKeyBtn("DEL", "\x1b[3~"),
          _buildKeyBtn("HOME", "\x1b[H"),
          _buildKeyBtn("END", "\x1b[F"),
          _buildKeyBtn("PGUP", "\x1b[5~"),
          _buildKeyBtn("PGDN", "\x1b[6~"),
          _buildKeyBtn("↑", "\x1b[A"),
          _buildKeyBtn("↓", "\x1b[B"),
          _buildKeyBtn("←", "\x1b[D"),
          _buildKeyBtn("→", "\x1b[C"),
          _buildKeyBtn("/", "/"),
          _buildKeyBtn("-", "-"),
          _buildKeyBtn("|", "|"),
        ],
      ),
    );
  }

  Widget _buildKeyBtn(String label, String seq) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceSecondary,
          foregroundColor: AppColors.accentPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
              color: AppColors.accentPrimary.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        onPressed: () => onSendRaw(seq),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'Courier',
          ),
        ),
      ),
    );
  }

  Widget _buildModifierBtn(
    String label,
    ModState state,
    VoidCallback onTap,
    VoidCallback onDoubleTap,
  ) {
    Color color = Colors.white54;
    Color bgColor = AppColors.surfaceSecondary;
    Color borderColor = Colors.white10;

    if (state == ModState.active) {
      color = AppColors.accentPrimary;
      bgColor = AppColors.accentPrimary.withValues(alpha: 0.15);
      borderColor = AppColors.accentPrimary.withValues(alpha: 0.5);
    } else if (state == ModState.locked) {
      color = AppColors.accentSecondary;
      bgColor = AppColors.accentSecondary.withValues(alpha: 0.2);
      borderColor = AppColors.accentSecondary.withValues(alpha: 0.6);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            height: 32,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Courier',
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
