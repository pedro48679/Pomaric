
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

Widget eisenhowerMatrix(Batch batch) {
    // Pesos base por doença (contágio = propensão a alastrar; econ = perda de valor).
    const meta = {
      'Rot': {'name': 'Rot', 'contagion': 0.95, 'econ': 0.90},
      'Anthracnose': {'name': 'Anthracnose', 'contagion': 0.85, 'econ': 0.85},
      'Blotch': {'name': 'Sooty Blotch', 'contagion': 0.55, 'econ': 0.40},
      'Scab': {'name': 'Scab', 'contagion': 0.35, 'econ': 0.60},
    };

    final dist = batch.healthDistribution;
    final total = batch.totalApples > 0 ? batch.totalApples : 1;
    final active = meta.keys.where((d) => (dist[d] ?? 0) > 0).toList();

    // Prevalência e severidade média REAIS por doença neste lote → posições data-driven.
    double maxPrev = 0.0;
    final prev = <String, double>{};
    final sev = <String, double>{};
    for (final d in active) {
      final applesOf = batch.apples.where((a) => a.primaryCondition == d).toList();
      final p = (dist[d] ?? 0) / total;
      prev[d] = p;
      if (p > maxPrev) maxPrev = p;
      sev[d] = applesOf.isEmpty
          ? 0.5
          : applesOf.map((a) => a.worstFrame?.diseaseSum ?? 0.0).fold(0.0, (x, y) => x + y) / applesOf.length;
    }
    if (maxPrev <= 0) maxPrev = 1;

    final points = active.map((d) {
      final m = meta[d]!;
      final x = ((m['econ'] as double) * (0.55 + 0.45 * sev[d]!) * 100).clamp(4.0, 98.0);
      final np = prev[d]! / maxPrev;
      final y = ((m['contagion'] as double) * (0.30 + 0.70 * np) * 100).clamp(4.0, 98.0);
      final count = dist[d] ?? 0;
      final action = (y >= 50 && x >= 50)
          ? 'Fazer agora'
          : (y < 50 && x >= 50)
              ? 'Agendar'
              : (y >= 50 && x < 50)
                  ? 'Monitorizar'
                  : 'Ignorar';
      return (d: d, name: m['name'] as String, x: x, y: y, count: count, sev: sev[d]!, action: action);
    }).toList();

    int qNow = 0, qSched = 0, qMon = 0, qIgn = 0;
    for (final p in points) {
      switch (p.action) {
        case 'Fazer agora': qNow += p.count; break;
        case 'Agendar': qSched += p.count; break;
        case 'Monitorizar': qMon += p.count; break;
        default: qIgn += p.count;
      }
    }

    Widget corner(String label, int count, Color c, {bool right = false}) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
            Text('$count maçãs', style: TextStyle(color: c.withValues(alpha: 0.85), fontSize: 9)),
          ],
        );

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 380,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.widgets, color: Colors.indigoAccent, size: 20),
            const SizedBox(width: 8),
            Text('Matriz de Ação Estratégica',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          Tooltip(
            message: 'Eixo Y = Urgência (contágio × prevalência real no lote)\n'
                     'Eixo X = Impacto (peso económico × severidade média real)\n'
                     'Tamanho da bolha = nº de maçãs afetadas.\n\n'
                     'Fazer agora (↗) · Agendar (↘) · Monitorizar (↖) · Ignorar (↙)',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
            ),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
          ),
        ]),
        Text('Posição data-driven pela prevalência e severidade reais deste lote',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 16),
        if (points.isEmpty)
          Expanded(child: Center(child: Text('Sem patologias ativas neste lote', style: TextStyle(color: AppColors.textSecondary))))
        else
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: Container(color: Colors.lightBlueAccent.withValues(alpha: 0.12))),
                          Expanded(child: Container(color: Colors.redAccent.withValues(alpha: 0.14))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: Container(color: Colors.green.withValues(alpha: 0.12))),
                          Expanded(child: Container(color: Colors.orangeAccent.withValues(alpha: 0.12))),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: ScatterChart(
                    ScatterChartData(
                      scatterSpots: points.map((p) {
                        return ScatterSpot(
                          p.x,
                          p.y,
                          dotPainter: FlDotCirclePainter(
                            radius: 14.0 + (prev[p.d]! / maxPrev) * 20.0,
                            color: AppColors.getColorForCondition(p.d).withValues(alpha: 0.82),
                            strokeWidth: 1.5,
                            strokeColor: Colors.white,
                          ),
                        );
                      }).toList(),
                      minX: 0,
                      maxX: 100,
                      minY: 0,
                      maxY: 100,
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.1)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawHorizontalLine: true,
                        drawVerticalLine: true,
                        checkToShowHorizontalLine: (val) => val == 50,
                        checkToShowVerticalLine: (val) => val == 50,
                        getDrawingHorizontalLine: (_) => FlLine(color: AppColors.textSecondary.withValues(alpha: 0.4), strokeWidth: 1, dashArray: [5, 5]),
                        getDrawingVerticalLine: (_) => FlLine(color: AppColors.textSecondary.withValues(alpha: 0.4), strokeWidth: 1, dashArray: [5, 5]),
                      ),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          axisNameWidget: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Impacto (severidade económica)', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          axisNameSize: 20,
                          sideTitles: SideTitles(showTitles: true, reservedSize: 16, interval: 50,
                            getTitlesWidget: (v, _) => Text(v == 0 ? 'baixo' : v >= 100 ? 'alto' : '', style: TextStyle(color: AppColors.textSecondary, fontSize: 8))),
                        ),
                        leftTitles: AxisTitles(
                          axisNameWidget: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('Urgência', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          axisNameSize: 20,
                          sideTitles: SideTitles(showTitles: true, reservedSize: 22, interval: 50,
                            getTitlesWidget: (v, _) => Text(v == 0 ? 'baixa' : v >= 100 ? 'alta' : '', style: TextStyle(color: AppColors.textSecondary, fontSize: 8))),
                        ),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      scatterTouchData: ScatterTouchData(
                        enabled: true,
                        touchTooltipData: ScatterTouchTooltipData(fitInsideHorizontally: true, fitInsideVertically: true,
                          getTooltipColor: (_) => AppColors.surface.withValues(alpha: 0.95),
                          getTooltipItems: (spot) {
                            var best = points.first;
                            double bd = double.infinity;
                            for (final p in points) {
                              final dd = (p.x - spot.x) * (p.x - spot.x) + (p.y - spot.y) * (p.y - spot.y);
                              if (dd < bd) { bd = dd; best = p; }
                            }
                            return ScatterTooltipItem(
                              '${best.name}\n',
                              textStyle: TextStyle(color: AppColors.getColorForCondition(best.d), fontWeight: FontWeight.bold, fontSize: 12),
                              children: [
                                TextSpan(
                                  text: '${best.action}\n',
                                  style: TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text: 'Impacto: ${best.x.toInt()} | Urgência: ${best.y.toInt()}\n',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                                ),
                                TextSpan(
                                  text: 'Severidade média: ${(best.sev * 100).toInt()}% · ${best.count} maçãs',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(top: 6, right: 8, child: corner('Fazer agora', qNow, Colors.redAccent, right: true)),
                Positioned(bottom: 6, right: 8, child: corner('Agendar', qSched, Colors.orangeAccent, right: true)),
                Positioned(top: 6, left: 8, child: corner('Monitorizar', qMon, Colors.lightBlueAccent)),
                Positioned(bottom: 6, left: 8, child: corner('Ignorar', qIgn, Colors.green)),
              ],
            ),
          ),
      ]),
    );
  }

  // ── dummy placeholder to keep line numbers stable ─────────────────────

Widget humanTriageActivity(BuildContext context, List<Apple> uncertain, List<CorrectionHistory> corrections) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 340,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.fact_check_outlined, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 8),
          Text('Auditoria Humana (Controlo Qualidade)', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        Text('Auditoria Pendente e Correções Aplicadas',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: triageQueuePanel(context, uncertain)),
            Container(width: 1, height: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 18), color: AppColors.glassBorder),
            Expanded(flex: 2, child: correctionsPanel(corrections)),
          ]),
        ),
      ]),
    );
  }

Widget triageQueuePanel(BuildContext context, List<Apple> uncertain) {
    const maxRows = 8;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(uncertain.isEmpty ? Icons.check_circle : Icons.pending_actions,
            color: uncertain.isEmpty ? AppColors.healthy : Colors.amber, size: 15),
        const SizedBox(width: 6),
        Text(
          uncertain.isEmpty ? 'Fila de Revisão · Tudo validado' : 'Fila de Revisão · ${uncertain.length} pendente${uncertain.length != 1 ? "s" : ""}',
          style: TextStyle(color: uncertain.isEmpty ? AppColors.healthy : Colors.amber, fontSize: 12.5, fontWeight: FontWeight.bold),
        ),
      ]),
      const SizedBox(height: 8),
      if (uncertain.isEmpty)
        Expanded(child: Center(child: Text('Nenhuma maçã necessita de revisão.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11))))
      else
        Expanded(
          child: ListView.builder(
            itemCount: min(uncertain.length, maxRows),
            itemBuilder: (context, i) {
              final apple = uncertain[i];
              final cond = apple.primaryCondition;
              final conf = apple.effectiveConfidence;
              final confColor = conf > 0.7 ? Colors.amber : Colors.orangeAccent;
              return InkWell(
                onTap: () => AppleCard.showAppleDetails(context, apple),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.getColorForCondition(cond), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(apple.id, style: TextStyle(color: AppColors.textPrimary, fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                    Text(AppColors.displayName(cond), style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                    const SizedBox(width: 8),
                    Text('${(conf * 100).toStringAsFixed(0)}%', style: TextStyle(color: confColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 14),
                  ]),
                ),
              );
            },
          ),
        ),
      if (uncertain.length > maxRows)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+ ${uncertain.length - maxRows} mais na fila completa', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
        ),
    ]);
  }

Widget correctionsPanel(List<CorrectionHistory> corrections) {
    const maxRows = 8;
    final sorted = [...corrections]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.history, color: Colors.purpleAccent, size: 15),
        const SizedBox(width: 6),
        Text(
          corrections.isEmpty ? 'Correções · Nenhuma' : 'Correções · ${corrections.length}',
          style: const TextStyle(color: Colors.purpleAccent, fontSize: 12.5, fontWeight: FontWeight.bold),
        ),
      ]),
      const SizedBox(height: 8),
      if (corrections.isEmpty)
        Expanded(child: Center(child: Text('Sem correções nesta sessão.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11))))
      else
        Expanded(
          child: ListView.builder(
            itemCount: min(sorted.length, maxRows),
            itemBuilder: (context, i) {
              final c = sorted[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.getColorForCondition(c.label), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(AppColors.displayName(c.label), style: TextStyle(color: AppColors.textPrimary, fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                  Text(c.correctedBy, style: TextStyle(color: AppColors.textSecondary, fontSize: 10), overflow: TextOverflow.ellipsis),
                  const SizedBox(width: 6),
                  Text(DateFormat('HH:mm').format(c.timestamp), style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ]),
              );
            },
          ),
        ),
      if (sorted.length > maxRows)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+ ${sorted.length - maxRows} mais no histórico completo', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
        ),
    ]);
  }

class BatchComparisonShowcase extends StatefulWidget {
  final Batch currentBatch;
  final List<Batch> allBatches;
  final void Function(Batch)? onBatchSelected;

  const BatchComparisonShowcase({
    Key? key,
    required this.currentBatch,
    required this.allBatches,
    this.onBatchSelected,
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
  void didUpdateWidget(covariant BatchComparisonShowcase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentBatch.id == _selectedCompareId) {
      setState(() {
        _selectedCompareId = 'media';
      });
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
          icon: Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 20),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
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
                // Reference historical or compared batch as a dashed background contour
                RadarDataSet(
                  fillColor: Colors.transparent,
                  borderColor: Colors.deepPurpleAccent.withValues(alpha: 0.75),
                  borderWidth: 1.8,
                  entryRadius: 0,
                  dataEntries: keys.map((k) => RadarEntry(value: compareM[k]!)).toList(),
                ),
                // Current batch as a glowing solid filled polygon
                RadarDataSet(
                  fillColor: Colors.cyanAccent.withValues(alpha: 0.28),
                  borderColor: Colors.cyanAccent,
                  borderWidth: 3.2,
                  entryRadius: 4.5,
                  dataEntries: keys.map((k) => RadarEntry(value: curM[k]!)).toList(),
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
              Text('Este Lote', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(width: 20),
              Container(width: 10, height: 2, decoration: const BoxDecoration(color: Colors.deepPurpleAccent)), // line dash symbol
              const SizedBox(width: 6),
              Text(compareLabel, style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
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
              Text('Scorecard Clínico', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              Text('Alvo: $compareLabel', style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
            children: [
              TableRow(children: [
                Text('Métrica', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('Atual', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('Alvo', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('Desvio', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
                  final a = _selectedCompareId == 'media' 
                      ? (widget.allBatches.fold<int>(0, (p, b) => p + b.totalApples) / (widget.allBatches.isEmpty ? 1 : widget.allBatches.length)).round()
                      : widget.allBatches.firstWhere((x) => x.id == _selectedCompareId).totalApples;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('$a', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
            final urgColor = b.urgencyScore > 0.4
                ? Colors.redAccent
                : b.urgencyScore > 0.2
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


// ── Carta de Controlo CEP (I-MR) + CUSUM ──────────────────────────────────
// Calibra X̄/UCL/LCL nos últimos lotes finalizados e aplica-os ao lote/triagem
// atual, dividido em janelas temporais. Alterna entre deteção de saltos (I-MR)
// e deteção de deriva lenta sustentada (CUSUM).

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
            // Gauge radial — pressão composta
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
  // J (Evenness de Pielou) = H / log₂(N_classes_ativas) — normalizado 0-1.
  // J alto = muitas doenças presentes em proporções similares (lote complexo).

Widget shannonDiversityIndex(Batch batch) {
    final dist = batch.healthDistribution;
    final total = batch.totalApples > 0 ? batch.totalApples : 1;
    const classes = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];
    final active = classes.where((d) => (dist[d] ?? 0) > 0).toList();

    if (active.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20), height: 340,
        child: Center(child: Text('Sem dados de distribuição', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    double H = 0.0;
    final Map<String, double> contribs = {};
    for (final d in active) {
      final p = (dist[d] ?? 0) / total;
      if (p > 0) {
        final c = -p * log(p) / log(2);
        H += c;
        contribs[d] = c;
      }
    }
    final Hmax = log(active.length) / log(2);
    final J = Hmax > 0 ? (H / Hmax).clamp(0.0, 1.0) : 0.0;

    final interpColor = J >= 0.55 ? Colors.redAccent : J >= 0.25 ? Colors.amber : AppColors.healthy;
    final interpLabel = J >= 0.55
        ? 'Lote Complexo — múltiplas doenças com pesos similares'
        : J >= 0.25
            ? 'Lote Moderado — algumas doenças relevantes coexistem'
            : 'Lote Dominado — uma doença prevalece claramente';

    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 340,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Row(children: [
            Icon(Icons.workspaces_outlined, color: Color(0xff10B981), size: 20),
            SizedBox(width: 8),
            Text('Diversidade de Doenças (Shannon)',
                style: TextStyle(color: Color(0xff10B981), fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          Tooltip(
            message: 'Índice de Shannon-Wiener\nH = −Σ pᵢ × log₂(pᵢ)\n\n'
                     'Evenness de Pielou: J = H / log₂(N_classes_ativas)\n'
                     'J = 0 → só uma doença presente\n'
                     'J = 1 → todas as classes com a mesma proporção\n\n'
                     'Quanto maior J, mais complexa e custosa a triagem:\n'
                     'cada doença exige protocolos diferentes.',
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
            ),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 15),
          ),
        ]),
        Text('Entropia de Shannon-Wiener · ${active.length} classes ativas de ${classes.length}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        // KPI row
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('H = ${H.toStringAsFixed(3)} bits',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              Text('Hmax = ${Hmax.toStringAsFixed(3)} para ${active.length} classes',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('J = ${(J * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: interpColor, fontSize: 20, fontWeight: FontWeight.bold)),
            Text('Evenness de Pielou', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
          ]),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: J, minHeight: 10,
            backgroundColor: AppColors.textSecondary.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(interpColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(interpLabel, style: TextStyle(color: interpColor, fontSize: 10, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        // Per-disease entropy contribution
        const Text('Contribuição para a entropia por classe:', style: TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 6),
        ...active.map((d) {
          final c = contribs[d] ?? 0.0;
          final frac = H > 0 ? c / H : 0.0;
          final color = AppColors.getColorForCondition(d);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(
                width: 75,
                child: Text(d, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: frac, minHeight: 8,
                    backgroundColor: color.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                child: Text('${(frac * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right),
              ),
            ]),
          );
        }),
      ]),
    );
  }

Widget floatingBatchOutbreakPopup(BuildContext context, WidgetRef ref, Batch b, BatchStats stats) {
    final diseasePT = stats.dominantAnomaly == 'Rot'
        ? 'Podridão'
        : stats.dominantAnomaly == 'Scab'
            ? 'Sarna'
            : stats.dominantAnomaly == 'Blotch'
                ? 'Sooty Blotch'
                : 'Antracnose';

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withValues(alpha: 0.08),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Risco Biológico Detetado',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lote sob risco elevado de surto de $diseasePT.',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.close, color: AppColors.textSecondary, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  ref.read(dismissedOutbreaksProvider.notifier).dismiss(b.id);
                },
                tooltip: 'Descartar este alerta',
              ),
            ],
          ),
        ),
      ),
    );
  }

Widget batchComparison(Batch current, List<Batch> allBatches) {
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
          headingTextStyle: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12),
          dataTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
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
                  if (isCurrent) Icon(Icons.arrow_right, color: AppColors.healthy, size: 16),
                  Text(b.id, style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? AppColors.healthy : AppColors.textPrimary)),
                ])),
                DataCell(Text(b.location, style: TextStyle(color: AppColors.textSecondary))),
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

  // ── Auditoria Humana (Controlo Qualidade) (fusão: fila de revisão + histórico) ────
  // Junta os 2 painéis operacionais num único card com 2 colunas — a fila
  // pendente e o registo de correções já não competem por um slot inteiro
  // cada, já que nenhum dos dois é, por si, uma visualização analítica.

List<Apple> filterApplesByTriagem(List<Apple> apples, String filter) {
    if (apples.isEmpty) return apples;
    final sorted = [...apples]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final dates = <String>{};
    for (final a in sorted) {
      dates.add('${a.timestamp.year}-${a.timestamp.month.toString().padLeft(2, '0')}-${a.timestamp.day.toString().padLeft(2, '0')}');
    }
    final limit = filter == '1t' ? 1 : 5;
    final allowed = dates.take(limit).toSet();
    return sorted.where((a) {
      final key = '${a.timestamp.year}-${a.timestamp.month.toString().padLeft(2, '0')}-${a.timestamp.day.toString().padLeft(2, '0')}';
      return allowed.contains(key);
    }).toList();
  }

Widget buildTriagemToggle(WidgetRef ref, String current) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          triBtn(ref, '1t', '1 Triagem', current),
          triBtn(ref, '5t', '5 Triagens', current),
        ],
      ),
    );
  }

Widget triBtn(WidgetRef ref, String val, String label, String current) {
    final selected = current == val;
    return GestureDetector(
      onTap: () => ref.read(batchTriagemFilterProvider.notifier).setFilter(val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceBright : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: selected ? const Color(0xff10B981) : AppColors.textSecondary,
            fontSize: 9,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ── Z-Score de Desvio Inter-Lote (Batch Drift Score) ──────────────────────
  // Compara o lote/triagem atual com μ e σ dos últimos lotes finalizados.

Widget batchPareto_unused(Batch batch) {
    final dist = batch.healthDistribution;
    final total = batch.totalApples;
    final diseases = ['Rot', 'Scab', 'Blotch', 'Anthracnose']
        .where((d) => (dist[d] ?? 0) > 0)
        .toList()
      ..sort((a, b) => (dist[b] ?? 0).compareTo(dist[a] ?? 0));

    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
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
                    'Distribuição de Anomalias (Pareto)',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Frequência absoluta por doença + curva cumulativa 80/20',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (diseases.isEmpty)
            Expanded(
              child: Center(
                child: Text('Sem anomalias neste lote',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            Expanded(
              child: Stack(
                children: [
                  BarChart(
                    BarChartData(
                      maxY: total.toDouble() > 0 ? total.toDouble() : 1.0,
                      minY: 0,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) =>
                            FlLine(color: AppColors.textSecondary.withOpacity(0.2), strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (v, _) {
                              final idx = v.toInt();
                              if (idx < 0 || idx >= diseases.length) return const SizedBox();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  diseases[idx],
                                  style: TextStyle(
                                    color: AppColors.getColorForCondition(diseases[idx]),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                            ),
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            getTitlesWidget: (v, _) {
                              final pct = total > 0 ? (v / total * 100) : 0.0;
                              return Text(
                                '${pct.toStringAsFixed(0)}%',
                                style: const TextStyle(color: Colors.cyanAccent, fontSize: 9),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      barGroups: () {
                        return List.generate(diseases.length, (i) {
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: (dist[diseases[i]] ?? 0).toDouble(),
                                color: AppColors.getColorForCondition(diseases[i]),
                                width: 18,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          );
                        });
                      }(),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 30, right: 36, bottom: 28),
                      child: LineChart(
                        LineChartData(
                          minX: -0.5,
                          maxX: diseases.length.toDouble() - 0.5,
                          minY: 0,
                          maxY: total.toDouble() > 0 ? total.toDouble() : 1.0,
                          gridData: FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: () {
                                double running = 0;
                                return List.generate(diseases.length, (i) {
                                  running += (dist[diseases[i]] ?? 0).toDouble();
                                  return FlSpot(i.toDouble(), running);
                                });
                              }(),
                              isCurved: true,
                              color: Colors.cyanAccent,
                              barWidth: 2.5,
                              dotData: const FlDotData(show: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }


  // ── Confiança por Patologia (Ridgeline / Joyplot) ─────────────────────────
  // Fusão de "Distribuição por Doença" + "Distribuição de Confiança por Doença":
  // uma crista de densidade por patologia mostra a FORMA completa da distribuição
  // de confiança CNN (não só médias/buckets) — cristas estreitas e altas = diagnóstico
  // consistente; largas ou bimodais = incerteza real nessa patologia.

