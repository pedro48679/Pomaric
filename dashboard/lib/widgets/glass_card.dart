import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double opacity;
  final double borderRadius;
  final bool elevated;
  final bool hasBlur;

  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.blur = 12, // Reduced to 12 as per redesign plan
    this.opacity = 0.6,
    this.borderRadius = 16,
    this.elevated = false,
    this.hasBlur = true,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // Variant elevated uses #1C3530, normal uses surface
    final baseColor = widget.elevated
        ? const Color(0xFF1C3530)
        : AppColors.surface;

    final border = Border.all(
      color: _isHovered
          ? AppColors.primary.withOpacity(0.4) // Brighten border color on hover
          : AppColors.glassBorder,
      width: 1,
    );

    final boxDecoration = BoxDecoration(
      color: baseColor.withOpacity(widget.opacity),
      borderRadius: BorderRadius.circular(widget.borderRadius),
      border: border,
      boxShadow: _isHovered
          ? [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.08),
                blurRadius: 12,
                spreadRadius: 2,
              )
            ]
          : null,
    );

    Widget cardContent = Container(
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      decoration: boxDecoration,
      child: widget.child,
    );

    if (widget.hasBlur) {
      cardContent = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
          child: cardContent,
        ),
      );
    } else {
      cardContent = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: cardContent,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: cardContent,
    );
  }
}
