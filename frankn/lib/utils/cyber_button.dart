import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

enum CyberButtonVariant { primary, warning, destructive, secondary }

class CyberButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final CyberButtonVariant variant;
  final bool isSmall;

  const CyberButton({
    super.key, 
    required this.text, 
    required this.onPressed,
    this.variant = CyberButtonVariant.primary,
    this.isSmall = false,
  });

  @override
  State<CyberButton> createState() => _CyberButtonState();
}

class _CyberButtonState extends State<CyberButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
      lowerBound: 0.0,
      upperBound: 4.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getVariantColor() {
    switch (widget.variant) {
      case CyberButtonVariant.warning: return AppColors.cyberYellow;
      case CyberButtonVariant.destructive: return AppColors.errorRed;
      case CyberButtonVariant.secondary: return AppColors.neonPink;
      default: return AppColors.neonCyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getVariantColor();

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onPressed();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_controller.value, _controller.value),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isSmall ? 12 : 20, 
                vertical: widget.isSmall ? 8 : 12
              ),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: Colors.black, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    offset: Offset(4 - _controller.value, 4 - _controller.value),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Text(
                widget.text.toUpperCase(),
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
              ),
            ),
          );
        },
      ),
    );
  }
}
