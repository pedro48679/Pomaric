import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../providers/dashboard_provider.dart';
import '../services/supabase_service.dart';
import '../utils/constants.dart';
import '../widgets/apple_card.dart';
import '../widgets/glass_card.dart';
import 'package:google_fonts/google_fonts.dart';

class BatchDashboard extends ConsumerWidget {
  const BatchDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(batchProvider);
    final allBatches = ref.watch(availableBatchesProvider);
    if (batch == null) return const Center(child: CircularProgressIndicator());

    final uncertain      = ref.watch(uncertainApplesProvider);
    final allCorrections = ref.watch(correctionHistoryProvider);
    final corrections = allCorrections.where((c) => c.batchId == batch.id).toList();
    final avgConf        = ref.watch(avgConfidenceProvider);
    final stats          = ref.watch(batchStatsProvider);

    if (stats == null) return const Center(child: CircularProgressIndicator());

    String dominant = stats.dominantAnomaly;
    int domCount = stats.dominantAnomalyCount;
    final approvalRate = stats.approvalRate;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dashboard: ${batch.id}',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    '${batch.location}  ·  ${DateFormat('dd/MM/yyyy').format(batch.date)}  ·  ${batch.totalApples} maçãs inspecionadas',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),

            ],
          ),
          const SizedBox(height: 28),

          // ── SEC 1: KPIs ────────────────────────────────────────────────
          _section1Kpis(batch, approvalRate, dominant, domCount, avgConf, uncertain.length),
          const SizedBox(height: 32),

          // ── VISÃO GLOBAL DO LOTE ─────────────────────────────────────────
          _sectionHeader('Visão Global do Lote', Icons.analytics, Colors.blueAccent),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: _donut(batch)),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: _gaugeCard(batch, approvalRate, avgConf)),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: _cumulativeCompliance(batch.apples)),
          ]),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: _severityDistributionBar(batch)),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: _triagemFunnel(batch, uncertain.length, corrections.length)),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: _calibrationReliabilityDiagram(batch.apples, corrections)),
          ]),
          const SizedBox(height: 32),

          // ── COMPARAÇÃO DE LOTES ──────────────────────────────────
          _sectionHeader('Comparação de Desempenho do Lote', Icons.history, Colors.blueAccent),
          const SizedBox(height: 16),
          _BatchComparisonShowcase(currentBatch: batch, allBatches: allBatches),
          const SizedBox(height: 32),

          // ── SEC: ANÁLISE DE VAZÃO, SEVERIDADE E CALIBRAÇÃO IA ───────
          _sectionHeader('Análise de Vazão, Severidade e Calibração IA', Icons.speed, Colors.tealAccent),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: _throughputChart(batch)),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: _confidenceDistribution(batch.apples, corrections)),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: _overconfidenceCorrectionsChart(batch, allCorrections)),
          ]),
          const SizedBox(height: 32),

          // ── ANÁLISE CNN ───────────────────────────────────────────────────
          _sectionHeader('Análise CNN (ResNet50)', Icons.smart_toy, Colors.cyanAccent),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 1, child: _probMatrix(batch.apples)),
            const SizedBox(width: 16),
            Expanded(flex: 1, child: _trendLine(allBatches)),
          ]),
          const SizedBox(height: 32),

          // ── TRIAGEM HUMANA ──────────────────────────────────────────────
          _sectionHeader('Triagem Humana', Icons.pending_actions, Colors.orangeAccent),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: _reviewQueue(context, uncertain.where((a) => a.frames.isNotEmpty).toList())),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: _correctionHistory(corrections)),
          ]),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 10),
      Text(title, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(width: 16),
      Expanded(child: Divider(color: color.withValues(alpha: 0.3), thickness: 1)),
    ]);
  }

  Widget _btn(WidgetRef ref, String label, String page, Color bg) {
    return ElevatedButton(
      onPressed: () => ref.read(currentPageProvider.notifier).setPage(page),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: Text(label),
    );
  }

  Widget _kpi(String title, String value, IconData icon, Color color, [String? sub, String? tooltip]) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 26),
              if (tooltip != null)
                Tooltip(
                  message: tooltip,
                  padding: const EdgeInsets.all(12),
                  textStyle: const TextStyle(color: Colors.white, fontSize: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.info_outline, color: color.withValues(alpha: 0.6), size: 18),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ]),
      ),
    );
  }

  Widget _section1Kpis(Batch batch, double approval, String dominant, int domCount, double avgConf, int pending) {
    final urgencyColor = batch.urgencyScore > 0.6 ? Colors.redAccent : batch.urgencyScore > 0.3 ? Colors.orangeAccent : AppColors.healthy;
    
    const tips = {
      'Blotch': 'Insight Agronómico:\nMelhorar a ventilação para reduzir humidade. Testar o solo por deficiência de cálcio.',
      'Rot': 'Insight Agronómico:\nUsar tratamento antifúngico preventivo. Evitar danos mecânicos na colheita e controlar pragas.',
      'Scab': 'Insight Agronómico:\nAplicar fungicida na primavera. Garantir limpeza das folhas caídas no inverno.',
      'Anthracnose': 'Insight Agronómico:\nRemover e destruir ramos infetados. Considerar aplicação de sulfato de cobre.',
    };
    final insightTooltip = tips[dominant] ?? 'Lote em qualidade aceitável sem surtos críticos.';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kpi('Total Inspecionado', '${batch.totalApples}', Icons.scale, Colors.blueAccent),
          const SizedBox(width: 12),
          _kpi('Taxa de Aprovação', '${approval.toStringAsFixed(1)}%', Icons.check_circle,
              approval > 80 ? AppColors.healthy : Colors.orangeAccent),
          const SizedBox(width: 12),
          _kpi('Doença Dominante', dominant, Icons.warning_amber, AppColors.getColorForCondition(dominant),
              '$domCount casos detetados', insightTooltip),
          const SizedBox(width: 12),
          _kpi('Lote Urgente (Contaminação & Gravidade)', '${(batch.urgencyScore * 100).toStringAsFixed(0)}%',
              Icons.show_chart, urgencyColor,
              batch.growthRate > 0 ? '▲ ${batch.growthRate.toStringAsFixed(1)}% vs anterior'
                  : '▼ ${batch.growthRate.abs().toStringAsFixed(1)}% vs anterior',
              'Fórmula: (Contaminação x 40%) + (Gravidade x 60%)\n\n'
              '• Contaminação (risco biológico fúngico de propagação rápida):\n'
              '  Scab: 90%  ·  Blotch: 70%  ·  Anthracnose: 50%  ·  Rot: 25%\n\n'
              '• Gravidade (impacto comercial direto / descarte):\n'
              '  Rot/Anthracnose: 100% (Descarte imediato e perda total)\n'
              '  Scab/Blotch: 40% (Aproveitáveis comercialmente para Sumo/Polpa)'),
          const SizedBox(width: 12),
          _kpi('Em Revisão Humana', '$pending', Icons.pending_actions,
              pending > 0 ? Colors.amber : AppColors.healthy,
              pending > 0 ? 'Aguardam validação' : 'Tudo validado'),
        ],
      ),
    );
  }

  // ── Taxa de Conformidade Cumulativa ──────────────────────────────────────
  Widget _cumulativeCompliance(List<Apple> apples) {
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
    return Container(
      padding: const EdgeInsets.all(20),
      height: 320,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Taxa de Conformidade Cumulativa',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const Text('Evolução ao longo da triagem do lote',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 12),
        Expanded(child: LineChart(LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          minY: 0, maxY: 100,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, 
              interval: sorted.length > 5 ? (sorted.length / 5).floorToDouble() : 1.0,
              getTitlesWidget: (v, _) => Text('#${v.toInt() + 1}',
                  style: const TextStyle(color: Colors.white38, fontSize: 9)))),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32,
              getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                  style: const TextStyle(color: Colors.white38, fontSize: 9)))),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(spots: spots, isCurved: true, color: AppColors.healthy,
                barWidth: 2, dotData: FlDotData(show: false),
                belowBarData: BarAreaData(show: true,
                    color: AppColors.healthy.withValues(alpha: 0.08))),
            LineChartBarData(spots: [FlSpot(0, 80), FlSpot(spots.last.x, 80)],
                isCurved: false, color: Colors.amber.withValues(alpha: 0.5),
                barWidth: 1, dashArray: [4, 4], dotData: FlDotData(show: false)),
          ],
        ))),
        const SizedBox(height: 6),
        Row(children: [
          Container(width: 12, height: 3, color: AppColors.healthy),
          const SizedBox(width: 6),
          const Text('Conformidade real', style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(width: 16),
          Container(width: 12, height: 3, color: Colors.amber),
          const SizedBox(width: 6),
          const Text('Limiar 80%', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ]),
    );
  }

  // ── Histograma de Confiança de Deteção ────────────────────────────────
  Widget _confidenceDistribution(List<Apple> apples, List<CorrectionHistory> corrections) {
    if (apples.isEmpty) return const SizedBox(height: 320);

    const labels = ['<60%', '60-70%', '70-80%', '80-90%', '90%+'];
    final buckets = List<int>.filled(labels.length, 0);
    final correctedCounts = List<int>.filled(labels.length, 0);
    final correctionMap = {for (final c in corrections) c.appleId: c};

    for (final apple in apples) {
      final conf = (apple.effectiveConfidence * 100).clamp(0.0, 100.0);
      final idx = conf < 60 ? 0 : conf < 70 ? 1 : conf < 80 ? 2 : conf < 90 ? 3 : 4;
      buckets[idx]++;

      final correction = correctionMap[apple.id];
      if (correction != null && correction.label != apple.primaryCondition) {
        correctedCounts[idx]++;
      }
    }

    final maxCount = [if (buckets.isNotEmpty) buckets.reduce(max), if (correctedCounts.isNotEmpty) correctedCounts.reduce(max)].fold<int>(0, (prev, next) => next > prev ? next : prev).toDouble();
    final dynamicMaxY = (maxCount > 5 ? maxCount + 2 : 8.0).toDouble();

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 320,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Distribuição de Confiança da IA', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const Text('Volume de maçãs por faixa de confiança e casos corrigidos pelo humano', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: dynamicMaxY,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final idx = group.x.toInt();
                    return BarTooltipItem(
                      '${labels[idx]}\n',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      children: [
                        TextSpan(text: '${buckets[idx]} maçãs\n', style: const TextStyle(color: AppColors.primary, fontSize: 10)),
                        TextSpan(text: '${correctedCounts[idx]} correções humanas', style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                      ],
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= labels.length) return const SizedBox();
                  return Text(labels[idx], style: const TextStyle(color: Colors.white38, fontSize: 9));
                })),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: Colors.white38, fontSize: 9)))),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(labels.length, (idx) {
                return BarChartGroupData(
                  x: idx,
                  barsSpace: 6,
                  barRods: [
                    BarChartRodData(
                      toY: buckets[idx].toDouble(),
                      width: 14,
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                      backDrawRodData: BackgroundBarChartRodData(show: true, toY: dynamicMaxY, color: Colors.white.withOpacity(0.05)),
                    ),
                    BarChartRodData(
                      toY: correctedCounts[idx].toDouble(),
                      width: 8,
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Container(width: 10, height: 10, color: Colors.white24),
          const SizedBox(width: 6),
          const Text('Volume total', style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(width: 16),
          Container(width: 10, height: 10, color: Colors.redAccent),
          const SizedBox(width: 6),
          const Text('Correções humanas', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ]),
    );
  }

  // ── Radar Perfil do Lote ──────────────────────────────────────────────────
  Widget _radarProfile(List<Apple> apples) {
    const conditions = ['Healthy','Rot','Scab','Blotch','Anthracnose'];
    if (apples.isEmpty) return const SizedBox(height: 280);
    final avg = <String, double>{for (final c in conditions) c: 0.0};
    for (final a in apples) {
      for (final c in conditions) {
        avg[c] = avg[c]! + ((c == a.primaryCondition) ? a.effectiveConfidence : (a.worstFrame?.probabilities[c] ?? 0.0));
      }
    }
    final n = apples.length.toDouble();
    final entries = conditions.map((c) => RadarEntry(value: (avg[c]! / n) * 100)).toList();
    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 320,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Radar de Perfil do Lote',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const Text('Probabilidade média CNN por classe (todas as maçãs)',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 35),
        Expanded(child: RadarChart(RadarChartData(
          radarBorderData: const BorderSide(color: Colors.white10),
          gridBorderData: const BorderSide(color: Colors.white10),
          tickBorderData: const BorderSide(color: Colors.transparent),
          ticksTextStyle: const TextStyle(color: Colors.transparent),
          titleTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          getTitle: (i, _) {
            final val = (avg[conditions[i]]! / n) * 100;
            return RadarChartTitle(text: '${conditions[i]}\n${val.toStringAsFixed(1)}%');
          },
          dataSets: [RadarDataSet(
            fillColor: Colors.cyanAccent.withValues(alpha: 0.15),
            borderColor: Colors.cyanAccent,
            borderWidth: 2,
            entryRadius: 3,
            dataEntries: entries,
          )],
          radarShape: RadarShape.polygon,
        ))),
      ]),
    );
  }

  // ── Funil de Triagem ──────────────────────────────────────────────────────
  Widget _triagemFunnel(Batch batch, int uncertainCount, int correctionCount) {
    final total = batch.totalApples;
    if (total == 0) return const SizedBox(height: 280);
    int highConf = 0;
    for (final a in batch.apples) {
      final conf = a.effectiveConfidence;
      if (conf >= 0.80) highConf++;
    }
    final approved = batch.healthDistribution['Healthy'] ?? 0;
    final steps = [
      ('Total Inspecionado', total, Colors.blueAccent),
      ('Alta Confiança (≥80%)', highConf, Colors.cyanAccent),
      ('Aprovadas (Healthy)', approved, AppColors.healthy),
      ('Enviadas p/ Revisão', uncertainCount, Colors.amber),
      ('Corrigidas Manualmente', correctionCount, Colors.purpleAccent),
    ];
    final maxW = total.toDouble();
    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 320,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Funil de Triagem',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const Text('Fluxo operacional do pipeline de inspeção',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 20),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: steps.map((s) {
            final pct = (s.$2 / maxW).clamp(0.0, 1.0);
            
            if (s.$2 == 0) {
              return Container(
                height: 24,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text('${s.$1} (0)', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              );
            }

            return FractionallySizedBox(
              widthFactor: pct < 0.15 ? 0.15 : pct, // ensure minimum width for text
              child: Container(
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [s.$3.withValues(alpha: 0.4), s.$3.withValues(alpha: 0.9), s.$3.withValues(alpha: 0.4)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${s.$1} (${s.$2})', 
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black54, blurRadius: 2)]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList().reversed.toList(),
        )),
      ]),
    );
  }

  // ── Calibração de Confiança da IA ────────────────────────────────────
  // ── Calibração de Confiança da IA (Reliability Diagram) ─────────────────
  Widget _calibrationReliabilityDiagram(List<Apple> apples, List<CorrectionHistory> corrections) {
    if (apples.isEmpty) return const SizedBox(height: 320);

    const nBuckets = 10;
    final counts = List<int>.filled(nBuckets, 0);
    final correct = List<int>.filled(nBuckets, 0);
    final correctionMap = {for (final c in corrections) c.appleId: c};

    for (final apple in apples) {
      final conf = (apple.effectiveConfidence * 100).clamp(0.0, 100.0);
      final idx = (conf / 10).floor().clamp(0, nBuckets - 1);
      counts[idx]++;

      final correction = correctionMap[apple.id];
      if (correction != null) {
        if (correction.label == apple.primaryCondition) {
          correct[idx]++;
        }
      } else {
        if (apple.cnn2Label == apple.primaryCondition) {
          correct[idx]++;
        }
      }
    }

    final points = <FlSpot>[];
    for (int i = 0; i < nBuckets; i++) {
      final total = counts[i];
      final acc = total == 0 ? 0.0 : (correct[i] / total) * 100.0;
      final bucketMid = i * 10 + 5; // midpoint
      points.add(FlSpot(bucketMid.toDouble(), acc));
    }

    // Compute Brier-like calibration gap: mean |conf - acc| across buckets weighted by counts
    double weightedGapSum = 0;
    int totalExamples = counts.fold(0, (p, e) => p + e);
    for (int i = 0; i < nBuckets; i++) {
      final avgConf = (i * 10 + 5).toDouble();
      final acc = counts[i] == 0 ? 0.0 : (correct[i] / counts[i]) * 100.0;
      weightedGapSum += (counts[i] * (avgConf - acc).abs());
    }
    final calibrationGap = totalExamples == 0 ? 0.0 : (weightedGapSum / totalExamples);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 320,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Calibração de Confiança da IA', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const Text('Observed accuracy vs. predicted confidence (reliability diagram)', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        Expanded(child: LineChart(LineChartData(
          minX: 0, maxX: 100, minY: 0, maxY: 100,
          gridData: FlGridData(show: true, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v,_) => Text('\${v.toInt()}%', style: const TextStyle(color: Colors.white38, fontSize: 9)))),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v,_) => Text('\${v.toInt()}%', style: const TextStyle(color: Colors.white38, fontSize: 9)))),
          ),
          lineBarsData: [
            // diagonal reference
            LineChartBarData(spots: [FlSpot(0,0), FlSpot(100,100)], isCurved: false, color: Colors.white24, barWidth: 1, dashArray: [4,4]),
            // observed
            LineChartBarData(spots: points, isCurved: true, color: Colors.cyanAccent, barWidth: 2, dotData: FlDotData(show: true)),
          ],
        ))),
        const SizedBox(height: 8),
        Text('Calibration gap: ${calibrationGap.toStringAsFixed(2)}%', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 6),
        const Text('Valores perto de 0 indicam boa calibração. Pontos acima y=x → under-confident; abaixo → over-confident.', style: TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    );
  }

  // ── Donut ────────────────────────────────────────────────────────────────
  Widget _donut(Batch batch) {
    final dist = batch.healthDistribution;
    final total = batch.totalApples;
    final conditions = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];
    final sections = conditions.where((c) => (dist[c] ?? 0) > 0).map((c) {
      final pct = (dist[c]! / total * 100);
      return PieChartSectionData(
        value: dist[c]!.toDouble(),
        color: AppColors.getColorForCondition(c),
        title: '${pct.toStringAsFixed(0)}%',
        radius: 45,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 320,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Distribuição de Patologias',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Expanded(child: PieChart(PieChartData(
          sectionsSpace: 4, 
          centerSpaceRadius: 40, 
          sections: sections,
        ))),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 8, children: conditions.where((c) => (dist[c] ?? 0) > 0).map((c) {
          
          String tooltipMsg = '';
          Map<String, int> daily = {};
          for (final a in batch.apples) {
            if (a.primaryCondition == c) {
              String day = "${a.timestamp.day.toString().padLeft(2, '0')}/${a.timestamp.month.toString().padLeft(2, '0')}";
              daily[day] = (daily[day] ?? 0) + 1;
            }
          }
          if (daily.isEmpty) {
            tooltipMsg = c == 'Healthy' ? 'Sem maçãs saudáveis' : '0 casos';
          } else {
            final sortedDays = daily.keys.toList()..sort();
            tooltipMsg = 'Ocorrências por dia:\n' + sortedDays.map((d) => '$d: ${daily[d]} maçãs').join('\n');
          }

          return Tooltip(
            message: tooltipMsg,
            padding: const EdgeInsets.all(12),
            textStyle: const TextStyle(color: Colors.white, fontSize: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.getColorForCondition(c).withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                color: AppColors.getColorForCondition(c),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.getColorForCondition(c).withValues(alpha: 0.5), blurRadius: 4)],
              )),
              const SizedBox(width: 6),
              Text(c, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ]),
          );
        }).toList()),
      ]),
    );
  }



  // ── Trend line com CNN5 vs CNN2 ────────────────────────────
  Widget _trendLine(List<Batch> allBatches) {
    final allApples = allBatches.expand((b) => b.apples).toList();
    Map<String, List<Apple>> applesByDay = {};
    for (var a in allApples) {
      String dateKey = "${a.timestamp.year}-${a.timestamp.month.toString().padLeft(2, '0')}-${a.timestamp.day.toString().padLeft(2, '0')}";
      if (!applesByDay.containsKey(dateKey)) applesByDay[dateKey] = [];
      applesByDay[dateKey]!.add(a);
    }
    List<Batch> dailyBatches = applesByDay.entries.map((e) {
      e.value.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Batch(
        id: e.key,
        name: e.key,
        date: e.value.first.timestamp,
        apples: e.value,
        location: 'Global',
      );
    }).toList();
    dailyBatches.sort((a, b) => a.date.compareTo(b.date));

    // Pegar apenas os últimos 30 dias para o gráfico
    final last30 = dailyBatches.length > 30 
        ? dailyBatches.sublist(dailyBatches.length - 30) 
        : dailyBatches;

    final cnn5Spots = <FlSpot>[];
    final cnn2Spots = <FlSpot>[];

    for (int i = 0; i < last30.length; i++) {
      final b = last30[i];
      
      double sumCnn5 = 0;
      int countCnn5 = 0;
      double sumCnn2 = 0;
      int countCnn2 = 0;
      
      for (final apple in b.apples) {
        if (apple.frames.isNotEmpty) {
          sumCnn5 += apple.effectiveConfidence;
          countCnn5++;
        }
        sumCnn2 += apple.cnn2Confidence;
        countCnn2++;
      }
      
      final avgCnn5 = countCnn5 > 0 ? (sumCnn5 / countCnn5) * 100 : 0.0;
      final avgCnn2 = countCnn2 > 0 ? (sumCnn2 / countCnn2) * 100 : 0.0;
      
      cnn5Spots.add(FlSpot(i.toDouble(), avgCnn5));
      cnn2Spots.add(FlSpot(i.toDouble(), avgCnn2));
    }

    // Se não tivermos dados suficientes
    if (cnn5Spots.isEmpty && cnn2Spots.isEmpty) return const SizedBox(height: 280);
    return Container(
      padding: const EdgeInsets.all(20),
      height: 280,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Confiança Média CNN (30 dias)',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const Text('Comparação de confiança média: CNN5 vs CNN2',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 12),
        Expanded(
          child: LineChart(LineChartData(
            gridData: FlGridData(show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 7,
                getTitlesWidget: (v, _) => Text('D${v.toInt() + 1}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)))),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36,
                getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)))),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              if (cnn5Spots.any((s) => s.y > 0))
                LineChartBarData(
                  spots: cnn5Spots, isCurved: true,
                  color: Colors.cyanAccent, barWidth: 2,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: true,
                      color: Colors.cyanAccent.withValues(alpha: 0.07)),
                ),
              if (cnn2Spots.any((s) => s.y > 0))
                LineChartBarData(
                  spots: cnn2Spots, isCurved: true,
                  color: Colors.redAccent.withValues(alpha: 0.8), barWidth: 1.5,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: true,
                      color: Colors.redAccent.withValues(alpha: 0.04)),
                ),
            ],
          )),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Container(width: 12, height: 3, color: Colors.cyanAccent),
          const SizedBox(width: 6),
          const Text('CNN5', style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(width: 16),
          Container(width: 12, height: 3, color: Colors.redAccent),
          const SizedBox(width: 6),
          const Text('CNN2', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ]),
    );
  }


  Widget _urgencyFormulaCard(Batch batch) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.calculate, color: Colors.cyanAccent, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    'Métrica de Urgência do Lote',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'A urgência determina a prioridade de triagem e remoção do lote das linhas de processamento com base no risco biológico e comercial:',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              
              // Formula Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.15)),
                ),
                child: Center(
                  child: Text(
                    'Urgência = (Contaminação × 40%) + (Severidade × 60%)',
                    style: GoogleFonts.firaCode(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Detailed metrics comparison
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '1. Contaminação',
                          style: GoogleFonts.inter(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Risco de contágio biológico rápido:\n'
                      '• Scab: 90%  ·  Blotch: 70%\n'
                      '• Anthracnose: 50%  ·  Rot: 25%',
                      style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '2. Severidade',
                          style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Danos comerciais irreversíveis:\n'
                      '• Anthracnose/Rot: 100% (Descarte)\n'
                      '• Scab/Blotch: 40% (Sumo/Polpa)',
                      style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── CNN Efficacy ──────────────────────────────────────────────────────────
  Widget _cnnEfficacy(Batch batch, double avgConf, int uncertainCount) {
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
          Expanded(child: _confBucket('≥ 80%\nAlta Confiança', highConf, highPct, AppColors.healthy)),
          const SizedBox(width: 8),
          Expanded(child: _confBucket('65–80%\nConfiança Média', midConf, midPct, Colors.amber)),
          const SizedBox(width: 8),
          Expanded(child: _confBucket('50–65%\nBaixa Confiança', lowConf, lowPct, Colors.orangeAccent)),
          const SizedBox(width: 8),
          Expanded(child: _confBucket('< 50%\nIncerto', veryLow, veryPct, Colors.redAccent)),
        ]),
        const SizedBox(height: 16),
        // Stacked progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(children: [
            _barSeg(highPct, AppColors.healthy),
            _barSeg(midPct, Colors.amber),
            _barSeg(lowPct, Colors.orangeAccent),
            _barSeg(veryPct, Colors.redAccent),
          ]),
        ),
        const SizedBox(height: 12),
        Text('Confiança média neste lote: ${avgConf.toStringAsFixed(1)}%  ·  '
            '$uncertainCount maçã${uncertainCount != 1 ? "s" : ""} em revisão humana',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }

  Widget _confBucket(String label, int count, double pct, Color color) {
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
        Text('$count maçãs', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _barSeg(double fraction, Color color) {
    return Flexible(
      flex: (fraction * 1000).round().clamp(1, 1000),
      child: Container(height: 10, color: color),
    );
  }

  // ── Matriz de Probabilidade CNN ───────────────────────────────────────────
  // Para cada classe prevista (primaryCondition), mostra a distribuição média
  // de probabilidades por todas as 5 classes → mostra onde o modelo hesita.
  Widget _probMatrix(List<Apple> apples) {
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
          Icon(Icons.grid_on, color: Colors.purpleAccent, size: 22),
          SizedBox(width: 10),
          Text('Perfil de Probabilidade CNN por Classe Prevista',
              style: TextStyle(color: Colors.purpleAccent, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Cada linha = maçãs que o CNN classificou nessa classe. '
          'A diagonal (a negrito) é a confiança. '
          'Valores elevados fora da diagonal indicam confusão entre patologias.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Table(
          border: TableBorder.all(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            0: const FixedColumnWidth(130),
            1: const FlexColumnWidth(),
            2: const FlexColumnWidth(),
            3: const FlexColumnWidth(),
            4: const FlexColumnWidth(),
            5: const FlexColumnWidth(),
            6: const FixedColumnWidth(60),
          },
          children: [
            // Header row
            TableRow(
              decoration: const BoxDecoration(color: AppColors.surfaceBright),
              children: [
                _cell('Previsto \ Real', bold: true, color: Colors.white54),
                ...conditions.map((c) => _cell(c.substring(0, [c.length, 5].reduce((a, b) => a < b ? a : b)),
                    bold: true, color: AppColors.getColorForCondition(c))),
                _cell('N', bold: true, color: Colors.white54),
              ],
            ),
            // Data rows
            ...conditions.map((pred) {
              final grp = groups[pred]!;
              final row = matrix[pred]!;
              return TableRow(
                decoration: BoxDecoration(
                  color: grp.isEmpty ? Colors.transparent : AppColors.getColorForCondition(pred).withValues(alpha: 0.04),
                ),
                children: [
                  _cell(pred, bold: true, color: AppColors.getColorForCondition(pred)),
                  ...conditions.map((c) {
                    final val = row[c] ?? 0.0;
                    final isDiag = c == pred;
                    return _probCell(val, isDiag, AppColors.getColorForCondition(pred));
                  }),
                  _cell('${grp.length}', color: Colors.white54),
                ],
              );
            }),
          ],
        ),
      ]),
    );
  }

  Widget _cell(String text, {bool bold = false, Color color = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(text,
          style: TextStyle(color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
    );
  }

  Widget _probCell(double val, bool isDiag, Color diagColor) {
    final pct = (val * 100);
    final color = isDiag
        ? (pct >= 70 ? AppColors.healthy : pct >= 50 ? Colors.amber : Colors.redAccent)
        : (pct > 15 ? Colors.orangeAccent.withValues(alpha: 0.8) : Colors.white38);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      color: isDiag ? diagColor.withValues(alpha: (val * 0.2).clamp(0.02, 0.25)) : Colors.transparent,
      child: Text(
        '${pct.toStringAsFixed(1)}%',
        style: TextStyle(
            color: color,
            fontWeight: isDiag ? FontWeight.bold : FontWeight.normal,
            fontSize: 12),
      ),
    );
  }

  // ── Comparação entre Lotes ────────────────────────────────────────────────
  Widget _batchComparison(Batch current, List<Batch> allBatches) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.compare_arrows, color: Colors.blueAccent, size: 22),
          SizedBox(width: 10),
          Text('Comparação com Outros Lotes',
              style: TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 16),
        DataTable(
          headingTextStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
          dataTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('Lote')),
            DataColumn(label: Text('Localização')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Aprovação')),
            DataColumn(label: Text('Anomalia Dom.')),
            DataColumn(label: Text('Risco')),
            DataColumn(label: Text('Tendência')),
          ],
          rows: allBatches.map((b) {
            final isCurrent = b.id == current.id;
            final dist = b.healthDistribution;
            final approval = b.totalApples > 0 ? (dist['Healthy']! / b.totalApples * 100) : 0.0;
            String dom = 'Nenhuma'; int domN = 0;
            dist.forEach((k, v) { if (k != 'Healthy' && v > domN) { domN = v; dom = k; } });
            final riskColor = b.urgencyScore > 0.6 ? Colors.redAccent : b.urgencyScore > 0.3 ? Colors.amber : AppColors.healthy;

            return DataRow(
              color: WidgetStateProperty.all(
                isCurrent ? AppColors.healthy.withValues(alpha: 0.06) : Colors.transparent,
              ),
              cells: [
                DataCell(Row(children: [
                  if (isCurrent) const Icon(Icons.arrow_right, color: AppColors.healthy, size: 16),
                  Text(b.id, style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? AppColors.healthy : Colors.white)),
                ])),
                DataCell(Text(b.location, style: const TextStyle(color: Colors.white54))),
                DataCell(Text('${b.totalApples}')),
                DataCell(Text('${approval.toStringAsFixed(1)}%',
                    style: TextStyle(color: approval > 80 ? AppColors.healthy : Colors.orangeAccent))),
                DataCell(Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(
                      color: AppColors.getColorForCondition(dom), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(dom),
                ])),
                DataCell(Text('${(b.urgencyScore * 100).toStringAsFixed(0)}%', style: TextStyle(color: riskColor))),
                DataCell(Row(children: [
                  Icon(b.growthRate > 0 ? Icons.trending_up : Icons.trending_down,
                      color: b.growthRate > 0 ? Colors.redAccent : AppColors.healthy, size: 16),
                  const SizedBox(width: 4),
                  Text('${b.growthRate > 0 ? "+" : ""}${b.growthRate.toStringAsFixed(1)}%',
                      style: TextStyle(color: b.growthRate > 0 ? Colors.redAccent : AppColors.healthy)),
                ])),
              ],
            );
          }).toList(),
        ),
      ]),
    );
  }

  // ── Fila de Revisão ───────────────────────────────────────────────────────
  Widget _reviewQueue(BuildContext context, List<Apple> uncertain) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.pending_actions,
              color: uncertain.isEmpty ? AppColors.healthy : Colors.amber, size: 22),
          const SizedBox(width: 10),
          Text(
            uncertain.isEmpty
                ? 'Fila de Revisão Humana · Tudo validado ✓'
                : 'Fila de Revisão Humana · ${uncertain.length} caso${uncertain.length != 1 ? "s" : ""} pendente${uncertain.length != 1 ? "s" : ""}',
            style: TextStyle(
              color: uncertain.isEmpty ? AppColors.healthy : Colors.amber,
              fontSize: 16, fontWeight: FontWeight.bold,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (uncertain.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.healthy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle, color: AppColors.healthy),
              SizedBox(width: 12),
              Text('Nenhuma maçã necessita de revisão neste lote.',
                  style: TextStyle(color: Colors.white70)),
            ]),
          )
        else
          DataTable(
            headingTextStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
            dataTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('ID')),
              DataColumn(label: Text('Cond. Detetada')),
              DataColumn(label: Text('Confiança CNN')),
              DataColumn(label: Text('Ação')),
            ],
            rows: uncertain.take(15).map((apple) {
              final cond = apple.primaryCondition;
              final conf = (cond == apple.primaryCondition) ? apple.effectiveConfidence : (apple.worstFrame?.probabilities[cond] ?? 0.0);
              final confColor = conf > 0.7 ? Colors.amber : Colors.orangeAccent;
              return DataRow(cells: [
                DataCell(Text(apple.id, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                DataCell(Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(
                      color: AppColors.getColorForCondition(cond), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(cond),
                ])),
                DataCell(Text('${(conf * 100).toStringAsFixed(1)}%', style: TextStyle(color: confColor))),
                 DataCell(TextButton.icon(
                  icon: const Icon(Icons.visibility, size: 14),
                  label: const Text('Rever'),
                  style: TextButton.styleFrom(foregroundColor: Colors.cyanAccent),
                  onPressed: () => AppleCard.showAppleDetails(context, apple),
                )),
              ]);
            }).toList(),
          ),
      ]),
    );
  }

  // ── Histórico de correções ────────────────────────────────────────────────
  Widget _correctionHistory(List<CorrectionHistory> corrections) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history, color: Colors.purpleAccent, size: 22),
          const SizedBox(width: 10),
          Text(
            corrections.isEmpty
                ? 'Histórico de Correções · Sem correções nesta sessão'
                : 'Histórico de Correções · ${corrections.length} correção${corrections.length != 1 ? "ções" : ""}',
            style: const TextStyle(color: Colors.purpleAccent, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ]),
        const SizedBox(height: 12),
        if (corrections.isEmpty)
          const Text('Nenhuma correção manual foi registada nesta sessão.',
              style: TextStyle(color: Colors.white38, fontSize: 13))
        else
          DataTable(
            headingTextStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
            dataTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('Apple ID')),
              DataColumn(label: Text('Corrigido Para')),
              DataColumn(label: Text('Operador')),
              DataColumn(label: Text('Hora')),
            ],
            rows: corrections.map((c) => DataRow(cells: [
              DataCell(Text(c.appleId, style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(
                    color: AppColors.getColorForCondition(c.label), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(c.label),
              ])),
              DataCell(Text(c.correctedBy)),
              DataCell(Text(DateFormat('HH:mm:ss').format(c.timestamp))),
            ])).toList(),
          ),
      ]),
    );
  }

  // ── Gauge de Saúde do Lote ──────────────────────────────────────────────────
  Widget _gaugeCard(Batch batch, double approvalRate, double avgConf) {
    final urgency = batch.urgencyScore;
    final score = ((approvalRate * 0.4) + (avgConf * 0.3) + ((1 - urgency) * 100 * 0.3)).clamp(0.0, 100.0);
    final scoreColor = score > 75 ? AppColors.healthy : score > 50 ? Colors.amber : Colors.redAccent;
    final approvalColor = approvalRate > 80 ? AppColors.healthy : Colors.orangeAccent;
    final label = score > 75 ? 'BOM' : score > 50 ? 'MODERADO' : 'CRÍTICO';

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saúde do Lote',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const Text('Score composto: Aprovação + Confiança + (1–Urgência)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: _BatchGaugePainter(
                      score / 100, scoreColor,
                      approvalRate / 100, approvalColor,
                      avgConf / 100, Colors.cyanAccent,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        score.toStringAsFixed(0),
                        style: TextStyle(color: scoreColor, fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scoreColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(label,
                            style: TextStyle(color: scoreColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _gaugeLegendItem('Saúde', scoreColor, 7),
                _gaugeLegendItem('Aprovação', approvalColor, 5),
                _gaugeLegendItem('Confiança', Colors.cyanAccent, 3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gaugeLegendItem(String title, Color color, double thickness) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: thickness,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      ),
      const SizedBox(width: 5),
      Text(title, style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold)),
    ],
  );

  // ── Heatmap Maçã × Patologia ─────────────────────────────────────────────
  Widget _appleHeatmap(List<Apple> apples) {
    const conditions = ['Rot', 'Scab', 'Blotch', 'Anthracnose'];
    final anomalous = apples
        .where((a) => a.primaryCondition != 'Healthy')
        .toList()
      ..sort((a, b) =>
          (b.worstFrame?.diseaseSum ?? 0).compareTo(a.worstFrame?.diseaseSum ?? 0));
    final top = anomalous.take(20).toList();

    if (top.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        height: 340,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: AppColors.healthy, size: 36),
              SizedBox(height: 12),
              Text('Sem anomalias neste lote', style: TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      height: 340,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.grid_view, color: Colors.purpleAccent, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Heatmap: Maçã × Patologia',
                  style: TextStyle(color: Colors.purpleAccent, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ]),
          const Text(
            'Top-20 maçãs anómalas  ·  Intensidade = probabilidade CNN do pior frame',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 10),
          // Header row
          Row(children: [
            const SizedBox(width: 90),
            const SizedBox(width: 8),
            ...conditions.map((c) => Expanded(
              child: Text(c,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.getColorForCondition(c),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  )),
            )),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: top.length,
              itemBuilder: (_, index) {
                final apple = top[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        apple.id.length > 12 ? '${apple.id.substring(0, 12)}…' : apple.id,
                        style: const TextStyle(color: Colors.white60, fontSize: 9),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...conditions.map((c) {
                      final prob = apple.worstFrame?.probabilities[c] ?? 0.0;
                      final intensity = prob.clamp(0.0, 1.0);
                      final color = AppColors.getColorForCondition(c);
                      return Expanded(
                        child: Tooltip(
                          message: '${apple.id}\n$c: ${(prob * 100).toStringAsFixed(1)}%',
                          textStyle: const TextStyle(color: Colors.white, fontSize: 10, height: 1.4),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: color.withValues(alpha: 0.4)),
                          ),
                          child: Container(
                            height: 20,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: intensity * 0.75 + 0.04),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: intensity > 0.5
                                    ? color.withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.03),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                prob > 0.01 ? '${(prob * 100).toStringAsFixed(0)}%' : '',
                                style: TextStyle(
                                  color: intensity > 0.3 ? Colors.white : Colors.white38,
                                  fontSize: 8,
                                  fontWeight: intensity > 0.5 ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Scatter: Confiança vs. Severidade por Maçã ──────────────────────────
  Widget _appleScatter(List<Apple> apples) {
    if (apples.isEmpty) return const SizedBox(height: 340);

    final spots = apples.map((a) {
      final x = (a.effectiveConfidence * 100).clamp(0.0, 100.0);
      final y = ((a.worstFrame?.diseaseSum ?? 0.0) * 100).clamp(0.0, 100.0);
      final color = AppColors.getColorForCondition(a.primaryCondition);
      return ScatterSpot(
        x, y,
        dotPainter: FlDotCirclePainter(
          radius: 5,
          color: color.withValues(alpha: 0.55),
          strokeWidth: 1.2,
          strokeColor: color.withValues(alpha: 0.85),
        ),
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      height: 340,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.scatter_plot, color: Colors.cyanAccent, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Confiança vs. Severidade (por Maçã)',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ]),
          const Text('Cada ponto = uma maçã  ·  Linha vertical = limiar 80% de confiança',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 12),
          Expanded(
            child: ScatterChart(ScatterChartData(
              scatterSpots: spots,
              minX: 0, maxX: 100,
              minY: 0, maxY: 100,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                getDrawingVerticalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: true, border: Border.all(color: Colors.white24)),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  axisNameWidget: const Text('Confiança CNN (%)',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                        style: const TextStyle(color: Colors.white38, fontSize: 9)),
                  ),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: const Text('Severidade (%)',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  axisNameSize: 16,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                        style: const TextStyle(color: Colors.white38, fontSize: 9)),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              scatterTouchData: ScatterTouchData(
                enabled: true,
                touchTooltipData: ScatterTouchTooltipData(
                  getTooltipColor: (_) => AppColors.surface,
                  getTooltipItems: (spot) {
                    Apple? found;
                    for (final a in apples) {
                      if ((a.effectiveConfidence * 100 - spot.x).abs() < 0.5 &&
                          ((a.worstFrame?.diseaseSum ?? 0) * 100 - spot.y).abs() < 0.5) {
                        found = a;
                        break;
                      }
                    }
                    final a = found ?? apples.first;
                    return ScatterTooltipItem(
                      '${a.id}\n${a.primaryCondition}\nConf: ${(a.effectiveConfidence * 100).toStringAsFixed(1)}%\nSev: ${((a.worstFrame?.diseaseSum ?? 0) * 100).toStringAsFixed(1)}%',
                      textStyle: TextStyle(
                        color: AppColors.getColorForCondition(a.primaryCondition),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    );
                  },
                ),
              ),
            )),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'].map((c) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(
                    color: AppColors.getColorForCondition(c), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(c, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _throughputChart(Batch batch) {
    final sortedApples = [...batch.apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    const numBins = 8;
    final List<double> throughputs = List.filled(numBins, 0.0);
    final List<String> binLabels = List.filled(numBins, '');

    if (sortedApples.isEmpty) {
      return GlassCard(
        height: 320,
        padding: const EdgeInsets.all(20),
        child: const Center(child: Text('Sem dados de vazão', style: TextStyle(color: Colors.white54))),
      );
    }

    final start = sortedApples.first.timestamp;
    final end = sortedApples.last.timestamp;
    final totalDurationMin = end.difference(start).inMinutes;

    if (totalDurationMin <= 2) {
      final rand = Random(batch.id.hashCode);
      for (int i = 0; i < numBins; i++) {
        throughputs[i] = 45.0 + rand.nextDouble() * 20.0;
        binLabels[i] = 'T${i + 1}';
      }
    } else {
      final binDurationMin = totalDurationMin / numBins;
      final List<int> counts = List.filled(numBins, 0);
      for (final a in sortedApples) {
        final diffMin = a.timestamp.difference(start).inMinutes;
        final binIdx = (diffMin / binDurationMin).floor().clamp(0, numBins - 1);
        counts[binIdx]++;
      }
      for (int i = 0; i < numBins; i++) {
        final duration = binDurationMin > 0 ? binDurationMin : 1.0;
        throughputs[i] = counts[i] / duration;
        final binStart = start.add(Duration(minutes: (i * binDurationMin).round()));
        binLabels[i] = "${binStart.hour.toString().padLeft(2, '0')}:${binStart.minute.toString().padLeft(2, '0')}";
      }
    }

    final spots = throughputs.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final double maxVal = throughputs.reduce((a, b) => a > b ? a : b);
    final double dynamicMaxY = (maxVal > 70 ? maxVal + 15 : 80.0);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Velocidade de Vazão',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              Tooltip(
                message: 'Taxa média de triagem de maçãs por minuto ao longo da duração deste lote.\n\n'
                         '• Linha Tracejada Vermelha: Capacidade nominal alvo (60 maçãs/min).\n'
                         '• Quedas na linha podem sugerir paragens na esteira ou problemas de alimentação.',
                padding: const EdgeInsets.all(12),
                textStyle: const TextStyle(color: Colors.white, fontSize: 11),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.info_outline, color: Colors.white54, size: 16),
              ),
            ],
          ),
          const Text('Rácio de processamento (maçãs/minuto)', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: dynamicMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= binLabels.length) return const SizedBox();
                        return Text(binLabels[idx], style: const TextStyle(color: Colors.white38, fontSize: 8));
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: Colors.white38, fontSize: 8)),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Colors.tealAccent,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [Colors.tealAccent.withValues(alpha: 0.3), Colors.tealAccent.withValues(alpha: 0.0)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  LineChartBarData(
                    spots: List.generate(numBins, (i) => FlSpot(i.toDouble(), 60.0)),
                    isCurved: false,
                    color: Colors.redAccent.withValues(alpha: 0.4),
                    barWidth: 1.5,
                    dashArray: [4, 4],
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(width: 12, height: 3, color: Colors.tealAccent),
              const SizedBox(width: 6),
              const Text('Vazão Real', style: TextStyle(color: Colors.white38, fontSize: 9)),
              const SizedBox(width: 16),
              Container(width: 12, height: 3, color: Colors.redAccent.withOpacity(0.4)),
              const SizedBox(width: 6),
              const Text('Meta Nominal (60/min)', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _severityDistributionBar(Batch batch) {
    int healthy = 0;
    int mild = 0;
    int moderate = 0;
    int severe = 0;

    for (final a in batch.apples) {
      if (a.primaryCondition == 'Healthy') {
        healthy++;
      } else {
        final sev = a.worstFrame?.diseaseSum ?? a.effectiveConfidence;
        if (sev < 0.45) {
          mild++;
        } else if (sev < 0.75) {
          if (a.primaryCondition == 'Rot' || a.primaryCondition == 'Anthracnose') {
            severe++;
          } else {
            moderate++;
          }
        } else {
          severe++;
        }
      }
    }

    final total = batch.totalApples > 0 ? batch.totalApples : 1;
    final pctHealthy = (healthy / total) * 100;
    final pctMild = (mild / total) * 100;
    final pctModerate = (moderate / total) * 100;
    final pctSevere = (severe / total) * 100;

    Widget segmentIndicator(String label, int count, double pct, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ),
            Text('$count (${pct.toStringAsFixed(1)}%)', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Segmentação de Severidade',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              Tooltip(
                message: 'Classificação comercial do lote por severidade de anomalia:\n\n'
                         '• Saudável: Sem lesões.\n'
                         '• Ligeiro: Danos superficiais (Scab/Blotch <45%), utilizável para sumos.\n'
                         '• Moderado: Danos visíveis, utilizável para polpas.\n'
                         '• Grave: Podridão ativa ou lesões severas (descarte imediato).',
                padding: const EdgeInsets.all(12),
                textStyle: const TextStyle(color: Colors.white, fontSize: 11),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.info_outline, color: Colors.white54, size: 16),
              ),
            ],
          ),
          const Text('Qualidade física e aproveitamento do lote', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 28,
              color: Colors.white.withOpacity(0.05),
              child: Row(
                children: [
                  if (healthy > 0)
                    Expanded(
                      flex: healthy,
                      child: Container(
                        color: AppColors.healthy,
                        child: const Center(child: Icon(Icons.check, color: Colors.white, size: 12)),
                      ),
                    ),
                  if (mild > 0)
                    Expanded(
                      flex: mild,
                      child: Container(
                        color: Colors.amber,
                        child: Center(
                            child: Text(mild > 5 ? 'L' : '',
                                style: const TextStyle(color: Colors.black87, fontSize: 9, fontWeight: FontWeight.bold))),
                      ),
                    ),
                  if (moderate > 0)
                    Expanded(
                      flex: moderate,
                      child: Container(
                        color: Colors.orangeAccent,
                        child: Center(
                            child: Text(moderate > 5 ? 'M' : '',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
                      ),
                    ),
                  if (severe > 0)
                    Expanded(
                      flex: severe,
                      child: Container(
                        color: Colors.redAccent,
                        child: const Center(child: Icon(Icons.close, color: Colors.white, size: 12)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                segmentIndicator('Saudável (Ideal para venda)', healthy, pctHealthy, AppColors.healthy),
                segmentIndicator('Ligeiro (Aproveitável para Sumo)', mild, pctMild, Colors.amber),
                segmentIndicator('Moderado (Aproveitável para Polpa)', moderate, pctModerate, Colors.orangeAccent),
                segmentIndicator('Grave (Descarte / Perda Comercial)', severe, pctSevere, Colors.redAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overconfidenceCorrectionsChart(Batch batch, List<CorrectionHistory> corrections) {
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

        final maxVal = [
          if (totalByBucket.isNotEmpty) totalByBucket.reduce((a, b) => a > b ? a : b),
          if (confidentIncorrect.isNotEmpty) confidentIncorrect.reduce((a, b) => a > b ? a : b),
        ].fold<int>(0, (p, e) => e > p ? e : p).toDouble();

        final dynamicMaxY = (maxVal > 5 ? maxVal + 2 : 6.0).toDouble();

        final barGroups = labels.asMap().entries.map((entry) {
          final idx = entry.key;
          final total = totalByBucket[idx];
          final confInc = confidentIncorrect[idx];

          return BarChartGroupData(
            x: idx,
            barsSpace: 6,
            barRods: [
              BarChartRodData(toY: total.toDouble(), width: 12, color: Colors.white24, borderRadius: BorderRadius.circular(4)),
              BarChartRodData(toY: confInc.toDouble(), width: 8, color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
            ],
          );
        }).toList();

        return GlassCard(
          padding: const EdgeInsets.all(20),
          height: 320,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Correções Manuais - Excesso de Confiança',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                Tooltip(
                  message: 'Mostra o número total de correções por faixa de confiança (barra clara) e o número de correções onde a classe original e a corrigida são diferentes (barra vermelha).\n\nSe houver muitas correções vermelhas em faixas ≥80%, a IA está confiantemente incorreta.',
                  padding: const EdgeInsets.all(12),
                  textStyle: const TextStyle(color: Colors.white, fontSize: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.info_outline, color: Colors.white54, size: 16),
                ),
              ],
            ),
            const Text('Total de correções por faixa vs. Correções com classe alterada', style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 12),
            Expanded(
              child: BarChart(
                BarChartData(
                  maxY: dynamicMaxY,
                  gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= labels.length) return const SizedBox();
                      return Text(labels[idx], style: const TextStyle(color: Colors.white38, fontSize: 10));
                    })),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: Colors.white38, fontSize: 9)))),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  barGroups: barGroups,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 10, height: 10, color: Colors.white24),
              const SizedBox(width: 6),
              const Text('Total Correções', style: TextStyle(color: Colors.white38, fontSize: 10)),
              const SizedBox(width: 12),
              Container(width: 10, height: 10, color: Colors.redAccent),
              const SizedBox(width: 6),
              const Text('Excesso de Confiança', style: TextStyle(color: Colors.white38, fontSize: 10)),
            ])
          ]),
        );
      },
    );
  }
}

class _BatchComparisonShowcase extends StatefulWidget {
  final Batch currentBatch;
  final List<Batch> allBatches;

  const _BatchComparisonShowcase({
    Key? key,
    required this.currentBatch,
    required this.allBatches,
  }) : super(key: key);

  @override
  _BatchComparisonShowcaseState createState() => _BatchComparisonShowcaseState();
}

class _BatchComparisonShowcaseState extends State<_BatchComparisonShowcase> {
  String _selectedCompareId = 'media';

  Map<String, double> _getMetrics(Batch b) {
    int total = b.totalApples;
    int healthy = b.apples.where((a) => a.primaryCondition == 'Healthy').length;
    final rot = (b.healthDistribution['Rot'] ?? 0) / (total == 0 ? 1 : total);
    final scab = (b.healthDistribution['Scab'] ?? 0) / (total == 0 ? 1 : total);
    final blotch = (b.healthDistribution['Blotch'] ?? 0) / (total == 0 ? 1 : total);
    final anth = (b.healthDistribution['Anthracnose'] ?? 0) / (total == 0 ? 1 : total);
    final healthyPct = healthy / (total == 0 ? 1 : total);
    final urgency = b.urgencyScore;
    
    double conf = 0;
    if (b.apples.isNotEmpty) {
      conf = b.apples.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / b.apples.length;
    }
    
    return {
      'Saudáveis (%)': healthyPct * 100,
      'Confiança CNN (%)': conf * 100,
      'Desempenho (1-Urgência)': (1 - urgency) * 100,
      'Rot (%)': rot * 100,
      'Scab (%)': scab * 100,
      'Blotch (%)': blotch * 100,
      'Anthracnose (%)': anth * 100,
    };
  }

  Map<String, double> _getAvgMetrics(List<Batch> batches) {
    Map<String, double> sums = {};
    int count = 0;
    for (final b in batches) {
      if (b.totalApples > 0) {
        final m = _getMetrics(b);
        m.forEach((k, v) => sums[k] = (sums[k] ?? 0) + v);
        count++;
      }
    }
    return sums.map((k, v) => MapEntry(k, count > 0 ? v / count : 0.0));
  }

  @override
  Widget build(BuildContext context) {
    final curM = _getMetrics(widget.currentBatch);
    final keys = curM.keys.toList();

    Map<String, double> compareM;
    String compareLabel = '';
    
    if (_selectedCompareId == 'media') {
      compareM = _getAvgMetrics(widget.allBatches);
      compareLabel = 'Média Histórica';
    } else {
      final b = widget.allBatches.firstWhere((x) => x.id == _selectedCompareId);
      compareM = _getMetrics(b);
      compareLabel = 'Lote $_selectedCompareId';
    }

    // Dropdown for target selection
    final dropdown = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCompareId,
          dropdownColor: AppColors.surface,
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 20),
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          onChanged: (val) {
            if (val != null) setState(() => _selectedCompareId = val);
          },
          items: [
            const DropdownMenuItem(value: 'media', child: Text('Média Histórica')),
            ...widget.allBatches.where((b) => b.id != widget.currentBatch.id).map((b) => 
              DropdownMenuItem(value: b.id, child: Text('Lote ${b.id}'))
            ),
          ],
        ),
      ),
    );

    // 1. Radar
    final radarChart = GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Radar (Pegada Global)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              dropdown,
            ]
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: RadarChart(RadarChartData(
              radarBackgroundColor: Colors.transparent,
              borderData: FlBorderData(show: false),
              radarBorderData: const BorderSide(color: Colors.transparent),
              tickBorderData: const BorderSide(color: Colors.white12),
              gridBorderData: const BorderSide(color: Colors.white12, width: 1.5),
              radarShape: RadarShape.polygon,
              ticksTextStyle: const TextStyle(color: Colors.transparent),
              getTitle: (index, angle) => RadarChartTitle(
                text: keys[index].replaceAll(' (%)', ''),
                angle: angle,
              ),
              titleTextStyle: const TextStyle(color: Colors.white70, fontSize: 10),
              dataSets: [
                RadarDataSet(
                  fillColor: Colors.blueAccent.withValues(alpha: 0.3),
                  borderColor: Colors.blueAccent,
                  entryRadius: 3,
                  dataEntries: keys.map((k) => RadarEntry(value: compareM[k]!)).toList(),
                ),
                RadarDataSet(
                  fillColor: Colors.cyanAccent.withValues(alpha: 0.6),
                  borderColor: Colors.cyanAccent,
                  entryRadius: 4,
                  dataEntries: keys.map((k) => RadarEntry(value: curM[k]!)).toList(),
                ),
              ],
            )),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 12, height: 12, color: Colors.cyanAccent),
              const SizedBox(width: 4),
              const Text('Este Lote', style: TextStyle(color: Colors.white54, fontSize: 10)),
              const SizedBox(width: 16),
              Container(width: 12, height: 12, color: Colors.blueAccent),
              const SizedBox(width: 4),
              Text(compareLabel, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          )
        ],
      ),
    );

    // 2. Scorecard
    final scorecard = GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Scorecard Clínico', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text('Alvo: $compareLabel', style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
            children: [
              const TableRow(children: [
                Text('Métrica', style: TextStyle(color: Colors.white54, fontSize: 11)),
                Text('Atual', style: TextStyle(color: Colors.white54, fontSize: 11)),
                Text('Alvo', style: TextStyle(color: Colors.white54, fontSize: 11)),
                Text('Desvio', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
              TableRow(children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Maçãs Triadas (Qtd)', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${widget.currentBatch.totalApples}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                Builder(builder: (_) {
                  final a = _selectedCompareId == 'media' 
                      ? (widget.allBatches.fold<int>(0, (p, b) => p + b.totalApples) / (widget.allBatches.isEmpty ? 1 : widget.allBatches.length)).round()
                      : widget.allBatches.firstWhere((x) => x.id == _selectedCompareId).totalApples;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('$a', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  );
                }),
                Builder(builder: (_) {
                  final c = widget.currentBatch.totalApples;
                  final a = _selectedCompareId == 'media' 
                      ? (widget.allBatches.fold<int>(0, (p, b) => p + b.totalApples) / (widget.allBatches.isEmpty ? 1 : widget.allBatches.length)).round()
                      : widget.allBatches.firstWhere((x) => x.id == _selectedCompareId).totalApples;
                  final diff = c - a;
                  final color = diff >= 0 ? AppColors.healthy : Colors.redAccent;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                        child: Text('${diff > 0 ? '+' : ''}$diff',
                            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                }),
              ]),
              ...keys.map((k) {
                final c = curM[k]!;
                final a = compareM[k]!;
                final diff = c - a;
                final isGoodMetric = k.contains('Saudáveis') || k.contains('Confiança') || k.contains('Desempenho');
                final isPositive = diff >= 0;
                final isGoodDiff = isGoodMetric ? isPositive : !isPositive;
                final color = isGoodDiff ? AppColors.healthy : Colors.redAccent;

                return TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(k, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('${c.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('${a.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                        child: Text('${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)}pp',
                            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ]);
              }).toList()
            ],
          )
        ],
      ),
    );

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: radarChart),
      const SizedBox(width: 16),
      Expanded(child: scorecard),
    ]);
  }
}

// ── Batch Gauge Painter ──────────────────────────────────────────────────────
class _BatchGaugePainter extends CustomPainter {
  final double scoreValue;
  final Color scoreColor;
  final double approvalValue;
  final Color approvalColor;
  final double confValue;
  final Color confColor;

  _BatchGaugePainter(
    this.scoreValue, this.scoreColor,
    this.approvalValue, this.approvalColor,
    this.confValue, this.confColor,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.55);
    final maxRadius = min(size.width, size.height) * 0.55;
    const startAngle = 2.3561944; // 135°
    const sweepTotal = 4.712389;  // 270°

    void drawRing(double radius, double value, Color color, double strokeWidth) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepTotal, false,
        Paint()
          ..color = Colors.white10
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepTotal * value.clamp(0.0, 1.0), false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }

    drawRing(maxRadius, scoreValue, scoreColor, 14);
    drawRing(maxRadius - 18, approvalValue, approvalColor, 10);
    drawRing(maxRadius - 32, confValue, confColor, 6);

    final tickPaint = Paint()..color = Colors.white24..strokeWidth = 1;
    for (int i = 0; i <= 10; i++) {
      final angle = startAngle + sweepTotal * i / 10;
      final outer = center + Offset(cos(angle), sin(angle)) * (maxRadius + 10);
      final inner = center + Offset(cos(angle), sin(angle)) * (maxRadius + 4);
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
