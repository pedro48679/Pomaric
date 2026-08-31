part of '../../global_dashboard.dart';

class SpcControlChart extends StatefulWidget {
  final String batchId;
  final List<Apple> currentApples;
  final List<Batch> allBatches;

  /// Correções manuais, alimentam os chips-semáforo de deriva (Z-scores,
  /// absorvidos do antigo cartão batchDriftZScore).
  final List<CorrectionHistory> corrections;

  const SpcControlChart({
    required this.batchId,
    required this.currentApples,
    required this.allBatches,
    this.corrections = const [],
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
                'Histórico insuficiente, são precisos pelo menos 2 lotes finalizados para calibrar os limites de controlo.',
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
                    'Um ponto fora da faixa (marcado a vermelho) é uma causa especial, algo mudou no processo, '
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
        const SizedBox(height: 8),
        _driftChips(),
        const SizedBox(height: 8),
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

  /// 3.C · Chips-semáforo de deriva (absorvem o cartão batchDriftZScore):
  /// Z-score de 5 métricas do lote atual vs μ±σ dos últimos 4 lotes
  /// finalizados. Verde |Z|<1 · âmbar 1–2 · vermelho ≥2. A carta responde
  /// "está estável?"; os chips respondem "o desvio é da fruta, da máquina
  /// ou do modelo?".
  Widget _driftChips() {
    final hist = widget.allBatches
        .where((b) => b.id != widget.batchId && !b.isActive && b.totalApples > 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final baseline = hist.take(4).toList();
    if (baseline.length < 2 || widget.currentApples.isEmpty) return const SizedBox.shrink();

    double healthyRate(List<Apple> apples) =>
        apples.isEmpty ? 0.0 : apples.where((a) => a.primaryCondition == 'Healthy').length / apples.length;
    double avgConf(List<Apple> apples) =>
        apples.isEmpty ? 0.0 : apples.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / apples.length;
    double avgSeverity(List<Apple> apples) => apples.isEmpty
        ? 0.0
        : apples.map((a) => a.worstFrame?.diseaseSum ?? 0.0).reduce((a, b) => a + b) / apples.length;
    double throughputOf(List<Apple> apples) {
      if (apples.length < 2) return 0.0;
      final sorted = [...apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final minutes = sorted.last.timestamp.difference(sorted.first.timestamp).inMinutes;
      return minutes <= 0 ? apples.length.toDouble() : apples.length / minutes;
    }
    double correctionRate(String batchId, List<Apple> apples) {
      if (apples.isEmpty) return 0.0;
      final ids = apples.map((a) => a.id).toSet();
      final count = widget.corrections.where((c) => c.batchId == batchId && ids.contains(c.appleId)).length;
      return count / apples.length;
    }

    (double, double) meanStd(List<double> values) {
      final mean = values.reduce((a, b) => a + b) / values.length;
      if (values.length < 2) return (mean, 0.0);
      final variance =
          values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / (values.length - 1);
      return (mean, sqrt(variance));
    }

    double zOf(double cur, double mu, double sd) => sd.abs() < 1e-9 ? 0.0 : (cur - mu) / sd;

    final metrics = <(String, double Function(Batch), double)>[];
    double curOf(double Function(List<Apple>) f) => f(widget.currentApples);
    // (label, extração no histórico, valor atual)
    metrics.add(('Saudável', (b) => healthyRate(b.apples), curOf(healthyRate)));
    metrics.add(('Confiança', (b) => avgConf(b.apples), curOf(avgConf)));
    metrics.add(('Cadência', (b) => throughputOf(b.apples), curOf(throughputOf)));
    metrics.add(('Severidade', (b) => avgSeverity(b.apples), curOf(avgSeverity)));
    metrics.add(('Correções', (b) => correctionRate(b.id, b.apples),
        correctionRate(widget.batchId, widget.currentApples)));

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final (label, histOf, cur) in metrics)
          Builder(builder: (_) {
            final (mu, sd) = meanStd(baseline.map(histOf).toList());
            final z = zOf(cur, mu, sd);
            final absZ = z.abs();
            final color = absZ >= 2 ? Colors.redAccent : absZ >= 1 ? Colors.amber : AppColors.healthy;
            return Tooltip(
              message: '$label, Z = ${z.toStringAsFixed(2)}\n'
                  'Atual: ${cur.toStringAsFixed(3)} · μ histórico: ${mu.toStringAsFixed(3)} (σ ${sd.toStringAsFixed(3)})\n'
                  '|Z|<1 Normal · 1–2 Atenção · ≥2 Anómalo',
              textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 10, height: 1.4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(z >= 0 ? Icons.arrow_upward : Icons.arrow_downward, color: color, size: 10),
                  const SizedBox(width: 3),
                  Text('$label ${z.toStringAsFixed(1)}',
                      style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold)),
                ]),
              ),
            );
          }),
      ],
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

  // Colunas por janela temporal: verde = dentro da faixa normal, vermelho =
  // fora de controlo. A faixa normal (X̄ ± 2.66·MR̄) e a média ficam na camada
  // de linha por trás (o BarChartData não suporta rangeAnnotations); o
  // alinhamento spaceAround ↔ minX -0.5..n-0.5 garante sobreposição exata.
  Widget _buildImrChart(
    List<double> binRates,
    List<String> binLabels,
    double xbar,
    double ucl,
    double lcl,
    List<bool> outOfControl,
  ) {
    final n = binRates.length;
    final candidateMax = [ucl * 100, ...binRates.map((v) => v * 100)].reduce((a, b) => a > b ? a : b);
    final maxY = (candidateMax + 10).clamp(20.0, 100.0);

    // Camada base: faixa normal + linhas de referência + eixos.
    final bandLayer = LineChart(LineChartData(
      minX: -0.5,
      maxX: n - 0.5,
      minY: 0,
      maxY: maxY,
      gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      rangeAnnotations: RangeAnnotations(
        horizontalRangeAnnotations: [
          HorizontalRangeAnnotation(y1: lcl * 100, y2: ucl * 100, color: AppColors.healthy.withValues(alpha: 0.10)),
        ],
      ),
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(y: ucl * 100, color: Colors.redAccent.withValues(alpha: 0.5), strokeWidth: 1.5, dashArray: [4, 4]),
        HorizontalLine(y: lcl * 100, color: Colors.redAccent.withValues(alpha: 0.5), strokeWidth: 1.5, dashArray: [4, 4]),
        HorizontalLine(y: xbar * 100, color: Colors.white38, strokeWidth: 1, dashArray: [2, 3]),
      ]),
      titlesData: FlTitlesData(
        // Reserva o mesmo espaço do eixo X da camada de barras (labels vazios -
        // reservedSize só conta com showTitles ativo).
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 22,
          getTitlesWidget: (v, _) => const SizedBox.shrink(),
        )),
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 32,
          getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(color: Colors.white38, fontSize: 8)),
        )),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: const [],
    ));

    // Camada de colunas: leitura imediata de "que janelas estão mal".
    final barLayer = BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround,
      minY: 0,
      maxY: maxY,
      barGroups: [
        for (int i = 0; i < n; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: binRates[i] * 100,
              width: max(10.0, 140 / n),
              color: outOfControl[i]
                  ? Colors.redAccent.withValues(alpha: 0.85)
                  : AppColors.healthy.withValues(alpha: 0.75),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ]),
      ],
      gridData: const FlGridData(show: false),
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
          getTitlesWidget: (v, _) => const SizedBox.shrink(),
        )),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppColors.surface.withValues(alpha: 0.95),
          getTooltipItem: (group, gi, rod, ri) {
            final idx = group.x;
            final flagged = outOfControl[idx];
            return BarTooltipItem(
              '${binLabels[idx]}\nTaxa de patologia: ${(binRates[idx] * 100).toStringAsFixed(1)}%\n'
              'Faixa normal: ${(lcl * 100).toStringAsFixed(1)}–${(ucl * 100).toStringAsFixed(1)}%'
              '${flagged ? "\n⚠ Fora de controlo" : ""}',
              TextStyle(
                color: flagged ? Colors.redAccent : AppColors.healthy,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            );
          },
        ),
      ),
    ));

    return Stack(children: [bandLayer, barLayer]);
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
// dos pontos reais de cada patologia, um polígono com tantos cantos quantos
// forem necessários para envolver os casos extremos dessa patologia. Uma
// patologia concentrada numa faixa estreita (ex: Healthy sempre a 0% de
// severidade) produz uma forma fina e achatada nessa zona, em vez de uma
// célula genérica a espalhar-se por onde não há dados.

  // ── Índice de Risco do Lote (IRL), Variável Híbrida Composta ─────────────
  // IRL = 100 × (0.35×Severidade + 0.25×RiscoConfiança + 0.15×PressãoVolume + 0.15×PressãoTemporal + 0.10×PressãoCorreção)

  // ── OEE da Linha de Triagem Visual (Visual Sorting OEE) ─────────────────
  // OEE = Disponibilidade × Performance × Qualidade

  // ── Faixa de Confiança por Maçã (Confidence Heat Strip) ─────────────────
  // Uma célula por maçã, em ordem cronológica, cor = confiança da CNN nessa
  // maçã específica. Deteta a olho janelas recentes de baixa confiança -
  // mais tático do que olhar só a média.
  // Codifica 2 dimensões numa só faixa: cor = patologia, opacidade = confiança.
  // Evita ser "mais um gráfico de confiança", a pergunta que responde é
  // "que problemas recentes E incertos precisam de olho humano primeiro?",
  // não "qual é a confiança" (isso já está no cronograma e no ridgeline).

