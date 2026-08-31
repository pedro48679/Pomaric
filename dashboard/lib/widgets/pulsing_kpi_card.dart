import 'package:flutter/material.dart';
import '../utils/constants.dart';

class PulsingKpiCard extends StatefulWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isPulsing;
  final VoidCallback onSuggestionTap;
  final String buttonText;
  final bool showButtonAlways;
  final Widget? sparkline;

  const PulsingKpiCard({
    Key? key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isPulsing,
    required this.onSuggestionTap,
    this.buttonText = 'Sugestão',
    this.showButtonAlways = false,
    this.sparkline,
  }) : super(key: key);

  @override
  State<PulsingKpiCard> createState() => _PulsingKpiCardState();
}

class _PulsingKpiCardState extends State<PulsingKpiCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _animation = Tween<double>(begin: 0.2, end: 0.8).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.isPulsing) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulsingKpiCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing && !oldWidget.isPulsing) {
      _controller.repeat(reverse: true);
    } else if (!widget.isPulsing && oldWidget.isPulsing) {
      _controller.stop();
      _controller.value = 0.2;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isPulsing
                    ? widget.color.withOpacity(_animation.value)
                    : widget.color.withOpacity(0.1),
                width: widget.isPulsing ? 2 : 1,
              ),
              boxShadow: widget.isPulsing ? [
                BoxShadow(
                  color: widget.color.withOpacity(_animation.value * 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                )
              ] : [],
            ),
            child: child,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 14),
                ),
                const Spacer(),
                if (widget.isPulsing || widget.showButtonAlways)
                  ElevatedButton(
                    onPressed: widget.onSuggestionTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.color.withOpacity(0.2),
                      foregroundColor: widget.color,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(widget.buttonText, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.value,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.5),
                fontSize: 9,
              ),
            ),
            if (widget.sparkline != null) ...[
              const SizedBox(height: 8),
              SizedBox(height: 20, width: double.infinity, child: widget.sparkline),
            ],
          ],
        ),
      ),
    );
  }
}
