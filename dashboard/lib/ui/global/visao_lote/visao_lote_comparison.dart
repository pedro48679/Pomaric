part of '../../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// VISÃO LOTE · COMPARAÇÃO E PRESSÃO
// Comparação entre lotes com ranking, e gauge radial de pressão fitossanitária.
// ═══════════════════════════════════════════════════════════

class BatchComparisonShowcase extends StatefulWidget {
  final Batch currentBatch;
  final List<Batch> allBatches;
  final void Function(Batch)? onBatchSelected;
  final double? quantityTargetScale;

  const BatchComparisonShowcase({
    Key? key,
    required this.currentBatch,
    required this.allBatches,
    this.onBatchSelected,
    this.quantityTargetScale,
  }) : super(key: key);

  @override
  BatchComparisonShowcaseState createState() => BatchComparisonShowcaseState();
}

class BatchComparisonShowcaseState extends State<BatchComparisonShowcase> {
  String _selectedCompareId = 'media';

  Map<String, double> _getMetrics(Batch b) {
    int total = b.totalApples;
    int healthy = b.apples.where((a) => a.primaryCondition == 'Healthy').length;
    final rot = (b.healthDistribution['Rot'] ?? 0) / (total == 0 ? 1 : total);
    final scab = (b.healthDistribution['Scab'] ?? 0) / (total == 0 ? 1 : total);
    final blotch = (b.healthDistribution['Blotch'] ?? 0) / (total == 0 ? 1 : total);
    final anth = (b.healthDistribution['Anthracnose'] ?? 0) / (total == 0 ? 1 : total);
    final healthyPct = healthy / (total == 0 ? 1 : total);
    
    double conf = 0;
    if (b.apples.isNotEmpty) {
      conf = b.apples.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / b.apples.length;
    }
    
    // Cálculo do Índice de Pielou (Complexidade J)
    final dist = b.healthDistribution;
    final totalA = total > 0 ? total : 1;
    const classes = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];
    final active = classes.where((d) => (dist[d] ?? 0) > 0).toList();
    double H = 0.0;
    for (final d in active) {
      final p = (dist[d] ?? 0) / totalA;
      if (p > 0) {
        H += -p * log(p) / log(2);
      }
    }
    final Hmax = log(active.length) / log(2);
    final J = Hmax > 0 ? (H / Hmax).clamp(0.0, 1.0) : 0.0;
    
    return {
      'Saudáveis (%)': healthyPct * 100,
      'Confiança CNN (%)': conf * 100,
      'Diversidade (%)': J * 100,
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
  void didUpdateWidget(covariant BatchComparisonShowcase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentBatch.id == _selectedCompareId) {
      setState(() {
        _selectedCompareId = 'media';
      });
    }
  }

  double _scaleRadarValue(String key, double actualValue) {
    if (key.contains('Saudáveis') || key.contains('Confiança')) {
      // Exagerar diferenças no topo (70% a 100%)
      if (actualValue <= 70) {
        return (actualValue / 70.0) * 30.0;
      } else {
        return 30.0 + ((actualValue - 70.0) / 30.0) * 70.0;
      }
    } else if (key.contains('Diversidade')) {
      // Escala linear pura, pois a diversidade usa de forma natural o range 0-100%
      return actualValue;
    } else {
      // Doenças: Expandir agressivamente o range 0-15% (ocupa 80% do raio)
      // Acima de 15%, comprime no limite exterior (20% do raio)
      if (actualValue <= 15.0) {
        return (actualValue / 15.0) * 80.0;
      } else {
        return 80.0 + ((actualValue - 15.0) / 85.0) * 20.0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sanity checks to prevent DropdownButton assertion errors when target matches current batch or doesn't exist
    if (_selectedCompareId == widget.currentBatch.id) {
      _selectedCompareId = 'media';
    }
    if (_selectedCompareId != 'media') {
      final exists = widget.allBatches.any((b) => b.id == _selectedCompareId);
      if (!exists) {
        _selectedCompareId = 'media';
      }
    }

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
      compareLabel = 'Lote ${b.id}';
    }

    // Dropdown for target selection
    final dropdown = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCompareId,
          dropdownColor: AppColors.surface,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.cyanAccent),
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
              Text('Radar (Pegada Global)', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
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
              gridBorderData: const BorderSide(color: Colors.white24, width: 1.2),
              radarShape: RadarShape.polygon,
              ticksTextStyle: const TextStyle(color: Colors.transparent),
              getTitle: (index, angle) => RadarChartTitle(
                text: keys[index].replaceAll(' (%)', ''),
                angle: angle,
              ),
              titleTextStyle: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
              dataSets: [
                // 1. Lote Atual (desenhado PRIMEIRO, no fundo, para não tapar a linha de referência)
                RadarDataSet(
                  fillColor: Colors.cyanAccent.withValues(alpha: 0.20),
                  borderColor: Colors.cyanAccent.withValues(alpha: 0.7),
                  borderWidth: 2.5,
                  entryRadius: 4.0,
                  dataEntries: keys.map((k) {
                    final v = curM[k] ?? 0.0;
                    return RadarEntry(value: _scaleRadarValue(k, v));
                  }).toList(),
                ),
                // 2. Referência (desenhada em SEGUNDO, por cima, para garantir contraste)
                RadarDataSet(
                  fillColor: Colors.purpleAccent.withValues(alpha: 0.15),
                  borderColor: Colors.purpleAccent,
                  borderWidth: 2.5,
                  entryRadius: 4.0,
                  dataEntries: keys.map((k) {
                    final v = compareM[k] ?? 0.0;
                    return RadarEntry(value: _scaleRadarValue(k, v));
                  }).toList(),
                ),
              ],
            )),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.cyanAccent, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text('Lote ${widget.currentBatch.id}', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(width: 20),
              Container(width: 10, height: 2, decoration: const BoxDecoration(color: Colors.purpleAccent)), // line dash symbol
              const SizedBox(width: 6),
              Text(compareLabel, style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );

    // 2. Scorecard (+ coluna "Δ Pomar": lote vs média dos OUTROS lotes -
    // absorve o dumbbell batchVsPomarProfile numa coluna quantificada).
    final others = widget.allBatches.where((b) => b.id != widget.currentBatch.id).toList();
    final othersM = others.isEmpty ? curM : _getAvgMetrics(others);
    final scorecard = GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Scorecard Clínico', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              Text('Alvo: $compareLabel', style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1), 4: FlexColumnWidth(1)},
            children: [
              TableRow(children: [
                Text('Métrica', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('Atual', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('Alvo', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('Desvio', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('Δ Pomar', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ]),
              TableRow(children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Maçãs Triadas (Qtd)', style: TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${widget.currentBatch.totalApples}', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
                Builder(builder: (_) {
                  final rawA = _selectedCompareId == 'media' 
                      ? (widget.allBatches.fold<int>(0, (p, b) => p + b.totalApples) / (widget.allBatches.isEmpty ? 1 : widget.allBatches.length)).round()
                      : widget.allBatches.firstWhere((x) => x.id == _selectedCompareId).totalApples;
                  final a = widget.quantityTargetScale != null ? (rawA * widget.quantityTargetScale!).round() : rawA;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('$a', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  );
                }),
                Builder(builder: (_) {
                  final c = widget.currentBatch.totalApples;
                  final rawA = _selectedCompareId == 'media' 
                      ? (widget.allBatches.fold<int>(0, (p, b) => p + b.totalApples) / (widget.allBatches.isEmpty ? 1 : widget.allBatches.length)).round()
                      : widget.allBatches.firstWhere((x) => x.id == _selectedCompareId).totalApples;
                  final a = widget.quantityTargetScale != null ? (rawA * widget.quantityTargetScale!).round() : rawA;
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
                const SizedBox.shrink(), // Δ Pomar não se aplica à contagem
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
                    child: Text(k, style: TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('${c.toStringAsFixed(1)}%', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('${a.toStringAsFixed(1)}%', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
                  // Δ vs média dos OUTROS lotes (semântica do antigo dumbbell).
                  Builder(builder: (_) {
                    final p = othersM[k] ?? c;
                    final dp = c - p;
                    final good = isGoodMetric ? dp >= 0 : dp <= 0;
                    final pColor = good ? AppColors.healthy : Colors.redAccent;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(dp >= 0 ? Icons.arrow_upward : Icons.arrow_downward, color: pColor, size: 11),
                          const SizedBox(width: 2),
                          Text('${dp.abs().toStringAsFixed(1)}pp',
                              style: TextStyle(color: pColor, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }),
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
      const SizedBox(width: 16),
      SizedBox(width: 230, child: _buildBatchRankingPanel()),
    ]);
  }

  Widget _buildBatchRankingPanel() {
    final sorted = [...widget.allBatches]..sort((a, b) {
      final aRate = a.totalApples > 0 ? (a.healthDistribution['Healthy'] ?? 0) / a.totalApples * 100 : 0.0;
      final bRate = b.totalApples > 0 ? (b.healthDistribution['Healthy'] ?? 0) / b.totalApples * 100 : 0.0;
      return bRate.compareTo(aRate);
    });

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.format_list_numbered, color: Color(0xff8B5CF6), size: 16),
            const SizedBox(width: 8),
            Text('Ranking de Lotes',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 2),
          Text('Toque para comparar  ·  → para navegar',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          const SizedBox(height: 10),
          ...sorted.asMap().entries.map((entry) {
            final i = entry.key;
            final b = entry.value;
            final isCurrent = b.id == widget.currentBatch.id;
            final isSelected = b.id == _selectedCompareId;
            final approval = b.totalApples > 0
                ? (b.healthDistribution['Healthy'] ?? 0) / b.totalApples * 100
                : 0.0;
            final urgColor = b.urgencyScore > 0.3
                ? Colors.redAccent
                : b.urgencyScore > 0.10
                    ? Colors.amber
                    : AppColors.healthy;

            return GestureDetector(
              onTap: () => setState(() => _selectedCompareId = b.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppColors.healthy.withOpacity(0.08)
                      : isSelected
                          ? const Color(0xff8B5CF6).withOpacity(0.08)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent
                        ? AppColors.healthy.withOpacity(0.3)
                        : isSelected
                            ? const Color(0xff8B5CF6).withOpacity(0.3)
                            : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(children: [
                  SizedBox(
                    width: 18,
                    child: Text('#${i + 1}',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Text(
                      b.id.length > 10 ? '${b.id.substring(0, 10)}…' : b.id,
                      style: TextStyle(
                        color: isCurrent ? AppColors.healthy : AppColors.textPrimary,
                        fontSize: 10,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    '${approval.toStringAsFixed(0)}%',
                    style: TextStyle(
                        color: approval >= 80 ? AppColors.healthy : Colors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: urgColor, shape: BoxShape.circle)),
                  if (!isCurrent) ...[
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: () => widget.onBatchSelected?.call(b),
                      child: Tooltip(
                        message: 'Ir para lote ${b.id}',
                        child: Icon(Icons.open_in_new,
                            size: 13, color: const Color(0xff8B5CF6)),
                      ),
                    ),
                  ] else
                    const SizedBox(width: 18),
                ]),
              ),
            );
          }).toList(),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                    color: AppColors.healthy, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('Atual', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
            const SizedBox(width: 12),
            const Icon(Icons.open_in_new, size: 9, color: Color(0xff8B5CF6)),
            const SizedBox(width: 4),
            Text('Navegar', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          ]),
        ],
      ),
    );
  }
}
Widget phytosanitaryPressureGauge(Batch batch) {
    final dist = batch.healthDistribution;
    final total = batch.totalApples > 0 ? batch.totalApples : 1;

    // Componentes normalizados 0-100
    final propagacao = (batch.contaminationScore * 100).clamp(0.0, 100.0);
    final danoComercial = (batch.severityScore * 100).clamp(0.0, 100.0);
    final taxaDoenca = ((1 - (dist['Healthy'] ?? 0) / total) * 100).clamp(0.0, 100.0);

    // Shannon diversity (normalized by max = log2(5) ≈ 2.322)
    double H = 0;
    for (final d in ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose']) {
      final p = (dist[d] ?? 0) / total;
      if (p > 0) H -= p * log(p) / log(2);
    }
    final diversidade = ((H / (log(5) / log(2))) * 100).clamp(0.0, 100.0);

    // Composite pressure score
    final pressure = (propagacao * 0.30 + danoComercial * 0.25 + taxaDoenca * 0.30 + diversidade * 0.15) / 100.0;
    final pressureColor = pressure >= 0.65 ? Colors.redAccent : pressure >= 0.35 ? Colors.amber : AppColors.healthy;

    final level = pressure >= 0.65 ? 'Crítica' : pressure >= 0.35 ? 'Moderada' : 'Baixa';

    final axes = [
      ('Propagação', propagacao),
      ('Dano Comercial', danoComercial),
      ('Taxa Doença', taxaDoenca),
      ('Diversidade', diversidade),
    ];

    Color compColor(double v01) => v01 >= 0.65 ? Colors.redAccent : v01 >= 0.35 ? Colors.amber : AppColors.healthy;

    Widget miniRing(String label, double v01, Color c) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: CircularProgressIndicator(
                      value: v01.clamp(0.0, 1.0),
                      strokeWidth: 5,
                      backgroundColor: c.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(c),
                    ),
                  ),
                  Text('${(v01 * 100).toStringAsFixed(0)}',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          ],
        );

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 340,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Row(children: [
            Icon(Icons.speed_rounded, color: Colors.cyanAccent, size: 20),
            SizedBox(width: 8),
            Text('Pressão Fitossanitária',
                style: TextStyle(color: Colors.cyanAccent, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          Tooltip(
            message: 'Índice composto de pressão fitossanitária:\n\n'
                     '  Propagação (30%): risco de alastramento entre maçãs\n'
                     '  Dano Comercial (25%): perda de valor de venda\n'
                     '  Taxa de Doença (30%): % de maçãs afetadas\n'
                     '  Diversidade (15%): complexidade do perfil de doenças\n\n'
                     'Gauge = pressão total · anéis = cada componente.\n'
                     'Valor mais alto = maior pressão = triagem mais custosa.',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
            ),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 15),
          ),
        ]),
        Text('Gauge = índice composto · anéis = componentes',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 8),
        Expanded(
          child: Row(children: [
            // Gauge radial, pressão composta
            Expanded(
              flex: 3,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.7,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      CustomPaint(
                        size: Size.infinite,
                        painter: _PhytoGaugePainter(pressure.clamp(0.0, 1.0), pressureColor),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('${(pressure * 100).toStringAsFixed(0)}',
                              style: TextStyle(color: pressureColor, fontSize: 34, fontWeight: FontWeight.bold, height: 1.0)),
                          Text('pressão · $level',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 4 componentes como mini-anéis (2×2)
            Expanded(
              flex: 2,
              child: Center(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: axes
                      .map((a) => SizedBox(width: 58, child: miniRing(a.$1, a.$2 / 100.0, compColor(a.$2 / 100.0))))
                      .toList(),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
/// Gauge radial semicircular (topo) para a pressão fitossanitária: bandas de
/// zona verde/âmbar/vermelho + arco de valor + marcador.
class _PhytoGaugePainter extends CustomPainter {
  final double value; // 0..1
  final Color color;
  _PhytoGaugePainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 6);
    final radius = min(size.width / 2, size.height) - 16;
    if (radius <= 0) return;
    const stroke = 14.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    Paint arc(Color c, {StrokeCap cap = StrokeCap.butt}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = cap
      ..color = c;

    // Track
    canvas.drawArc(rect, pi, pi, false, arc((AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.06)));
    // Zonas (semicírculo superior: startAngle=pi, sweep=pi no sentido horário)
    void zone(double from, double to, Color c) =>
        canvas.drawArc(rect, pi + from * pi, (to - from) * pi, false, arc(c.withOpacity(0.28)));
    zone(0.0, 0.35, AppColors.healthy);
    zone(0.35, 0.65, Colors.amber);
    zone(0.65, 1.0, Colors.redAccent);
    // Arco de valor
    canvas.drawArc(rect, pi, value.clamp(0.0, 1.0) * pi, false, arc(color, cap: StrokeCap.round));
    // Marcador
    final ang = pi + value.clamp(0.0, 1.0) * pi;
    final tip = Offset(center.dx + radius * cos(ang), center.dy + radius * sin(ang));
    canvas.drawCircle(tip, stroke * 0.6, Paint()..color = (AppColors.isDark ? Colors.white : Colors.white));
    canvas.drawCircle(tip, stroke * 0.42, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PhytoGaugePainter old) => old.value != value || old.color != color;
}

  // ── D3: Índice de Diversidade de Shannon-Wiener ──────────────────────────
  // H = -Σ pᵢ × log₂(pᵢ) sobre todas as classes de doença.
