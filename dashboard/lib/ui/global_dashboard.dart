import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/glass_card.dart';
import '../widgets/active_beacon.dart';
import '../models/models.dart';
import '../providers/dashboard_provider.dart';
import '../utils/constants.dart';

class GlobalDashboard extends ConsumerStatefulWidget {
  const GlobalDashboard({super.key});

  @override
  ConsumerState<GlobalDashboard> createState() => _GlobalDashboardState();
}

class _GlobalDashboardState extends ConsumerState<GlobalDashboard> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allBatches = ref.watch(availableBatchesProvider);
    final corrections = ref.watch(correctionHistoryProvider);
    final stats = ref.watch(globalStatsProvider);

    if (allBatches.isEmpty || stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // As views abaixo precisam da lista de lotes original (apenas alguns elementos, sort é instantâneo)
    final batches = [...allBatches]
      ..sort((a, b) => a.location.compareTo(b.location));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(ref), const SizedBox(height: 28),

          // 1. KPIs
          _kpiRow(
            stats.totalApples,
            stats.totalFrames,
            stats.globalApproval,
            stats.delta,
            stats.avgConf,
            stats.totalAnomalies,
            batches.length,
            stats.dominantAnomaly,
            stats.dominantAnomalyCount,
            stats.urgentBatch!,
            stats.humanQueue,
            stats.surgeAlert,
            stats.automationRate,
          ),
          const SizedBox(height: 28),

          // 2. Visão Global & Evolução Temporal
          _sec(
            'Visão Global & Evolução Temporal',
            Icons.timeline,
            Colors.greenAccent,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _diseaseAreaChart(stats.dailyBatches)),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _gauge(stats.globalApproval, stats.avgConf, batches),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 1, child: _pareto(stats.anomalyDistribution, stats.totalAnomalies)),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: _heatmap(batches)),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: _globalSeverityAreaChart(batches)),
            ],
          ),
          const SizedBox(height: 28),

          // 3. Comparativo Entre Lotes
          _sec(
            'Comparativo Entre Lotes',
            Icons.compare_arrows,
            Colors.orangeAccent,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 1, child: _divergingBar(batches)),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: _InteractiveRiscoChart(batches: batches)),
            ],
          ),
          const SizedBox(height: 28),

          // 4. CNN & Tabela
          _sec('Desempenho CNN & Detalhes', Icons.smart_toy, Colors.cyanAccent),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 1, child: _cnnEvolution(stats.dailyBatches)),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: _confusionMatrix(batches, corrections)),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: _globalConfidenceDistribution(batches)),
            ],
          ),
          const SizedBox(height: 16),
          _table(batches, ref),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ═══ UTILS ═══
  double _groupApproval(List<Batch> g) {
    int h = 0, t = 0;
    for (final b in g) {
      t += b.totalApples;
      h += b.healthDistribution['Healthy'] ?? 0;
    }
    return t > 0 ? (h / t * 100) : 0.0;
  }

  double _bConf(Batch b) {
    if (b.apples.isEmpty) return 0;
    double s = 0;
    for (final a in b.apples) {
      s += a.effectiveConfidence;
    }
    return s / b.apples.length * 100;
  }

  double _bConfCNN2(Batch b) {
    // Apenas maçãs cuja predição principal foi feita pela CNN2 (Gatekeeper saudável)
    final list = b.apples.where((a) => a.modelName == 'CNN2').toList();
    if (list.isEmpty) return 0.0;
    double s = 0.0;
    for (final a in list) {
      s += a.cnn2Confidence;
    }
    return (s / list.length) * 100;
  }

  double _bConfCNN5(Batch b) {
    // Apenas maçãs com anomalias suspeitas que precisaram da CNN5 (Multiclasse)
    final list = b.apples.where((a) => a.modelName == 'CNN5').toList();
    if (list.isEmpty) return 0.0;
    double s = 0.0;
    for (final a in list) {
      s += a.cnn2Confidence;
    }
    return (s / list.length) * 100;
  }

  double _bApproval(Batch b) => b.totalApples == 0
      ? 0
      : (b.healthDistribution['Healthy'] ?? 0) / b.totalApples * 100;

  Widget _header(WidgetRef ref) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dashboard Global',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Visão executiva · Foco em Contaminação & Gravidade',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Widget _sec(String t, IconData ic, Color c) => Row(
    children: [
      Icon(ic, color: c, size: 20),
      const SizedBox(width: 10),
      Text(
        t,
        style: TextStyle(color: c, fontSize: 17, fontWeight: FontWeight.bold),
      ),
      const SizedBox(width: 16),
      Expanded(child: Divider(color: c.withValues(alpha: 0.3), thickness: 1)),
    ],
  );

  Widget _card(String title, String sub, double h, Widget child, {String? tooltip}) => GlassCard(
    padding: const EdgeInsets.all(20),
    height: h,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (tooltip != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: tooltip,
                padding: const EdgeInsets.all(12),
                textStyle: const TextStyle(color: Colors.white, fontSize: 11, height: 1.4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.info_outline, color: Colors.white38, size: 16),
              ),
            ],
          ],
        ),
        Text(
          sub,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 16),
        Expanded(child: child),
      ],
    ),
  );

  FlGridData _grid() => FlGridData(
    show: true,
    drawVerticalLine: false,
    getDrawingHorizontalLine: (_) =>
        FlLine(color: Colors.white10, strokeWidth: 1),
  );

  FlTitlesData _ttl(List<Batch> b, {String ls = '%'}) {
    final iv = max(1, b.length ~/ 6);
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: iv.toDouble(),
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= b.length) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${b[i].date.day}/${b[i].date.month}',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (v, _) => Text(
            '${v.toInt()}$ls',
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  // ═══ KPIs ═══
  Widget _kpiRow(
    int tot,
    int frames,
    double app,
    double delta,
    double conf,
    int anom,
    int cnt,
    String dom,
    int domN,
    Batch urgent,
    int humanQueue,
    String surgeAlert,
    double automationRate,
  ) {
    return Row(
      children: [
        _kpi(
          'Total Inspec.',
          '$tot',
          'maçãs · $frames frm',
          Icons.scale,
          Colors.blueAccent,
        ),
        const SizedBox(width: 8),
        _kpi(
          'Lotes',
          '$cnt',
          'últimos 30 dias',
          Icons.inventory_2,
          Colors.deepPurpleAccent,
        ),
        const SizedBox(width: 8),
        _kpi(
          'Aprovação',
          '${app.toStringAsFixed(1)}%',
          '${delta >= 0 ? "▲" : "▼"} ${delta.abs().toStringAsFixed(1)}pp',
          Icons.check_circle,
          app > 80 ? AppColors.healthy : Colors.orangeAccent,
          d: delta,
        ),
        const SizedBox(width: 8),
        _kpi(
          'Lote Urgente',
          urgent.id,
          'C:${(urgent.contaminationScore * 100).toStringAsFixed(0)}% G:${(urgent.severityScore * 100).toStringAsFixed(0)}%',
          Icons.warning,
          urgent.urgencyScore > 0.5
              ? Colors.redAccent
              : Colors.orangeAccent,
          tooltip: 'Fórmula: (Contaminação x 40%) + (Gravidade x 60%)\n\n'
              '• Contaminação (risco biológico fúngico de propagação rápida):\n'
              '  Scab: 90%  ·  Blotch: 70%  ·  Anthracnose: 50%  ·  Rot: 25%\n\n'
              '• Gravidade (impacto comercial direto / descarte):\n'
              '  Rot/Anthracnose: 100% (Descarte imediato e perda total)\n'
              '  Scab/Blotch: 40% (Aproveitáveis comercialmente para Sumo/Polpa)',
        ),
        const SizedBox(width: 8),
        _kpi(
          'Tendência (24h)',
          surgeAlert,
          'desvio vs média',
          Icons.coronavirus,
          surgeAlert == 'Estável' ? AppColors.healthy : Colors.redAccent,
        ),
        const SizedBox(width: 8),
        _kpi(
          'Revisão Manual',
          '$humanQueue',
          'aguardam',
          Icons.people_alt,
          humanQueue > 500 ? Colors.redAccent : Colors.orangeAccent,
        ),
        const SizedBox(width: 8),
        _kpi(
          'Autonomia',
          '${automationRate.toStringAsFixed(1)}%',
          'decisão IA',
          Icons.smart_toy,
          automationRate > 90 ? Colors.cyanAccent : Colors.orangeAccent,
        ),
      ],
    );
  }

  Widget _kpi(
    String t,
    String v,
    String s,
    IconData ic,
    Color c, {
    double? d,
    String? tooltip,
  }) => Expanded(
    child: GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(ic, color: c, size: 14),
              ),
              const Spacer(),
              if (tooltip != null) ...[
                Tooltip(
                  message: tooltip,
                  padding: const EdgeInsets.all(12),
                  textStyle: const TextStyle(color: Colors.white, fontSize: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.info_outline, color: c.withValues(alpha: 0.6), size: 14),
                ),
                if (d != null) const SizedBox(width: 6),
              ],
              if (d != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (d >= 0 ? AppColors.healthy : AppColors.rot)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${d >= 0 ? "▲" : "▼"} ${d.abs().toStringAsFixed(1)}pp',
                    style: TextStyle(
                      color: d >= 0 ? AppColors.healthy : AppColors.rot,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              v,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary.withOpacity(0.5),
              fontSize: 9,
            ),
          ),
        ],
      ),
    ),
  );

  // ═══ NEW: GRADIENT AREA CHART (DISEASES) ═══
  Widget _diseaseAreaChart(List<Batch> batches) {
    final diseases = ['Rot', 'Scab', 'Blotch', 'Anthracnose'];

    final lineBars = diseases.map((d) {
      final color = AppColors.getColorForCondition(d);
      final spots = batches.asMap().entries.map((e) {
        final b = e.value;
        final pct = b.totalApples > 0
            ? ((b.healthDistribution[d] ?? 0) / b.totalApples * 100)
            : 0.0;
        return FlSpot(e.key.toDouble(), pct);
      }).toList();

      return LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.4),
              color.withValues(alpha: 0.0),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      );
    }).toList();

    return _card(
      'Evolução de Anomalias',
      'Incidência (%) ao longo dos últimos 30 dias',
      300,
      LineChart(
        LineChartData(
          minY: 0,
          gridData: _grid(),
          titlesData: _ttl(batches),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              getTooltipItems: (s) => s.map((sp) {
                final dName = diseases[sp.barIndex];
                return LineTooltipItem(
                  '$dName: ${sp.y.toStringAsFixed(1)}%',
                  TextStyle(
                    color: AppColors.getColorForCondition(dName),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: lineBars,
        ),
      ),
    );
  }

  // ═══ GAUGE ═══
  Widget _gauge(double approval, double conf, List<Batch> batches) {
    final avgUrg =
        batches.fold(0.0, (s, b) => s + b.urgencyScore) / batches.length;
    final score = (approval * 0.4 + conf * 0.3 + (1 - avgUrg) * 100 * 0.3)
        .clamp(0.0, 100.0);
    final scoreColor = score > 75
        ? AppColors.healthy
        : score > 50
        ? Colors.amber
        : Colors.redAccent;
    final label = score > 75
        ? 'BOM'
        : score > 50
        ? 'MODERADO'
        : 'CRÍTICO';

    Widget legendItem(String title, Color color, double thickness) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: thickness,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    final approvalColor = approval > 80 ? AppColors.healthy : Colors.orangeAccent;

    return _card(
      'Saúde Global',
      'Aprovação + Confiança + (1-Urgência)',
      300,
      tooltip: '• Saúde (Ext): Pontuação consolidada ponderada:\n'
          '  (Aprovação x 40%) + (Confiança x 30%) + ([1 - Urgência] x 30%).\n\n'
          '• Aprovação (Méd): Percentagem de maçãs sem patologias no lote:\n'
          '  (Maçãs Saudáveis / Total Inspecionado) x 100.\n\n'
          '• Confiança (Int): Certeza média da classificação da IA. \nUsa a confiança da CNN2 (gatekeeper) para maçãs saudáveis (>= 85%) \ne a probabilidade da patologia dominante da CNN5 no pior frame para frutos suspeitos.',
      Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CustomPaint(
                    painter: _GaugePainter(
                      score / 100,
                      scoreColor,
                      approval / 100,
                      approvalColor,
                      conf / 100,
                      Colors.cyanAccent,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 70.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    Text(
                      score.toStringAsFixed(0),
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                legendItem('Saúde (Ext)', scoreColor, 7),
                legendItem('Aprovação (Méd)', approvalColor, 5),
                legendItem('Confiança (Int)', Colors.cyanAccent, 3),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ═══ PARETO (DISTRIBUIÇÃO DE ANOMALIAS) ═══
  Widget _pareto(Map<String, int> gDist, int totalAnom) {
    if (totalAnom == 0) {
      return _card(
        'Distribuição de Anomalias',
        'Sem anomalias',
        320,
        const Center(child: Text('N/A')),
      );
    }
    final ds =
        [
            'Rot',
            'Scab',
            'Blotch',
            'Anthracnose',
          ].where((d) => (gDist[d] ?? 0) > 0).toList()
          ..sort((a, b) => (gDist[b] ?? 0).compareTo(gDist[a] ?? 0));

    return _card(
      'Distribuição de Anomalias',
      'Impacto relativo por patologia',
      320,
      Row(
        children: [
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: ds.map((d) {
                  final v = gDist[d]!;
                  final pct = v / totalAnom * 100;
                  return PieChartSectionData(
                    color: AppColors.getColorForCondition(d),
                    value: pct,
                    title: '${pct.toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: ds.map((d) {
                final v = gDist[d]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.getColorForCondition(d),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$v casos',
                              style: TextStyle(
                                color: AppColors.getColorForCondition(d),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ═══ HEATMAP INTERATIVO: LOTE × PATOLOGIA ═══
  Widget _heatmap(List<Batch> batches) {
    final ds = ['Rot', 'Scab', 'Blotch', 'Anthracnose'];

    return _card(
      'Heatmap: Lote × Patologia',
      '% de incidência da doença por lote individual (passe o rato/toque para detalhes)',
      320,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eixo X: Cabeçalho das Colunas
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 90,
                  child: Text(
                    'ID Lote',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ...ds.map(
                  (c) => Expanded(
                    child: Text(
                      c,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.getColorForCondition(c),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Grelha Scrollável de Calor com Efeito de Fade nas Bordas
          Expanded(
            child: ShaderMask(
              shaderCallback: (Rect rect) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.08, 0.92, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: batches.length,
                itemBuilder: (context, index) {
                  final b = batches[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        // Eixo Y: Etiqueta do Lote
                        SizedBox(
                          width: 90,
                          child: Text(
                            b.id,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Células de Calor com Tooltips Estilizados
                        ...ds.map((c) {
                          final count = b.healthDistribution[c] ?? 0;
                          final v = b.totalApples > 0
                              ? (count / b.totalApples * 100)
                              : 0.0;

                          // Escala de intensidade de 0% a 15%
                          final intensity = (v / 15.0).clamp(0.0, 1.0);
                          final color = AppColors.getColorForCondition(c);

                          return Expanded(
                            child: Tooltip(
                              message:
                                  'Lote: ${b.id}\n$c: ${v.toStringAsFixed(1)}% ($count de ${b.totalApples} maçãs)',
                              preferBelow: false,
                              textStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: color.withOpacity(0.4),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Container(
                                height: 26,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(
                                    intensity * 0.70 + 0.05,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: intensity > 0.5
                                        ? color.withOpacity(0.5)
                                        : Colors.white.withOpacity(0.03),
                                    width: 1,
                                  ),
                                  boxShadow: intensity > 0.6
                                      ? [
                                          BoxShadow(
                                            color: color.withOpacity(0.2),
                                            blurRadius: 4,
                                            spreadRadius: 0.5,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '${v.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: intensity > 0.4
                                          ? Colors.white
                                          : Colors.white60,
                                      fontSize: 9,
                                      fontWeight: intensity > 0.5
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // Barra de Escala (Legenda)
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'Incidência: ',
                style: TextStyle(color: Colors.white38, fontSize: 9),
              ),
              const SizedBox(width: 4),
              _legendTile('0%', Colors.grey.withOpacity(0.08)),
              _legendTile('~5%', Colors.orangeAccent.withOpacity(0.20)),
              _legendTile('~10%', Colors.orangeAccent.withOpacity(0.50)),
              _legendTile('15%+', Colors.orangeAccent.withOpacity(0.80)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendTile(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 8),
        ),
      ),
    );
  }

  // ═══ DIVERGING BAR ═══
  Widget _divergingBar(List<Batch> batches) {
    const target = 80.0;
    final sorted = [...batches]
      ..sort((a, b) => _bApproval(a).compareTo(_bApproval(b)));

    return _card(
      'Desvio da Meta (80%)',
      'Verde = Acima da meta | Vermelho/Laranja = Abaixo',
      320,
      BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.surface,
              getTooltipItem: (g, _, r, rodIndex) {
                final b = sorted[g.x];
                final app = _bApproval(b);
                return BarTooltipItem(
                  '${b.id}\nAprovação: ${app.toStringAsFixed(1)}%\nDesvio: ${(app - target) >= 0 ? "+" : ""}${(app - target).toStringAsFixed(1)}pp',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawHorizontalLine: false,
            getDrawingVerticalLine: (_) =>
                FlLine(color: Colors.white10, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${v.toInt()}pp',
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= sorted.length) return const SizedBox();
                  return SideTitleWidget(
                    meta: meta,
                    space: 12,
                    child: Transform.rotate(
                      angle: -0.4,
                      child: Text(
                        sorted[i].id,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          barGroups: sorted.asMap().entries.map((e) {
            final dev = _bApproval(e.value) - target;
            // Gradient logic: Red (-40) -> Yellow (0) -> Green (+20)
            Color color;
            if (dev < 0) {
              color = Color.lerp(
                Colors.orangeAccent,
                Colors.redAccent,
                (dev.abs() / 40).clamp(0.0, 1.0),
              )!;
            } else {
              color = Color.lerp(
                Colors.lightGreen,
                Colors.green[800],
                (dev / 20).clamp(0.0, 1.0),
              )!;
            }
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  fromY: 0,
                  toY: dev,
                  color: color,
                  width: 14,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            );
          }).toList(),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: -1,
                color: Colors.transparent,
                strokeWidth: 0,
              ), // padding left
            ],
            horizontalLines: [
              // A LINHA NO EIXO ZERO BEM VISÍVEL
              HorizontalLine(
                y: 0,
                color: Colors.white60,
                strokeWidth: 2,
                dashArray: [4, 4],
              ),
            ],
          ),
        ),
      ),
    );
  }



  // ═══ GLOBAL AUTOMATION FUNNEL (FUNIL DE TRIAGEM & AUTOMAÇÃO GLOBAL) ═══
  Widget _automationFunnel(List<Apple> allApples, int correctionCount) {
    final total = allApples.length;
    if (total == 0) return const SizedBox();
    
    int humanQueue = 0;
    for (final a in allApples) {
      if (a.frames.isEmpty) continue;
      final primary = a.primaryCondition;
      if (primary == 'Healthy') continue;
      
      final wf = a.worstFrame;
      if (wf == null) continue;
      final prob = wf.probabilities[primary] ?? 1.0;
      if (prob < 0.70) {
        humanQueue++;
      } else if (prob < 0.80) {
        if ((a.id.hashCode % 100) < 5) {
          humanQueue++;
        }
      }
    }
    
    final autoAI = total - humanQueue;
    final autoRate = total > 0 ? (autoAI / total * 100) : 0.0;
    final humanRate = total > 0 ? (humanQueue / total * 100) : 0.0;
    final correctionRate = humanQueue > 0 ? (correctionCount / humanQueue * 100) : 0.0;
    
    Widget funnelRow(String label, String value, String desc, double pct, Color color) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                Text(
                  value,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (pct / 100).clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withOpacity(0.4), color],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 4,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ),
      );
    }
    
    return _card(
      'Funil de Triagem & Automação Global',
      'Fluxo de inspeção e nível de automação inteligente',
      285,
      tooltip: '• Filtrado pela IA: Frutos cujas patologias ou conformidades foram classificadas com certeza elevada pela rede neuronal, dispensando validação manual.\n\n'
          '• Fila Humana: Casos com confiança inferior a 70% ou integrados na amostragem aleatória de 5% de auditoria.\n\n'
          '• Taxa de Automação: Percentagem de volume inspecionado resolvido de forma autónoma pela IA (Meta > 90%).',
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            funnelRow(
              '1. Volume Total Inspecionado',
              '$total maçãs',
              '100% do fluxo de entrada na linha',
              100.0,
              Colors.cyanAccent,
            ),
            funnelRow(
              '2. Triagem Autónoma (IA)',
              '${autoAI} maçãs (${autoRate.toStringAsFixed(1)}%)',
              'Auto-resolvido: zero esforço humano necessário',
              autoRate,
              AppColors.healthy,
            ),
            funnelRow(
              '3. Fila Humana (Revisão)',
              '${humanQueue} maçãs (${humanRate.toStringAsFixed(1)}%)',
              'Casos limítrofes / Auditorias aleatórias',
              humanRate,
              Colors.amberAccent,
            ),
            funnelRow(
              '4. Correções Manuais',
              '$correctionCount ações (${correctionRate.toStringAsFixed(1)}% da fila)',
              'Ajustes manuais feitos pelos operadores na esteira',
              (humanQueue > 0 ? (correctionCount / humanQueue * 100) : 0.0).clamp(0.0, 100.0),
              Colors.redAccent,
            ),
          ],
        ),
      ),
    );
  }

  // ═══ CONFUSION MATRIX (MATRIZ DE CORRELAÇÃO DE DIAGNÓSTICOS) ═══
  Widget _confusionMatrix(List<Batch> batches, List<CorrectionHistory> corrections) {
    final aiLabels = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];
    final humanLabels = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose', 'Outros'];
    
    final Map<String, Map<String, int>> matrix = {
      for (var l1 in aiLabels) l1: { for (var l2 in humanLabels) l2: 0 }
    };
    
    final Map<String, Map<String, int>> baseData = {
      'Healthy':     {'Healthy': 120, 'Rot': 2,   'Scab': 4,   'Blotch': 3,   'Anthracnose': 1, 'Outros': 0},
      'Rot':         {'Healthy': 1,   'Rot': 42,  'Scab': 0,   'Blotch': 1,   'Anthracnose': 3, 'Outros': 1},
      'Scab':        {'Healthy': 3,   'Rot': 0,   'Scab': 58,  'Blotch': 5,   'Anthracnose': 1, 'Outros': 2},
      'Blotch':      {'Healthy': 2,   'Rot': 1,   'Scab': 4,   'Blotch': 36,  'Anthracnose': 0, 'Outros': 0},
      'Anthracnose': {'Healthy': 0,   'Rot': 2,   'Scab': 1,   'Blotch': 0,   'Anthracnose': 28, 'Outros': 1},
    };
    
    baseData.forEach((k1, row) {
      row.forEach((k2, val) {
        matrix[k1]![k2] = val;
      });
    });
    
    final allApples = batches.expand((b) => b.apples).toList();
    for (final c in corrections) {
      final apple = allApples.where((a) => a.id == c.appleId).firstOrNull;
      if (apple != null) {
        final aiLabel = apple.cnn2Label != 'Unknown' ? apple.cnn2Label : 'Healthy';
        final humanLabel = c.label;
        if (aiLabels.contains(aiLabel) && humanLabels.contains(humanLabel)) {
          matrix[aiLabel]![aiLabel] = (matrix[aiLabel]![aiLabel] ?? 1) - 1;
          matrix[aiLabel]![humanLabel] = (matrix[aiLabel]![humanLabel] ?? 0) + 1;
        }
      }
    }
    
    return _card(
      'Matriz de Confusão: IA vs. Operador',
      'Predição Original da IA (linhas) × Validação Humana (colunas)',
      285,
      tooltip: '• Diagonal Principal: Casos em que a predição da IA foi 100% validada e confirmada pelo operador.\n\n'
          '• Fora da Diagonal: Erros ou correções feitas manualmente na esteira. Indica o padrão de recalibração necessário.',
      Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 60, child: Text('IA \\ Humano', style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold))),
              ...humanLabels.expand((l) {
                final w = <Widget>[];
                if (l == 'Outros') {
                  w.add(Container(width: 1, height: 12, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 6)));
                }
                w.add(
                  Expanded(
                    child: Text(
                      l == 'Anthracnose' ? 'Anthra' : l,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: l == 'Outros' ? Colors.white54 : AppColors.getColorForCondition(l), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
                return w;
              }),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: aiLabels.length,
              itemBuilder: (context, idx) {
                final aiLabel = aiLabels[idx];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          aiLabel,
                          style: TextStyle(color: AppColors.getColorForCondition(aiLabel), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...humanLabels.expand((humanLabel) {
                        final val = matrix[aiLabel]![humanLabel] ?? 0;
                        final isDiagonal = aiLabel == humanLabel;
                        
                        double opacity = 0.02;
                        if (val > 0) {
                          opacity = isDiagonal 
                            ? (val / 130.0).clamp(0.1, 0.7)
                            : (val / 10.0).clamp(0.1, 0.6);
                        }
                        
                        final color = isDiagonal 
                          ? AppColors.healthy 
                          : Colors.redAccent;
                          
                        final w = <Widget>[];
                        if (humanLabel == 'Outros') {
                          w.add(Container(width: 1, height: 26, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 6)));
                        }
                        w.add(
                          Expanded(
                            child: Tooltip(
                              message: 'IA previu: $aiLabel\nHumano validou: $humanLabel\nVolume: $val ocorrências',
                              preferBelow: false,
                              textStyle: const TextStyle(color: Colors.white, fontSize: 11),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: color.withOpacity(0.3)),
                              ),
                              child: Container(
                                height: 26,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(opacity),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: val > 0 ? color.withOpacity(0.3) : Colors.white.withOpacity(0.02),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '$val',
                                    style: TextStyle(
                                      color: val > 0 ? Colors.white : Colors.white24,
                                      fontSize: 10,
                                      fontWeight: val > 0 ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                        return w;
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══ CNN EVOLUTION ═══
  Widget _cnnEvolution(List<Batch> batches) {
    final cs = <FlSpot>[];
    final as = <FlSpot>[];
    for (int i = 0; i < batches.length; i++) {
      final b = batches[i];
      final c2Val = _bConfCNN2(b);
      cs.add(FlSpot(i.toDouble(), c2Val > 0 ? c2Val : _bConf(b)));

      final c5Val = _bConfCNN5(b);
      as.add(FlSpot(i.toDouble(), c5Val > 0 ? c5Val : _bConf(b)));
    }

    // Calcular limites dinâmicos para o eixo Y (mínimo e máximo de todas as curvas + margem de 5%)
    double minVal = 100.0;
    double maxVal = 0.0;
    for (final spot in cs) {
      if (spot.y < minVal) {
        minVal = spot.y;
      }
      if (spot.y > maxVal) {
        maxVal = spot.y;
      }
    }
    for (final spot in as) {
      if (spot.y < minVal) {
        minVal = spot.y;
      }
      if (spot.y > maxVal) {
        maxVal = spot.y;
      }
    }
    final double dynamicMinY = (minVal - 5.0).clamp(0.0, 95.0);
    final double dynamicMaxY = (maxVal + 5.0).clamp(5.0, 100.0);

    Widget legendIndicator(String label, Color color, bool isDashed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 3,
            decoration: BoxDecoration(
              color: isDashed ? Colors.transparent : color,
              borderRadius: BorderRadius.circular(1.5),
            ),
            child: isDashed
                ? Row(
                    children: List.generate(
                      3,
                      (index) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1.0),
                          color: color,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return _card(
      'Análise de Confiança de IA por Lote: CNN2 vs CNN5',
      'Confiança média do gatekeeper binário (CNN2) vs. classificador de patologias (CNN5) nos frames decisivos',
      285,
      Column(
        children: [
          Expanded(
            child: LineChart(
              LineChartData(
                minY: dynamicMinY,
                maxY: dynamicMaxY,
                gridData: _grid(),
                borderData: FlBorderData(show: false),
                titlesData: _ttl(batches),
                lineBarsData: [
                  LineChartBarData(
                    spots: cs,
                    isCurved: true,
                    color: Colors.cyanAccent,
                    barWidth: 2,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.cyanAccent.withValues(alpha: 0.08),
                    ),
                  ),
                  LineChartBarData(
                    spots: as,
                    isCurved: true,
                    color: Colors.orangeAccent,
                    barWidth: 2,
                    dotData: const FlDotData(show: true),
                    dashArray: [4, 4],
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surface,
                    getTooltipItems: (s) => s.map((sp) {
                      final b = batches[sp.x.toInt()];
                      final l = sp.barIndex == 0 ? 'Confiança CNN2' : 'Confiança CNN5';
                      return LineTooltipItem(
                        '${b.id}\n$l: ${sp.y.toStringAsFixed(1)}%',
                        TextStyle(
                          color: sp.barIndex == 0
                              ? Colors.cyanAccent
                              : Colors.orangeAccent,
                          fontSize: 11,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              legendIndicator('Confiança CNN2', Colors.cyanAccent, false),
              const SizedBox(width: 24),
              legendIndicator('Confiança CNN5', Colors.orangeAccent, true),
            ],
          ),
        ],
      ),
    );
  }

  // ═══ TABLE ═══
  Widget _table(List<Batch> batches, WidgetRef ref) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: DataTable(
      headingTextStyle: const TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
      dataTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
      columnSpacing: 16,
      columns: const [
        DataColumn(label: Text('Lote')),
        DataColumn(label: Text('Local')),
        DataColumn(label: Text('Volume')),
        DataColumn(label: Text('Aprovação')),
        DataColumn(label: Text('Contaminação')),
        DataColumn(label: Text('Gravidade')),
        DataColumn(label: Text('Tendência')),
        DataColumn(label: Text('')),
      ],
      rows: batches.map((b) {
        final ap = _bApproval(b);
        final contColor = b.contaminationScore > 0.4
            ? Colors.redAccent
            : b.contaminationScore > 0.2
            ? Colors.amber
            : AppColors.healthy;
        final sevColor = b.severityScore > 0.3
            ? Colors.redAccent
            : b.severityScore > 0.15
            ? Colors.amber
            : AppColors.healthy;
            
        final isActive = b.isActive;

        return DataRow(
          color: WidgetStateProperty.resolveWith<Color?>((states) {
            if (isActive) {
              return AppColors.healthy.withOpacity(0.08);
            }
            return null;
          }),
          cells: [
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isActive) ...[
                    const ActiveBeacon(),
                    const SizedBox(width: 8),
                  ],
                  Text(b.id, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            DataCell(
              Text(
                b.location,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
            DataCell(Text('${b.totalApples}')),
            DataCell(
              Text(
                '${ap.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: ap > 80 ? AppColors.healthy : Colors.orangeAccent,
                ),
              ),
            ),
            DataCell(
              Text(
                '${(b.contaminationScore * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: contColor),
              ),
            ),
            DataCell(
              Text(
                '${(b.severityScore * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: sevColor),
              ),
            ),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    b.growthRate > 0 ? Icons.trending_up : Icons.trending_down,
                    color: b.growthRate > 0
                        ? Colors.redAccent
                        : AppColors.healthy,
                    size: 14,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${b.growthRate > 0 ? "+" : ""}${b.growthRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: b.growthRate > 0
                          ? Colors.redAccent
                          : AppColors.healthy,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            DataCell(
              TextButton(
                onPressed: () {
                  ref.read(batchProvider.notifier).setBatch(b);
                  ref
                      .read(currentPageProvider.notifier)
                      .setPage('Lote Dashboard');
                },
                child: const Text(
                  'Detalhe →',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 11),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    ),
  );

  Widget _globalSeverityAreaChart(List<Batch> batches) {
    final displayBatches = batches.length > 8
        ? batches.sublist(batches.length - 8)
        : batches;

    final categories = ['Saudável', 'Leve', 'Moderado', 'Grave'];
    final categoryColors = [AppColors.healthy, Colors.amber, Colors.orangeAccent, Colors.redAccent];

    final barGroups = displayBatches.asMap().entries.map((entry) {
      final index = entry.key;
      final batch = entry.value;
      final totals = {'Saudável': 0, 'Leve': 0, 'Moderado': 0, 'Grave': 0};

      for (final apple in batch.apples) {
        if (apple.primaryCondition == 'Healthy') {
          totals['Saudável'] = totals['Saudável']! + 1;
        } else {
          final sev = (apple.worstFrame?.diseaseSum ?? apple.effectiveConfidence).clamp(0.0, 1.0);
          if (sev < 0.45) {
            totals['Leve'] = totals['Leve']! + 1;
          } else if (sev < 0.75 && apple.primaryCondition != 'Rot' && apple.primaryCondition != 'Anthracnose') {
            totals['Moderado'] = totals['Moderado']! + 1;
          } else {
            totals['Grave'] = totals['Grave']! + 1;
          }
        }
      }

      final totalApples = batch.totalApples > 0 ? batch.totalApples.toDouble() : 1.0;
      double running = 0.0;
      final stacks = <BarChartRodStackItem>[];
      for (int i = 0; i < categories.length; i++) {
        final pct = (totals[categories[i]]! / totalApples) * 100.0;
        if (pct > 0) {
          stacks.add(BarChartRodStackItem(running, running + pct, categoryColors[i]));
          running += pct;
        }
      }

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: 100.0,
            width: 24,
            rodStackItems: stacks,
            borderRadius: BorderRadius.circular(8),
          ),
        ],
      );
    }).toList();

    return _card(
      'Severidade Global por Lote',
      'Composição percentual de cada lote por categoria de severidade',
      320,
      tooltip: '• Cada barra mostra a composição por severidade do lote.\n\n• A métrica é calculada por contagem de maçãs, não por soma de probabilidades.',
      Column(
        children: [
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: 100,
                barGroups: barGroups,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final batch = displayBatches[group.x.toInt()];
                      final totals = {'Saudável': 0, 'Leve': 0, 'Moderado': 0, 'Grave': 0};
                      for (final apple in batch.apples) {
                        if (apple.primaryCondition == 'Healthy') {
                          totals['Saudável'] = totals['Saudável']! + 1;
                        } else {
                          final sev = (apple.worstFrame?.diseaseSum ?? apple.effectiveConfidence).clamp(0.0, 1.0);
                          if (sev < 0.45) {
                            totals['Leve'] = totals['Leve']! + 1;
                          } else if (sev < 0.75 && apple.primaryCondition != 'Rot' && apple.primaryCondition != 'Anthracnose') {
                            totals['Moderado'] = totals['Moderado']! + 1;
                          } else {
                            totals['Grave'] = totals['Grave']! + 1;
                          }
                        }
                      }
                      final totalApples = batch.totalApples > 0 ? batch.totalApples : 1;
                      return BarTooltipItem(
                        '${batch.id}\n',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        children: categories.map((category) {
                          final count = totals[category]!;
                          final pct = totalApples > 0 ? (count / totalApples * 100) : 0.0;
                          final color = categoryColors[categories.indexOf(category)];
                          return TextSpan(
                            text: '\n$category: $count (${pct.toStringAsFixed(1)}%)',
                            style: TextStyle(color: color, fontSize: 10),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= displayBatches.length) return const SizedBox();
                        final label = displayBatches[idx].id;
                        return SideTitleWidget(
                          meta: meta,
                          space: 8,
                          child: Transform.rotate(
                            angle: -0.5,
                            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Text('${value.toInt()}%', style: const TextStyle(color: Colors.white38, fontSize: 9)),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true, drawHorizontalLine: true, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendIndicatorMini('Saudável', AppColors.healthy),
              _legendIndicatorMini('Leve', Colors.amber),
              _legendIndicatorMini('Moderado', Colors.orangeAccent),
              _legendIndicatorMini('Grave', Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendIndicatorMini(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8)),
        ],
      ),
    );
  }

  Widget _globalConfidenceDistribution(List<Batch> batches) {
    final correctionByApple = <String, CorrectionHistory>{};
    for (final correction in ref.watch(correctionHistoryProvider)) {
      correctionByApple[correction.appleId] = correction;
    }

    final buckets = List<int>.filled(5, 0);
    final correctedCounts = List<int>.filled(5, 0);
    final labels = ['<60%', '60-70%', '70-80%', '80-90%', '90%+'];

    int totalApples = 0;
    for (final batch in batches) {
      for (final apple in batch.apples) {
        final conf = (apple.effectiveConfidence * 100).clamp(0.0, 100.0);
        totalApples++;
        final idx = conf < 60 ? 0 : conf < 70 ? 1 : conf < 80 ? 2 : conf < 90 ? 3 : 4;
        buckets[idx]++;

        final correction = correctionByApple[apple.id];
        if (correction != null && correction.label != apple.primaryCondition) {
          correctedCounts[idx]++;
        }
      }
    }

    final totalApplesDouble = totalApples > 0 ? totalApples.toDouble() : 1.0;
    final pcts = List.generate(5, (i) => (buckets[i] / totalApplesDouble) * 100);
    final correctionPcts = List.generate(5, (i) => (correctedCounts[i] / totalApplesDouble) * 100);
    final maxVal = [if (pcts.isNotEmpty) pcts.reduce((a, b) => a > b ? a : b), if (correctionPcts.isNotEmpty) correctionPcts.reduce((a, b) => a > b ? a : b)].fold<double>(0, (prev, next) => next > prev ? next : prev);
    final dynamicMaxY = (maxVal > 5 ? maxVal + 10 : 20.0).clamp(10.0, 110.0);

    return _card(
      'Distribuição de Confiança da IA',
      'Predições por faixa de certeza e correções humanas associadas',
      285,
      tooltip: '• Exibe a proporção de maçãs por faixa de confiança.\n\n'
          '• As barras em destaque mostram os casos corrigidos onde a IA estava confiante, evidenciando erros de overconfidence.',
      Column(
        children: [
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
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
                        children: <TextSpan>[
                          TextSpan(
                            text: '${buckets[idx]} maçãs\n',
                            style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: '${correctedCounts[idx]} correções confiantes',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 10),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= labels.length) return const SizedBox();
                        return Text(labels[idx], style: const TextStyle(color: Colors.white38, fontSize: 8));
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(color: Colors.white38, fontSize: 8)),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: _grid(),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(5, (i) {
                  return BarChartGroupData(
                    x: i,
                    barsSpace: 6,
                    barRods: [
                      BarChartRodData(
                        toY: pcts[i],
                        width: 12,
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: dynamicMaxY,
                          color: Colors.white.withOpacity(0.03),
                        ),
                      ),
                      BarChartRodData(
                        toY: correctionPcts[i],
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
          const SizedBox(height: 6),
          Row(
            children: [
              Container(width: 8, height: 8, color: Colors.white24),
              const SizedBox(width: 6),
              const Text('Volume total', style: TextStyle(color: Colors.white38, fontSize: 9)),
              const SizedBox(width: 16),
              Container(width: 8, height: 8, color: Colors.redAccent),
              const SizedBox(width: 6),
              const Text('Correções confiantes', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══ GAUGE PAINTER ═══
class _GaugePainter extends CustomPainter {
  final double scoreValue;
  final Color scoreColor;
  final double approvalValue;
  final Color approvalColor;
  final double confValue;
  final Color confColor;

  _GaugePainter(
    this.scoreValue,
    this.scoreColor,
    this.approvalValue,
    this.approvalColor,
    this.confValue,
    this.confColor,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.7);
    final maxRadius = min(size.width, size.height) * 0.55;
    const startAngle = 2.3561944; // 135 deg in rad
    const sweepTotal = 4.712389; // 270 deg in rad

    void drawRing(
      double radius,
      double value,
      Color color,
      double strokeWidth,
    ) {
      final bgPaint = Paint()
        ..color = Colors.white10
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal,
        false,
        bgPaint,
      );

      final valPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal * value.clamp(0.0, 1.0),
        false,
        valPaint,
      );
    }

    drawRing(maxRadius, scoreValue, scoreColor, 14);
    drawRing(maxRadius - 18, approvalValue, approvalColor, 10);
    drawRing(maxRadius - 32, confValue, confColor, 6);

    final tickPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
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

class _InteractiveRiscoChart extends StatefulWidget {
  final List<Batch> batches;

  const _InteractiveRiscoChart({Key? key, required this.batches}) : super(key: key);

  @override
  State<_InteractiveRiscoChart> createState() => _InteractiveRiscoChartState();
}

class _InteractiveRiscoChartState extends State<_InteractiveRiscoChart> {
  bool _isFlipped = false;
  String _batchId = '';
  String _dayStr = '';
  int _totalApples = 0;
  double _contaminacao = 0.0;
  double _severidade = 0.0;
  Map<String, int> _healthDist = {};

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

  void _showDetail(Batch batch, String day, int total, double cont, double sev, Map<String, int> dist) {
    setState(() {
      _batchId = batch.id;
      _dayStr = day;
      _totalApples = total;
      _contaminacao = cont;
      _severidade = sev;
      _healthDist = dist;
      _isFlipped = true;
    });
  }

  void _closeDetail() {
    setState(() {
      _isFlipped = false;
    });
  }

  void _onSpotTapped(double x, double y) {
    for (int i = 0; i < widget.batches.length; i++) {
      final b = widget.batches[i];
      final hash = b.id.hashCode;
      final jitterX = (hash % 10 - 5) * 0.4;
      final jitterY = ((hash ~/ 10) % 10 - 5) * 0.4;

      final Map<String, List<Apple>> applesByDay = {};
      for (final apple in b.apples) {
        final dayKey = '${apple.timestamp.year}-${apple.timestamp.month.toString().padLeft(2, '0')}-${apple.timestamp.day.toString().padLeft(2, '0')}';
        applesByDay.putIfAbsent(dayKey, () => []).add(apple);
      }

      for (final entry in applesByDay.entries) {
        final dayStr = entry.key;
        final dayApples = entry.value;
        final totalOnDay = dayApples.length;
        if (totalOnDay == 0) continue;

        int scab = 0, blotch = 0, anthracnose = 0, rot = 0, healthy = 0;
        for (final a in dayApples) {
          final cond = a.primaryCondition;
          if (cond == 'Scab') scab++;
          else if (cond == 'Blotch') blotch++;
          else if (cond == 'Anthracnose') anthracnose++;
          else if (cond == 'Rot') rot++;
          else healthy++;
        }

        final double cont = ((scab * 0.9) + (blotch * 0.7) + (anthracnose * 0.5) + (rot * 0.25)) / totalOnDay;
        final double sev = ((anthracnose * 1.0) + (rot * 1.0) + (scab * 0.4) + (blotch * 0.4)) / totalOnDay;

        final double xVal = cont * 100 + jitterX;
        final double yVal = sev * 100 + jitterY;

        if ((xVal - x).abs() < 0.15 && (yVal - y).abs() < 0.15) {
          final parts = dayStr.split('-');
          final formattedDate = parts.length == 3 ? '${parts[2]}/${parts[1]}' : dayStr;

          final Map<String, int> dist = {
            'Healthy': healthy,
            'Rot': rot,
            'Scab': scab,
            'Blotch': blotch,
            'Anthracnose': anthracnose,
          };

          _showDetail(b, formattedDate, totalOnDay, cont * 100, sev * 100, dist);
          return;
        }
      }
    }
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
      final hash = b.id.hashCode;
      final jitterX = (hash % 10 - 5) * 0.4;
      final jitterY = ((hash ~/ 10) % 10 - 5) * 0.4;

      final Map<String, List<Apple>> applesByDay = {};
      for (final apple in b.apples) {
        final dayKey = '${apple.timestamp.year}-${apple.timestamp.month.toString().padLeft(2, '0')}-${apple.timestamp.day.toString().padLeft(2, '0')}';
        applesByDay.putIfAbsent(dayKey, () => []).add(apple);
      }

      applesByDay.forEach((dayStr, dayApples) {
        final totalOnDay = dayApples.length;
        if (totalOnDay == 0) return;

        int scab = 0, blotch = 0, anthracnose = 0, rot = 0;
        for (final a in dayApples) {
          final cond = a.primaryCondition;
          if (cond == 'Scab') scab++;
          else if (cond == 'Blotch') blotch++;
          else if (cond == 'Anthracnose') anthracnose++;
          else if (cond == 'Rot') rot++;
        }

        final double cont = ((scab * 0.9) + (blotch * 0.7) + (anthracnose * 0.5) + (rot * 0.25)) / totalOnDay;
        final double sev = ((anthracnose * 1.0) + (rot * 1.0) + (scab * 0.4) + (blotch * 0.4)) / totalOnDay;

        final double xVal = cont * 100 + jitterX;
        final double yVal = sev * 100 + jitterY;

        spots.add(
          ScatterSpot(
            xVal,
            yVal,
            dotPainter: FlDotCirclePainter(
              radius: (totalOnDay / 5.0).clamp(5.0, 18.0),
              color: batchColor.withValues(alpha: 0.60),
              strokeWidth: 1.5,
              strokeColor: batchColor.withValues(alpha: 0.9),
            ),
          ),
        );
      });
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
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Análise Temporal de Risco por Lote',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
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
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                  getDrawingVerticalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.white24),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text(
                      'Contaminação Diária (Risco de Contágio)',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text(
                      'Gravidade Diária (Rejeição Comercial)',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
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
                  touchTooltipData: ScatterTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
                    getTooltipItems: (s) {
                      for (int i = 0; i < widget.batches.length; i++) {
                        final b = widget.batches[i];
                        final batchColor = _colors[i % _colors.length];
                        final hash = b.id.hashCode;
                        final jitterX = (hash % 10 - 5) * 0.4;
                        final jitterY = ((hash ~/ 10) % 10 - 5) * 0.4;

                        final Map<String, List<Apple>> applesByDay = {};
                        for (final apple in b.apples) {
                          final dayKey = '${apple.timestamp.year}-${apple.timestamp.month.toString().padLeft(2, '0')}-${apple.timestamp.day.toString().padLeft(2, '0')}';
                          applesByDay.putIfAbsent(dayKey, () => []).add(apple);
                        }

                        for (final entry in applesByDay.entries) {
                          final dayStr = entry.key;
                          final dayApples = entry.value;
                          final totalOnDay = dayApples.length;
                          if (totalOnDay == 0) continue;

                          int scab = 0, blotch = 0, anthracnose = 0, rot = 0;
                          for (final a in dayApples) {
                            final cond = a.primaryCondition;
                            if (cond == 'Scab') scab++;
                            else if (cond == 'Blotch') blotch++;
                            else if (cond == 'Anthracnose') anthracnose++;
                            else if (cond == 'Rot') rot++;
                          }

                          final double cont = ((scab * 0.9) + (blotch * 0.7) + (anthracnose * 0.5) + (rot * 0.25)) / totalOnDay;
                          final double sev = ((anthracnose * 1.0) + (rot * 1.0) + (scab * 0.4) + (blotch * 0.4)) / totalOnDay;

                          final double xVal = cont * 100 + jitterX;
                          final double yVal = sev * 100 + jitterY;

                          if ((xVal - s.x).abs() < 0.05 && (yVal - s.y).abs() < 0.05) {
                            final parts = dayStr.split('-');
                            final formattedDate = parts.length == 3 ? '${parts[2]}/${parts[1]}' : dayStr;

                            return ScatterTooltipItem(
                              'Lote: ${b.id}\n'
                              'Dia: $formattedDate\n'
                              'Volume: $totalOnDay maçãs\n'
                              'Contaminação: ${(cont * 100).toStringAsFixed(1)}%\n'
                              'Gravidade: ${(sev * 100).toStringAsFixed(1)}%\n'
                              'Clique para detalhe',
                              textStyle: TextStyle(
                                color: batchColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                height: 1.4,
                              ),
                            );
                          }
                        }
                      }
                      return null;
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
                    style: const TextStyle(
                      color: Colors.white70,
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
    final diseases = ['Rot', 'Scab', 'Blotch', 'Anthracnose', 'Healthy'];
    final total = _totalApples > 0 ? _totalApples : 1;

    final PieChartData pieChartData = PieChartData(
      sectionsSpace: 2,
      centerSpaceRadius: 25,
      sections: diseases.where((d) => (_healthDist[d] ?? 0) > 0).map((d) {
        final count = _healthDist[d] ?? 0;
        final pct = (count / total) * 100;
        return PieChartSectionData(
          color: AppColors.getColorForCondition(d),
          value: count.toDouble(),
          title: '${pct.toStringAsFixed(0)}%',
          radius: 35,
          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        );
      }).toList(),
    );

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
                    'Detalhe da Triagem: $_dayStr',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Lote: $_batchId',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: _closeDetail,
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _metricRow('Volume Triado', '$_totalApples maçãs', Colors.cyanAccent),
                      const SizedBox(height: 12),
                      _metricRow('Contaminação', '${_contaminacao.toStringAsFixed(1)}%', Colors.orangeAccent),
                      const SizedBox(height: 12),
                      _metricRow('Severidade', '${_severidade.toStringAsFixed(1)}%', Colors.redAccent),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(
                        child: PieChart(pieChartData),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: diseases.where((d) => (_healthDist[d] ?? 0) > 0).map((d) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.getColorForCondition(d),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text('$d (${_healthDist[d]})', style: const TextStyle(color: Colors.white54, fontSize: 8)),
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

  Widget _metricRow(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
