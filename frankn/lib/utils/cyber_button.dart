import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

enum CyberButtonVariant { primary, warning, destructive, secondary }

class CyberButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final CyberButtonVariant variant;
  final bool isSmall;
  final IconData? icon;

  const CyberButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.variant = CyberButtonVariant.primary,
    this.isSmall = false,
    this.icon,
  });

  @override
  State<CyberButton> createState() => _CyberButtonState();
}

class _CyberButtonState extends State<CyberButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getVariantColor() {
    switch (widget.variant) {
      case CyberButtonVariant.warning:
        return AppColors.accentWarning;
      case CyberButtonVariant.destructive:
        return AppColors.accentError;
      case CyberButtonVariant.secondary:
        return AppColors.accentSecondary;
      default:
        return AppColors.accentPrimary;
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
          final scale = 1.0 - (_controller.value * 0.05);

          return Transform.scale(
            scale: scale,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isSmall ? 14 : 24,
                vertical: widget.isSmall ? 8 : 14,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: color.withOpacity(0.8),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25 - _controller.value * 0.05),
                    blurRadius: 10 + _controller.value * 4,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: widget.isSmall ? 14 : 18,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.text.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: widget.isSmall ? 11 : 13,
                        letterSpacing: 1.5,
                        shadows: [
                          Shadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
