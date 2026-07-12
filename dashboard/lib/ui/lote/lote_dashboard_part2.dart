
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

class SpcControlChart extends StatefulWidget {
  final String batchId;
  final List<Apple> currentApples;
  final List<Batch> allBatches;

  const SpcControlChart({
    required this.batchId,
    required this.currentApples,
    required this.allBatches,
  });

  @override
  State<SpcControlChart> createState() => SpcControlChartState();
}

class SpcControlChartState extends State<SpcControlChart> {
  bool _showCusum = false;

  @override
  Widget build(BuildContext context) {
    final baselineDesc = widget.allBatches
        .where((b) => b.id != widget.batchId && !b.isActive && b.totalApples > 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final baseline = baselineDesc.take(5).toList().reversed.toList(); // ascendente (mais antigo→mais recente)

    if (baseline.length < 2) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 360,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Controlo Estatístico (CEP / CUSUM)',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Text(
                'Histórico insuficiente — são precisos pelo menos 2 lotes finalizados para calibrar os limites de controlo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ),
        ]),
      );
    }

    final rates = baseline.map((b) {
      final nonHealthy = b.apples.where((a) => a.primaryCondition != 'Healthy').length;
      return nonHealthy / b.totalApples;
    }).toList();

    final xbar = rates.reduce((a, b) => a + b) / rates.length;
    final mrValues = <double>[];
    for (int i = 1; i < rates.length; i++) {
      mrValues.add((rates[i] - rates[i - 1]).abs());
    }
    final mrBar = mrValues.reduce((a, b) => a + b) / mrValues.length;
    final sigma = mrBar / 1.128;
    final ucl = (xbar + 2.66 * mrBar).clamp(0.0, 1.0);
    final lcl = (xbar - 2.66 * mrBar).clamp(0.0, 1.0);

    final apples = [...widget.currentApples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (apples.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 360,
        child: Center(child: Text('Sem dados no lote/triagem selecionada', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    const numBins = 8;
    final start = apples.first.timestamp;
    final end = apples.last.timestamp;
    final totalMin = end.difference(start).inMinutes;
    final List<double> binRates = List.filled(numBins, 0.0);
    final List<String> binLabels = List.filled(numBins, '');

    if (totalMin <= 1) {
      final nonHealthy = apples.where((a) => a.primaryCondition != 'Healthy').length;
      final rate = nonHealthy / apples.length;
      for (int i = 0; i < numBins; i++) {
        binRates[i] = rate;
        binLabels[i] = 'B${i + 1}';
      }
    } else {
      final binDurationMin = totalMin / numBins;
      final List<List<Apple>> bins = List.generate(numBins, (_) => []);
      for (final a in apples) {
        final diffMin = a.timestamp.difference(start).inMinutes;
        final idx = (diffMin / binDurationMin).floor().clamp(0, numBins - 1);
        bins[idx].add(a);
      }
      for (int i = 0; i < numBins; i++) {
        final binStart = start.add(Duration(minutes: (i * binDurationMin).round()));
        binLabels[i] = "${binStart.hour.toString().padLeft(2, '0')}:${binStart.minute.toString().padLeft(2, '0')}";
        if (bins[i].isEmpty) {
          binRates[i] = i > 0 ? binRates[i - 1] : xbar;
        } else {
          final nonHealthy = bins[i].where((a) => a.primaryCondition != 'Healthy').length;
          binRates[i] = nonHealthy / bins[i].length;
        }
      }
    }

    final outOfControl = List.generate(numBins, (i) => binRates[i] > ucl || binRates[i] < lcl);
    final outOfControlCount = outOfControl.where((b) => b).length;

    // Recalcula SH/SL só para o veredito do cabeçalho (o gráfico CUSUM em si
    // é desenhado por _buildCusumChart, que faz o mesmo cálculo).
    final k = 0.5 * sigma;
    final h = 5.0 * sigma;
    double shPrev = 0, slPrev = 0;
    bool cusumBreach = false;
    for (final r in binRates) {
      shPrev = max(0.0, shPrev + (r - xbar - k));
      slPrev = max(0.0, slPrev + (xbar - k - r));
      if (shPrev > h || slPrev > h) cusumBreach = true;
    }

    final bool alarmed = _showCusum ? cusumBreach : outOfControlCount > 0;
    final Color verdictColor = alarmed ? Colors.redAccent : AppColors.healthy;
    final String verdictText = _showCusum
        ? (cusumBreach ? 'Deriva sustentada detetada' : 'Sem deriva sustentada')
        : (outOfControlCount > 0
            ? '$outOfControlCount janela${outOfControlCount != 1 ? 's' : ''} fora de controlo'
            : 'Processo sob controlo');

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 380,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Row(children: [
            Flexible(
              child: Text(_showCusum ? 'CUSUM · Deriva de Qualidade' : 'Carta CEP (I-MR) · Taxa de Patologia',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: _showCusum
                  ? 'CUSUM (Soma Cumulativa) acumula pequenos desvios face ao alvo histórico ao longo do lote.\n\n'
                    'Deteta derivas LENTAS e sustentadas (ex: lente a sujar, luz a variar) que a carta CEP não apanha porque nenhum ponto individual ultrapassa os limites.\n\n'
                    'Cruzar a linha de decisão H = deriva sustentada confirmada.'
                  : 'O que esta carta verifica:\n'
                    'Divide o lote atual em 8 janelas de tempo e mede a % de maçãs com doença detetada em cada uma.\n'
                    'Compara essa taxa com o que é "normal" para esta linha (calculado nos últimos '
                    '${baseline.length} lotes já concluídos).\n\n'
                    'A faixa verde sombreada é a zona normal (X̄ ± 2.66×MR̄). '
                    'Um ponto fora da faixa (marcado a vermelho) é uma causa especial — algo mudou no processo, '
                    'não é apenas ruído aleatório do dia a dia.',
              padding: const EdgeInsets.all(12),
              textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
              ),
              child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
            ),
            ]),
          ),
          _spcToggle(),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: verdictColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: verdictColor.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(alarmed ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: verdictColor, size: 15),
            const SizedBox(width: 6),
            Text(verdictText, style: TextStyle(color: verdictColor, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          _showCusum
              ? 'Deteção precoce de deriva lenta face ao alvo (T = X̄ = ${(xbar * 100).toStringAsFixed(1)}%)'
              : 'Faixa normal: ${(lcl * 100).toStringAsFixed(1)}% – ${(ucl * 100).toStringAsFixed(1)}% (baseado nos últimos ${baseline.length} lotes)',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(_showCusum ? 'cusum' : 'imr'),
            child: _showCusum
                ? _buildCusumChart(binRates, binLabels, xbar, sigma)
                : _buildImrChart(binRates, binLabels, xbar, ucl, lcl, outOfControl),
          ),
        ),
      ]),
    );
  }

  Widget _spcToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _spcToggleBtn('Saltos', !_showCusum, () => setState(() => _showCusum = false)),
        _spcToggleBtn('Deriva Lenta', _showCusum, () => setState(() => _showCusum = true)),
      ]),
    );
  }

  Widget _spcToggleBtn(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.purpleAccent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.purpleAccent : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }

  Widget _buildImrChart(
    List<double> binRates,
    List<String> binLabels,
    double xbar,
    double ucl,
    double lcl,
    List<bool> outOfControl,
  ) {
    final spots = binRates.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value * 100)).toList();
    final candidateMax = [ucl * 100, ...binRates.map((v) => v * 100)].reduce((a, b) => a > b ? a : b);
    final maxY = (candidateMax + 10).clamp(20.0, 100.0);

    return LineChart(LineChartData(
      minY: 0,
      maxY: maxY,
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      rangeAnnotations: RangeAnnotations(
        horizontalRangeAnnotations: [
          HorizontalRangeAnnotation(y1: lcl * 100, y2: ucl * 100, color: AppColors.healthy.withValues(alpha: 0.08)),
        ],
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 22, interval: 1,
          getTitlesWidget: (v, _) {
            final idx = v.toInt();
            if (idx < 0 || idx >= binLabels.length) return const SizedBox();
            return Text(binLabels[idx], style: const TextStyle(color: Colors.white38, fontSize: 8));
          },
        )),
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 32,
          getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(color: Colors.white38, fontSize: 8)),
        )),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipColor: (_) => AppColors.surface.withValues(alpha: 0.95),
          getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
            if (spot.barIndex != 3) return null; // só a série real, não as linhas de referência
            final idx = spot.x.toInt();
            if (idx < 0 || idx >= binLabels.length) return null;
            final flagged = outOfControl[idx];
            return LineTooltipItem(
              '${binLabels[idx]}\nTaxa de patologia: ${(binRates[idx] * 100).toStringAsFixed(1)}%${flagged ? "\n⚠ Fora de controlo" : ""}',
              TextStyle(
                color: flagged ? Colors.redAccent : Colors.cyanAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: List.generate(binRates.length, (i) => FlSpot(i.toDouble(), ucl * 100)),
          isCurved: false, color: Colors.redAccent.withValues(alpha: 0.5), barWidth: 1.5, dashArray: const [4, 4], dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: List.generate(binRates.length, (i) => FlSpot(i.toDouble(), lcl * 100)),
          isCurved: false, color: Colors.redAccent.withValues(alpha: 0.5), barWidth: 1.5, dashArray: const [4, 4], dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: List.generate(binRates.length, (i) => FlSpot(i.toDouble(), xbar * 100)),
          isCurved: false, color: Colors.white38, barWidth: 1, dashArray: const [2, 3], dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: Colors.cyanAccent,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
              radius: outOfControl[idx] ? 5 : 3,
              color: outOfControl[idx] ? Colors.redAccent : Colors.cyanAccent,
              strokeWidth: outOfControl[idx] ? 2 : 0,
              strokeColor: Colors.white,
            ),
          ),
        ),
      ],
    ));
  }

  Widget _buildCusumChart(List<double> binRates, List<String> binLabels, double xbar, double sigma) {
    final k = 0.5 * sigma;
    final h = 5.0 * sigma;
    final List<double> sh = [];
    final List<double> sl = [];
    double shPrev = 0, slPrev = 0;
    for (final r in binRates) {
      final shCur = max(0.0, shPrev + (r - xbar - k));
      final slCur = max(0.0, slPrev + (xbar - k - r));
      sh.add(shCur);
      sl.add(slCur);
      shPrev = shCur;
      slPrev = slCur;
    }

    final shSpots = sh.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value * 100)).toList();
    final slSpots = sl.asMap().entries.map((e) => FlSpot(e.key.toDouble(), -e.value * 100)).toList();
    final candidateMax = [...sh, ...sl, h].reduce((a, b) => a > b ? a : b) * 100;
    final maxY = (candidateMax + 5).clamp(10.0, 200.0);

    return LineChart(LineChartData(
      minY: -maxY,
      maxY: maxY,
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 22, interval: 1,
          getTitlesWidget: (v, _) {
            final idx = v.toInt();
            if (idx < 0 || idx >= binLabels.length) return const SizedBox();
            return Text(binLabels[idx], style: const TextStyle(color: Colors.white38, fontSize: 8));
          },
        )),
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 32,
          getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: Colors.white38, fontSize: 8)),
        )),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipColor: (_) => AppColors.surface.withValues(alpha: 0.95),
          getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
            if (spot.barIndex != 3 && spot.barIndex != 4) return null; // só SH/SL, não as linhas de referência
            final idx = spot.x.toInt();
            if (idx < 0 || idx >= binLabels.length) return null;
            final isRising = spot.barIndex == 3;
            final value = isRising ? sh[idx] * 100 : sl[idx] * 100;
            final breach = value > h * 100;
            return LineTooltipItem(
              '${binLabels[idx]}\n${isRising ? "Deriva ascendente" : "Deriva descendente"}: ${value.toStringAsFixed(1)}'
              '${breach ? "\n⚠ Acima da linha de decisão" : ""}',
              TextStyle(
                color: isRising ? Colors.redAccent : Colors.cyanAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: List.generate(binRates.length, (i) => FlSpot(i.toDouble(), h * 100)),
          isCurved: false, color: Colors.amber.withValues(alpha: 0.6), barWidth: 1.5, dashArray: const [4, 4], dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: List.generate(binRates.length, (i) => FlSpot(i.toDouble(), -h * 100)),
          isCurved: false, color: Colors.amber.withValues(alpha: 0.6), barWidth: 1.5, dashArray: const [4, 4], dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: List.generate(binRates.length, (i) => FlSpot(i.toDouble(), 0)),
          isCurved: false, color: Colors.white24, barWidth: 1, dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: shSpots,
          isCurved: false,
          color: Colors.redAccent,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
              radius: sh[idx] * 100 > h * 100 ? 5 : 3,
              color: Colors.redAccent,
              strokeWidth: sh[idx] * 100 > h * 100 ? 2 : 0,
              strokeColor: Colors.white,
            ),
          ),
        ),
        LineChartBarData(
          spots: slSpots,
          isCurved: false,
          color: Colors.cyanAccent,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
              radius: sl[idx] * 100 > h * 100 ? 5 : 3,
              color: Colors.cyanAccent,
              strokeWidth: sl[idx] * 100 > h * 100 ? 2 : 0,
              strokeColor: Colors.white,
            ),
          ),
        ),
      ],
    ));
  }
}

// ── Confiança vs. Severidade: Território por Patologia (Convex Hull) ───────
// Em vez de células fixas (hexbin), calcula o invólucro convexo (convex hull)
// dos pontos reais de cada patologia — um polígono com tantos cantos quantos
// forem necessários para envolver os casos extremos dessa patologia. Uma
// patologia concentrada numa faixa estreita (ex: Healthy sempre a 0% de
// severidade) produz uma forma fina e achatada nessa zona, em vez de uma
// célula genérica a espalhar-se por onde não há dados.

Widget batchDriftZScore(Batch batch, List<Apple> currentApples, List<Batch> allBatches, List<CorrectionHistory> allCorrections) {
    final hist = allBatches
        .where((b) => b.id != batch.id && !b.isActive && b.totalApples > 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final baseline = hist.take(4).toList();

    if (baseline.length < 2) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 360,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Z-Score de Desvio Inter-Lote', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Text(
                'Histórico insuficiente — são precisos pelo menos 2 lotes finalizados para calcular o desvio estatístico.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ),
        ]),
      );
    }

    double healthyRate(List<Apple> apples) =>
        apples.isEmpty ? 0.0 : apples.where((a) => a.primaryCondition == 'Healthy').length / apples.length;
    double avgConf(List<Apple> apples) =>
        apples.isEmpty ? 0.0 : apples.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / apples.length;
    double avgSeverity(List<Apple> apples) => apples.isEmpty
        ? 0.0
        : apples.map((a) => a.worstFrame?.diseaseSum ?? 0.0).reduce((a, b) => a + b) / apples.length;
    double throughput(List<Apple> apples) {
      if (apples.length < 2) return 0.0;
      final sorted = [...apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final minutes = sorted.last.timestamp.difference(sorted.first.timestamp).inMinutes;
      return minutes <= 0 ? apples.length.toDouble() : apples.length / minutes;
    }
    double correctionRate(String batchId, List<Apple> apples) {
      if (apples.isEmpty) return 0.0;
      final ids = apples.map((a) => a.id).toSet();
      final count = allCorrections.where((c) => c.batchId == batchId && ids.contains(c.appleId)).length;
      return count / apples.length;
    }

    (double, double) meanStd(List<double> values) {
      final mean = values.reduce((a, b) => a + b) / values.length;
      if (values.length < 2) return (mean, 0.0);
      final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / (values.length - 1);
      return (mean, sqrt(variance));
    }

    double zOf(double cur, double mu, double sd) => sd.abs() < 1e-9 ? 0.0 : (cur - mu) / sd;

    final (muHealthy, sdHealthy) = meanStd(baseline.map((b) => healthyRate(b.apples)).toList());
    final (muConf, sdConf) = meanStd(baseline.map((b) => avgConf(b.apples)).toList());
    final (muThroughput, sdThroughput) = meanStd(baseline.map((b) => throughput(b.apples)).toList());
    final (muSeverity, sdSeverity) = meanStd(baseline.map((b) => avgSeverity(b.apples)).toList());
    final (muCorr, sdCorr) = meanStd(baseline.map((b) => correctionRate(b.id, b.apples)).toList());

    final zHealthy = zOf(healthyRate(currentApples), muHealthy, sdHealthy);
    final zConf = zOf(avgConf(currentApples), muConf, sdConf);
    final zThroughput = zOf(throughput(currentApples), muThroughput, sdThroughput);
    final zSeverity = zOf(avgSeverity(currentApples), muSeverity, sdSeverity);
    final zCorr = zOf(correctionRate(batch.id, currentApples), muCorr, sdCorr);

    final allZ = [zHealthy, zConf, zThroughput, zSeverity, zCorr];
    final anomalousCount = allZ.where((z) => z.abs() >= 2).length;
    final attentionCount = allZ.where((z) => z.abs() >= 1 && z.abs() < 2).length;
    final Color summaryColor = anomalousCount > 0 ? Colors.redAccent : (attentionCount > 0 ? Colors.amber : AppColors.healthy);
    final String summaryText = anomalousCount > 0
        ? '$anomalousCount métrica${anomalousCount != 1 ? 's' : ''} anómala${anomalousCount != 1 ? 's' : ''} vs. histórico'
        : (attentionCount > 0
            ? '$attentionCount métrica${attentionCount != 1 ? 's' : ''} em atenção'
            : 'Todas as métricas dentro do normal');

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 380,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Z-Score de Desvio Inter-Lote', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          Tooltip(
            message: 'O que este gráfico verifica:\n'
                      'Compara cada métrica do lote/triagem atual com a média (μ) e desvio-padrão (σ) '
                      'dos últimos ${baseline.length} lotes finalizados — responde a "isto é normal para esta linha, ou é invulgar?"\n\n'
                      'Z = (valor atual − μ) / σ\n\n'
                      '|Z| < 1: Normal  ·  1 ≤ |Z| < 2: Atenção  ·  |Z| ≥ 2: Anómalo (desvio estatisticamente significativo)',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12)),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: summaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: summaryColor.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(anomalousCount > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: summaryColor, size: 15),
            const SizedBox(width: 6),
            Text(summaryText, style: TextStyle(color: summaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 8),
        Text('Comparado com a média dos últimos ${baseline.length} lotes finalizados', style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Column(children: [
              zScoreRow('Taxa Saudável', zHealthy),
              zScoreRow('Confiança Média CNN', zConf),
              zScoreRow('Vazão (maçãs/min)', zThroughput),
              zScoreRow('Severidade Média', zSeverity),
              zScoreRow('Taxa de Correção Manual', zCorr),
            ]),
          ),
        ),
      ]),
    );
  }

Widget zScoreRow(String label, double z) {
    final clamped = z.clamp(-3.0, 3.0);
    final frac = ((clamped + 3) / 6).clamp(0.0, 1.0);
    final absZ = z.abs();
    final color = absZ >= 2 ? Colors.redAccent : absZ >= 1 ? Colors.amber : AppColors.healthy;
    final statusWord = absZ >= 2 ? 'Anómalo' : absZ >= 1 ? 'Atenção' : 'Normal';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
              child: Text(statusWord, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Icon(z >= 0 ? Icons.arrow_upward : Icons.arrow_downward, color: color, size: 12),
            const SizedBox(width: 2),
            Text('Z = ${z.toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.bold)),
          ]),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 14,
          width: double.infinity,
          child: LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0 ? constraints.maxWidth : 200.0;
            return Stack(clipBehavior: Clip.none, children: [
              SizedBox(
                width: w,
                height: 14,
                child: Row(children: [
                  Expanded(flex: 1, child: Container(color: Colors.redAccent.withValues(alpha: 0.12))),
                  Expanded(flex: 1, child: Container(color: Colors.amber.withValues(alpha: 0.12))),
                  Expanded(flex: 2, child: Container(color: AppColors.healthy.withValues(alpha: 0.12))),
                  Expanded(flex: 1, child: Container(color: Colors.amber.withValues(alpha: 0.12))),
                  Expanded(flex: 1, child: Container(color: Colors.redAccent.withValues(alpha: 0.12))),
                ]),
              ),
              Positioned(
                left: (frac * w - 6).clamp(0.0, w - 12 > 0 ? w - 12 : 0.0),
                top: 0,
                child: Container(
                  width: 12,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
            ]);
          }),
        ),
      ]),
    );
  }

  // ── Índice de Risco do Lote (IRL) — Variável Híbrida Composta ─────────────
  // IRL = 100 × (0.35×Severidade + 0.25×RiscoConfiança + 0.15×PressãoVolume + 0.15×PressãoTemporal + 0.10×PressãoCorreção)

Widget batchRiskIndexCard(Batch batch, List<Apple> currentApples, List<Batch> allBatches, List<CorrectionHistory> allCorrections) {
    if (currentApples.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 340,
        child: Center(child: Text('Sem dados no lote/triagem selecionada', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    final hist = allBatches
        .where((b) => b.id != batch.id && !b.isActive && b.totalApples > 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final baseline = hist.take(5).toList();

    double contaminationOf(List<Apple> apples) {
      if (apples.isEmpty) return 0.0;
      final dist = <String, int>{'Healthy': 0, 'Rot': 0, 'Blotch': 0, 'Scab': 0, 'Anthracnose': 0};
      for (final a in apples) {
        final c = a.primaryCondition;
        dist[c] = (dist[c] ?? 0) + 1;
      }
      final score = (dist['Scab']! * 0.9) + (dist['Blotch']! * 0.7) + (dist['Anthracnose']! * 0.5) + (dist['Rot']! * 0.25);
      return score / apples.length;
    }

    double throughputOf(List<Apple> apples) {
      if (apples.length < 2) return 0.0;
      final sorted = [...apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final minutes = sorted.last.timestamp.difference(sorted.first.timestamp).inMinutes;
      return minutes <= 0 ? apples.length.toDouble() : apples.length / minutes;
    }

    // Baselines partilhadas (usadas tanto para o lote atual como para os
    // pontos históricos da tendência abaixo, para que sejam comparáveis).
    final avgBatchSize = baseline.isNotEmpty ? baseline.map((b) => b.totalApples).reduce((a, b) => a + b) / baseline.length : 0.0;
    double throughputMean = 0, throughputSd = 0;
    if (baseline.length >= 2) {
      final histThroughputs = baseline.map((b) => throughputOf(b.apples)).toList();
      throughputMean = histThroughputs.reduce((a, b) => a + b) / histThroughputs.length;
      final variance = histThroughputs.map((x) => (x - throughputMean) * (x - throughputMean)).reduce((a, b) => a + b) / (histThroughputs.length - 1);
      throughputSd = sqrt(variance);
    }

    double irlOf(List<Apple> apples, String batchIdForCorrections) {
      if (apples.isEmpty) return 0.0;
      final sV = contaminationOf(apples).clamp(0.0, 1.0);
      final avgC = apples.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / apples.length;
      final cV = (1 - avgC).clamp(0.0, 1.0);
      double vV = 0.0;
      if (avgBatchSize > 0) vV = ((apples.length / avgBatchSize) - 1.0).clamp(0.0, 1.0);
      double tV = 0.0;
      if (throughputSd.abs() > 1e-9) {
        final z = (throughputOf(apples) - throughputMean) / throughputSd;
        tV = (z.abs() / 3).clamp(0.0, 1.0);
      }
      final idsLocal = apples.map((a) => a.id).toSet();
      final correctionsLocal = allCorrections.where((cor) => cor.batchId == batchIdForCorrections && idsLocal.contains(cor.appleId)).length;
      final mV = (correctionsLocal / apples.length).clamp(0.0, 1.0);
      return (100 * (0.35 * sV + 0.25 * cV + 0.15 * vV + 0.15 * tV + 0.10 * mV)).clamp(0.0, 100.0);
    }

    // S — Severidade
    final s = contaminationOf(currentApples).clamp(0.0, 1.0);

    // C — Risco de Confiança (1 − confiança média)
    final avgConf = currentApples.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / currentApples.length;
    final c = (1 - avgConf).clamp(0.0, 1.0);

    // V — Pressão de Volume (excesso acima da média histórica)
    final v = avgBatchSize > 0 ? ((currentApples.length / avgBatchSize) - 1.0).clamp(0.0, 1.0) : 0.0;

    // T — Pressão Temporal (|Z| do throughput vs. histórico, normalizado)
    double t = 0.0;
    if (throughputSd.abs() > 1e-9) {
      final z = (throughputOf(currentApples) - throughputMean) / throughputSd;
      t = (z.abs() / 3).clamp(0.0, 1.0);
    }

    // M — Pressão de Correção Manual
    final ids = currentApples.map((a) => a.id).toSet();
    final correctionsInBatch = allCorrections.where((cor) => cor.batchId == batch.id && ids.contains(cor.appleId)).length;
    final m = (correctionsInBatch / currentApples.length).clamp(0.0, 1.0);

    final irl = (100 * (0.35 * s + 0.25 * c + 0.15 * v + 0.15 * t + 0.10 * m)).clamp(0.0, 100.0);

    // Tendência: IRL calculado com a mesma fórmula/baseline para os últimos
    // lotes finalizados + o lote atual — dá dimensão temporal ao índice,
    // em vez de um número estático isolado.
    final trendPoints = [
      ...baseline.reversed.map((b) => irlOf(b.apples, b.id)), // mais antigo → mais recente
      irl,
    ];

    String tier;
    Color tierColor;
    if (irl < 25) {
      tier = 'Baixo';
      tierColor = AppColors.healthy;
    } else if (irl < 50) {
      tier = 'Médio';
      tierColor = Colors.amber;
    } else if (irl < 75) {
      tier = 'Alto';
      tierColor = Colors.orangeAccent;
    } else {
      tier = 'Crítico';
      tierColor = Colors.redAccent;
    }

    // Mostra a CONTRIBUIÇÃO em pontos (valor × peso) em vez do valor bruto —
    // a % de severidade/confiança já está visível no waffle, no ridgeline e
    // no cronograma; aqui o que interessa é quanto cada fator pesa no IRL final.
    Widget factorBar(String label, double value, double weight) {
      final contribution = value * weight * 100;
      final maxContribution = weight * 100;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 128, child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.surfaceBright,
                valueColor: AlwaysStoppedAnimation(tierColor.withValues(alpha: 0.75)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: Text('+${contribution.toStringAsFixed(1)}/${maxContribution.toStringAsFixed(0)}pt',
                textAlign: TextAlign.right, style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
          ),
        ]),
      );
    }

    final trendDelta = trendPoints.length >= 2 ? trendPoints.last - trendPoints[trendPoints.length - 2] : null;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 360,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Índice de Risco do Lote (IRL)', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          Tooltip(
            message: 'IRL = 100 × (0.35×Severidade + 0.25×RiscoConfiança + 0.15×PressãoVolume + 0.15×PressãoTemporal + 0.10×PressãoCorreção)\n\n'
                      '<25 Baixo · 25-50 Médio · 50-75 Alto · >75 Crítico\n\n'
                      'As barras mostram a contribuição em pontos de cada fator para o IRL final '
                      '(não o valor bruto — esse já está no waffle, no ridgeline e no cronograma de qualidade).\n\n'
                      'A tendência à direita mostra o mesmo cálculo aplicado aos últimos lotes finalizados, '
                      'para ver se o risco está a subir ou a descer lote a lote.',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12)),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
          ),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(irl.toStringAsFixed(0), style: TextStyle(color: tierColor, fontSize: 40, fontWeight: FontWeight.bold, height: 1)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: tierColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(tier, style: TextStyle(color: tierColor, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          if (trendPoints.length >= 2) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    height: 28,
                    child: LineChart(LineChartData(
                      minY: 0,
                      maxY: 100,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: List.generate(trendPoints.length, (i) => FlSpot(i.toDouble(), trendPoints[i])),
                          isCurved: true,
                          curveSmoothness: 0.2,
                          color: tierColor.withValues(alpha: 0.85),
                          barWidth: 2,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                              radius: idx == trendPoints.length - 1 ? 3.5 : 2,
                              color: idx == trendPoints.length - 1 ? tierColor : tierColor.withValues(alpha: 0.5),
                              strokeWidth: 0,
                            ),
                          ),
                          belowBarData: BarAreaData(show: true, color: tierColor.withValues(alpha: 0.08)),
                        ),
                      ],
                    )),
                  ),
                  if (trendDelta != null)
                    Text(
                      '${trendDelta >= 0 ? "▲" : "▼"} ${trendDelta.abs().toStringAsFixed(0)}pt vs. lote anterior',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                    ),
                ]),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        factorBar('Severidade', s, 0.35),
        factorBar('Risco de Confiança', c, 0.25),
        factorBar('Pressão de Volume', v, 0.15),
        factorBar('Pressão Temporal', t, 0.15),
        factorBar('Pressão de Correção', m, 0.10),
      ]),
    );
  }

  // ── OEE da Linha de Triagem Visual (Visual Sorting OEE) ─────────────────
  // OEE = Disponibilidade × Performance × Qualidade

Widget visualSortingOee(Batch batch, List<Apple> currentApples, List<Batch> allBatches,
      List<CorrectionHistory> allCorrections, List<Apple> uncertainInBatch) {
    if (currentApples.length < 2) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        height: 340,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('OEE da Linha de Triagem Visual', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Text('Dados insuficientes no lote/triagem selecionada.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ),
        ]),
      );
    }

    final sorted = [...currentApples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final plannedMin = sorted.last.timestamp.difference(sorted.first.timestamp).inMinutes;

    double downtimeMin = 0;
    for (int i = 1; i < sorted.length; i++) {
      final gapMin = sorted[i].timestamp.difference(sorted[i - 1].timestamp).inMinutes;
      if (gapMin > 2) downtimeMin += gapMin; // paragem de linha > 2 min
    }
    final activeMin = (plannedMin - downtimeMin).clamp(0.0, plannedMin <= 0 ? 1.0 : plannedMin.toDouble());
    final a = plannedMin <= 0 ? 1.0 : (activeMin / plannedMin).clamp(0.0, 1.0);

    // Taxa Ideal — percentil 90 do throughput dos últimos lotes finalizados
    final hist = allBatches
        .where((b) => b.id != batch.id && !b.isActive && b.totalApples > 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final baseline = hist.take(5).toList();

    double throughputOf(List<Apple> apples) {
      if (apples.length < 2) return 0.0;
      final s = [...apples]..sort((x, y) => x.timestamp.compareTo(y.timestamp));
      final minutes = s.last.timestamp.difference(s.first.timestamp).inMinutes;
      return minutes <= 0 ? apples.length.toDouble() : apples.length / minutes;
    }

    double idealRate = 0.0;
    if (baseline.isNotEmpty) {
      final rates = baseline.map((b) => throughputOf(b.apples)).where((r) => r > 0).toList()..sort();
      if (rates.isNotEmpty) {
        final idx = (0.9 * (rates.length - 1)).round().clamp(0, rates.length - 1);
        idealRate = rates[idx];
      }
    }

    double p;
    if (idealRate <= 0 || activeMin <= 0) {
      p = 1.0; // sem baseline suficiente para comparar — não penaliza
    } else {
      final realRate = currentApples.length / activeMin;
      p = (realRate / idealRate).clamp(0.0, 1.0);
    }

    // Qualidade — retrabalho = correções aplicadas + ainda pendentes de revisão
    final ids = currentApples.map((x) => x.id).toSet();
    final correctedIds = allCorrections
        .where((cor) => cor.batchId == batch.id && ids.contains(cor.appleId))
        .map((cor) => cor.appleId)
        .toSet();
    final pendingIds = uncertainInBatch.where((x) => ids.contains(x.id)).map((x) => x.id).toSet();
    final reworkIds = {...correctedIds, ...pendingIds};
    final q = ((currentApples.length - reworkIds.length) / currentApples.length).clamp(0.0, 1.0);

    final oee = (a * p * q * 100).clamp(0.0, 100.0);

    String tier;
    Color tierColor;
    if (oee >= 85) {
      tier = 'Classe Mundial';
      tierColor = AppColors.healthy;
    } else if (oee >= 60) {
      tier = 'Aceitável';
      tierColor = Colors.amber;
    } else {
      tier = 'Crítico';
      tierColor = Colors.redAccent;
    }

    // Cascata: mostra onde os 100% iniciais se perdem, em vez de 3 anéis
    // desligados — responde diretamente a "onde é que estamos a perder eficiência?".
    final afterAvailability = 100 * a;
    final afterPerformance = 100 * a * p;
    final afterQuality = oee;

    final List<(String, double)> losses = [
      ('Disponibilidade', 100 - afterAvailability),
      ('Performance', afterAvailability - afterPerformance),
      ('Qualidade', afterPerformance - afterQuality),
    ];
    final biggestLoss = losses.reduce((x, y) => y.$2 > x.$2 ? y : x);

    final List<(String, double, double, Color)> stages = [
      ('Ideal', 0.0, 100.0, AppColors.textSecondary.withValues(alpha: 0.35)),
      ('Disponibilidade', afterAvailability, 100.0, Colors.cyanAccent),
      ('Performance', afterPerformance, afterAvailability, Colors.purpleAccent),
      ('Qualidade', afterQuality, afterPerformance, Colors.amber),
      ('OEE Final', 0.0, afterQuality, tierColor),
    ];

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 360,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('OEE da Linha de Triagem Visual', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          Tooltip(
            message: 'O que este gráfico mostra:\n'
                      'Parte de 100% "ideal" e vai descontando, em cascata, cada causa de perda de eficiência, '
                      'até chegar ao OEE final — assim vê-se de imediato ONDE se está a perder mais, não só o resultado total.\n\n'
                      '• Disponibilidade: tempo ativo vs. planeado (perde-se com paragens > 2 min)\n'
                      '• Performance: ritmo real vs. percentil 90 histórico (últimos ${baseline.length} lotes)\n'
                      '• Qualidade: (total − retrabalho) / total\n\n'
                      '≥85% Classe Mundial · 60-85% Aceitável · <60% Crítico',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12)),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
          ),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${oee.toStringAsFixed(1)}%', style: TextStyle(color: tierColor, fontSize: 34, fontWeight: FontWeight.bold, height: 1)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: tierColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(tier, style: TextStyle(color: tierColor, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
        Text(
          'Maior perda: ${biggestLoss.$1} (-${biggestLoss.$2.toStringAsFixed(1)}pp)',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: BarChart(BarChartData(
            minY: 0,
            maxY: 100,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 26,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= stages.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(stages[idx].$1, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 7.5)),
                  );
                },
              )),
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 30,
                getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: TextStyle(color: AppColors.textSecondary, fontSize: 8)),
              )),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.surface.withValues(alpha: 0.95),
                getTooltipItem: (group, groupIdx, rod, rodIdx) {
                  final (label, fromY, toY, _) = stages[group.x];
                  return BarTooltipItem(
                    '$label\n${(toY - fromY).toStringAsFixed(1)}pp',
                    TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
            barGroups: List.generate(stages.length, (i) {
              final (_, fromY, toY, color) = stages[i];
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(fromY: fromY, toY: toY, color: color, width: 24, borderRadius: BorderRadius.circular(4)),
              ]);
            }),
          )),
        ),
      ]),
    );
  }

  // ── Faixa de Confiança por Maçã (Confidence Heat Strip) ─────────────────
  // Uma célula por maçã, em ordem cronológica, cor = confiança da CNN nessa
  // maçã específica. Deteta a olho janelas recentes de baixa confiança —
  // mais tático do que olhar só a média.
  // Codifica 2 dimensões numa só faixa: cor = patologia, opacidade = confiança.
  // Evita ser "mais um gráfico de confiança" — a pergunta que responde é
  // "que problemas recentes E incertos precisam de olho humano primeiro?",
  // não "qual é a confiança" (isso já está no cronograma e no ridgeline).

