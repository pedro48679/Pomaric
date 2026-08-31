part of '../../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// ANÁLISE TEMPORAL DE RISCO, gráfico de dispersão interativo com
// flip para detalhe diário por lote.
// ═══════════════════════════════════════════════════════════

Map<String, List<Apple>> _groupApplesByDay(Batch batch) {
  final map = <String, List<Apple>>{};
  for (final apple in batch.apples) {
    final dayKey =
        '${apple.timestamp.year}-${apple.timestamp.month.toString().padLeft(2, '0')}-${apple.timestamp.day.toString().padLeft(2, '0')}';
    map.putIfAbsent(dayKey, () => []).add(apple);
  }
  return map;
}

({double cont, double sev, Map<String, int> dist}) _computeDayRiskMetrics(List<Apple> dayApples) {
  int scab = 0, blotch = 0, anthracnose = 0, rot = 0, healthy = 0;
  for (final a in dayApples) {
    switch (a.primaryCondition) {
      case 'Scab':
        scab++;
      case 'Blotch':
        blotch++;
      case 'Anthracnose':
        anthracnose++;
      case 'Rot':
        rot++;
      default:
        healthy++;
    }
  }
  final total = dayApples.length;
  final cont = total == 0
      ? 0.0
      : ((scab * 0.9) + (blotch * 0.7) + (anthracnose * 0.5) + (rot * 0.25)) / total;
  final sev = total == 0
      ? 0.0
      : ((anthracnose * 1.0) + (rot * 1.0) + (scab * 0.4) + (blotch * 0.4)) / total;
  return (
    cont: cont,
    sev: sev,
    dist: {
      'Healthy': healthy,
      'Rot': rot,
      'Scab': scab,
      'Blotch': blotch,
      'Anthracnose': anthracnose,
    },
  );
}

// Limiares fixos de zona de risco, mesma escala sempre, independente do que
// está filtrado/visível. O "Quadrante Crítico" desenhado no gráfico usa
// exatamente estes dois valores (contCritThreshold/sevCritThreshold), para a
// mancha vermelha representar sempre a mesma coisa que a "Zona: Crítico"
// mostrada no tooltip/detalhe de cada ponto.
const double contCritThreshold = 15.0;
const double sevCritThreshold = 20.0;

String _riskZoneLabel(double contPct, double sevPct) {
  if (contPct >= contCritThreshold || sevPct >= sevCritThreshold) return 'Crítico';
  if (contPct >= 8 || sevPct >= 12) return 'Moderado';
  if (contPct >= 4 || sevPct >= 6) return 'Atenção';
  return 'Baixo';
}

Color _riskZoneColor(String zone) {
  switch (zone) {
    case 'Crítico':
      return Colors.redAccent;
    case 'Moderado':
      return Colors.orangeAccent;
    case 'Atenção':
      return Colors.amber;
    default:
      return AppColors.healthy;
  }
}

class _RiscoDayDetail {
  final Batch batch;
  final String formattedDate;
  final int totalApples;
  final double contaminacaoPct;
  final double severidadePct;
  final Map<String, int> healthDist;
  final String dominantDisease;
  final double avgConfidencePct;
  final double contDeltaVsBatch;
  final double sevDeltaVsBatch;
  final int cnn2Count;
  final int cnn5Count;
  final int uncertainCount;
  final String riskZone;

  const _RiscoDayDetail({
    required this.batch,
    required this.formattedDate,
    required this.totalApples,
    required this.contaminacaoPct,
    required this.severidadePct,
    required this.healthDist,
    required this.dominantDisease,
    required this.avgConfidencePct,
    required this.contDeltaVsBatch,
    required this.sevDeltaVsBatch,
    required this.cnn2Count,
    required this.cnn5Count,
    required this.uncertainCount,
    required this.riskZone,
  });

  factory _RiscoDayDetail.from(Batch batch, String dayKey, List<Apple> dayApples) {
    final metrics = _computeDayRiskMetrics(dayApples);
    final contPct = metrics.cont * 100;
    final sevPct = metrics.sev * 100;

    final parts = dayKey.split('-');
    final formattedDate = parts.length == 3 ? '${parts[2]}/${parts[1]}' : dayKey;

    String dominant = 'Nenhuma';
    int domCount = 0;
    for (final entry in metrics.dist.entries) {
      if (entry.key != 'Healthy' && entry.value > domCount) {
        domCount = entry.value;
        dominant = entry.key;
      }
    }

    double confSum = 0;
    int cnn2 = 0, cnn5 = 0, uncertain = 0;
    for (final a in dayApples) {
      confSum += a.effectiveConfidence;
      if (a.modelName == 'CNN2') {
        cnn2++;
      } else if (a.modelName == 'CNN5') {
        cnn5++;
      }
      if (a.primaryCondition != 'Healthy') {
        final wf = a.worstFrame;
        final prob = wf?.probabilities[a.primaryCondition] ?? 1.0;
        if (prob < 0.80 || (prob < 0.85 && (a.id.hashCode % 100) < 5)) {
          uncertain++;
        }
      }
    }

    return _RiscoDayDetail(
      batch: batch,
      formattedDate: formattedDate,
      totalApples: dayApples.length,
      contaminacaoPct: contPct,
      severidadePct: sevPct,
      healthDist: metrics.dist,
      dominantDisease: dominant,
      avgConfidencePct: dayApples.isEmpty ? 0 : (confSum / dayApples.length) * 100,
      contDeltaVsBatch: contPct - batch.contaminationScore * 100,
      sevDeltaVsBatch: sevPct - batch.severityScore * 100,
      cnn2Count: cnn2,
      cnn5Count: cnn5,
      uncertainCount: uncertain,
      riskZone: _riskZoneLabel(contPct, sevPct),
    );
  }

  double get jitterX => (batch.id.hashCode % 10 - 5) * 0.4;
  double get jitterY => ((batch.id.hashCode ~/ 10) % 10 - 5) * 0.4;
  double get chartX => contaminacaoPct + jitterX;
  double get chartY => severidadePct + jitterY;
}

_RiscoDayDetail? _findRiscoDayAt(List<Batch> batches, double x, double y, {double tolerance = 0.15}) {
  for (final batch in batches) {
    for (final entry in _groupApplesByDay(batch).entries) {
      if (entry.value.isEmpty) continue;
      final detail = _RiscoDayDetail.from(batch, entry.key, entry.value);
      if ((detail.chartX - x).abs() < tolerance && (detail.chartY - y).abs() < tolerance) {
        return detail;
      }
    }
  }
  return null;
}

/// Decoração das Trajetórias de Risco: tinte + rótulo do quadrante crítico
/// e pontas de seta na direção do movimento mais recente de cada lote.
/// As reservas de eixo (left 56 = axisName 20 + títulos 36; bottom 46 =
/// axisName 16 + títulos 30) replicam a geometria dos charts sobrepostos.
class _RiskDecorPainter extends CustomPainter {
  final double maxX, maxY;
  final List<({Offset from, Offset to, Color color, double clearance})> arrows;
  _RiskDecorPainter({required this.maxX, required this.maxY, required this.arrows});

  @override
  void paint(Canvas canvas, Size size) {
    const double left = 56, bottom = 46;
    final plot = Rect.fromLTRB(left, 0, size.width, size.height - bottom);
    if (plot.width <= 0 || plot.height <= 0 || maxX <= 0 || maxY <= 0) return;
    double xPix(double v) => plot.left + (v / maxX) * plot.width;
    double yPix(double v) => plot.bottom - (v / maxY) * plot.height;

    // Quadrante crítico: limiares FIXOS (contCritThreshold/sevCritThreshold -
    // os mesmos usados em _riskZoneLabel para classificar cada ponto como
    // "Crítico"), não metade do eixo dinâmico. Um limiar relativo ao máximo
    // atual mudava de significado sempre que o filtro da legenda alterava a
    // escala dos eixos (ex.: filtrar um lote com valores altos reduzia o
    // "máximo", o que baixava o limiar de "metade da escala" e fazia a mancha
    // vermelha classificar como crítico o que antes não era, sem os dados
    // terem mudado).
    final qLeft = xPix(contCritThreshold).clamp(plot.left, plot.right);
    final qBottom = yPix(sevCritThreshold).clamp(plot.top, plot.bottom);
    if (qLeft < plot.right && qBottom > plot.top) {
      final qRect = Rect.fromLTRB(qLeft, plot.top, plot.right, qBottom);
      canvas.drawRect(qRect, Paint()..color = Colors.redAccent.withValues(alpha: 0.05));
      final tp = TextPainter(
        text: TextSpan(
          text: 'QUADRANTE CRÍTICO',
          style: TextStyle(
            color: Colors.redAccent.withValues(alpha: 0.55),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      if (tp.width + 16 < qRect.width) {
        tp.paint(canvas, Offset(plot.right - tp.width - 8, plot.top + 6));
      }
    }

    // Pontas de seta.
    for (final a in arrows) {
      final p0 = Offset(xPix(a.from.dx), yPix(a.from.dy));
      final p1 = Offset(xPix(a.to.dx), yPix(a.to.dy));
      final dir = p1 - p0;
      if (dir.distance < 2) continue;
      final u = dir / dir.distance;
      final nrm = Offset(-u.dy, u.dx);
      final base = p1 + u * (a.clearance + 3);
      final tip = p1 + u * (a.clearance + 12);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + nrm.dx * 4.5, base.dy + nrm.dy * 4.5)
        ..lineTo(base.dx - nrm.dx * 4.5, base.dy - nrm.dy * 4.5)
        ..close();
      canvas.drawPath(path, Paint()..color = a.color.withValues(alpha: 0.95));
    }
  }

  @override
  bool shouldRepaint(covariant _RiskDecorPainter old) =>
      old.maxX != maxX || old.maxY != maxY || old.arrows != arrows;
}

class _InteractiveRiscoChart extends StatefulWidget {
  final List<Batch> batches;

  const _InteractiveRiscoChart({Key? key, required this.batches}) : super(key: key);

  @override
  State<_InteractiveRiscoChart> createState() => _InteractiveRiscoChartState();
}

class _InteractiveRiscoChartState extends State<_InteractiveRiscoChart> {
  bool _isFlipped = false;
  _RiscoDayDetail? _detail;
  // Filtro da legenda: vazio = mostrar todos os lotes (estado inicial).
  // Clicar num lote da legenda mostra só esse; clicar num segundo soma-o ao
  // filtro; voltar a clicar um já selecionado remove-o. Ver um detalhe de dia
  // (clique numa esfera) e sair repõe o filtro vazio (todos voltam a aparecer).
  Set<String> _selectedBatchIds = {};

  List<Batch> get _visibleBatches => _selectedBatchIds.isEmpty
      ? widget.batches
      : widget.batches.where((b) => _selectedBatchIds.contains(b.id)).toList();

  void _toggleBatch(String batchId) {
    setState(() {
      if (_selectedBatchIds.contains(batchId)) {
        _selectedBatchIds = {..._selectedBatchIds}..remove(batchId);
      } else {
        _selectedBatchIds = {..._selectedBatchIds, batchId};
      }
    });
  }

  final List<Color> _colors = [
    Colors.cyanAccent,
    Colors.greenAccent,
    Colors.orangeAccent,
    Colors.pinkAccent,
    Colors.blueAccent,
    Colors.yellowAccent,
    Colors.deepOrangeAccent,
    Colors.purpleAccent,
    Colors.lightGreenAccent,
    Colors.redAccent,
  ];

  void _showDetail(_RiscoDayDetail detail) {
    setState(() {
      _detail = detail;
      _isFlipped = true;
    });
  }

  void _closeDetail() {
    setState(() {
      _isFlipped = false;
      _detail = null;
      // Ver o detalhe de um dia e voltar repõe a vista completa do lote.
      _selectedBatchIds = {};
    });
  }

  void _onSpotTapped(double x, double y) {
    final found = _findRiscoDayAt(_visibleBatches, x, y);
    if (found != null) _showDetail(found);
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: _isFlipped ? pi : 0.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, val, __) {
        final isBack = val >= pi / 2;
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(val),
          alignment: Alignment.center,
          child: isBack
              ? Transform(
                  transform: Matrix4.identity()..rotateY(pi),
                  alignment: Alignment.center,
                  child: _buildBackFace(),
                )
              : _buildFrontFace(),
        );
      },
    );
  }

  Widget _buildFrontFace() {
    final List<ScatterSpot> spots = [];
    // 2.A · Trajetórias de Risco: segmentos que ligam os dias consecutivos de
    // cada lote (opacidade cresce para o presente), a direção do movimento É
    // a tendência (substitui a coluna "Tendência" e a comparação mental).
    final List<LineChartBarData> trailSegments = [];
    final List<({Offset from, Offset to, Color color, double clearance})> trailArrows = [];

    for (int i = 0; i < widget.batches.length; i++) {
      final b = widget.batches[i];
      final batchColor = _colors[i % _colors.length];
      // Filtro da legenda: cor mantém-se ligada ao índice na lista completa
      // (não à lista filtrada), para o lote não mudar de cor ao filtrar.
      if (_selectedBatchIds.isNotEmpty && !_selectedBatchIds.contains(b.id)) continue;

      // Dias ordenados cronologicamente (as keys são yyyy-MM-dd → sort lexical).
      final entries = _groupApplesByDay(b).entries.where((e) => e.value.isNotEmpty).toList()
        ..sort((a, c) => a.key.compareTo(c.key));
      final details = [for (final e in entries) _RiscoDayDetail.from(b, e.key, e.value)];
      if (details.isEmpty) continue;

      // Deterioração ativa: trajetória global a apontar para cima/direita.
      final drift = details.length >= 2
          ? (details.last.chartX - details.first.chartX) + (details.last.chartY - details.first.chartY)
          : 0.0;
      final deteriorating = details.length >= 2 && drift > 3.0;

      for (int d = 0; d < details.length; d++) {
        final detail = details[d];
        final isLatest = d == details.length - 1;
        // Fade temporal: dias antigos esbatidos; só o dia mais recente a 100%.
        final t = details.length > 1 ? d / (details.length - 1) : 1.0;
        final bubbleAlpha = isLatest ? 0.85 : (0.22 + 0.30 * t);
        final radius = (detail.totalApples / 5.0).clamp(5.0, 18.0);
        spots.add(
          ScatterSpot(
            detail.chartX,
            detail.chartY,
            dotPainter: FlDotCirclePainter(
              radius: radius,
              color: batchColor.withValues(alpha: bubbleAlpha),
              // Dia mais recente destacado; vermelho se o lote está a deteriorar.
              strokeWidth: isLatest ? 3.0 : 1.0,
              strokeColor: isLatest
                  ? (deteriorating ? Colors.redAccent : (AppColors.isDark ? Colors.white : Colors.black87))
                  : batchColor.withValues(alpha: 0.55),
            ),
          ),
        );
        if (d > 0) {
          trailSegments.add(LineChartBarData(
            spots: [
              FlSpot(details[d - 1].chartX, details[d - 1].chartY),
              FlSpot(detail.chartX, detail.chartY),
            ],
            isCurved: false,
            barWidth: 1.4,
            color: batchColor.withValues(alpha: 0.12 + 0.48 * t),
            dotData: const FlDotData(show: false),
          ));
        }
        if (isLatest && details.length >= 2) {
          // Ponta de seta na direção do movimento, fora do raio da bolha.
          trailArrows.add((
            from: Offset(details[d - 1].chartX, details[d - 1].chartY),
            to: Offset(detail.chartX, detail.chartY),
            color: deteriorating ? Colors.redAccent : batchColor,
            clearance: radius,
          ));
        }
      }
    }

    double maxXVal = 5.0;
    double maxYVal = 5.0;
    for (final spot in spots) {
      if (spot.x > maxXVal) maxXVal = spot.x;
      if (spot.y > maxYVal) maxYVal = spot.y;
    }
    final double dynamicMaxX = (maxXVal + 10.0).clamp(10.0, 110.0);
    final double dynamicMaxY = (maxYVal + 10.0).clamp(10.0, 110.0);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 380,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Análise Temporal de Risco por Lote',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Cores = Lotes diferentes | Esferas = Triagem Diária | Clique no círculo para detalhes | '
                    'Clique na legenda para filtrar lotes',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                  ),
                ],
              ),
              Tooltip(
                message: '• Eixo X: Risco de propagação biológica fúngica.\n'
                         '• Eixo Y: Impacto de perdas comerciais.\n'
                         '• Clique num círculo para abrir o detalhe de anomalias daquele dia.',
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
          const SizedBox(height: 12),
          Expanded(
            child: BrushZoomViewer(
              child: Stack(
                children: [
                // Quadrante crítico + pontas de seta das trajetórias (decoração
                // sob os dados; usa as mesmas reservas de eixos dos charts).
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _RiskDecorPainter(
                        maxX: dynamicMaxX,
                        maxY: dynamicMaxY,
                        arrows: trailArrows,
                      ),
                    ),
                  ),
                ),
                // Trilhas temporais (por baixo do scatter): mesmos min/max e
                // mesmas reservas de eixos ⇒ os dois plots alinham pixel a pixel.
                Positioned.fill(
                  child: IgnorePointer(
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: dynamicMaxX,
                        minY: 0,
                        maxY: dynamicMaxY,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            axisNameWidget: const SizedBox.shrink(),
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (v, _) => const SizedBox.shrink(),
                            ),
                          ),
                          leftTitles: AxisTitles(
                            axisNameWidget: const SizedBox.shrink(),
                            axisNameSize: 20,
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              getTitlesWidget: (v, _) => const SizedBox.shrink(),
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        lineBarsData: trailSegments,
                      ),
                    ),
                  ),
                ),
                ScatterChart(
              ScatterChartData(
                scatterSpots: spots,
                minX: 0,
                maxX: dynamicMaxX,
                minY: 0,
                maxY: dynamicMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  getDrawingHorizontalLine: (_) => FlLine(color: AppColors.textSecondary.withOpacity(0.2), strokeWidth: 1),
                  getDrawingVerticalLine: (_) => FlLine(color: AppColors.textSecondary.withOpacity(0.2), strokeWidth: 1),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text(
                      'Contaminação Diária (Risco de Contágio)',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: Text(
                      'Gravidade Diária (Rejeição Comercial)',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                scatterTouchData: ScatterTouchData(
                  enabled: true,
                  touchCallback: (FlTouchEvent event, ScatterTouchResponse? response) {
                    if (event is FlTapUpEvent && response != null && response.touchedSpot != null) {
                      final spot = response.touchedSpot!.spot;
                      _onSpotTapped(spot.x, spot.y);
                    }
                  },
                  touchTooltipData: ScatterTouchTooltipData(fitInsideHorizontally: true, fitInsideVertically: true,
                    getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
                    getTooltipItems: (s) {
                      final detail = _findRiscoDayAt(_visibleBatches, s.x, s.y, tolerance: 0.05);
                      if (detail == null) return null;
                      final batchIdx = widget.batches.indexWhere((b) => b.id == detail.batch.id);
                      final batchColor = _colors[batchIdx % _colors.length];
                      return ScatterTooltipItem(
                        'Lote: ${detail.batch.id}\n'
                        'Dia: ${detail.formattedDate}\n'
                        'Volume: ${detail.totalApples} maçãs\n'
                        'Contaminação: ${detail.contaminacaoPct.toStringAsFixed(1)}%\n'
                        'Gravidade: ${detail.severidadePct.toStringAsFixed(1)}%\n'
                        'Zona: ${detail.riskZone}\n'
                        'Clique para detalhe',
                        textStyle: TextStyle(
                          color: batchColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                      );
                    },
                  ),
                ),
              ),
                ),
              ],
            ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: widget.batches.asMap().entries.map((e) {
              final b = e.value;
              final color = _colors[e.key % _colors.length];
              final hasFilter = _selectedBatchIds.isNotEmpty;
              final isSelected = _selectedBatchIds.contains(b.id);
              // 3 estados: sem filtro (normal) · selecionado (destacado) ·
              // filtrado (esbatido), torna visível o que está ativo.
              final isDimmed = hasFilter && !isSelected;
              return GestureDetector(
                onTap: () => _toggleBatch(b.id),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withOpacity(0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? color.withOpacity(0.7) : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color.withOpacity(isDimmed ? 0.10 : 0.35),
                            shape: BoxShape.circle,
                            border: Border.all(color: isDimmed ? color.withOpacity(0.3) : color, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          b.id,
                          style: TextStyle(
                            color: isDimmed ? AppColors.textSecondary.withOpacity(0.4) : AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBackFace() {
    final d = _detail;
    if (d == null) return const SizedBox.shrink();

    const diseases = ['Rot', 'Scab', 'Blotch', 'Anthracnose', 'Healthy'];
    final total = d.totalApples > 0 ? d.totalApples : 1;
    final zoneColor = _riskZoneColor(d.riskZone);
    final pipelineTotal = d.cnn2Count + d.cnn5Count;

    final pieChartData = PieChartData(
      sectionsSpace: 2,
      centerSpaceRadius: 22,
      sections: diseases.where((dis) => (d.healthDist[dis] ?? 0) > 0).map((dis) {
        final count = d.healthDist[dis] ?? 0;
        final pct = (count / total) * 100;
        return PieChartSectionData(
          color: AppColors.getColorForCondition(dis),
          value: count.toDouble(),
          title: '${pct.toStringAsFixed(0)}%',
          radius: 32,
          titleStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
        );
      }).toList(),
    );

    String fmtDelta(double v) => '${v >= 0 ? "+" : ""}${v.toStringAsFixed(1)}pp';

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 380,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detalhe da Triagem: ${d.formattedDate}',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Lote: ${d.batch.id}  ·  ${d.batch.location}',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: zoneColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: zoneColor.withOpacity(0.5)),
                ),
                child: Text(
                  'Zona ${d.riskZone}',
                  style: TextStyle(color: zoneColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                onPressed: _closeDetail,
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        (() {
                          final contCount = d.totalApples - (d.healthDist['Healthy'] ?? 0);
                          final domCount = d.healthDist[d.dominantDisease] ?? 0;
                          return Column(
                            children: [
                              _metricRow('Volume Inspecionado', '${d.totalApples} maçãs processadas', Colors.cyanAccent),
                              const SizedBox(height: 8),
                              _metricRow('Taxa de Contaminação', '${d.contaminacaoPct.toStringAsFixed(1)}% ($contCount infetadas)', Colors.orangeAccent),
                              const SizedBox(height: 8),
                              _metricRow('Índice de Severidade', '${d.severidadePct.toStringAsFixed(1)}% (perda comercial)', Colors.redAccent),
                              const SizedBox(height: 8),
                              _metricRow(
                                'Variação vs Média do Lote',
                                '${fmtDelta(d.contDeltaVsBatch)} contágio  ·  ${fmtDelta(d.sevDeltaVsBatch)} gravidade',
                                d.contDeltaVsBatch > 0 || d.sevDeltaVsBatch > 0 ? Colors.orangeAccent : AppColors.healthy,
                              ),
                              const SizedBox(height: 8),
                              _metricRow(
                                'Principal Patologia',
                                '${d.dominantDisease} ($domCount casos)',
                                AppColors.getColorForCondition(d.dominantDisease),
                              ),
                              const SizedBox(height: 8),
                              _metricRow(
                                'Confiança Média da IA',
                                '${d.avgConfidencePct.toStringAsFixed(1)}% de certeza',
                                Colors.cyanAccent,
                              ),
                              const SizedBox(height: 8),
                              _metricRow(
                                'Fila de Revisão Humana',
                                '${d.uncertainCount} maçã${d.uncertainCount == 1 ? '' : 's'} (casos limite)',
                                d.uncertainCount > 0 ? Colors.amber : AppColors.healthy,
                              ),
                            ],
                          );
                        })(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(child: PieChart(pieChartData)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: diseases.where((dis) => (d.healthDist[dis] ?? 0) > 0).map((dis) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.getColorForCondition(dis),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$dis (${d.healthDist[dis]})',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 8),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _pipelineSplitRow(d.cnn2Count, d.cnn5Count, pipelineTotal),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pipelineSplitRow(int cnn2, int cnn5, int total) {
    final c2Pct = total > 0 ? cnn2 / total : 0.0;
    final c5Pct = total > 0 ? cnn5 / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pipeline IA (este dia)',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (c2Pct > 0)
                  Expanded(
                    flex: (c2Pct * 100).round().clamp(1, 100),
                    child: Container(color: AppColors.primary.withOpacity(0.7)),
                  ),
                if (c5Pct > 0)
                  Expanded(
                    flex: (c5Pct * 100).round().clamp(1, 100),
                    child: Container(color: AppColors.blotch.withOpacity(0.8)),
                  ),
                if (total == 0)
                  Expanded(child: Container(color: AppColors.textSecondary.withOpacity(0.2))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CNN2 ${(c2Pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: AppColors.primary, fontSize: 9),
            ),
            Text(
              'CNN5 ${(c5Pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: AppColors.blotch, fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricRow(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
