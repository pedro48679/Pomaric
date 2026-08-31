import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '_chart_kit.dart';

// ═══════════════════════════════════════════════════════════
// BI · FLUXO E CADÊNCIA
// Cadência vs sanidade (SPC) com a doença dominante na cor do ponto, e Sankey do fluxo de reclassificação.
// ═══════════════════════════════════════════════════════════
///                                faixa open-set evidente e badge de contagem.
///   • HarvestValueChart       , Copo de valor económico da colheita:
///                                Categoria A (Healthy) vs B (Blotch+Scab).
///
/// Cada widget PREENCHE o espaço do pai (pensado para viver dentro do
/// helper `_card(...)` da página). Não faz agregação, recebe payloads
/// já prontos dos adaptadores.
/// ════════════════════════════════════════════════════════════════════════

// ═════════════════════════ 1 · CADÊNCIA vs SANIDADE (SPC) ═════════════════════════

class SpcPoint {
  final String label; // lote/bucket (ex.: 'T-07')
  final double throughput; // maçãs/hora ativa (eixo esq.)
  final double contamRate; // 0..1 (eixo dir.)
  final String dominantClass; // doença #1 da sessão ('Healthy' se nenhuma)
  final bool breach;
  final String? period; // detalhe temporal para o hover (dia · janela · maçãs)
  final bool aggregated; // bloco de contexto (várias sessões antigas fundidas)
  const SpcPoint(
    this.label,
    this.throughput,
    this.contamRate, {
    this.dominantClass = 'Healthy',
    this.breach = false,
    this.period,
    this.aggregated = false,
  });
}

class CadenciaSanidadeData {
  final List<SpcPoint> points;
  final double meanRate;
  final double ucl;
  final double lcl;

  /// Índice do primeiro ponto dentro dos últimos 7 dias (zona de foco). 0
  /// quando não há histórico mais antigo, ou seja, quando tudo é recente.
  final int recentFromIndex;

  const CadenciaSanidadeData({
    required this.points,
    required this.meanRate,
    required this.ucl,
    required this.lcl,
    this.recentFromIndex = 0,
  });

  /// Só faz sentido destacar o recente quando existe contexto antigo a seguir.
  bool get hasFocusSplit => recentFromIndex > 0 && recentFromIndex < points.length;
}

class SpcCadenceChart extends StatelessWidget {
  final CadenciaSanidadeData data;
  const SpcCadenceChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final pts = data.points;
    if (pts.isEmpty) {
      return Center(child: Text('Sem dados no período', style: axisStyle(size: 11)));
    }
    final n = pts.length;
    final maxTp = pts.map((p) => p.throughput).fold<double>(1, math.max) * 1.15;
    const double leftRes = 34, rightRes = 34, botRes = 24;

    // Foco (últimos 7 dias) vs contexto (histórico agregado). O contexto fica
    // deliberadamente mais esbatido para o olho cair primeiro no recente.
    final split = data.recentFromIndex;
    final hasSplit = data.hasFocusSplit;
    bool isRecent(int i) => !hasSplit || i >= split;

    // NOTA de alinhamento: ambos os charts do Stack reservam SEMPRE os mesmos
    // espaços de eixo (showTitles true dos dois lados; o chart que não é dono
    // do eixo desenha widgets vazios), senão os plots ficam desalinhados.
    FlTitlesData titles(bool forBars) => FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            axisNameWidget: Text('maçãs/h', style: axisStyle(size: 9)),
            axisNameSize: 14,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: leftRes,
              getTitlesWidget: (v, _) => forBars
                  ? Text(v.toInt().toString(), style: axisStyle(size: 8))
                  : const SizedBox.shrink(),
            ),
          ),
          rightTitles: AxisTitles(
            axisNameWidget: Text('% doentes', style: axisStyle(size: 9)),
            axisNameSize: 14,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: rightRes,
              getTitlesWidget: (v, _) => !forBars
                  ? Text('${(v * 100).toInt()}%', style: axisStyle(size: 8))
                  : const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: botRes,
              interval: 1,
              getTitlesWidget: (v, _) {
                if (!forBars) return const SizedBox.shrink();
                final i = v.round();
                if (i < 0 || i >= n) return const SizedBox.shrink();
                // Cada barra é um lote curto ('T-07'), cabe mostrar todas as
                // sessões do cronograma sem saltar rótulos.
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    pts[i].label,
                    style: axisStyle(size: 7).copyWith(
                      color: AppColors.textSecondary.withOpacity(isRecent(i) ? 1.0 : 0.45),
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
        );

    final barChart = BarChart(
      BarChartData(
        // spaceAround centra o grupo i em (i+0.5)/n do plot, coincide com os
        // x inteiros do LineChart (minX -0.5 .. n-0.5). O antigo `center`
        // empacotava as barras no meio, desalinhadas da linha.
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: maxTp,
        barGroups: [
          for (int i = 0; i < n; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: pts[i].throughput,
                width: math.max(3, 150 / n),
                color: AppColors.primary.withOpacity(isRecent(i) ? 0.42 : 0.14),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ]),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: gridLineColor(), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: titles(true),
        barTouchData: BarTouchData(enabled: false),
      ),
    );

    final lineChart = LineChart(
      LineChartData(
        minX: -0.5,
        maxX: n - 0.5,
        minY: 0,
        maxY: 1,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: titles(false),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => AppColors.surface.withOpacity(0.96),
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.x.round().clamp(0, n - 1);
              final p = pts[i];
              return LineTooltipItem(
                '${p.label}\n',
                TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11),
                children: [
                  if (p.period != null)
                    TextSpan(
                      text: '${p.period}\n',
                      style: TextStyle(color: AppColors.textSecondary.withOpacity(0.75), fontSize: 9),
                    ),
                  TextSpan(
                    text: '${p.throughput.toStringAsFixed(1)} maçãs/h ativa\n',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                  ),
                  TextSpan(
                    text: '${(p.contamRate * 100).toStringAsFixed(0)}% doentes\n',
                    style: TextStyle(color: AppColors.scab, fontSize: 10),
                  ),
                  TextSpan(
                    text: 'Doença #1: ${AppColors.displayName(p.dominantClass)}',
                    style: TextStyle(color: classColor(p.dominantClass), fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        extraLinesData: ExtraLinesData(verticalLines: [
          // Fronteira entre o histórico agregado e os últimos 7 dias.
          if (hasSplit)
            VerticalLine(
              x: split - 0.5,
              color: AppColors.primary.withOpacity(0.45),
              strokeWidth: 1,
              dashArray: [4, 3],
              label: VerticalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(left: 6, bottom: 2),
                style: axisStyle(size: 8, bold: true).copyWith(color: AppColors.primary.withOpacity(0.9)),
                labelResolver: (_) => 'últimos 7 dias',
              ),
            ),
        ], horizontalLines: [
          HorizontalLine(
            y: data.ucl,
            color: AppColors.rot.withOpacity(0.75),
            strokeWidth: 1.2,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: axisStyle(size: 8),
              labelResolver: (_) => 'LCS ${(data.ucl * 100).toStringAsFixed(0)}%',
            ),
          ),
          HorizontalLine(y: data.meanRate, color: AppColors.textSecondary.withOpacity(0.5), strokeWidth: 1, dashArray: [3, 3]),
          HorizontalLine(y: data.lcl, color: AppColors.healthy.withOpacity(0.6), strokeWidth: 1, dashArray: [6, 4]),
        ]),
        lineBarsData: [
          LineChartBarData(
            spots: [for (int i = 0; i < n; i++) FlSpot(i.toDouble(), pts[i].contamRate)],
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 2.2,
            color: AppColors.textSecondary.withOpacity(0.55),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) {
                final i = spot.x.round().clamp(0, n - 1);
                final p = pts[i];
                // Cor do ponto = doença dominante da hora (dobra o "ranking").
                final c = classColor(p.dominantClass);
                // Blocos de contexto: mais pequenos e esbatidos, para não
                // competirem com as sessões reais dos últimos 7 dias.
                final recent = isRecent(i);
                return FlDotCirclePainter(
                  radius: recent ? 4.5 : 3.0,
                  color: recent ? c : c.withOpacity(0.45),
                  strokeWidth: recent ? 1.5 : 1.0,
                  strokeColor: AppColors.background,
                );
              },
            ),
          ),
        ],
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: [
            HorizontalRangeAnnotation(
              y1: data.lcl,
              y2: data.ucl,
              color: AppColors.textSecondary.withOpacity(0.08),
            ),
          ],
          verticalRangeAnnotations: [
            // Realce muito ténue da zona de foco: dá-lhe presença sem roubar
            // leitura à faixa normal do SPC que corre por trás.
            if (hasSplit)
              VerticalRangeAnnotation(
                x1: split - 0.5,
                x2: n - 0.5,
                color: AppColors.primary.withOpacity(0.05),
              ),
          ],
        ),
      ),
    );

    final legendClasses = <String>{for (final p in pts) if (p.dominantClass != 'Healthy') p.dominantClass}.toList()
      ..sort((a, b) => kClassOrder.indexOf(a).compareTo(kClassOrder.indexOf(b)));

    return Column(
      children: [
        Expanded(child: Stack(children: [barChart, lineChart])),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            ChartLegend(items: [
              MapEntry('Volume processado/h', AppColors.primary.withOpacity(0.5)),
              MapEntry('Taxa de contaminação', AppColors.textSecondary.withOpacity(0.55)),
              MapEntry('Faixa normal', AppColors.textSecondary.withOpacity(0.2)),
            ]),
            if (legendClasses.isNotEmpty) ...[
              Text('Patologia predominante:', style: axisStyle(size: 10, bold: true)),
              ChartLegend(items: [
                for (final c in legendClasses) MapEntry(AppColors.displayName(c), classColor(c)),
              ]),
            ],
            if (hasSplit)
              Text(
                '· antes da linha: histórico agregado em blocos',
                style: axisStyle(size: 9).copyWith(color: AppColors.textSecondary.withOpacity(0.7)),
              ),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════ 2 · FLUXO DE RECLASSIFICAÇÃO (Sankey) ═════════════════════════

class SankeyLink {
  final String source;
  final String target;
  final double value;
  const SankeyLink(this.source, this.target, this.value);
}

class SankeyData {
  final List<String> nodes;
  final List<SankeyLink> links;

  // Chips de custo (absorvem o antigo cnnCostMatrixChart 2×2):
  final int confirmations;
  final int highConfErrors; // errado com confiança ≥80% (aceitação automática), o erro mais caro
  final int lowConfErrors;

  const SankeyData({
    required this.nodes,
    required this.links,
    this.confirmations = 0,
    this.highConfErrors = 0,
    this.lowConfErrors = 0,
  });
  bool get isEmpty => links.isEmpty;
  int get totalReviews => confirmations + highConfErrors + lowConfErrors;
}

class ReclassSankeyChart extends StatelessWidget {
  final SankeyData data;
  const ReclassSankeyChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Sem correções humanas concluídas ainda.\nO fluxo aparece quando o operador corrige classificações na Triagem Manual.',
            textAlign: TextAlign.center,
            style: axisStyle(size: 11),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, box) => CustomPaint(
        size: Size(box.maxWidth, box.maxHeight),
        painter: _SankeyPainter(data),
      ),
    );
  }
}

class _SankeyBand {
  final double y, h;
  double cursor;
  _SankeyBand(this.y, this.h) : cursor = y;
}

class _SankeyPainter extends CustomPainter {
  final SankeyData d;
  _SankeyPainter(this.d);

  @override
  void paint(Canvas canvas, Size size) {
    if (d.links.isEmpty) return;
    const double labelW = 78, headerH = 22, botPad = 6, nodeW = 15;
    final plotTop = headerH;
    final plotH = size.height - headerH - botPad;
    final xLeft = labelW;
    final xRight = size.width - labelW - nodeW;
    if (plotH <= 0 || xRight <= xLeft) return;

    final outTotal = <String, double>{};
    final inTotal = <String, double>{};
    for (final l in d.links) {
      outTotal[l.source] = (outTotal[l.source] ?? 0) + l.value;
      inTotal[l.target] = (inTotal[l.target] ?? 0) + l.value;
    }
    final leftNodes = d.nodes.where((n) => (outTotal[n] ?? 0) > 0).toList();
    final rightNodes = d.nodes.where((n) => (inTotal[n] ?? 0) > 0).toList();
    final grand = d.links.fold<double>(0, (s, l) => s + l.value);
    if (grand <= 0) return;

    // Compressão controlada: com muitas classes (novas doenças promovidas de
    // "Outros") o gap encolhe e cada nó tem uma altura mínima legível.
    final maxNodes = math.max(leftNodes.length, rightNodes.length);
    final gap = (plotH * 0.03).clamp(4.0, 14.0);
    const minNodeH = 5.0;

    // Escala vertical partilhada, com folga (gap) entre nós.
    double bandScale(int count) {
      final gaps = (count - 1).clamp(0, count) * gap;
      return (plotH - gaps) / grand;
    }

    final sL = bandScale(leftNodes.length);
    final sR = bandScale(rightNodes.length);

    final leftBand = <String, _SankeyBand>{};
    double y = plotTop;
    for (final nk in leftNodes) {
      final h = math.max(minNodeH, (outTotal[nk] ?? 0) * sL);
      leftBand[nk] = _SankeyBand(y, h);
      y += h + gap;
    }
    final rightBand = <String, _SankeyBand>{};
    y = plotTop;
    for (final nk in rightNodes) {
      final h = math.max(minNodeH, (inTotal[nk] ?? 0) * sR);
      rightBand[nk] = _SankeyBand(y, h);
      y += h + gap;
    }
    final labelFont = maxNodes > 6 ? 8.5 : 10.0;

    // Fitas ordenadas pela posição do nó de origem (reduz cruzamentos).
    final links = [...d.links]
      ..sort((a, b) => (leftBand[a.source]?.y ?? 0).compareTo(leftBand[b.source]?.y ?? 0));
    SankeyLink? topBias; // fita off-diagonal mais grossa = viés nº 1 do modelo
    for (final l in links) {
      final lb = leftBand[l.source];
      final rb = rightBand[l.target];
      if (lb == null || rb == null) continue;
      final y0L = lb.cursor, y0R = rb.cursor;
      final hL = l.value * sL, hR = l.value * sR;
      lb.cursor += hL;
      rb.cursor += hR;
      final x0 = xLeft + nodeW, x1 = xRight;
      final cx = (x0 + x1) / 2;
      final isDiag = l.source == l.target;
      final path = Path()
        ..moveTo(x0, y0L)
        ..cubicTo(cx, y0L, cx, y0R, x1, y0R)
        ..lineTo(x1, y0R + hR)
        ..cubicTo(cx, y0R + hR, cx, y0L + hL, x0, y0L + hL)
        ..close();
      canvas.drawPath(path, Paint()..color = isDiag ? classColorExt(l.source).withOpacity(0.15) : classColorExt(l.source).withOpacity(0.75));
      if (!isDiag && (topBias == null || l.value > topBias!.value)) {
        topBias = l;
      }
    }



    // Nós + rótulos por fora (esquerda à esquerda, direita à direita).
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void node(String nk, _SankeyBand b, double x, bool left, double total) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, b.y, nodeW, b.h), const Radius.circular(3)),
        Paint()..color = classColorExt(nk),
      );
      tp
        ..text = TextSpan(children: [
          TextSpan(
              text: '${AppColors.displayName(nk)}\n',
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: labelFont, fontWeight: FontWeight.w700)),
          TextSpan(text: total.toInt().toString(), style: axisStyle(size: labelFont - 1.5)),
        ])
        ..textAlign = left ? TextAlign.right : TextAlign.left
        ..layout(maxWidth: labelW - 6);
      final tx = left ? x - tp.width - 6 : x + nodeW + 6;
      tp.paint(canvas, Offset(tx, b.y + b.h / 2 - tp.height / 2));
    }

    leftBand.forEach((k, b) => node(k, b, xLeft, true, outTotal[k] ?? 0));
    rightBand.forEach((k, b) => node(k, b, xRight, false, inTotal[k] ?? 0));

    // Cabeçalhos das colunas.
    tp.textAlign = TextAlign.left;
    tp.text = TextSpan(text: 'CNN (original)', style: axisStyle(size: 10, bold: true));
    tp.layout();
    tp.paint(canvas, Offset(0, 2));
    tp.text = TextSpan(text: 'Corrigido (humano)', style: axisStyle(size: 10, bold: true));
    tp.layout();
    tp.paint(canvas, Offset(size.width - tp.width, 2));
  }

  @override
  bool shouldRepaint(covariant _SankeyPainter old) => old.d != d;
}
