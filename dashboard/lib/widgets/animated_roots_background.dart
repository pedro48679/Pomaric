import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class AnimatedRootsBackground extends StatefulWidget {
  final Widget child;

  const AnimatedRootsBackground({Key? key, required this.child}) : super(key: key);

  @override
  State<AnimatedRootsBackground> createState() => _AnimatedRootsBackgroundState();
}

class _AnimatedRootsBackgroundState extends State<AnimatedRootsBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // A very slow, 30-second loop to simulate calm biological breathing
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            // Dark forest background color
            Positioned.fill(
              child: Container(
                color: AppColors.background,
              ),
            ),
            // Layer containing the animated roots
            Positioned.fill(
              child: CustomPaint(
                painter: _RootsPainter(progress: _controller.value),
              ),
            ),
            // The content of the page
            Positioned.fill(
              child: widget.child,
            ),
          ],
        );
      },
    );
  }
}

class _RootsPainter extends CustomPainter {
  final double progress;

  _RootsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.healthy.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    // Define 5 distinct root system nodes across the viewport
    final double angle = progress * 2 * pi;

    // Root system 1: Top-Left to Center
    _drawRootSystem(
      canvas,
      paint,
      dotPaint,
      start: const Offset(0, 0),
      control1: Offset(size.width * 0.25, size.height * 0.1 + sin(angle) * 30),
      control2: Offset(size.width * 0.15 + cos(angle) * 20, size.height * 0.45),
      end: Offset(size.width * 0.35, size.height * 0.6),
      pulseProgress: (progress + 0.0) % 1.0,
    );

    // Root system 2: Bottom-Left to Center-Right
    _drawRootSystem(
      canvas,
      paint,
      dotPaint,
      start: Offset(0, size.height),
      control1: Offset(size.width * 0.15, size.height * 0.85 + cos(angle) * 25),
      control2: Offset(size.width * 0.35 + sin(angle) * 30, size.height * 0.55),
      end: Offset(size.width * 0.5, size.height * 0.4),
      pulseProgress: (progress + 0.2) % 1.0,
    );

    // Root system 3: Top-Right to Center-Left
    _drawRootSystem(
      canvas,
      paint,
      dotPaint,
      start: Offset(size.width, 0),
      control1: Offset(size.width * 0.85, size.height * 0.2 + cos(angle) * 35),
      control2: Offset(size.width * 0.6 + sin(angle) * 20, size.height * 0.6),
      end: Offset(size.width * 0.4, size.height * 0.7),
      pulseProgress: (progress + 0.4) % 1.0,
    );

    // Root system 4: Bottom-Right to Middle
    _drawRootSystem(
      canvas,
      paint,
      dotPaint,
      start: Offset(size.width, size.height),
      control1: Offset(size.width * 0.8 + sin(angle) * 25, size.height * 0.75),
      control2: Offset(size.width * 0.55, size.height * 0.85 + cos(angle) * 30),
      end: Offset(size.width * 0.65, size.height * 0.5),
      pulseProgress: (progress + 0.6) % 1.0,
    );

    // Root system 5: Top-Middle to Bottom-Middle
    _drawRootSystem(
      canvas,
      paint,
      dotPaint,
      start: Offset(size.width * 0.5, 0),
      control1: Offset(size.width * 0.45 + cos(angle) * 30, size.height * 0.3),
      control2: Offset(size.width * 0.55 + sin(angle) * 25, size.height * 0.7),
      end: Offset(size.width * 0.48, size.height * 0.95),
      pulseProgress: (progress + 0.8) % 1.0,
    );
  }

  void _drawRootSystem(
    Canvas canvas,
    Paint linePaint,
    Paint dotPaint, {
    required Offset start,
    required Offset control1,
    required Offset control2,
    required Offset end,
    required double pulseProgress,
  }) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(control1.dx, control1.dy, control2.dx, control2.dy, end.dx, end.dy);

    // Draw main root
    canvas.drawPath(path, linePaint);

    // Draw secondary branches splitting from control points
    final branch1Start = _cubicBezierPoint(start, control1, control2, end, 0.35);
    final branch1End = Offset(
      branch1Start.dx + (end.dx - start.dx) * 0.3 + sin(progress * 2 * pi) * 15,
      branch1Start.dy + (end.dy - start.dy) * 0.1 + cos(progress * 2 * pi) * 15,
    );
    canvas.drawLine(branch1Start, branch1End, linePaint);

    final branch2Start = _cubicBezierPoint(start, control1, control2, end, 0.7);
    final branch2End = Offset(
      branch2Start.dx - (end.dx - start.dx) * 0.2 + cos(progress * 2 * pi) * 20,
      branch2Start.dy + (end.dy - start.dy) * 0.35 + sin(progress * 2 * pi) * 10,
    );
    canvas.drawLine(branch2Start, branch2End, linePaint);

    // Draw glowing data node traveling along the main root system
    final pulsePos = _cubicBezierPoint(start, control1, control2, end, pulseProgress);
    canvas.drawCircle(pulsePos, 2.5, dotPaint);
    final pulseGlowPaint = Paint()
      ..color = dotPaint.color.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pulsePos, 5.0, pulseGlowPaint);
  }

  // Cubic Bezier helper function
  Offset _cubicBezierPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final double u = 1 - t;
    final double tt = t * t;
    final double uu = u * u;
    final double uuu = uu * u;
    final double ttt = tt * t;

    final double x = uuu * p0.dx + 3 * uu * t * p1.dx + 3 * u * tt * p2.dx + ttt * p3.dx;
    final double y = uuu * p0.dy + 3 * uu * t * p1.dy + 3 * u * tt * p2.dy + ttt * p3.dy;

    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _RootsPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
