import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '_chart_kit.dart';

// ═══════════════════════════════════════════════════════════
// BI · ZONA DE INCERTEZA
// Grelha de densidade sem sobreposição de bolhas, com faixa open-set evidente.
// ═══════════════════════════════════════════════════════════
// ═════════════════════════ 3 · ZONA DE INCERTEZA (grelha de densidade) ═════════════════════════

class UncertaintyCell {
  final double top1; // centro da célula (0..1)
  final double margin; // centro da célula (0..1)
  final String topClass;
  final String topPair; // par top1↔top2 dominante na célula (co-confusão)
  final double avgDispersion; // dispersão média entre vistas (0..1, do hull)
  final int n;
  const UncertaintyCell({
    required this.top1,
    required this.margin,
    required this.topClass,
    required this.n,
    this.topPair = '',
    this.avgDispersion = 0.0,
  });
}

class UncertaintyData {
  final List<UncertaintyCell> cells;
  final int total;
  final int opensetCount;
  final double top1Threshold;
  final double marginThreshold;

  // Régua marginal (bandas de decisão do CNN5, absorve o _openSetRadar):
  final int bandAccept; // ≥70%
  final int bandTriage; // 30–70%
  final int bandAutoOthers; // <30%
  final int routedTotal;

  // Top-3 pares confundidos (absorve o _cnn5CoConfusionMatrix):
  final List<({String pair, int n})> topPairs;

  const UncertaintyData({
    required this.cells,
    required this.total,
    required this.opensetCount,
    this.top1Threshold = 0.70,
    this.marginThreshold = 0.15,
    this.bandAccept = 0,
    this.bandTriage = 0,
    this.bandAutoOthers = 0,
    this.routedTotal = 0,
    this.topPairs = const [],
  });
  bool get isEmpty => cells.isEmpty;
}

/// Retângulo do plot, partilhado entre o painter e o hit-test do hover.
Rect _uncPlotRect(Size size) =>
    Rect.fromLTRB(38, 34, size.width - 14, size.height - 46);

/// Início dinâmico do eixo X (confiança top-1): múltiplo de 10% abaixo do
/// mínimo dos dados, limitado a [0, 60%] para a fronteira de aceitação (80%)
/// e a zona open-set ficarem sempre dentro do gráfico.
double _uncXMin(UncertaintyData d) {
  if (d.cells.isEmpty) return 0.0;
  double mn = 1.0;
  for (final c in d.cells) {
    mn = math.min(mn, c.top1);
  }
  return (((mn * 10).floor() - 1) / 10.0).clamp(0.0, 0.6);
}

class UncertaintyZoneChart extends StatefulWidget {
  final UncertaintyData data;
  const UncertaintyZoneChart({super.key, required this.data});

  @override
  State<UncertaintyZoneChart> createState() => _UncertaintyZoneChartState();
}

class _UncertaintyZoneChartState extends State<UncertaintyZoneChart> {
  UncertaintyCell? _hovered;
  Offset? _hoverPos;

  UncertaintyCell? _cellAt(Offset local, Size size) {
    final plot = _uncPlotRect(size);
    if (plot.width <= 0 || plot.height <= 0) return null;
    final xMin = _uncXMin(widget.data);
    UncertaintyCell? best;
    double bestDist = 18; // raio de captura em px
    for (final c in widget.data.cells.where((c) => c.n > 5)) {
      final pos = Offset(
        plot.left + ((c.top1 - xMin) / (1 - xMin)) * plot.width,
        plot.top + (1 - c.margin) * plot.height,
      );
      final d = (pos - local).distance;
      if (d < bestDist) {
        bestDist = d;
        best = c;
      }
    }
    return best;
  }

  Widget _countChip(String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: axisStyle(size: 9)),
        const SizedBox(width: 4),
        Text(count, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) {
      return Center(child: Text('Sem probabilidades multi-classe (CNN5) no período', style: axisStyle(size: 11)));
    }

    final h = _hovered;
    final infoText = h == null
        ? ''
        : 'Confiança: ${(h.top1 * 100).toStringAsFixed(0)}% · Diferença 1º/2º: ${(h.margin * 100).toStringAsFixed(0)}pp\n'
            'Volume: ${h.n} maçãs · Decisão: ${AppColors.displayName(h.topClass)}'
            '${h.topPair.isNotEmpty ? '\nConfusão entre: ${h.topPair.replaceAll('↔', ' e ')}' : ''}';

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              return MouseRegion(
                onHover: (e) => setState(() {
                  _hovered = _cellAt(e.localPosition, size);
                  _hoverPos = e.localPosition;
                }),
                onExit: (_) => setState(() {
                  _hovered = null;
                  _hoverPos = null;
                }),
                child: GestureDetector(
                  onTapDown: (e) => setState(() {
                    _hovered = _cellAt(e.localPosition, size);
                    _hoverPos = e.localPosition;
                  }),
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: size,
                        painter: _UncertaintyPainter(data, hovered: _hovered),
                      ),
                      if (h != null && _hoverPos != null)
                        hoverTooltipOverlay(pos: _hoverPos!, containerSize: size, text: infoText),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        if (data.routedTotal > 0) ...[
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _countChip('Rejeição (<30%)', '${data.bandAutoOthers}', AppColors.rot),
              _countChip('Triagem (30–80%)', '${data.bandTriage}', AppColors.scab),
              _countChip('Aceite (≥80%)', '${data.bandAccept}', AppColors.healthy),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _UncertaintyPainter extends CustomPainter {
  final UncertaintyData d;
  final UncertaintyCell? hovered;
  _UncertaintyPainter(this.d, {this.hovered});

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _uncPlotRect(size);
    if (plot.width <= 0 || plot.height <= 0) return;

    final xMin = _uncXMin(d);
    double xPix(double v) => plot.left + ((v - xMin) / (1 - xMin)) * plot.width;
    double yPix(double v) => plot.top + (1 - v) * plot.height;

    final thrX = xPix(d.top1Threshold);

    // Fundo limpo sem bordas duras nem linhas tracejadas grossas
    canvas.drawRect(Rect.fromLTRB(plot.left, plot.top, xPix(0.3), plot.bottom), Paint()..color = AppColors.rot.withValues(alpha: 0.03));
    canvas.drawRect(Rect.fromLTRB(xPix(0.3), plot.top, thrX, plot.bottom), Paint()..color = AppColors.scab.withValues(alpha: 0.03));
    canvas.drawRect(Rect.fromLTRB(thrX, plot.top, plot.right, plot.bottom), Paint()..color = AppColors.healthy.withValues(alpha: 0.03));
    
    // Grelha suave
    final gridPaint = Paint()..color = gridLineColor()..strokeWidth = 1;
    for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      canvas.drawLine(Offset(plot.left, yPix(t)), Offset(plot.right, yPix(t)), gridPaint);
      final gx = xMin + t * (1 - xMin);
      canvas.drawLine(Offset(xPix(gx), plot.top), Offset(xPix(gx), plot.bottom), gridPaint);
    }

    final validCells = d.cells.where((c) => c.n > 5).toList();
    if (validCells.isEmpty) return;

    final maxN = validCells.fold<int>(1, (m, c) => math.max(m, c.n));
    final cellPx = 0.1 * plot.width;
    final rCap = cellPx * 0.46;
    for (final c in validCells) {
      final pos = Offset(xPix(c.top1), yPix(c.margin));
      final r = (6 + 15 * math.sqrt(c.n / maxN)).clamp(6.0, rCap < 8 ? 8.0 : rCap);
      
      Paint fillPaint;
      if (c.topPair.isNotEmpty && c.topPair.contains('↔')) {
        final parts = c.topPair.split('↔');
        final c1 = parts.isNotEmpty ? parts[0].trim() : c.topClass;
        final c2 = parts.length > 1 ? parts[1].trim() : c.topClass;
        fillPaint = Paint()
          ..shader = ui.Gradient.linear(
            Offset(pos.dx - r, pos.dy),
            Offset(pos.dx + r, pos.dy),
            [
              AppColors.getColorForCondition(c1).withValues(alpha: 0.92),
              AppColors.getColorForCondition(c2).withValues(alpha: 0.92),
            ],
          );
      } else {
        fillPaint = Paint()..color = AppColors.getColorForCondition(c.topClass).withValues(alpha: 0.92);
      }
      
      canvas.drawCircle(pos, r, fillPaint);
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = AppColors.background,
      );
      
      if (hovered != null && identical(c, hovered)) {
        canvas.drawCircle(
          pos,
          r + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = AppColors.textPrimary,
        );
      }
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    // Eixo Y (margem)
    for (final t in [0.0, 0.5, 1.0]) {
      tp.text = TextSpan(text: '${(t * 100).toInt()}%', style: axisStyle(size: 8));
      tp.layout();
      tp.paint(canvas, Offset(plot.left - tp.width - 5, yPix(t) - tp.height / 2));
    }
    // Eixo X (top-1)
    for (final v in {xMin, d.top1Threshold, 1.0}) {
      tp.text = TextSpan(
          text: '${(v * 100).toInt()}%',
          style: v == d.top1Threshold ? axisStyle(size: 8, bold: true) : axisStyle(size: 8));
      tp.layout();
      tp.paint(canvas, Offset(xPix(v) - tp.width / 2, plot.bottom + 2));
    }

    tp.text = TextSpan(text: 'Confiança Principal (top-1)  →', style: axisStyle(size: 9));
    tp.layout();
    tp.paint(canvas, Offset(plot.right - tp.width, plot.bottom + 18));
    tp.text = TextSpan(text: 'Margem para a 2ª opção  ↑', style: axisStyle(size: 9));
    tp.layout();
    tp.paint(canvas, Offset(plot.left - 2, plot.top - 14));
  }

  @override
  bool shouldRepaint(covariant _UncertaintyPainter old) => old.d != d || old.hovered != hovered;
}
