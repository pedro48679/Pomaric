part of '../../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// VISÃO COMPUTACIONAL · FLIP CARD
// Cartão que vira para revelar a leitura alternativa do mesmo
// dado. Usado nos dois pares de cartões do capítulo da CNN.
// ═══════════════════════════════════════════════════════════

class _FlipCard extends StatefulWidget {
  final Widget front;
  final Widget back;
  final double height;
  final String frontLabel;
  final String backLabel;
  final String frontTooltip;
  final String backTooltip;
  
  const _FlipCard({
    required this.front,
    required this.back,
    required this.frontLabel,
    required this.backLabel,
    required this.frontTooltip,
    required this.backTooltip,
    this.height = 380,
  });

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard> {
  bool _flipped = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: _flipped ? pi : 0.0),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOut,
        builder: (context, val, __) {
          final isBack = val >= pi / 2;
          final face = isBack
              ? Transform(
                  transform: Matrix4.identity()..rotateY(pi),
                  alignment: Alignment.center,
                  child: widget.back,
                )
              : widget.front;
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(val),
            alignment: Alignment.center,
            child: Stack(
              children: [
                Positioned.fill(child: face),
                Positioned(
                  right: 14,
                  bottom: 12,
                  child: Transform(
                    transform: isBack ? (Matrix4.identity()..rotateY(pi)) : Matrix4.identity(),
                    alignment: Alignment.center,
                    child: Tooltip(
                      message: isBack ? widget.frontTooltip : widget.backTooltip,
                      textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: InkWell(
                        onTap: () => setState(() => _flipped = !_flipped),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.flip_camera_android, color: AppColors.primary, size: 14),
                            const SizedBox(width: 5),
                            Text(isBack ? widget.frontLabel : widget.backLabel,
                                style: TextStyle(
                                    color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
