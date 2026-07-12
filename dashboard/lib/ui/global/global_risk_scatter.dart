part of '../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// ANÁLISE TEMPORAL DE RISCO — gráfico de dispersão interativo com
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

String _riskZoneLabel(double contPct, double sevPct) {
  if (contPct >= 15 || sevPct >= 20) return 'Crítico';
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

class _InteractiveRiscoChart extends StatefulWidget {
  final List<Batch> batches;

  const _InteractiveRiscoChart({Key? key, required this.batches}) : super(key: key);

  @override
  State<_InteractiveRiscoChart> createState() => _InteractiveRiscoChartState();
}

class _InteractiveRiscoChartState extends State<_InteractiveRiscoChart> {
  bool _isFlipped = false;
  _RiscoDayDetail? _detail;

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
    });
  }

  void _onSpotTapped(double x, double y) {
    final found = _findRiscoDayAt(widget.batches, x, y);
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

    for (int i = 0; i < widget.batches.length; i++) {
      final b = widget.batches[i];
      final batchColor = _colors[i % _colors.length];

      for (final entry in _groupApplesByDay(b).entries) {
        if (entry.value.isEmpty) continue;
        final detail = _RiscoDayDetail.from(b, entry.key, entry.value);

        spots.add(
          ScatterSpot(
            detail.chartX,
            detail.chartY,
            dotPainter: FlDotCirclePainter(
              radius: (detail.totalApples / 5.0).clamp(5.0, 18.0),
              color: batchColor.withValues(alpha: 0.60),
              strokeWidth: 1.5,
              strokeColor: batchColor.withValues(alpha: 0.9),
            ),
          ),
        );
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
                    'Cores = Lotes diferentes | Esferas = Triagem Diária | Clique no círculo para detalhes',
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
            child: ScatterChart(
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
                      final detail = _findRiscoDayAt(widget.batches, s.x, s.y, tolerance: 0.05);
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
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: widget.batches.asMap().entries.map((e) {
              final b = e.value;
              final color = _colors[e.key % _colors.length];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.35),
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    b.id,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
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
                        _metricRow('Volume Triado', '${d.totalApples} maçãs', Colors.cyanAccent),
                        const SizedBox(height: 8),
                        _metricRow('Contaminação', '${d.contaminacaoPct.toStringAsFixed(1)}%', Colors.orangeAccent),
                        const SizedBox(height: 8),
                        _metricRow('Severidade', '${d.severidadePct.toStringAsFixed(1)}%', Colors.redAccent),
                        const SizedBox(height: 8),
                        _metricRow(
                          'Δ vs Média do Lote',
                          '${fmtDelta(d.contDeltaVsBatch)} cont · ${fmtDelta(d.sevDeltaVsBatch)} sev',
                          d.contDeltaVsBatch > 0 || d.sevDeltaVsBatch > 0 ? Colors.orangeAccent : AppColors.healthy,
                        ),
                        const SizedBox(height: 8),
                        _metricRow(
                          'Doença Dominante',
                          d.dominantDisease,
                          AppColors.getColorForCondition(d.dominantDisease),
                        ),
                        const SizedBox(height: 8),
                        _metricRow(
                          'Confiança IA (dia)',
                          '${d.avgConfidencePct.toStringAsFixed(1)}%',
                          Colors.cyanAccent,
                        ),
                        const SizedBox(height: 8),
                        _metricRow(
                          'Triagem Incerta',
                          '${d.uncertainCount} maçã${d.uncertainCount == 1 ? '' : 's'}',
                          d.uncertainCount > 0 ? Colors.amber : AppColors.healthy,
                        ),
                        const SizedBox(height: 12),
                        _pipelineSplitRow(d.cnn2Count, d.cnn5Count, pipelineTotal),
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
