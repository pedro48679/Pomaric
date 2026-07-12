
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/constants.dart';
import '../../widgets/apple_card.dart';
import '../../widgets/glass_card.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/skeleton_card.dart';

class ConfidenceSeverityHullPlot extends StatefulWidget {
  final List<Apple> apples;
  const ConfidenceSeverityHullPlot({required this.apples});

  @override
  State<ConfidenceSeverityHullPlot> createState() => ConfidenceSeverityHullPlotState();
}

class ConfidenceSeverityHullPlotState extends State<ConfidenceSeverityHullPlot> {
  Apple? _hovered;

  // Andrew's monotone chain — devolve os vértices do invólucro convexo, em ordem.
  static List<Offset> _convexHull(List<Offset> points) {
    if (points.length < 3) return points;
    final pts = [...points]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    double cross(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lower = <Offset>[];
    for (final p in pts) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  // Expande cada ponto real num pequeno quadrado antes do hull — garante que
  // patologias com 1 único caso, ou todos colineares (ex: severidade sempre 0),
  // ainda produzem um polígono visível em vez de degenerarem numa linha/ponto.
  static List<Offset> _inflate(List<Offset> points, double pad) {
    final result = <Offset>[];
    for (final p in points) {
      result.add(Offset(p.dx - pad, p.dy - pad));
      result.add(Offset(p.dx + pad, p.dy - pad));
      result.add(Offset(p.dx - pad, p.dy + pad));
      result.add(Offset(p.dx + pad, p.dy + pad));
    }
    return result;
  }

  static double _polygonArea(List<Offset> pts) {
    if (pts.length < 3) return 0;
    double sum = 0;
    for (int i = 0; i < pts.length; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % pts.length];
      sum += p1.dx * p2.dy - p2.dx * p1.dy;
    }
    return sum.abs() / 2;
  }

  @override
  Widget build(BuildContext context) {
    final apples = widget.apples;
    if (apples.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 340,
        child: Center(child: Text('Sem maçãs para analisar', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    const diseaseOrder = ['Healthy', 'Blotch', 'Scab', 'Rot', 'Anthracnose'];
    final Map<String, List<Apple>> byCondition = {};
    for (final a in apples) {
      byCondition.putIfAbsent(a.primaryCondition, () => []).add(a);
    }

    final clusters = <HullCluster>[];
    for (final d in diseaseOrder) {
      final group = byCondition[d];
      if (group == null || group.isEmpty) continue;
      final points = group.map((a) => Offset(
            (a.effectiveConfidence * 100).clamp(0.0, 100.0),
            ((a.worstFrame?.diseaseSum ?? 0.0) * 100).clamp(0.0, 100.0),
          )).toList();
      final hull = _convexHull(_inflate(points, 3.0));
      final avgConf = points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
      final avgSev = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
      clusters.add(HullCluster(AppColors.displayName(d), AppColors.getColorForCondition(d), hull, points, avgConf, avgSev));
    }
    // Clusters maiores desenhados primeiro (atrás), para não tapar clusters pequenos.
    clusters.sort((a, b) => _polygonArea(b.hull).compareTo(_polygonArea(a.hull)));

    void updateHover(Offset localPosition, Size size) {
      const leftMargin = 34.0;
      const bottomMargin = 20.0;
      final plotW = size.width - leftMargin;
      final plotH = size.height - bottomMargin;
      if (plotW <= 0 || plotH <= 0) return;
      final dx = localPosition.dx - leftMargin;
      final dy = localPosition.dy;
      if (dx < 0 || dx > plotW || dy < 0 || dy > plotH) {
        if (_hovered != null) setState(() => _hovered = null);
        return;
      }
      final dataX = (dx / plotW) * 100;
      final dataY = 100 - (dy / plotH) * 100;

      Apple? nearest;
      double bestDist = double.infinity;
      for (final a in apples) {
        final ax = (a.effectiveConfidence * 100).clamp(0.0, 100.0);
        final ay = ((a.worstFrame?.diseaseSum ?? 0.0) * 100).clamp(0.0, 100.0);
        final d = (ax - dataX) * (ax - dataX) + (ay - dataY) * (ay - dataY);
        if (d < bestDist) {
          bestDist = d;
          nearest = a;
        }
      }
      final next = (nearest != null && sqrt(bestDist) < 5) ? nearest : null;
      if (next != _hovered) setState(() => _hovered = next);
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 340,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.change_history, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Confiança vs. Severidade (Território por Patologia)',
                style: TextStyle(color: Colors.cyanAccent, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          Tooltip(
            message: 'Cada forma é o invólucro convexo (convex hull) dos casos reais dessa patologia — '
                      'um polígono com tantos cantos quantos necessários para envolver os pontos extremos.\n\n'
                      'Forma fina e achatada = essa patologia ocorre sempre numa faixa estreita '
                      '(ex: Healthy tende a ficar perto de 0% de severidade).\n'
                      'Forma larga = maior variação de confiança/severidade nessa patologia.',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
            ),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
          ),
        ]),
        Text('Cada ponto = uma maçã · forma = território real de cada patologia',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final size = constraints.biggest;
            return MouseRegion(
              onHover: (event) => updateHover(event.localPosition, size),
              onExit: (_) {
                if (_hovered != null) setState(() => _hovered = null);
              },
              child: GestureDetector(
                onTapDown: (details) => updateHover(details.localPosition, size),
                child: CustomPaint(
                  size: size,
                  painter: HullPainter(
                    clusters: clusters,
                    hoveredApple: _hovered,
                    gridColor: AppColors.textSecondary.withValues(alpha: 0.08),
                    axisColor: AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          _hovered != null
              ? '${_hovered!.id}  ·  ${AppColors.displayName(_hovered!.primaryCondition)}  ·  confiança ${(_hovered!.effectiveConfidence * 100).toStringAsFixed(0)}%  ·  severidade ${((_hovered!.worstFrame?.diseaseSum ?? 0.0) * 100).toStringAsFixed(0)}%'
              : 'Passa o rato sobre um ponto para detalhes',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: clusters.map((c) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                  color: c.color, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('${c.label} (${c.count})', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
            ],
          )).toList(),
        ),
      ]),
    );
  }
}

class HullCluster {
  final String label;
  final Color color;
  final List<Offset> hull; // polígono já com padding, em espaço de dados 0-100
  final List<Offset> points; // pontos reais (uma maçã cada), em espaço de dados
  final double avgConf;
  final double avgSeverity;

  HullCluster(this.label, this.color, this.hull, this.points, this.avgConf, this.avgSeverity);

  int get count => points.length;
}

class HullPainter extends CustomPainter {
  final List<HullCluster> clusters;
  final Apple? hoveredApple;
  final Color gridColor;
  final Color axisColor;

  static const double leftMargin = 34.0;
  static const double bottomMargin = 20.0;

  HullPainter({
    required this.clusters,
    required this.hoveredApple,
    required this.gridColor,
    required this.axisColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - leftMargin;
    final plotH = size.height - bottomMargin;
    if (plotW <= 0 || plotH <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (int i = 0; i <= 5; i++) {
      final gx = leftMargin + plotW * i / 5;
      canvas.drawLine(Offset(gx, 0), Offset(gx, plotH), gridPaint);
      final gy = plotH * i / 5;
      canvas.drawLine(Offset(leftMargin, gy), Offset(size.width, gy), gridPaint);
    }

    void drawText(String text, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: axisColor, fontSize: 9)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos);
    }

    for (int i = 0; i <= 5; i++) {
      final v = i * 20;
      final gx = leftMargin + plotW * i / 5;
      drawText('$v%', Offset(gx - 9, plotH + 4));
      final gy = plotH - plotH * i / 5;
      drawText('$v%', Offset(0, gy - 5));
    }

    Offset toPx(Offset data) => Offset(
          leftMargin + (data.dx.clamp(0.0, 100.0) / 100) * plotW,
          plotH - (data.dy.clamp(0.0, 100.0) / 100) * plotH,
        );

    for (final cluster in clusters) {
      if (cluster.hull.length >= 3) {
        final path = Path();
        for (int i = 0; i < cluster.hull.length; i++) {
          final p = toPx(cluster.hull[i]);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        path.close();

        canvas.drawPath(path, Paint()..color = cluster.color.withValues(alpha: 0.22)..style = PaintingStyle.fill);
        canvas.drawPath(
          path,
          Paint()
            ..color = cluster.color.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }

      for (final pt in cluster.points) {
        final p = toPx(pt);
        canvas.drawCircle(p, 2.6, Paint()..color = cluster.color.withValues(alpha: 0.85));
      }
    }

    if (hoveredApple != null) {
      final x = (hoveredApple!.effectiveConfidence * 100).clamp(0.0, 100.0);
      final y = ((hoveredApple!.worstFrame?.diseaseSum ?? 0.0) * 100).clamp(0.0, 100.0);
      final p = toPx(Offset(x, y));
      canvas.drawCircle(
        p, 5.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant HullPainter oldDelegate) =>
      oldDelegate.clusters != clusters || oldDelegate.hoveredApple != hoveredApple;
}

// ── Ridgeline (Joyplot): densidade de confiança por patologia ──────────────

Widget confidenceHeatStrip(List<Apple> apples) {
    if (apples.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 400,
        child: Center(child: Text('Sem maçãs para analisar', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    const maxCells = 60;
    final sorted = [...apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final recent = sorted.length > maxCells ? sorted.sublist(sorted.length - maxCells) : sorted;

    Color cellColor(Apple a) {
      final base = AppColors.getColorForCondition(a.primaryCondition);
      final alpha = (0.25 + a.effectiveConfidence * 0.75).clamp(0.25, 1.0);
      return base.withValues(alpha: alpha);
    }

    bool needsAttention(Apple a) => a.primaryCondition != 'Healthy' && a.effectiveConfidence < 0.6;

    final avgConf = recent.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / recent.length;
    final flaggedCount = recent.where(needsAttention).length;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 400,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Faixa de Triagem Recente', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          Tooltip(
            message: 'Cada célula representa uma maçã, em ordem cronológica (mais recente à direita).\n\n'
                      '• Cor = patologia detetada\n'
                      '• Opacidade = confiança da CNN (esbatido = incerto, vivo = confiante)\n\n'
                      'Uma célula colorida E esbatida é o pior cenário: uma doença recente que a IA ainda '
                      'não tem a certeza de ter classificado bem — marcada com contorno branco, é a primeira '
                      'a merecer um olhar humano.',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
            ),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
          ),
        ]),
        Text(
          'Últimas ${recent.length} maçãs · confiança média ${(avgConf * 100).toStringAsFixed(0)}%'
          '${flaggedCount > 0 ? " · $flaggedCount a precisar de atenção" : ""}',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Row(
                children: recent.map((a) {
                  final flagged = needsAttention(a);
                  return Expanded(
                    child: Tooltip(
                      message: '${a.id}\n${a.primaryCondition}\nConfiança: ${(a.effectiveConfidence * 100).toStringAsFixed(0)}%'
                          '${flagged ? "\n⚠ precisa de atenção" : ""}',
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: cellColor(a).withValues(alpha: 0.6)),
                      ),
                      textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 10, height: 1.4),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 0.8),
                        decoration: BoxDecoration(
                          color: cellColor(a),
                          borderRadius: BorderRadius.circular(2),
                          border: flagged ? Border.all(color: Colors.white, width: 1) : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'].map((c) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(
                      color: AppColors.getColorForCondition(c), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  Text(AppColors.displayName(c), style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
                ],
              )).toList(),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text('esbatido = incerto', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              const SizedBox(width: 6),
              Container(
                width: 46,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(colors: [AppColors.healthy.withValues(alpha: 0.25), AppColors.healthy]),
                ),
              ),
              const SizedBox(width: 6),
              Text('vivo = confiante', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
            ]),
          ]),
        ),
      ]),
    );
  }

  // ── B3/B4: Matriz 2×2 Confiança × Classificação ─────────────────────────
  //
  // x = confiança da CNN: 0 = <75% · 1 = ≥75%
  // y = classificação: 0 = incorreta (operador corrigiu) · 1 = correta
  //
  // (1,0): alta confiança + incorreto → mais grave (CNN confiante mas errou)
  // (0,0): baixa confiança + incorreto → esperado (CNN incerta e errou)
  // (1,1): alta confiança + correto → ideal
  // (0,1): baixa confiança + correto → conservador/seguro

Widget cnnCostMatrixChart(Batch batch) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseService.getManualReviews(batchId: batch.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return GlassCard(
              padding: const EdgeInsets.all(20),
              height: 280,
              child: const Center(child: CircularProgressIndicator()));
        }

        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return GlassCard(
            padding: const EdgeInsets.all(20),
            height: 280,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.grid_view_rounded, color: AppColors.textSecondary, size: 32),
              const SizedBox(height: 12),
              Text('Matriz Confiança × Classificação — Sem revisões manuais',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Esta matriz cruza a confiança CNN (x) com a correção do operador (y).\n'
                'Aparece quando existem correções na triagem humana.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ]),
          );
        }

        // Compute 2×2 matrix:
        //   x=0 = conf <75%  |  x=1 = conf ≥75%
        //   y=0 = incorrect  |  y=1 = correct
        int c00 = 0, c01 = 0, c10 = 0, c11 = 0;
        for (final r in rows) {
          final orig = r['original_class'] as String? ?? '';
          if (orig.isEmpty) continue;
          final corr = r['corrected_class'] as String?;
          final confRaw = (r['original_confidence'] ?? 0) as num;
          final confVal = confRaw.toDouble();
          final confPct = confVal <= 1.0 ? confVal * 100 : confVal;
          final highConf = confPct >= 75.0; // x=1
          final isCorrect = corr == null || corr.isEmpty || corr == orig; // y=1

          if (!highConf && !isCorrect) c00++;
          else if (!highConf && isCorrect) c01++;
          else if (highConf && !isCorrect) c10++;
          else c11++;
        }
        final total = c00 + c01 + c10 + c11;

        String pctStr(int c) => total > 0 ? '${(c / total * 100).round()}%' : '0%';

        return GlassCard(
          padding: const EdgeInsets.all(20),
          height: 280,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Row(children: [
                Icon(Icons.grid_view_rounded, color: Colors.orangeAccent, size: 20),
                SizedBox(width: 8),
                Text('Matriz Confiança × Classificação',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 15, fontWeight: FontWeight.bold)),
              ]),
              Tooltip(
                message: 'x = confiança CNN  (0 = <75% · 1 = ≥75%)\n'
                         'y = classificação   (0 = incorreta · 1 = correta, segundo o operador)\n\n'
                         '(0,1)  baixa conf + correto    → conservador, sem custo\n'
                         '(1,1)  alta conf + correto     → ideal, sem custo\n'
                         '(0,0)  baixa conf + incorreto  → esperado, custo ×1\n'
                         '(1,0)  alta conf + incorreto   → grave, custo ×3\n\n'
                         'Total: $total revisões',
                padding: const EdgeInsets.all(12),
                textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
                decoration: BoxDecoration(
                  color: AppColors.surface, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
                ),
                child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 15),
              ),
            ]),
            Text('x = confiança CNN (<75% / ≥75%)  ·  y = correto segundo operador  ·  $total revisões',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 12),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Y axis label (vertical)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Text('Classificação (y)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                // 2×2 grid
                Expanded(
                  child: Column(children: [
                    // y=1 row: Correto
                    Expanded(
                      child: Row(children: [
                        Expanded(child: matrixCell('(0,1)', c01, pctStr(c01), 'Baixa conf.\nCorreto', Colors.teal)),
                        const SizedBox(width: 6),
                        Expanded(child: matrixCell('(1,1)', c11, pctStr(c11), 'Alta conf.\nCorreto', AppColors.healthy)),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    // y=0 row: Incorreto
                    Expanded(
                      child: Row(children: [
                        Expanded(child: matrixCell('(0,0)', c00, pctStr(c00), 'Baixa conf.\nIncorreto', Colors.amber)),
                        const SizedBox(width: 6),
                        Expanded(child: matrixCell('(1,0)', c10, pctStr(c10), 'Alta conf.\nIncorreto ×3', Colors.redAccent)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    // X axis labels
                    Row(children: [
                      Expanded(child: Center(child: Text('x=0 (Conf. <75%)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)))),
                      const SizedBox(width: 6),
                      Expanded(child: Center(child: Text('x=1 (Conf. ≥75%)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)))),
                    ]),
                  ]),
                ),
                // Y axis tick labels
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Column(children: [
                    Expanded(child: Center(child: RotatedBox(quarterTurns: 1, child: Text('y=1', style: TextStyle(color: AppColors.textSecondary, fontSize: 9))))),
                    const SizedBox(height: 6),
                    Expanded(child: Center(child: RotatedBox(quarterTurns: 1, child: Text('y=0', style: TextStyle(color: AppColors.textSecondary, fontSize: 9))))),
                    const SizedBox(height: 22),
                  ]),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }

Widget matrixCell(String coord, int count, String pctLabel, String label, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(coord, style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 1),
              Text('$count', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold, height: 1.1)),
              Text(pctLabel, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 10)),
              const SizedBox(height: 1),
              Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 8.5), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }

  // ── C1: Composição Temporal de Doenças ──────────────────────────────────
  // Divide a sessão em 8 janelas de tempo equitativas e mostra a proporção
  // de cada doença em cada janela — revela se há surtos ou zonas contaminadas.

Widget confidenceRidgelineByPathology(List<Apple> apples) {
    // Ordem escolhida para afastar patologias com cores próximas (Rot e
    // Anthracnose são ambas tons de vermelho/rosa) — reduz a confusão visual
    // onde as cristas se sobrepõem.
    const diseaseOrder = ['Anthracnose', 'Blotch', 'Rot', 'Scab', 'Healthy'];
    final Map<String, List<double>> confsByDisease = {};
    for (final a in apples) {
      confsByDisease.putIfAbsent(a.primaryCondition, () => []).add((a.effectiveConfidence * 100).clamp(0.0, 100.0));
    }

    final active = diseaseOrder.where((d) => (confsByDisease[d] ?? []).isNotEmpty).toList();

    if (active.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 400,
        child: Center(child: Text('Sem dados de confiança para exibir', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    // Eixo fixo em 0-100%: uma patologia sem casos abaixo de 60% de confiança
    // simplesmente produz uma crista "achatada" perto de 0 nessa zona — a
    // curva só sobe perto de onde os dados reais estão, sem precisar de
    // recortar o eixo.
    const samples = 60;
    const bandwidth = 9.0;
    List<double> gaussianKde(List<double> xs) {
      final density = List<double>.filled(samples, 0.0);
      for (int i = 0; i < samples; i++) {
        final t = i / (samples - 1) * 100;
        double sum = 0;
        for (final x in xs) {
          final z = (t - x) / bandwidth;
          sum += exp(-0.5 * z * z);
        }
        density[i] = sum;
      }
      final maxD = density.reduce(max);
      if (maxD > 0) {
        for (int i = 0; i < samples; i++) {
          density[i] /= maxD;
        }
      }
      return density;
    }

    final series = active.map((d) {
      final xs = confsByDisease[d]!;
      final avg = xs.reduce((a, b) => a + b) / xs.length;
      return RidgeSeries(AppColors.displayName(d), AppColors.getColorForCondition(d), gaussianKde(xs), xs.length, avg);
    }).toList();

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 400,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Confiança por Patologia (Distribuição)',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          Tooltip(
            message: 'Cada crista mostra a forma completa da distribuição de confiança da CNN para essa patologia — '
                      'não apenas a média.\n\n'
                      'Crista estreita e alta = diagnóstico consistente nessa patologia.\n'
                      'Crista larga ou com várias corcovas = incerteza real ou grupos distintos de casos.',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
            ),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
          ),
        ]),
        Text('Forma da distribuição de confiança CNN · uma crista por patologia · lote filtrado',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 10),
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: RidgelinePainter(series: series, samples: samples, axisColor: AppColors.textSecondary, xMin: 0, xMax: 100),
          ),
        ),
      ]),
    );
  }

class RidgeSeries {
  final String label;
  final Color color;
  final List<double> density; // normalizada 0-1, amostrada uniformemente em 0-100%
  final int count;
  final double avgConf;

  RidgeSeries(this.label, this.color, this.density, this.count, this.avgConf);
}

class RidgelinePainter extends CustomPainter {
  final List<RidgeSeries> series; // ordem: topo → base
  final int samples;
  final Color axisColor;
  final double xMin;
  final double xMax;

  static const double leftMargin = 78.0;
  static const double bottomMargin = 18.0;

  RidgelinePainter({
    required this.series,
    required this.samples,
    required this.axisColor,
    this.xMin = 0,
    this.xMax = 100,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - leftMargin;
    final plotH = size.height - bottomMargin;
    if (plotW <= 0 || plotH <= 0 || series.isEmpty) return;

    final rowH = plotH / series.length;
    // Sobreposição reduzida (era 1.7×) para que cristas de cores próximas
    // (ex: Rot/Anthracnose) não se fundam visualmente umas nas outras.
    final ridgeMaxHeight = rowH * 1.2;

    final gridPaint = Paint()
      ..color = axisColor.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (int i = 0; i <= 5; i++) {
      final gx = leftMargin + plotW * i / 5;
      canvas.drawLine(Offset(gx, 0), Offset(gx, plotH), gridPaint);
    }

    // Desenhar de cima para baixo: a crista de baixo é pintada por último e
    // fica à frente, sobrepondo ligeiramente a base da crista acima (efeito joyplot).
    for (int s = 0; s < series.length; s++) {
      final ser = series[s];
      final baseline = rowH * s + rowH * 0.88;

      final path = Path();
      for (int i = 0; i < samples; i++) {
        final x = leftMargin + plotW * i / (samples - 1);
        final y = baseline - ser.density[i] * ridgeMaxHeight;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.lineTo(leftMargin + plotW, baseline);
      path.lineTo(leftMargin, baseline);
      path.close();

      canvas.drawPath(path, Paint()..color = ser.color.withValues(alpha: 0.42)..style = PaintingStyle.fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = ser.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${ser.label}\n${ser.count} · ${ser.avgConf.toStringAsFixed(0)}%',
          style: TextStyle(color: ser.color, fontSize: 9.5, fontWeight: FontWeight.bold, height: 1.25),
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.right,
      )..layout(maxWidth: leftMargin - 10);
      tp.paint(canvas, Offset(leftMargin - 8 - tp.width, rowH * s + rowH * 0.32));
    }

    void drawText(String text, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: axisColor, fontSize: 9)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos);
    }

    for (int i = 0; i <= 5; i++) {
      final v = (xMin + (xMax - xMin) * i / 5).round();
      final gx = leftMargin + plotW * i / 5;
      drawText('$v%', Offset(gx - 10, plotH + 3));
    }
  }

  @override
  bool shouldRepaint(covariant RidgelinePainter oldDelegate) => true;
}

// ── Cronograma Analítico de Qualidade ───────────────────────────────────────
// Composição de patologias empilhada por janela temporal, confiança da CNN
// sobreposta e surtos marcados. A legenda é clicável: tocar numa patologia
// remove-a da pilha (útil para isolar as restantes quando "Healthy" domina
// visualmente o gráfico).

Widget temporalDiseaseDistribution(Batch batch) {
    final sorted = [...batch.apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    const diseases = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];

    if (sorted.length < 3) {
      return GlassCard(
        padding: const EdgeInsets.all(20), height: 300,
        child: Center(child: Text('Dados insuficientes para análise temporal (mínimo 3 maçãs)',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.center)),
      );
    }

    final nBins = min(8, sorted.length);
    final double perBin = sorted.length / nBins;
    final List<List<int>> bins = [];
    final List<String> binLabels = [];

    for (int b = 0; b < nBins; b++) {
      final start = (b * perBin).round().clamp(0, sorted.length);
      final end = ((b + 1) * perBin).round().clamp(0, sorted.length);
      if (start >= end) continue;
      final slice = sorted.sublist(start, end);
      bins.add(diseases.map((d) => slice.where((a) => a.primaryCondition == d).length).toList());
      final label = DateFormat('HH:mm').format(slice.first.timestamp);
      binLabels.add(label);
    }

    final barGroups = bins.asMap().entries.map((e) {
      final i = e.key;
      final counts = e.value;
      final total = counts.fold(0, (s, c) => s + c);
      final rodStack = <BarChartRodStackItem>[];
      double cumY = 0;
      for (int d = 0; d < diseases.length; d++) {
        final pct = total > 0 ? counts[d] / total * 100.0 : 0.0;
        if (pct > 0.01) {
          rodStack.add(BarChartRodStackItem(
              cumY, cumY + pct, AppColors.getColorForCondition(diseases[d]).withValues(alpha: 0.88)));
          cumY += pct;
        }
      }
      return BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(
          toY: 100,
          width: 28,
          rodStackItems: rodStack,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true, toY: 100,
            color: AppColors.textSecondary.withValues(alpha: 0.06),
          ),
        )],
      );
    }).toList();

    final dist = batch.healthDistribution;
    final activeDiseases = diseases.where((d) => (dist[d] ?? 0) > 0).toList();

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 300,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.stacked_bar_chart, color: Color(0xffF59E0B), size: 20),
          SizedBox(width: 8),
          Text('Composição Temporal por Patologia',
              style: TextStyle(color: Color(0xffF59E0B), fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        Text('Distribuição proporcional de doenças ao longo da sessão · $nBins janelas de tempo',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        Expanded(
          child: BarChart(BarChartData(
            maxY: 100,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true, drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: AppColors.textSecondary.withValues(alpha: 0.1), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= binLabels.length) return const SizedBox();
                  return SideTitleWidget(meta: meta,
                    child: Text(binLabels[i], style: TextStyle(color: AppColors.textSecondary, fontSize: 7.5)));
                },
              )),
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 7.5)),
              )),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(fitInsideHorizontally: true, fitInsideVertically: true,
                getTooltipColor: (_) => AppColors.surface.withValues(alpha: 0.95),
                getTooltipItem: (group, gIdx, rod, stackIdx) {
                  if (gIdx >= bins.length) return null;
                  final counts = bins[gIdx];
                  final total = counts.fold(0, (s, c) => s + c);
                  // Find the disease for the tapped stack item
                  int accumulated = 0;
                  String disease = '';
                  int count = 0;
                  for (int d = 0; d < diseases.length; d++) {
                    if (counts[d] > 0) {
                      if (accumulated == stackIdx) { disease = diseases[d]; count = counts[d]; break; }
                      accumulated++;
                    }
                  }
                  if (disease.isEmpty) return null;
                  final pct = total > 0 ? count / total * 100 : 0.0;
                  return BarTooltipItem(
                    '${binLabels[gIdx]}\n$disease: $count (${pct.toStringAsFixed(1)}%)',
                    TextStyle(color: AppColors.getColorForCondition(disease), fontSize: 10, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
            barGroups: barGroups,
          )),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 10, children: activeDiseases.map((d) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.getColorForCondition(d), shape: BoxShape.circle)),
          const SizedBox(width: 3),
          Text(d, style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
        ])).toList()),
      ]),
    );
  }

  // ── C2: Taxa de Doença por Janela Temporal (Surtos) ──────────────────────
  // Detecta janelas de tempo com taxa de doença anormalmente elevada (surtos):
  // pontos a vermelho se a taxa exceder a média + 1.5 desvios-padrão.

Widget temporalDiseaseRate(Batch batch) {
    final sorted = [...batch.apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (sorted.length < 3) {
      return GlassCard(
        padding: const EdgeInsets.all(20), height: 300,
        child: Center(child: Text('Dados insuficientes para deteção de surtos',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.center)),
      );
    }

    final nBins = min(8, sorted.length);
    final double perBin = sorted.length / nBins;
    final List<double> rates = [];
    final List<String> labels = [];

    for (int b = 0; b < nBins; b++) {
      final start = (b * perBin).round().clamp(0, sorted.length);
      final end = ((b + 1) * perBin).round().clamp(0, sorted.length);
      if (start >= end) continue;
      final slice = sorted.sublist(start, end);
      final diseased = slice.where((a) => a.primaryCondition != 'Healthy').length;
      rates.add(slice.isEmpty ? 0.0 : diseased / slice.length * 100.0);
      labels.add(DateFormat('HH:mm').format(slice.first.timestamp));
    }

    final avgRate = rates.isEmpty ? 0.0 : rates.fold(0.0, (s, r) => s + r) / rates.length;
    final variance = rates.fold(0.0, (s, r) => s + (r - avgRate) * (r - avgRate)) / max(1, rates.length);
    final std = sqrt(variance);
    final burstThreshold = avgRate + max(std * 1.5, 10.0);
    final burstBins = rates.asMap().entries.where((e) => e.value > burstThreshold).map((e) => e.key).toSet();
    final maxY = max(rates.isEmpty ? 10.0 : rates.reduce(max) * 1.25, 15.0);

    final spots = rates.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final avgSpots = spots.isEmpty ? <FlSpot>[] : [FlSpot(0, avgRate), FlSpot((spots.length - 1).toDouble(), avgRate)];

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 300,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Row(children: [
            Icon(Icons.show_chart, color: Color(0xffF59E0B), size: 20),
            SizedBox(width: 8),
            Text('Surtos de Doença na Sessão',
                style: TextStyle(color: Color(0xffF59E0B), fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          if (burstBins.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Text('${burstBins.length} surto(s) detetado(s)',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.healthy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.healthy.withValues(alpha: 0.3)),
              ),
              child: Text('Sem surtos detetados',
                  style: TextStyle(color: AppColors.healthy, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
        ]),
        Text('Taxa de doença por janela · média: ${avgRate.toStringAsFixed(1)}%  · limiar de surto: ${burstThreshold.toStringAsFixed(1)}%',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        Expanded(
          child: LineChart(LineChartData(
            maxY: maxY, minY: 0,
            gridData: FlGridData(
              show: true, drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: AppColors.textSecondary.withValues(alpha: 0.1), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 22, interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (v != v.roundToDouble() || i < 0 || i >= labels.length) return const SizedBox();
                  return SideTitleWidget(meta: meta,
                    child: Text(labels[i], style: TextStyle(color: AppColors.textSecondary, fontSize: 7.5)));
                },
              )),
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 7.5)),
              )),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(fitInsideHorizontally: true, fitInsideVertically: true,
                getTooltipColor: (_) => AppColors.surface.withValues(alpha: 0.95),
                getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                  final i = s.x.toInt();
                  final isBurst = burstBins.contains(i);
                  return LineTooltipItem(
                    '${i < labels.length ? labels[i] : ''}\n${s.y.toStringAsFixed(1)}% doença${isBurst ? '\n⚠ Surto: taxa ${(s.y - avgRate).toStringAsFixed(1)}pp acima da média' : ''}',
                    TextStyle(color: isBurst ? Colors.redAccent : AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: AppColors.healthy,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) {
                    final isBurst = burstBins.contains(spot.x.toInt());
                    return FlDotCirclePainter(
                      radius: isBurst ? 5.5 : 3.5,
                      color: isBurst ? Colors.redAccent : AppColors.healthy,
                      strokeWidth: isBurst ? 2 : 1,
                      strokeColor: isBurst ? Colors.redAccent.withValues(alpha: 0.4) : Colors.white24,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [AppColors.healthy.withValues(alpha: 0.2), AppColors.healthy.withValues(alpha: 0.0)],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  ),
                ),
              ),
              if (avgSpots.length >= 2)
                LineChartBarData(
                  spots: avgSpots,
                  isCurved: false,
                  color: Colors.amber.withValues(alpha: 0.6),
                  barWidth: 1.5,
                  dashArray: [5, 5],
                  dotData: const FlDotData(show: false),
                ),
            ],
          )),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Container(width: 12, height: 2.5, color: AppColors.healthy),
          const SizedBox(width: 4),
          Text('Taxa de doença', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          const SizedBox(width: 14),
          Container(width: 5, height: 2.5, color: Colors.amber.withValues(alpha: 0.6)),
          const SizedBox(width: 2),
          Container(width: 5, height: 2.5, color: Colors.amber.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text('Média', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          const SizedBox(width: 14),
          Container(width: 9, height: 9, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('Surto (>1.5σ acima da média)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
        ]),
      ]),
    );
  }

  // ── D1: Pressão Fitossanitária (Radar Composto) ──────────────────────────
  // Combina 4 dimensões num radar: Propagação, Dano Comercial, Taxa de Doença,
  // e Diversidade de Doenças. A área do polígono representa a pressão total.

Widget cnnEfficacy(Batch batch, double avgConf, int uncertainCount) {
    final total = batch.totalApples;
    if (total == 0) return const SizedBox();

    // Bucket confidence distribution from worstFrame probabilities
    int highConf = 0, midConf = 0, lowConf = 0, veryLow = 0;
    for (final apple in batch.apples) {
      final conf = apple.effectiveConfidence;
      if (conf >= 0.80) highConf++;
      else if (conf >= 0.65) midConf++;
      else if (conf >= 0.50) lowConf++;
      else veryLow++;
    }
    final highPct  = highConf / total;
    final midPct   = midConf / total;
    final lowPct   = lowConf / total;
    final veryPct  = veryLow / total;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.smart_toy, color: Colors.cyanAccent, size: 22),
          SizedBox(width: 10),
          Text('Eficácia CNN — Distribuição de Confiança',
              style: TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: confBucket('≥ 80%\nAlta Confiança', highConf, highPct, AppColors.healthy)),
          const SizedBox(width: 8),
          Expanded(child: confBucket('65–80%\nConfiança Média', midConf, midPct, Colors.amber)),
          const SizedBox(width: 8),
          Expanded(child: confBucket('50–65%\nBaixa Confiança', lowConf, lowPct, Colors.orangeAccent)),
          const SizedBox(width: 8),
          Expanded(child: confBucket('< 50%\nIncerto', veryLow, veryPct, Colors.redAccent)),
        ]),
        const SizedBox(height: 16),
        // Stacked progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(children: [
            barSeg(highPct, AppColors.healthy),
            barSeg(midPct, Colors.amber),
            barSeg(lowPct, Colors.orangeAccent),
            barSeg(veryPct, Colors.redAccent),
          ]),
        ),
        const SizedBox(height: 12),
        Text('Confiança média neste lote: ${avgConf.toStringAsFixed(1)}%  ·  '
            '$uncertainCount maçã${uncertainCount != 1 ? "s" : ""} em revisão humana',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ]),
    );
  }

Widget confBucket(String label, int count, double pct, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text('${(pct * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        Text('$count maçãs', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10), textAlign: TextAlign.center),
      ]),
    );
  }

Widget barSeg(double fraction, Color color) {
    return Flexible(
      flex: (fraction * 1000).round().clamp(1, 1000),
      child: Container(height: 10, color: color),
    );
  }

Widget probMatrix(List<Apple> apples) {
    const conditions = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];

    // Group apples by predicted class
    final Map<String, List<Apple>> groups = {for (final c in conditions) c: []};
    for (final a in apples) {
      groups[a.primaryCondition]?.add(a);
    }

    // Compute average probability per class per group
    Map<String, Map<String, double>> matrix = {};
    for (final pred in conditions) {
      final grp = groups[pred]!;
      if (grp.isEmpty) { matrix[pred] = {for (final c in conditions) c: 0.0}; continue; }
      Map<String, double> avg = {for (final c in conditions) c: 0.0};
      for (final a in grp) {
        for (final c in conditions) {
          avg[c] = avg[c]! + ((c == a.primaryCondition) ? a.effectiveConfidence : (a.worstFrame?.probabilities[c] ?? 0.0));
        }
      }
      matrix[pred] = avg.map((k, v) => MapEntry(k, v / grp.length));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.grid_on, color: Colors.purpleAccent, size: 20),
          const SizedBox(width: 8),
          Text('Matriz de Confusão e Confiança CNN',
              style: TextStyle(color: Colors.purpleAccent, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        Text(
          'Diagonal (a negrito) = certeza do diagnóstico. Células fora da diagonal acendem-se a vermelho/laranja em caso de confusão entre patologias.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 16),
        Table(
          border: TableBorder.all(color: AppColors.textSecondary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            0: const FixedColumnWidth(100),
            1: const FlexColumnWidth(),
            2: const FlexColumnWidth(),
            3: const FlexColumnWidth(),
            4: const FlexColumnWidth(),
            5: const FlexColumnWidth(),
            6: const FixedColumnWidth(40),
          },
          children: [
            // Header row
            TableRow(
              decoration: BoxDecoration(color: AppColors.surfaceBright),
              children: [
                cell('Previsto \\ Real', bold: true, color: Colors.white54),
                ...conditions.map((c) => cell(c.substring(0, [c.length, 5].reduce((a, b) => a < b ? a : b)),
                    bold: true, color: AppColors.getColorForCondition(c))),
                cell('N', bold: true, color: Colors.white54),
              ],
            ),
            // Data rows
            ...conditions.map((pred) {
              final grp = groups[pred]!;
              final row = matrix[pred]!;
              return TableRow(
                decoration: BoxDecoration(
                  color: grp.isEmpty ? Colors.transparent : AppColors.getColorForCondition(pred).withValues(alpha: 0.02),
                ),
                children: [
                  cell(pred, bold: true, color: AppColors.getColorForCondition(pred)),
                  ...conditions.map((c) {
                    final val = row[c] ?? 0.0;
                    final isDiag = c == pred;
                    return probCell(val, isDiag, AppColors.getColorForCondition(pred));
                  }),
                  cell('${grp.length}', color: AppColors.textSecondary),
                ],
              );
            }),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            colorLegendChip('Certeza CNN (Diagonal)', Colors.cyanAccent.withValues(alpha: 0.18)),
            const SizedBox(width: 10),
            colorLegendChip('Confusão Elevada (>15%)', Colors.redAccent.withValues(alpha: 0.15)),
            const SizedBox(width: 10),
            colorLegendChip('Confusão Leve (5-15%)', Colors.orangeAccent.withValues(alpha: 0.1)),
          ],
        ),
      ]),
    );
  }

Widget colorLegendChip(String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
        ),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: AppColors.textSecondary, fontSize: 8)),
      ],
    );
  }

Widget cell(String text, {bool bold = false, Color? color}) {
    final finalColor = color ?? AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(text,
          style: TextStyle(color: finalColor, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 10)),
    );
  }

Widget probCell(double val, bool isDiag, Color diagColor) {
    final pct = (val * 100);
    final color = isDiag
        ? (pct >= 70 ? AppColors.healthy : pct >= 50 ? Colors.amber : Colors.redAccent)
        : (pct > 15 ? Colors.redAccent : (pct > 5 ? Colors.orangeAccent : (AppColors.isDark ? Colors.white38 : Colors.black38)));
        
    final cellBg = isDiag
        ? diagColor.withValues(alpha: (val * 0.22).clamp(0.02, 0.28))
        : (val > 0.15 
            ? Colors.redAccent.withValues(alpha: (val * 0.15).clamp(0.02, 0.2)) 
            : (val > 0.05 
                ? Colors.orangeAccent.withValues(alpha: (val * 0.12).clamp(0.02, 0.12)) 
                : Colors.transparent));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      color: cellBg,
      child: Text(
        '${pct.toStringAsFixed(1)}%',
        style: TextStyle(
            color: color,
            fontWeight: isDiag ? FontWeight.bold : FontWeight.normal,
            fontSize: 10),
      ),
    );
  }

  // ── Comparação entre Lotes ────────────────────────────────────────────────

Widget bayesianDiagram(Batch batch, List<Batch> allBatches) {
    const allClasses = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];

    // Priori: proporção histórica em todos os lotes
    int totalHistorical = 0;
    final Map<String, int> historicalCounts = {for (final c in allClasses) c: 0};
    for (final b in allBatches) {
      totalHistorical += b.totalApples;
      for (final c in allClasses) {
        historicalCounts[c] = historicalCounts[c]! + (b.healthDistribution[c] ?? 0);
      }
    }
    final Map<String, double> priors = {
      for (final c in allClasses)
        c: totalHistorical > 0
            ? (historicalCounts[c]! / totalHistorical).clamp(0.01, 1.0)
            : 1.0 / allClasses.length,
    };

    // Verossimilhança: confiança média da CNN quando prevê cada classe
    final Map<String, double> likelihoods = {};
    for (final c in allClasses) {
      final classApples = batch.apples.where((a) => a.primaryCondition == c).toList();
      likelihoods[c] = classApples.isEmpty
          ? 0.05
          : (classApples.map((a) => a.effectiveConfidence).fold(0.0, (s, v) => s + v) / classApples.length)
              .clamp(0.01, 1.0);
    }

    // Posteriori: P(classe | lote) ∝ P(CNN | classe) × P(classe)
    final Map<String, double> unnorm = {
      for (final c in allClasses) c: likelihoods[c]! * priors[c]!,
    };
    final double normSum = unnorm.values.fold(0.0, (s, v) => s + v);
    final Map<String, double> posteriors = {
      for (final c in allClasses)
        c: normSum > 0 ? unnorm[c]! / normSum : 1.0 / allClasses.length,
    };

    // Exibir apenas doenças ativas ou com posteriori relevante
    final displayClasses = ['Rot', 'Scab', 'Blotch', 'Anthracnose']
        .where((c) => (batch.healthDistribution[c] ?? 0) > 0 || posteriors[c]! > 0.05)
        .toList();

    if (displayClasses.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.account_tree, color: Color(0xff8B5CF6), size: 20),
            SizedBox(width: 8),
            Text('Atualização Bayesiana do Diagnóstico',
                style: TextStyle(color: Color(0xff8B5CF6), fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 20),
          Center(
            child: Text('Lote saudável — sem patologias para análise Bayesiana',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
        ]),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Row(children: [
            Icon(Icons.account_tree, color: Color(0xff8B5CF6), size: 20),
            SizedBox(width: 8),
            Text('Atualização Bayesiana do Diagnóstico',
                style: TextStyle(color: Color(0xff8B5CF6), fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          Tooltip(
            message: 'Teorema de Bayes: P(Doença|Evidência) ∝ P(Evidência|Doença) × P(Doença)\n\n'
                     '• PRIORI: taxa histórica base de cada doença em todos os lotes\n'
                     '• VEROSSIMILHANÇA: confiança média da CNN ao detetar a doença neste lote\n'
                     '• POSTERIORI: crença atualizada — combina o contexto histórico com a evidência CNN\n\n'
                     '↑ Vermelho: CNN reforçou a hipótese de doença\n'
                     '↓ Verde: CNN descartou a hipótese\n'
                     '→ Amarelo: sem atualização significativa',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
            ),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
          ),
        ]),
        Text(
          'P(Doença|CNN) ∝ P(CNN|Doença) × P(Doença)  ·  $totalHistorical maçãs históricas',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 16),
        // Cabeçalhos das colunas
        Row(children: [
          const SizedBox(width: 90),
          Expanded(
            flex: 3,
            child: Center(
              child: Text('PRIORI\nBase histórica',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Center(
              child: Text('VEROSSIMILHANÇA\nCerteza CNN',
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            flex: 3,
            child: Center(
              child: Text('POSTERIORI\nCrença atualizada',
                  style: const TextStyle(color: Color(0xff8B5CF6), fontSize: 9, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        ...displayClasses.map((c) {
          final prior = priors[c]!;
          final likelihood = likelihoods[c]!;
          final posterior = posteriors[c]!;
          final color = AppColors.getColorForCondition(c);
          final delta = posterior - prior;
          final deltaColor = delta > 0.05
              ? Colors.redAccent
              : delta < -0.05
                  ? AppColors.healthy
                  : Colors.amber;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Label
              SizedBox(
                width: 90,
                child: Row(children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(c,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
              // Priori bar
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: prior.clamp(0.0, 1.0),
                      minHeight: 14,
                      backgroundColor: AppColors.textSecondary.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.5)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${(prior * 100).toStringAsFixed(1)}%',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(width: 8),
              // Verossimilhança bar
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: likelihood.clamp(0.0, 1.0),
                      minHeight: 14,
                      backgroundColor: Colors.cyanAccent.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent.withValues(alpha: 0.7)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${(likelihood * 100).toStringAsFixed(1)}%',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                ]),
              ),
              // Seta de atualização
              SizedBox(
                width: 28,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    delta > 0.05
                        ? Icons.arrow_upward
                        : delta < -0.05
                            ? Icons.arrow_downward
                            : Icons.remove,
                    color: deltaColor,
                    size: 14,
                  ),
                  Text(
                    '${delta >= 0 ? '+' : ''}${(delta * 100).toStringAsFixed(0)}pp',
                    style: TextStyle(color: deltaColor, fontSize: 7.5, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
              // Posteriori bar
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: posterior.clamp(0.0, 1.0),
                      minHeight: 14,
                      backgroundColor: const Color(0xff8B5CF6).withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xff8B5CF6)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${(posterior * 100).toStringAsFixed(1)}%',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
          );
        }).toList(),
        const SizedBox(height: 8),
        const Divider(height: 1, thickness: 0.5),
        const SizedBox(height: 8),
        Wrap(spacing: 14, children: [
          bayesChip(Colors.redAccent, 'Aumento ↑ — CNN reforça hipótese de doença'),
          bayesChip(AppColors.healthy, 'Redução ↓ — CNN descarta hipótese'),
          bayesChip(Colors.amber, 'Neutro → sem mudança significativa'),
        ]),
      ]),
    );
  }

Widget bayesChip(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
    ]);
  }

Widget overconfidenceCorrectionsChart(Batch batch, List<CorrectionHistory> corrections) {
    const labels = ['<60%', '60-70%', '70-80%', '80-90%', '90%+'];

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseService.getManualReviews(batchId: batch.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return GlassCard(padding: const EdgeInsets.all(20), height: 320, child: const Center(child: CircularProgressIndicator()));
        }

        final rows = snapshot.data ?? [];

        final totalByBucket = List<int>.filled(labels.length, 0);
        final confidentIncorrect = List<int>.filled(labels.length, 0);

        for (final r in rows) {
          final confVal = (r['original_confidence'] ?? 0) as num;
          final conf = confVal.toDouble();
          final idx = conf < 60 ? 0 : conf < 70 ? 1 : conf < 80 ? 2 : conf < 90 ? 3 : 4;
          totalByBucket[idx]++;

          final orig = r['original_class']?.toString();
          final corr = r['corrected_class']?.toString();
          if (corr != null && corr.isNotEmpty && orig != null && orig != corr) {
            confidentIncorrect[idx]++;
          }
        }

        final List<ScatterSpot> spots = [];
        for (int i = 0; i < labels.length; i++) {
          final total = totalByBucket[i];
          final incorrect = confidentIncorrect[i];
          final pctError = total > 0 ? (incorrect / total * 100) : 0.0;
          
          if (total > 0) {
            // Radius scales from 6.0 (1 apple) to 22.0 (maximum)
            final double radius = (total * 2.0 + 6.0).clamp(6.0, 22.0);
            spots.add(
              ScatterSpot(
                i.toDouble(),
                pctError,
                dotPainter: FlDotCirclePainter(
                  radius: radius,
                  color: Colors.redAccent.withValues(alpha: 0.45),
                  strokeWidth: 2,
                  strokeColor: Colors.redAccent,
                ),
              ),
            );
          }
        }

        return GlassCard(
          padding: const EdgeInsets.all(20),
          height: 320,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bubble_chart, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text('Bolhas de Excesso de Confiança (Erro da IA)',
                        style: TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                Tooltip(
                  message: 'Eixo Y: Taxa de erro % (correções que mudaram a classe prevista pela IA)\n'
                           'Eixo X: Faixa de confiança que a IA declarou\n'
                           'Tamanho da Bolha: Volume total de frutos nessa faixa.\n\n'
                           'Uma bolha grande e alta no quadrante superior direito (ex: 90%+) indica que a IA erra com frequência mesmo declarando alta certeza.',
                  padding: const EdgeInsets.all(12),
                  textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
                  ),
                  child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
                ),
              ],
            ),
            Text('Taxa de erro da IA vs. Faixa de confiança prevista · Tamanho = volume total', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 16),
            Expanded(
              child: ScatterChart(
                ScatterChartData(
                  scatterSpots: spots,
                  minX: -0.5, maxX: 4.5,
                  minY: 0, maxY: 100,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    getDrawingHorizontalLine: (value) => FlLine(color: AppColors.textSecondary.withValues(alpha: 0.1), strokeWidth: 0.8),
                    getDrawingVerticalLine: (value) => FlLine(color: AppColors.textSecondary.withValues(alpha: 0.1), strokeWidth: 0.8),
                  ),
                  borderData: FlBorderData(show: true, border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12)),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= labels.length) return const SizedBox();
                          return Text(labels[idx], style: TextStyle(color: AppColors.textSecondary, fontSize: 10));
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.redAccent, width: 1.5),
                ),
              ),
              const SizedBox(width: 6),
              Text('Bolha = Taxa de Erro da IA (Altura) vs. Volume (Raio)', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
            ])
          ]),
        );
      },
    );
  }

  // ── Timeline Mestre: Heatmap + Surtos + Sparkline de Entropia ─────────────
  // Fusão de 3 widgets em 1: heatmap de qualidade, deteção de surtos (⚠)
  // e o monitor cardíaco de entropia da IA como linha sobreposta.

