import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class CyberButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const CyberButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: Alignment.center,

        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(64, 36),

        foregroundColor: AppColors.voidBlack,
        backgroundColor: AppColors.neonCyan,
        shape: const BeveledRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
