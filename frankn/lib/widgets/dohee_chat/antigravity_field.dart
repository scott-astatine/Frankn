import 'dart:math';
import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class Particle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  Color color;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
  });
}

class AntigravityField extends StatefulWidget {
  const AntigravityField({super.key});

  @override
  State<AntigravityField> createState() => _AntigravityFieldState();
}

class _AntigravityFieldState extends State<AntigravityField>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  Offset? _touchPos;
  final Random _random = Random();
  static const int _particleCount = 35;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(_updateParticles)..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_particles.isEmpty) {
      final size = MediaQuery.of(context).size;
      for (int i = 0; i < _particleCount; i++) {
        _particles.add(
          Particle(
            x: _random.nextDouble() * size.width,
            y: _random.nextDouble() * size.height,
            vx: (_random.nextDouble() - 0.5) * 0.8,
            vy: (_random.nextDouble() - 0.5) * 0.8,
            size: _random.nextDouble() * 2.5 + 1.5,
            color: _random.nextBool()
                ? NeoColors.cyan.withValues(alpha: 0.3)
                : NeoColors.fuchsia.withValues(alpha: 0.3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateParticles() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final touch = _touchPos;

    for (var p in _particles) {
      // Basic movement
      p.x += p.vx;
      p.y += p.vy;

      // Wrap around bounds with margins
      if (p.x < -20) p.x = size.width + 10;
      if (p.x > size.width + 20) p.x = -10;
      if (p.y < -20) p.y = size.height + 10;
      if (p.y > size.height + 20) p.y = -10;

      // Antigravity touch interaction: push particles away from pointer
      if (touch != null) {
        final dx = p.x - touch.dx;
        final dy = p.y - touch.dy;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < 150 && dist > 0) {
          // Force multiplier gets stronger as the pointer gets closer
          final force = (150 - dist) / 150;
          final pushX = (dx / dist) * force * 1.5;
          final pushY = (dy / dist) * force * 1.5;
          
          p.x += pushX;
          p.y += pushY;
        }
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        setState(() => _touchPos = e.position);
      },
      onPointerMove: (e) {
        setState(() => _touchPos = e.position);
      },
      onPointerUp: (e) {
        setState(() => _touchPos = null);
      },
      onPointerCancel: (e) {
        setState(() => _touchPos = null);
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: AntigravityPainter(
          particles: _particles,
          touchPos: _touchPos,
        ),
      ),
    );
  }
}

class AntigravityPainter extends CustomPainter {
  final List<Particle> particles;
  final Offset? touchPos;

  AntigravityPainter({required this.particles, required this.touchPos});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()..strokeWidth = 0.5;

    // Draw connection lines
    for (int i = 0; i < particles.length; i++) {
      final p1 = particles[i];
      for (int j = i + 1; j < particles.length; j++) {
        final p2 = particles[j];
        final dx = p1.x - p2.x;
        final dy = p1.y - p2.y;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist < 110) {
          final alpha = (1.0 - (dist / 110)) * 0.15;
          // Mix colors based on which particles are connected
          final color = p1.color.withValues(alpha: alpha);
          linePaint.color = color;
          canvas.drawLine(Offset(p1.x, p1.y), Offset(p2.x, p2.y), linePaint);
        }
      }
    }

    // Draw touch glow (gravity emitter effect)
    final touch = touchPos;
    if (touch != null) {
      final Paint touchGlowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            NeoColors.cyan.withValues(alpha: 0.08),
            NeoColors.cyan.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: touch, radius: 100),
        );
      canvas.drawCircle(touch, 100, touchGlowPaint);

      // Core micro emitter dot
      final Paint emitterPaint = Paint()
        ..color = NeoColors.cyan.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(touch, 2.0, emitterPaint);
    }

    // Draw nodes/particles
    final Paint particlePaint = Paint()..style = PaintingStyle.fill;
    for (var p in particles) {
      particlePaint.color = p.color;
      canvas.drawCircle(Offset(p.x, p.y), p.size, particlePaint);

      // Small secondary outer glow for larger particles
      if (p.size > 3.0) {
        final glowPaint = Paint()
          ..color = p.color.withValues(alpha: 0.05)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(p.x, p.y), p.size * 2, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant AntigravityPainter oldDelegate) => true;
}
