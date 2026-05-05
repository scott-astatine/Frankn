import 'package:flutter/material.dart';

class ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.15),
          Colors.transparent,
          Colors.black.withValues(alpha: 0.15),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 3))
      ..style = PaintingStyle.fill;

    for (double i = 0; i < size.height; i += 3) {
      canvas.drawRect(Rect.fromLTWH(0, i, size.width, 1.5), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

