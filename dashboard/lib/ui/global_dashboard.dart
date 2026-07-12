import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';

import '../widgets/glass_card.dart';
import '../widgets/active_beacon.dart';
import '../models/models.dart';
import '../providers/dashboard_provider.dart';
import '../utils/constants.dart';
import '../widgets/skeleton_card.dart';
import '../widgets/hybrid_image.dart';
import '../services/supabase_service.dart';
import '../widgets/pulsing_kpi_card.dart';
import '../widgets/urgency_formula_card.dart';
import '../widgets/apple_card.dart';
import '../widgets/donut_chart_widget.dart';
// Fusão por tema: reutiliza os gráficos de lote (funções/classes públicas das
// libraries lote/*) dentro da dashboard unificada. Prefixo `lote` evita colisões.
// (As libraries lote/* são importadas diretamente — imports não são transitivos.)
import 'lote/lote_dashboard_part2.dart' as lote;
import 'lote/lote_charts_matrices.dart' as lote;
import 'lote/lote_timeline.dart' as lote;
import 'lote/lote_misc.dart' as lote;

part 'global/global_dashboard_part1.dart';
part 'global/global_dashboard_part2.dart';
part 'global/global_risk_scatter.dart';
part 'global/global_batch_treemap.dart';
part 'global/global_misc_widgets.dart';

String getDominantDiseaseENForBatch(Batch b) {
  final dist = b.healthDistribution;
  String dominant = 'Healthy';
  int maxVal = 0;
  for (final k in ['Rot', 'Scab', 'Blotch', 'Anthracnose']) {
    if ((dist[k] ?? 0) > maxVal) {
      maxVal = dist[k]!;
      dominant = k;
    }
  }
  return dominant;
}

String getDominantDiseasePTForBatch(Batch b) {
  final dom = getDominantDiseaseENForBatch(b);
  switch (dom) {
    case 'Rot': return 'Podridão';
    case 'Scab': return 'Sarna';
    case 'Blotch': return 'Sooty Blotch';
    case 'Anthracnose': return 'Antracnose';
    default: return 'Nenhuma';
  }
}

class GlobalDashboard extends ConsumerStatefulWidget {
  const GlobalDashboard({super.key});

  @override
  ConsumerState<GlobalDashboard> createState() => _GlobalDashboardState();
}

class _GlobalDashboardState extends ConsumerState<GlobalDashboard> {
  static const double _comparativoTripleChartHeight = 420;

  String _sortColumn = 'Lote';
  bool _sortAscending = true;

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
    final allBatches = ref.watch(filteredBatchesProvider);
    final corrections = ref.watch(correctionHistoryProvider);
    final stats = ref.watch(globalStatsProvider);
    final reviewsAsync = ref.watch(manualReviewsProvider);

    // ── Dados de lote em foco (secções de fusão por tema) ───────────────
    final availableBatches = ref.watch(availableBatchesProvider);
    final selectedBatch = ref.watch(batchProvider);
    final batchStats = ref.watch(batchStatsProvider);
    final triFilter = ref.watch(batchTriagemFilterProvider);
    final uncertain = ref.watch(uncertainApplesProvider);

    if (allBatches.isEmpty || stats == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonCard(height: 80),
            const SizedBox(height: 28),
            Row(
              children: List.generate(
                5,
                (index) => const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.0),
                    child: SkeletonCard(height: 100),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: const [
                Expanded(flex: 3, child: SkeletonCard(height: 300)),
                SizedBox(width: 16),
                Expanded(flex: 2, child: SkeletonCard(height: 300)),
              ],
            ),
          ],
        ),
      );
    }

    // Sort batches statefully
    final batches = [...allBatches];
    batches.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case 'Lote':
          cmp = a.id.compareTo(b.id);
          break;
        case 'Local':
          cmp = a.location.compareTo(b.location);
          break;
        case 'Volume':
          cmp = a.totalApples.compareTo(b.totalApples);
          break;
        case 'Aprovação':
          cmp = _bApproval(a).compareTo(_bApproval(b));
          break;
        case 'Contaminação':
          cmp = a.contaminationScore.compareTo(b.contaminationScore);
          break;
        case 'Gravidade':
          cmp = a.severityScore.compareTo(b.severityScore);
          break;
        case 'Tendência':
          cmp = a.growthRate.compareTo(b.growthRate);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    final dismissedIds = ref.watch(dismissedOutbreaksProvider);
    final isDismissed = ref.watch(outbreaksPopupDismissedProvider);
    final riskBatches = batches.where((b) {
      final dom = getDominantDiseaseENForBatch(b);
      return dom != 'Healthy' && b.urgencyScore > 0.15 && !dismissedIds.contains(b.id);
    }).toList();
    final showSystemSurge = stats.surgeAlert != 'Estável' && !dismissedIds.contains('SYSTEM_SURGE');

    // Derivados do lote em foco.
    final bool loteReady = selectedBatch != null && batchStats != null;
    final List<Apple> filteredApples =
        loteReady ? lote.filterApplesByTriagem(selectedBatch.apples, triFilter) : const <Apple>[];
    final List<CorrectionHistory> loteCorrections =
        loteReady ? corrections.where((c) => c.batchId == selectedBatch.id).toList() : const <CorrectionHistory>[];

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(ref, stats, batches),
              const SizedBox(height: 24),

          // ══════════════════ CAPÍTULO 1 · VISÃO GLOBAL ══════════════════
          // Resumo executivo — sempre global (não reage à seleção de lote).
          _chapterHeader('1', 'Visão Global', 'Estado geral da produção · sempre global', const Color(0xff10B981)),
          const SizedBox(height: 20),
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
            (stats.globalApproval * 0.4 + stats.avgConf * 0.3 + (1 - (batches.isEmpty ? 0.0 : batches.fold(0.0, (s, b) => s + b.urgencyScore) / batches.length)) * 100 * 0.3).clamp(0.0, 100.0),
            stats.dailyBatches,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 360,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: _globalDonut(stats)),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: _diseaseAreaChart(stats.dailyBatches)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildGlobalComplianceChart(stats.dailyBatches)),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _automationFunnel(batches.expand((b) => b.apples).toList(), corrections.length)),
            ],
          ),
          const SizedBox(height: 40),

          // ═════════ CAPÍTULO 2 · ANÁLISE & COMPARAÇÃO DE LOTES ═════════
          // Comparação entre lotes + seleção do "lote em foco" (driver do funil).
          _chapterHeader('2', 'Análise & Comparação de Lotes',
              'Compare lotes e padrões · escolha o lote em foco', const Color(0xffF59E0B)),
          const SizedBox(height: 16),
          // Comparação: scatter temporal de risco (1 bolha/dia, cor por lote,
          // clique para detalhe) + heatmap Lote×Patologia. Treemap e bar de
          // risco (_batchRiskComparison) desativados — código preservado.
          SizedBox(
            height: 420,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _InteractiveRiscoChart(batches: batches)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _heatmap(batches)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _globalSeverityAreaChart(batches),
          const SizedBox(height: 16),

          // ═════ BARREIRA: comparação entre lotes (M:N, acima) vs. detalhe
          // de UM lote (1:N, abaixo) ═════
          _loteGate(batches, ref),
          const SizedBox(height: 32),

          // ═════════ DETALHE DO LOTE EM FOCO (dentro do Capítulo 2) ═════════
          if (loteReady) ...[
            Align(alignment: Alignment.centerLeft, child: lote.buildTriagemToggle(ref, triFilter)),
            const SizedBox(height: 12),
            // Donut de patologias do lote (substitui a % acumulada — duplicada com o Cap 1).
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SizedBox(height: 380, child: const DonutChartWidget())),
              const SizedBox(width: 16),
              Expanded(child: lote.masterTimeline(selectedBatch)),
            ]),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: lote.eisenhowerMatrix(selectedBatch)),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: lote.phytosanitaryPressureGauge(selectedBatch)),
            ]),
            const SizedBox(height: 16),
            lote.BatchComparisonShowcase(
              currentBatch: selectedBatch,
              allBatches: availableBatches,
              onBatchSelected: (b) => ref.read(batchProvider.notifier).setBatch(b),
            ),
            const SizedBox(height: 16),
            // Confiança/CEP/Z-score do lote (movidos do Cap 3).
            lote.confidenceRidgelineByPathology(filteredApples),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: lote.ConfidenceSeverityHullPlot(apples: selectedBatch.apples)),
              const SizedBox(width: 16),
              Expanded(child: lote.cnnCostMatrixChart(selectedBatch)),
            ]),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: lote.SpcControlChart(batchId: selectedBatch.id, currentApples: filteredApples, allBatches: availableBatches),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: lote.batchDriftZScore(selectedBatch, filteredApples, availableBatches, corrections),
              ),
            ]),
            const SizedBox(height: 16),
            lote.humanTriageActivity(context, uncertain.where((a) => a.frames.isNotEmpty).toList(), loteCorrections),
          ] else
            _loteEmptyHint(),
          const SizedBox(height: 40),

          // ═════════ CAPÍTULO 3 · PERFORMANCE DA CNN ═════════
          // Só gráficos sobre o CNN + feed de produção em tempo real no fundo.
          _chapterHeader('3', 'Performance da CNN',
              'Confiança e evolução do modelo', const Color(0xff06B6D4)),
          const SizedBox(height: 16),
          _cnnEvolution(stats.dailyBatches),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _confusionMatrix(batches, corrections, reviewsAsync)),
              const SizedBox(width: 16),
              Expanded(child: _pipelineCalibrationChart(stats.dailyBatches, reviewsAsync)),
            ],
          ),
          const SizedBox(height: 28),
          _scopeLabel('Pomar · tempo real'),
          const SizedBox(height: 12),
          _productionFeed(ref),
          const SizedBox(height: 32),
        ],
          ),
        ),
        if ((riskBatches.isNotEmpty || showSystemSurge) && !isDismissed)
          Positioned(
            top: 24,
            right: 32,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 1.0, end: 0.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(400 * value, 0),
                  child: child,
                );
              },
              child: _OutbreakAlertPopup(
                riskBatches: riskBatches,
                showSystemSurge: showSystemSurge,
                onDismiss: () => ref.read(outbreaksPopupDismissedProvider.notifier).setDismissed(true),
              ),
            ),
          ),
      ],
    );
  }

  /// Sub-rótulo de âmbito dentro de uma secção temática (Pomar vs Lote).
  Widget _scopeLabel(String text) => Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(text.toUpperCase(),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
        ],
      );

  Widget _loteEmptyHint() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('Selecione um lote em foco (Capítulo 2) para ver o detalhe e a performance da CNN.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );

  /// Cabeçalho de capítulo do funil top-down (número grande + título + subtítulo).
  Widget _chapterHeader(String number, String title, String subtitle, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(number, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
            Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(child: Divider(color: color.withValues(alpha: 0.25), thickness: 1)),
      ],
    );
  }

  /// Tabela de lotes como "barreira" visual: separa a comparação M:N (acima,
  /// âmbar) do detalhe de UM lote em foco (abaixo, ciano — inclui o radar
  /// 1:N do BatchComparisonShowcase, que compara esse lote com os outros).
  Widget _loteGate(List<Batch> batches, WidgetRef ref) {
    final selected = ref.watch(batchProvider);
    const amber = Color(0xffF59E0B);
    const cyan = Colors.cyanAccent;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Faixa superior — zona de comparação entre lotes (M:N).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: amber.withOpacity(0.10),
              border: Border(bottom: BorderSide(color: amber.withOpacity(0.35), width: 1)),
            ),
            child: Row(children: [
              Icon(Icons.compare_arrows, size: 14, color: amber),
              const SizedBox(width: 8),
              Text('COMPARAÇÃO ENTRE LOTES',
                  style: TextStyle(color: amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const Spacer(),
              Text('todos × todos', style: TextStyle(color: amber.withOpacity(0.7), fontSize: 10)),
            ]),
          ),
          _table(batches, ref),
          // Faixa inferior — transição para o detalhe do lote em foco (1:N).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: cyan.withOpacity(0.08),
              border: Border(top: BorderSide(color: cyan.withOpacity(0.35), width: 1)),
            ),
            child: Row(children: [
              Icon(Icons.arrow_downward, size: 14, color: cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected != null
                      ? 'Detalhe abaixo: ${selected.id} (1 lote vs. os restantes)'
                      : 'Clique em "Focar" acima para ver o detalhe de um lote abaixo',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cyan, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// Cap 1 · Donut global saudáveis vs patologias (dados de GlobalStats).
  Widget _globalDonut(GlobalStats stats) {
    final Map<String, int> dist = {
      'Healthy': stats.totalHealthy,
      ...stats.anomalyDistribution,
    }..removeWhere((k, v) => v <= 0);
    final total = stats.totalApples;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.donut_large, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('Saudáveis vs Patologias',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                PieChart(PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 52,
                  sections: dist.entries.map((e) {
                    final color = AppColors.getColorForCondition(e.key);
                    final pct = total > 0 ? e.value / total * 100 : 0.0;
                    return PieChartSectionData(
                      color: color,
                      value: e.value.toDouble(),
                      title: pct >= 6 ? '${pct.toStringAsFixed(0)}%' : '',
                      radius: 44,
                      titleStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    );
                  }).toList(),
                )),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$total',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('maçãs', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: dist.entries.map((e) {
              return Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.getColorForCondition(e.key))),
                const SizedBox(width: 6),
                Text('${AppColors.displayName(e.key)} (${e.value})',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ]);
            }).toList(),
          ),
        ],
      ),
    );
  }

}

/// Sparkline minimalista para os KPI cards (polilinha + ponto final).
class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparkPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    double lo = values.first, hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : (hi - lo);
    final dx = size.width / (values.length - 1);
    double xOf(int i) => i * dx;
    double yOf(double v) => size.height - ((v - lo) / range) * size.height;

    final path = Path()..moveTo(xOf(0), yOf(values.first));
    for (int i = 1; i < values.length; i++) {
      path.lineTo(xOf(i), yOf(values[i]));
    }
    // Área suave sob a linha.
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    // Ponto final.
    canvas.drawCircle(Offset(xOf(values.length - 1), yOf(values.last)), 2.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values || old.color != color;
}
