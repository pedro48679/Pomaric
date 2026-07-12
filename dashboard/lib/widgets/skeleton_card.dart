import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'glass_card.dart';

class SkeletonCard extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const SkeletonCard({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 16,
  });

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    // Animate from -1.5 to 1.5 to shift the gradient position
    _animation = Tween<double>(begin: -1.5, end: 1.5).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return GlassCard(
          width: widget.width,
          height: widget.height,
          borderRadius: widget.borderRadius,
          opacity: 0.2, // Lower opacity to make shimmer visible
          hasBlur: false, // Disables blur on skeletons to prevent GPU lag
          padding: EdgeInsets.zero,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              gradient: LinearGradient(
                begin: Alignment(-1.5, -0.4),
                end: Alignment(1.5, 0.4),
                colors: [
                  AppColors.surface,
                  AppColors.surfaceBright,
                  AppColors.surface,
                ],
                stops: [
                  (0.0 + _animation.value).clamp(0.0, 1.0),
                  (0.5 + _animation.value).clamp(0.0, 1.0),
                  (1.0 + _animation.value).clamp(0.0, 1.0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}