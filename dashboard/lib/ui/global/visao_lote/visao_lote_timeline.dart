part of '../../global_dashboard.dart';

class QualityTimelineChart extends StatefulWidget {
  final Batch batch;
  const QualityTimelineChart({required this.batch});

  @override
  State<QualityTimelineChart> createState() => QualityTimelineChartState();
}

class QualityTimelineChartState extends State<QualityTimelineChart> {
  final Set<String> _excluded = {};

  static const Color _burstColor = Color(0xFF6B7280); // cinza neutro, deliberadamente fora da paleta das patologias

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
    // Banda de dispersão da confiança (P25–P75), absorve o essencial do
    // ridgeline: banda estreita = classificação estável; larga = re-triagem.
    final List<double> confP25 = List.filled(numBins, 0.0);
    final List<double> confP75 = List.filled(numBins, 0.0);
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
        confP25[i] = 100.0;
        confP75[i] = 100.0;
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
        final sortedConf = binApples.map((a) => a.effectiveConfidence * 100).toList()..sort();
        double pct(double p) {
          final pos = (sortedConf.length - 1) * p;
          final lo = pos.floor(), hi = pos.ceil();
          return (sortedConf[lo] + (sortedConf[hi] - sortedConf[lo]) * (pos - lo)).clamp(0.0, 100.0);
        }
        confP25[i] = pct(0.25);
        confP75[i] = pct(0.75);
        anomalyRates[i] = (100 - pctByDisease['Healthy']![i]).clamp(0.0, 100.0);
      }
    }

    // Deteção de surtos (taxa anomalia > média + 1.5σ), sempre calculada sobre
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
        Text('Composição de patologias · confiança da CNN sobreposta · surtos marcados, $numBins janelas temporais',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 14),
        Expanded(
          child: activeOrder.isEmpty
              ? Center(child: Text('Todas as patologias estão ocultas, toca na legenda para mostrar',
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
                          final bandW = confP75[idx] - confP25[idx];
                          final lines = <String>[
                            '${binTimes[idx]}',
                            'Confiança: ${confidences[idx].toStringAsFixed(0)}% '
                                '(P25–P75: ${confP25[idx].toStringAsFixed(0)}–${confP75[idx].toStringAsFixed(0)}%)',
                          ];
                          for (final d in activeOrder.reversed) {
                            final v = pctByDisease[d]![idx];
                            if (v > 0.5) lines.add('${AppColors.displayName(d)}: ${v.toStringAsFixed(0)}%');
                          }
                          if (isBurst[idx]) lines.add('⚠ Surto detetado');
                          if (bandW > 30) lines.add('⚠ Classificação instável (banda ${bandW.toStringAsFixed(0)} pp)');
                          return spots.map((s) => s == spots.first
                              ? LineTooltipItem(lines.join('\n'), TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold, height: 1.4))
                              : null).toList();
                        },
                      ),
                    ),
                    betweenBarsData: [
                      // Banda P25–P75 da confiança (índices logo a seguir às camadas empilhadas).
                      BetweenBarsData(
                        fromIndex: activeOrder.length,
                        toIndex: activeOrder.length + 1,
                        color: Colors.white.withValues(alpha: 0.13),
                      ),
                    ],
                    lineBarsData: [
                      for (final d in activeOrder.reversed) stackedLayer(cumByDisease[d]!, AppColors.getColorForCondition(d)),
                      // Limites da banda de dispersão (linhas quase invisíveis; o
                      // preenchimento é feito pelo betweenBarsData acima).
                      LineChartBarData(
                        spots: spotsOf(confP75),
                        isCurved: true,
                        curveSmoothness: 0.2,
                        color: Colors.white.withValues(alpha: 0.25),
                        barWidth: 0.6,
                        dotData: const FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: spotsOf(confP25),
                        isCurved: true,
                        curveSmoothness: 0.2,
                        color: Colors.white.withValues(alpha: 0.25),
                        barWidth: 0.6,
                        dotData: const FlDotData(show: false),
                      ),
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
              Container(width: 12, height: 6, color: Colors.white.withValues(alpha: 0.15)),
              const SizedBox(width: 4),
              Text('Banda P25–P75', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
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

  // ── Análise de Risco Biológico ─────────────────────────────────────────

  // ═══ PARETO DE ANOMALIAS DO LOTE (removed) ═══
  // _batchPareto removed per user request, replaced by productionQualityTimeline

  // ── MATRIZ DE EISENHOWER ────────────────────────────────────────────────

