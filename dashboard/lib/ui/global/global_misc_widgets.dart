part of '../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// SparklinePainter (usado pelo treemap) e popup de alerta de surto.
// ═══════════════════════════════════════════════════════════

class SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    final double stepX = size.width / (data.length - 1);
    final double maxVal = data.reduce(max);
    final double minVal = data.reduce(min);
    final double range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - ((data[i] - minVal) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) => oldDelegate.data != data;
}

// ── Popup de Alerta de Surto ────────────────────────────────────────────────
// Cartão limpo e discreto (sem barra de título estilo "janela 2008"), com
// animação de entrada suave, minimização "genie-like" (encolhe para um canto,
// como minimizar uma janela no macOS) e saída animada antes de ser descartado.
class _OutbreakAlertPopup extends StatefulWidget {
  final List<Batch> riskBatches;
  final bool showSystemSurge;
  final VoidCallback onDismiss;

  const _OutbreakAlertPopup({
    required this.riskBatches,
    required this.showSystemSurge,
    required this.onDismiss,
  });

  @override
  State<_OutbreakAlertPopup> createState() => _OutbreakAlertPopupState();
}

class _OutbreakAlertPopupState extends State<_OutbreakAlertPopup> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _entrance;

  bool _minimized = false;
  bool _expanded = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _entrance = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    setState(() => _dismissing = true);
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    String mainPathology = 'Healthy';
    if (widget.riskBatches.isNotEmpty) {
      final counts = <String, int>{};
      for (final b in widget.riskBatches) {
        final dom = getDominantDiseaseENForBatch(b);
        counts[dom] = (counts[dom] ?? 0) + 1;
      }
      var maxVal = -1;
      counts.forEach((k, v) {
        if (v > maxVal) {
          maxVal = v;
          mainPathology = k;
        }
      });
    } else if (widget.showSystemSurge) {
      mainPathology = 'Rot';
    }

    final mainPathologyLabel = mainPathology == 'Rot'
        ? 'Rot'
        : mainPathology == 'Scab'
            ? 'Scab'
            : mainPathology == 'Blotch'
                ? 'Sooty Blotch'
                : mainPathology == 'Anthracnose'
                    ? 'Anthracnose'
                    : 'Estável';

    double avgUrgency = 0.0;
    if (widget.riskBatches.isNotEmpty) {
      avgUrgency = widget.riskBatches.map((b) => b.urgencyScore).reduce((a, b) => a + b) / widget.riskBatches.length;
    } else if (widget.showSystemSurge) {
      avgUrgency = 0.6;
    }

    String threatLevelText = 'BAIXO';
    Color threatColor = AppColors.healthy;
    double progressValue = 0.33;
    if (avgUrgency > 0.45) {
      threatLevelText = 'CRÍTICO';
      threatColor = Colors.redAccent;
      progressValue = 1.0;
    } else if (avgUrgency > 0.20) {
      threatLevelText = 'MODERADO';
      threatColor = Colors.orangeAccent;
      progressValue = 0.66;
    }

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) => Opacity(
        opacity: _entrance.value,
        child: Transform.scale(
          scale: 0.92 + 0.08 * _entrance.value,
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          // Encolhe/expande a partir do canto inferior direito, com fade —
          // aproximação do efeito "genie" de minimizar uma janela no macOS.
          return ScaleTransition(
            scale: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
            alignment: Alignment.bottomRight,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: _minimized
            ? _buildMinimizedIcon()
            : _buildExpandedCard(mainPathologyLabel, threatLevelText, threatColor, progressValue),
      ),
    );
  }

  Widget _buildMinimizedIcon() {
    return GestureDetector(
      key: const ValueKey('minimized'),
      onTap: () => setState(() => _minimized = false),
      child: Tooltip(
        message: 'Reabrir alerta de surto',
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45), width: 1.2),
            boxShadow: [
              BoxShadow(color: Colors.redAccent.withValues(alpha: 0.18), blurRadius: 10, spreadRadius: 1),
            ],
          ),
          child: const Center(
            child: Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedCard(String pathologyLabel, String threatLevelText, Color threatColor, double progressValue) {
    return Container(
      key: const ValueKey('expanded'),
      width: 280,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: Colors.redAccent.withValues(alpha: 0.7), width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppColors.isDark ? 0.35 : 0.10),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Alerta Crítico',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  _iconGhostButton(Icons.remove_rounded, 'Minimizar', () => setState(() => _minimized = true)),
                  const SizedBox(width: 2),
                  _iconGhostButton(Icons.close_rounded, 'Descartar', _dismissing ? null : _handleDismiss),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'RISCO BIOLÓGICO DETETADO',
                style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.85), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.4),
              ),
              const SizedBox(height: 3),
              Text(
                pathologyLabel,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Nível de Ameaça', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
                  Text(threatLevelText, style: TextStyle(color: threatColor, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 4,
                  backgroundColor: AppColors.surfaceBright,
                  valueColor: AlwaysStoppedAnimation(threatColor),
                ),
              ),
              if (widget.riskBatches.isNotEmpty) ...[
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Outros lotes afetados', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: !_expanded
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 110),
                            child: SingleChildScrollView(
                              child: Column(
                                children: widget.riskBatches.map((b) {
                                  final bDom = getDominantDiseaseENForBatch(b);
                                  final bDomLabel = AppColors.displayName(bDom);
                                  final condColor = AppColors.getColorForCondition(bDom);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(b.id, style: TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
                                            Text(bDomLabel.toUpperCase(), style: TextStyle(color: condColor, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(2),
                                          child: LinearProgressIndicator(
                                            value: b.urgencyScore,
                                            minHeight: 2,
                                            backgroundColor: AppColors.surfaceBright,
                                            valueColor: AlwaysStoppedAnimation(condColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconGhostButton(IconData icon, String tooltip, VoidCallback? onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, color: AppColors.textSecondary, size: 15),
        ),
      ),
    );
  }
}
