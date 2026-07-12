import 'package:flutter/material.dart';
import '../utils/constants.dart';

class TechGridBackground extends StatelessWidget {
  final Widget child;

  const TechGridBackground({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base dark background
        Positioned.fill(
          child: Container(
            color: AppColors.background,
          ),
        ),
        // Custom painted tech grid and gradients
        Positioned.fill(
          child: CustomPaint(
            painter: const _TechGridPainter(),
          ),
        ),
        // Content
        Positioned.fill(
          child: child,
        ),
      ],
    );
  }
}

class _TechGridPainter extends CustomPainter {
  const _TechGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw large radial gradient glows in corners
    final paintGlow1 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.healthy.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: const Offset(0, 0), radius: 500));
    canvas.drawCircle(const Offset(0, 0), 500, paintGlow1);

    final paintGlow2 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(size.width, size.height), radius: 600));
    canvas.drawCircle(Offset(size.width, size.height), 600, paintGlow2);

    // 2. Draw subtle grid lines
    final gridPaint = Paint()
      ..color = AppColors.isDark
          ? Colors.white.withValues(alpha: 0.015)
          : Colors.black.withValues(alpha: 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    const double step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 3. Draw tiny radar/calibration ticks or dots at intersections
    final dotPaint = Paint()
      ..color = AppColors.healthy.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    for (double x = step; x < size.width; x += step * 4) {
      for (double y = step; y < size.height; y += step * 4) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
