import 'dart:math';
import 'dart:ui' as ui;
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
import '../widgets/skeleton_card.dart';
import 'lote/lote_dashboard_part1.dart';
import 'lote/lote_dashboard_part2.dart';
import 'lote/lote_charts_matrices.dart';
import 'lote/lote_timeline.dart';
import 'lote/lote_misc.dart';

class BatchDashboard extends ConsumerWidget {
  const BatchDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(batchProvider);
    final allBatches = ref.watch(availableBatchesProvider);
    final stats          = ref.watch(batchStatsProvider);

    if (batch == null || stats == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
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
            const SizedBox(height: 32),
            Row(
              children: const [
                Expanded(flex: 4, child: SkeletonCard(height: 300)),
                SizedBox(width: 16),
                Expanded(flex: 6, child: SkeletonCard(height: 300)),
              ],
            ),
          ],
        ),
      );
    }

    final uncertain      = ref.watch(uncertainApplesProvider);
    final allCorrections = ref.watch(correctionHistoryProvider);
    final corrections = allCorrections.where((c) => c.batchId == batch.id).toList();
    final avgConf        = ref.watch(avgConfidenceProvider);
    final triFilter      = ref.watch(batchTriagemFilterProvider);
    final filteredApples = filterApplesByTriagem(batch.apples, triFilter);

    String dominant = stats.dominantAnomaly;
    int domCount = stats.dominantAnomalyCount;
    final approvalRate = stats.approvalRate;

    // Fast navigation logic
    final currentIdx = allBatches.indexWhere((b) => b.id == batch.id);
    final prevBatch = currentIdx > 0 ? allBatches[currentIdx - 1] : null;
    final nextBatch = currentIdx != -1 && currentIdx < allBatches.length - 1 ? allBatches[currentIdx + 1] : null;

    final dismissedIds = ref.watch(dismissedOutbreaksProvider);
    final hasOutbreak = stats.dominantAnomaly != 'Healthy' && batch.urgencyScore > 0.15 && !dismissedIds.contains(batch.id);

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // NOTE: navegação Pomar↔Lote é feita pelo toggle segmentado em
          // ProductionDashboard; o antigo botão "Voltar à Visão Geral" foi
          // removido por redundância (Fase 1 — fusão de dashboards).

          // ── HEADER ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 340,
                          child: Text(
                            'Dashboard: ${batch.id}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: prevBatch == null
                              ? null
                              : () => ref.read(batchProvider.notifier).setBatch(prevBatch),
                          icon: const Icon(Icons.chevron_left),
                          color: AppColors.primary,
                          disabledColor: AppColors.textSecondary.withOpacity(0.2),
                          tooltip: prevBatch != null ? 'Lote Anterior: ${prevBatch.id}' : 'Primeiro Lote',
                        ),
                        IconButton(
                          onPressed: nextBatch == null
                              ? null
                              : () => ref.read(batchProvider.notifier).setBatch(nextBatch),
                          icon: const Icon(Icons.chevron_right),
                          color: AppColors.primary,
                          disabledColor: AppColors.textSecondary.withOpacity(0.2),
                          tooltip: nextBatch != null ? 'Próximo Lote: ${nextBatch.id}' : 'Último Lote',
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.arrow_drop_down, color: AppColors.primary),
                          tooltip: 'Selecionar Lote',
                          onSelected: (newValue) {
                            if (newValue == 'Global') {
                              ref.read(currentPageProvider.notifier).setPage('Controlo do Pomar');
                            } else {
                              final selected = allBatches.firstWhere((b) => b.id == newValue);
                              ref.read(batchProvider.notifier).setBatch(selected);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem<String>(
                              value: 'Global',
                              child: Text(
                                'Visão Geral (Global)',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ...allBatches.map((b) => PopupMenuItem<String>(
                              value: b.id,
                              child: Text(
                                b.id,
                                style: TextStyle(
                                  color: b.id == batch.id ? AppColors.primary : AppColors.textPrimary,
                                  fontWeight: b.id == batch.id ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            )),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${batch.location}  ·  ${DateFormat('dd/MM/yyyy').format(batch.date)}  ·  ${batch.totalApples} maçãs inspecionadas',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Row(
                children: [
                  headerMetric('Autonomia', '${(batch.totalApples == 0 ? 100.0 : (1 - (uncertain.length / batch.totalApples)) * 100).toStringAsFixed(1)}%', (batch.totalApples == 0 ? 100.0 : (1 - (uncertain.length / batch.totalApples)) * 100) > 90 ? AppColors.healthy : Colors.orangeAccent),
                  const SizedBox(width: 24),
                  headerMetric('Confiança IA', '${avgConf.toStringAsFixed(1)}%', Colors.cyanAccent),
                  const SizedBox(width: 24),
                  headerMetric('Revisão Manual', '${uncertain.length}', uncertain.isNotEmpty ? Colors.amber : AppColors.healthy),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── SEC 1: KPIs ────────────────────────────────────────────────
          section1Kpis(context, batch, dominant, domCount, uncertain.length),
          const SizedBox(height: 28),
          // ── GRELHA ANALÍTICA 6×2 ─────────────────────────────────────────
          Row(children: [
            Text('VISÃO GLOBAL DO LOTE',
                style: TextStyle(color: const Color(0xff10B981), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(width: 16),
            const Expanded(child: Divider(color: Color(0x0fffffff), thickness: 1)),
            const SizedBox(width: 16),
            buildTriagemToggle(ref, triFilter),
          ]),
          const SizedBox(height: 16),

          // Linha 1 · Conformidade Cumulativa + Cronograma de Qualidade
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: cumulativeCompliance(filteredApples)),
            const SizedBox(width: 16),
            Expanded(child: masterTimeline(batch)),
          ]),
          const SizedBox(height: 16),

          // Linha 2 · Faixa de Triagem Recente + Confiança por Patologia (Ridgeline)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: confidenceHeatStrip(filteredApples)),
            const SizedBox(width: 16),
            Expanded(child: confidenceRidgelineByPathology(filteredApples)),
          ]),
          const SizedBox(height: 16),

          // Linha 3 · Confiança×Severidade (Convex Hull) + Matriz de Custo CNN
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: ConfidenceSeverityHullPlot(apples: batch.apples)),
            const SizedBox(width: 16),
            Expanded(child: cnnCostMatrixChart(batch)),
          ]),
          const SizedBox(height: 16),

          // Linha 4 · Priorização de Ação + Pressão Fitossanitária
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: eisenhowerMatrix(batch)),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: phytosanitaryPressureGauge(batch)),
          ]),
          const SizedBox(height: 16),

          // Linha 5 · Comparação de Desempenho do Lote
          BatchComparisonShowcase(
            currentBatch: batch,
            allBatches: allBatches,
            onBatchSelected: (b) => ref.read(batchProvider.notifier).setBatch(b),
          ),
          const SizedBox(height: 24),

          // ── CONTROLO ESTATÍSTICO DE PROCESSO (CEP) ────────────────────────
          Row(children: [
            const Icon(Icons.show_chart, color: Colors.purpleAccent, size: 20),
            const SizedBox(width: 10),
            const Text('Controlo Estatístico de Processo (CEP)',
                style: TextStyle(color: Colors.purpleAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 16),
            Expanded(child: Divider(color: Colors.purpleAccent.withValues(alpha: 0.3), thickness: 1)),
          ]),
          const SizedBox(height: 16),
          // Linha 6 · CEP (I-MR / CUSUM) + Z-Score de Desvio Inter-Lote
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: SpcControlChart(batchId: batch.id, currentApples: filteredApples, allBatches: allBatches),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: batchDriftZScore(batch, filteredApples, allBatches, allCorrections),
            ),
          ]),
          const SizedBox(height: 16),

          // Linha 7 · Índice de Risco do Lote + OEE da Linha de Triagem Visual
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: batchRiskIndexCard(batch, filteredApples, allBatches, allCorrections),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: visualSortingOee(batch, filteredApples, allBatches, allCorrections, uncertain),
            ),
          ]),
          const SizedBox(height: 16),

          // Linha 8 · Auditoria Humana (Controlo Qualidade)
          humanTriageActivity(context, uncertain.where((a) => a.frames.isNotEmpty).toList(), corrections),
          const SizedBox(height: 16),
        ],
          ),
        ),
        if (hasOutbreak)
          Positioned(
            top: 24,
            right: 32,
            child: floatingBatchOutbreakPopup(context, ref, batch, stats),
          ),
      ],
    );
  }
}
