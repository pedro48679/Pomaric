
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

class QualityTimelineChart extends StatefulWidget {
  final Batch batch;
  const QualityTimelineChart({required this.batch});

  @override
  State<QualityTimelineChart> createState() => QualityTimelineChartState();
}

class QualityTimelineChartState extends State<QualityTimelineChart> {
  final Set<String> _excluded = {};

  static const Color _burstColor = Color(0xFF6B7280); // cinza neutro — deliberadamente fora da paleta das patologias

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    if (batch.apples.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 320,
        child: Center(child: Text('Sem dados para o Cronograma de Qualidade', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    final sorted = [...batch.apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    const numBins = 10;
    const diseaseOrder = ['Healthy', 'Blotch', 'Scab', 'Rot', 'Anthracnose'];

    final start = sorted.first.timestamp;
    final end = sorted.last.timestamp;
    final totalMs = end.difference(start).inMilliseconds;

    final List<double> confidences = List.filled(numBins, 0.0);
    final List<double> anomalyRates = List.filled(numBins, 0.0);
    final List<bool> isBurst = List.filled(numBins, false);
    final List<String> binTimes = List.filled(numBins, '');
    final Map<String, List<double>> pctByDisease = {for (final d in diseaseOrder) d: List.filled(numBins, 0.0)};

    for (int i = 0; i < numBins; i++) {
      final binStart = start.add(Duration(milliseconds: (totalMs * i ~/ numBins)));
      final binEnd = start.add(Duration(milliseconds: (totalMs * (i + 1) ~/ numBins)));

      final binApples = sorted.where((a) =>
        !a.timestamp.isBefore(binStart) && a.timestamp.isBefore(binEnd.add(const Duration(milliseconds: 1)))
      ).toList();

      binTimes[i] = '${binStart.hour.toString().padLeft(2, '0')}:${binStart.minute.toString().padLeft(2, '0')}';

      if (binApples.isEmpty) {
        pctByDisease['Healthy']![i] = 100.0;
        confidences[i] = 100.0;
        anomalyRates[i] = 0.0;
      } else {
        final counts = <String, int>{for (final d in diseaseOrder) d: 0};
        for (final a in binApples) {
          final c = a.primaryCondition;
          counts[c] = (counts[c] ?? 0) + 1;
        }
        for (final d in diseaseOrder) {
          pctByDisease[d]![i] = (counts[d]! / binApples.length * 100).clamp(0.0, 100.0);
        }
        final avgConf = binApples.map((a) => a.effectiveConfidence).fold(0.0, (s, v) => s + v) / binApples.length;
        confidences[i] = (avgConf * 100).clamp(0.0, 100.0);
        anomalyRates[i] = (100 - pctByDisease['Healthy']![i]).clamp(0.0, 100.0);
      }
    }

    // Deteção de surtos (taxa anomalia > média + 1.5σ) — sempre calculada sobre
    // o lote completo, independentemente de patologias ocultas pela legenda.
    final avgAnomaly = anomalyRates.fold(0.0, (s, v) => s + v) / numBins;
    final varAnomaly = anomalyRates.fold(0.0, (s, v) => s + (v - avgAnomaly) * (v - avgAnomaly)) / numBins;
    final burstThreshold = avgAnomaly + max(sqrt(varAnomaly) * 1.5, 10.0);
    for (int i = 0; i < numBins; i++) {
      isBurst[i] = anomalyRates[i] > burstThreshold;
    }

    // Composição empilhada (cumulativa), só sobre as patologias ativas (não ocultadas).
    final activeOrder = diseaseOrder.where((d) => !_excluded.contains(d)).toList();
    final Map<String, List<double>> cumByDisease = {};
    List<double> running = List.filled(numBins, 0.0);
    for (final d in activeOrder) {
      running = List.generate(numBins, (i) => running[i] + pctByDisease[d]![i]);
      cumByDisease[d] = List.from(running);
    }

    List<FlSpot> spotsOf(List<double> vals) => List.generate(vals.length, (i) => FlSpot(i.toDouble(), vals[i]));

    LineChartBarData stackedLayer(List<double> vals, Color color) => LineChartBarData(
          spots: spotsOf(vals),
          isCurved: false,
          barWidth: 0,
          color: Colors.transparent,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.85)),
        );

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 320,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Cronograma Analítico de Qualidade',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          Row(children: [
            if (isBurst.any((b) => b))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _burstColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _burstColor.withValues(alpha: 0.4)),
                ),
                child: Text('${isBurst.where((b) => b).length} surto(s) ⚠',
                    style: TextStyle(color: _burstColor, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Distribuição Patológica Temporal, empilhada por janela temporal.\n\n'
                       '• Área colorida: % de maçãs por patologia nessa janela\n'
                       '• Linha branca: confiança média da CNN\n'
                       '• Banda cinzenta: surto detetado (taxa de patologia > média + 1.5σ)\n\n'
                       'Toca numa patologia da legenda para a remover/adicionar da pilha.',
              padding: const EdgeInsets.all(12),
              textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
              decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
              ),
              child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 15),
            ),
          ]),
        ]),
        Text('Composição de patologias · confiança da CNN sobreposta · surtos marcados — $numBins janelas temporais',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 14),
        Expanded(
          child: activeOrder.isEmpty
              ? Center(child: Text('Todas as patologias estão ocultas — toca na legenda para mostrar',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)))
              : LayoutBuilder(builder: (context, constraints) {
                  final bandWidth = ((constraints.maxWidth - 34) / numBins * 0.85).clamp(4.0, 60.0);
                  return LineChart(LineChartData(
                    minY: 0,
                    maxY: 100,
                    minX: 0,
                    maxX: (numBins - 1).toDouble(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(color: AppColors.textSecondary.withValues(alpha: 0.1), strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true, reservedSize: 20, interval: 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= binTimes.length) return const SizedBox();
                          return Text(binTimes[idx], style: TextStyle(color: AppColors.textSecondary, fontSize: 8));
                        },
                      )),
                      leftTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true, reservedSize: 32,
                        getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: TextStyle(color: AppColors.textSecondary, fontSize: 8)),
                      )),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    extraLinesData: ExtraLinesData(verticalLines: [
                      for (int i = 0; i < numBins; i++)
                        if (isBurst[i])
                          VerticalLine(
                            x: i.toDouble(),
                            color: _burstColor.withValues(alpha: 0.22),
                            strokeWidth: bandWidth,
                            label: VerticalLineLabel(
                              show: true,
                              alignment: Alignment.topCenter,
                              padding: const EdgeInsets.only(bottom: 2),
                              style: TextStyle(color: _burstColor, fontSize: 10, fontWeight: FontWeight.bold),
                              labelResolver: (_) => '⚠',
                            ),
                          ),
                    ]),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        fitInsideHorizontally: true, fitInsideVertically: true,
                        getTooltipColor: (_) => AppColors.surface.withValues(alpha: 0.95),
                        getTooltipItems: (spots) {
                          final idx = spots.isNotEmpty ? spots.first.x.toInt() : 0;
                          final lines = <String>['${binTimes[idx]}', 'Confiança: ${confidences[idx].toStringAsFixed(0)}%'];
                          for (final d in activeOrder.reversed) {
                            final v = pctByDisease[d]![idx];
                            if (v > 0.5) lines.add('${AppColors.displayName(d)}: ${v.toStringAsFixed(0)}%');
                          }
                          if (isBurst[idx]) lines.add('⚠ Surto detetado');
                          return spots.map((s) => s == spots.first
                              ? LineTooltipItem(lines.join('\n'), TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold, height: 1.4))
                              : null).toList();
                        },
                      ),
                    ),
                    lineBarsData: [
                      for (final d in activeOrder.reversed) stackedLayer(cumByDisease[d]!, AppColors.getColorForCondition(d)),
                      LineChartBarData(
                        spots: spotsOf(confidences),
                        isCurved: true,
                        curveSmoothness: 0.2,
                        color: Colors.white,
                        barWidth: 2.2,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                            radius: isBurst[idx] ? 4.5 : 2.5,
                            color: Colors.white,
                            strokeWidth: isBurst[idx] ? 1.5 : 0.8,
                            strokeColor: _burstColor.withValues(alpha: isBurst[idx] ? 0.9 : 0.0),
                          ),
                        ),
                        belowBarData: BarAreaData(show: false),
                      ),
                    ],
                  ));
                }),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            ...diseaseOrder.map((d) {
              final excluded = _excluded.contains(d);
              return GestureDetector(
                onTap: () => setState(() {
                  if (excluded) {
                    _excluded.remove(d);
                  } else {
                    _excluded.add(d);
                  }
                }),
                child: Opacity(
                  opacity: excluded ? 0.35 : 1.0,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(
                        color: AppColors.getColorForCondition(d), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 4),
                    Text(AppColors.displayName(d),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9.5,
                          decoration: excluded ? TextDecoration.lineThrough : TextDecoration.none,
                        )),
                  ]),
                ),
              );
            }),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 2, color: Colors.white),
              const SizedBox(width: 4),
              Text('Confiança CNN', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, color: _burstColor.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text('Surto', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
            ]),
          ],
        ),
      ]),
    );
  }
}

Widget masterTimeline(Batch batch) => QualityTimelineChart(batch: batch);

  // ── Diagrama Bayesiano ────────────────────────────────────────────────────
  // Visualiza a atualização de crença: Priori × Verossimilhança CNN → Posteriori.
  // Priori = taxa histórica; Verossimilhança = conf. CNN no lote atual.

Widget cumulativeCompliance(List<Apple> apples) {
    if (apples.isEmpty) return const SizedBox(height: 280);
    final sorted = [...apples]..sort((a, b) => a.id.compareTo(b.id));
    int healthy = 0;
    final spots = <FlSpot>[];
    for (int i = 0; i < sorted.length; i++) {
      if (sorted[i].primaryCondition == 'Healthy') healthy++;
      if (i % (sorted.length ~/ 20 + 1) == 0 || i == sorted.length - 1) {
        spots.add(FlSpot(i.toDouble(), (healthy / (i + 1)) * 100));
      }
    }

    final windowSize = (sorted.length * 0.05).round().clamp(10, 50);
    final movingSpots = <FlSpot>[];
    for (int i = 0; i < sorted.length; i++) {
      if (i % (sorted.length ~/ 20 + 1) == 0 || i == sorted.length - 1) {
        int start = (i - windowSize + 1).clamp(0, sorted.length);
        int localHealthy = 0;
        int localTotal = 0;
        for (int j = start; j <= i; j++) {
          if (sorted[j].primaryCondition == 'Healthy') localHealthy++;
          localTotal++;
        }
        movingSpots.add(FlSpot(i.toDouble(), localTotal == 0 ? 100.0 : (localHealthy / localTotal) * 100));
      }
    }

    final movingColor = AppColors.isDark ? const Color(0xff06B6D4) : const Color(0xff0284C7);

    return Container(
      padding: const EdgeInsets.all(20),
      height: 320,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Taxa de Conformidade (Acumulada)',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
        Text('Variação Temporal da Qualidade (Média Móvel vs. Cumulativa)',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        Expanded(child: LineChart(LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: AppColors.textSecondary.withValues(alpha: 0.2), strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          minY: 0, maxY: 100,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, 
              interval: sorted.length > 5 ? (sorted.length / 5).floorToDouble() : 1.0,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text('#${v.toInt() + 1}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              ))),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32,
              getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 9)))),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.healthy,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, barData) => spot.x == barData.spots.last.x,
                getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                  radius: 6,
                  color: AppColors.healthy,
                  strokeWidth: 2.5,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.healthy.withValues(alpha: 0.22),
                    AppColors.healthy.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            LineChartBarData(spots: movingSpots, isCurved: true, color: movingColor,
                barWidth: 1.5, dashArray: [4, 4], dotData: const FlDotData(show: false)),
            LineChartBarData(spots: [FlSpot(0, 80), FlSpot(spots.last.x, 80)],
                isCurved: false, color: Colors.amber.withValues(alpha: 0.5),
                barWidth: 1, dashArray: [4, 4], dotData: const FlDotData(show: false)),
          ],
        ))),
        const SizedBox(height: 6),
        Row(children: [
          Container(width: 12, height: 3, color: AppColors.healthy),
          const SizedBox(width: 6),
          Text('Cumulativa', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          const SizedBox(width: 16),
          Row(
            children: [
              Container(width: 4, height: 3, color: movingColor),
              const SizedBox(width: 2),
              Container(width: 4, height: 3, color: movingColor),
            ],
          ),
          const SizedBox(width: 6),
          Text('Tendência Local (Janela ${windowSize})', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          const SizedBox(width: 16),
          Row(
            children: [
              Container(width: 4, height: 3, color: Colors.amber),
              const SizedBox(width: 2),
              Container(width: 4, height: 3, color: Colors.amber),
            ],
          ),
          const SizedBox(width: 6),
          Text('Alvo 80%', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ]),
      ]),
    );
  }

  // ── Análise de Risco Biológico ─────────────────────────────────────────

Widget productionQualityTimeline(Batch batch) {
    if (batch.apples.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 280,
        child: Center(child: Text('Sem dados de qualidade', style: TextStyle(color: AppColors.textSecondary))),
      );
    }
    
    final sorted = [...batch.apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    const numBins = 10;

    final start = sorted.first.timestamp;
    final end = sorted.last.timestamp;
    final totalMs = end.difference(start).inMilliseconds;

    final List<double> healthyRates = List.filled(numBins, 0.0);
    final List<double> confidences = List.filled(numBins, 0.0);
    final List<double> anomalyRates = List.filled(numBins, 0.0);
    final List<double> throughputs = List.filled(numBins, 0.0);
    final List<String> binTimes = List.filled(numBins, '');

    for (int i = 0; i < numBins; i++) {
      final binStart = start.add(Duration(milliseconds: (totalMs * i ~/ numBins)));
      final binEnd = start.add(Duration(milliseconds: (totalMs * (i + 1) ~/ numBins)));
      
      final binApples = sorted.where((a) =>
        !a.timestamp.isBefore(binStart) && a.timestamp.isBefore(binEnd.add(const Duration(milliseconds: 1)))
      ).toList();

      binTimes[i] = '${binStart.hour.toString().padLeft(2, '0')}:${binStart.minute.toString().padLeft(2, '0')}';

      if (binApples.isEmpty) {
        healthyRates[i] = 100.0;
        confidences[i] = 100.0;
        anomalyRates[i] = 0.0;
        throughputs[i] = 0.0;
      } else {
        final healthyCount = binApples.where((a) => a.primaryCondition == 'Healthy').length;
        final anomalyCount = binApples.length - healthyCount;
        final avgConf = binApples.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / binApples.length;
        
        healthyRates[i] = (healthyCount / binApples.length * 100).clamp(0.0, 100.0);
        confidences[i] = (avgConf * 100).clamp(0.0, 100.0);
        anomalyRates[i] = (anomalyCount / binApples.length * 100).clamp(0.0, 100.0);
        
        final binDurationMinutes = (totalMs / numBins) / (60.0 * 1000.0);
        final dur = binDurationMinutes > 0 ? binDurationMinutes : 1.0;
        throughputs[i] = binApples.length / dur;
      }
    }

    final maxThroughput = throughputs.reduce(max);
    final List<double> normThroughputs = throughputs.map((t) => maxThroughput > 0 ? t / maxThroughput : 0.0).toList();

    Widget buildHeatmapRow(String label, List<double> values, Color baseColor, String Function(int) tooltipResolver, {bool isNormalized = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Row(
                children: List.generate(numBins, (col) {
                  final val = values[col];
                  // If normalized value is already between 0 and 1, use it. Otherwise divide by 100 for percentages.
                  final intensity = isNormalized ? val : (val / 100.0).clamp(0.0, 1.0);
                  
                  return Expanded(
                    child: Tooltip(
                      message: 'Intervalo: ${binTimes[col]}\n${tooltipResolver(col)}',
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: baseColor.withValues(alpha: 0.3)),
                      ),
                      textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 10, height: 1.4),
                      child: Container(
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: baseColor.withValues(alpha: intensity * 0.8 + 0.05),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: intensity > 0.6 
                                ? baseColor.withValues(alpha: 0.5) 
                                : Colors.white.withValues(alpha: 0.03),
                            width: 0.8,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            isNormalized 
                                ? '${throughputs[col].toStringAsFixed(0)}' 
                                : '${val.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: intensity > 0.4 ? Colors.white : AppColors.textSecondary,
                              fontSize: 8,
                              fontWeight: intensity > 0.6 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Mapeamento Térmico de Qualidade Operacional',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              Icon(Icons.grid_on, color: AppColors.textSecondary, size: 16),
            ],
          ),
          Text('Indicadores de Qualidade, Fiabilidade Preditiva e Fluxo',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildHeatmapRow('Taxa Saudável', healthyRates, AppColors.healthy, (col) => 'Taxa Saudável: ${healthyRates[col].toStringAsFixed(1)}%'),
                buildHeatmapRow('Certeza CNN', confidences, Colors.cyanAccent, (col) => 'Certeza CNN Média: ${confidences[col].toStringAsFixed(1)}%'),
                buildHeatmapRow('Taxa Anomalias', anomalyRates, Colors.redAccent, (col) => 'Taxa Anomalias: ${anomalyRates[col].toStringAsFixed(1)}%'),
                buildHeatmapRow('Vazão (frutos/min)', normThroughputs, Colors.purpleAccent, (col) => 'Vazão: ${throughputs[col].toStringAsFixed(1)} maçãs/min', isNormalized: true),
                
                // Bins time header row at the bottom
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 140),
                    Expanded(
                      child: Row(
                        children: List.generate(numBins, (col) => Expanded(
                          child: Text(
                            binTimes[col],
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        )),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══ PARETO DE ANOMALIAS DO LOTE (removed) ═══
  // _batchPareto removed per user request — replaced by productionQualityTimeline

  // ── MATRIZ DE EISENHOWER ────────────────────────────────────────────────

