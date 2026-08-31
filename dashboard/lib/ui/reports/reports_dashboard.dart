import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/mappers/bi_adapters.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bi_charts_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../utils/constants.dart';
import '../../services/pdf_service.dart';
import 'package:printing/printing.dart';

// Barra, tabelas e secções do relatório movidas para part files.
part 'reports_toolbar.dart';
part 'reports_tables.dart';
part 'reports_sections.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RELATÓRIO DE ESTADO DO POMAR
// Documento formal, orientado a tabelas de dados (sem gráficos, sem prosa
// gerada), que consolida a informação de toda a dashboard (KPIs globais,
// distribuição de patologias, lotes, pipeline CNN, foco no lote selecionado
// e estado do equipamento). As secções aparecem/desaparecem consoante o
// estado real dos dados. O mesmo modelo (ReportData) alimenta o ecrã e o PDF.
// ═══════════════════════════════════════════════════════════════════════════

// Planos de ação por patologia (guia de tratamento pós-colheita/agronómico).
const Map<String, String> _diseaseActions = {
  'Rot':
      'Isolar o lote, higienizar caixas de colheita e manter armazenamento rigoroso a 0.5 - 1.5 °C para abrandar a propagação de esporos.',
  'Scab':
      'Aplicar pulverizações de Cálcio e Silício para fortalecer a epiderme em futuras colheitas; arejar ramos (poda) e remover folhas caídas.',
  'Blotch':
      'Fator crítico de humidade. Garantir secagem rápida pós-lavagem, reduzir a humidade relativa da câmara e forçar ventilação.',
  'Anthracnose':
      'Foco fúngico ativo. Higienizar as linhas de triagem e planear tratamentos preventivos com cobre no pomar de origem.',
};
const Map<String, String> _diseaseCitations = {
  'Rot': 'UC Davis Postharvest Technology Center & WSU Tree Fruit Research.',
  'Scab': 'Cornell University (CALS) e Penn State Extension.',
  'Blotch': 'Diretrizes FAO e Penn State Extension.',
  'Anthracnose': 'Pacific Northwest Plant Disease Management Handbook (OSU).',
};

class ReportsView extends ConsumerWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(filteredBatchesProvider);
    final stats = ref.watch(globalStatsProvider);

    if (batches.isEmpty || stats == null) {
      return _emptyState();
    }

    final data = _assemble(ref, batches, stats);
    int sectionCounter = 1;

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          _toolbar(context, ref, data),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _documentHeader(data),
                      const SizedBox(height: 20),
                      _CollapsibleSection(
                        title: '${sectionCounter++}. Resumo Quantitativo',
                        child: _summaryTable(data),
                      ),
                      const SizedBox(height: 22),
                      _CollapsibleSection(
                        title: '${sectionCounter++}. Distribuição por Patologia',
                        child: _distributionTable(data),
                      ),
                      const SizedBox(height: 22),
                      _CollapsibleSection(
                        title: '${sectionCounter++}. Detalhe por Lote',
                        child: _batchTable(data),
                      ),
                      const SizedBox(height: 22),
                      _CollapsibleSection(
                        title: '${sectionCounter++}. Desempenho da Visão Computacional',
                        child: _cnnTable(data),
                      ),
                      if (data.economic != null && data.economic!.hasData) ...[
                        const SizedBox(height: 22),
                        _CollapsibleSection(
                          title: '${sectionCounter++}. Valor Económico da Colheita',
                          child: _economicSection(data.economic!),
                        ),
                      ],
                      if (data.focus != null) ...[
                        const SizedBox(height: 22),
                        _CollapsibleSection(
                          title: '${sectionCounter++}. Lote em Foco: ${data.focus!.id}',
                          child: _focusTables(data.focus!),
                        ),
                      ],
                      if (data.iot != null) ...[
                        const SizedBox(height: 22),
                        _CollapsibleSection(
                          title: '${sectionCounter++}. Equipamento de Captura',
                          child: _iotTable(data.iot!),
                        ),
                      ],
                      const SizedBox(height: 22),
                      _CollapsibleSection(
                        title: '${sectionCounter++}. Observações e Ações Recomendadas',
                        child: _recommendationsTable(data),
                      ),
                      const SizedBox(height: 28),
                      _reportFooter(data),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ASSEMBLER, providers → ReportData (partilhado entre ecrã e PDF)
  // ─────────────────────────────────────────────────────────────────────────
  ReportData _assemble(WidgetRef ref, List<Batch> batches, GlobalStats stats) {
    final user = ref.watch(authProvider);
    final range = ref.watch(dateRangeFilterProvider);
    final currentBatch = ref.watch(batchProvider);
    final iotHb = ref.watch(raspberryHeartbeatProvider).value;
    // Fila global de revisão (mesma fonte da §1/humanQueue), antes usava-se
    // uncertainApplesProvider, que só cobre o lote em foco, e o PDF do pomar
    // completo mostrava dois números contraditórios para a mesma coisa.
    final dbPending = ref.watch(dbPendingReviewProvider);

    final periodLabel = range == '7d' ? 'Últimos 7 dias' : 'Últimos 30 dias';
    final generatedBy = user?.username.toUpperCase() ?? 'SISTEMA';

    final avgUrg = batches.isEmpty ? 0.0 : batches.fold(0.0, (s, b) => s + b.urgencyScore) / batches.length;
    final healthScore = (stats.globalApproval * 0.4 + stats.avgConf * 0.3 + (1 - avgUrg) * 100 * 0.3).clamp(0.0, 100.0);
    final statusLabel = _statusLabel(healthScore);

    final batchRisks = batches.map((b) {
      final dist = b.healthDistribution;
      String dom = 'Nenhuma';
      int domN = 0;
      dist.forEach((k, v) {
        if (k != 'Healthy' && v > domN) {
          domN = v;
          dom = k;
        }
      });
      final healthy = dist['Healthy'] ?? 0;
      return BatchRiskRow(
        id: b.id,
        location: b.location,
        dominant: dom,
        total: b.totalApples,
        healthy: healthy,
        approval: b.totalApples > 0 ? healthy / b.totalApples * 100 : 0.0,
        contamination: b.contaminationScore,
        severity: b.severityScore,
        urgency: b.urgencyScore,
      );
    }).toList();

    final allApples = batches.expand((b) => b.apples).toList();
    int c2Final = 0, c5Final = 0, otherFinal = 0;
    int c2TotalEvaluated = 0;
    double c2Sum = 0, c5Sum = 0;
    int c2Healthy = 0, c5Healthy = 0;
    for (final a in allApples) {
      // O CNN2 gatekeeper avalia sempre todas as maçãs inicialmente
      c2TotalEvaluated++;
      c2Sum += a.cnn2Confidence;

      switch (a.modelName) {
        case 'CNN2':
          c2Final++;
          if (a.primaryCondition == 'Healthy') c2Healthy++;
          break;
        case 'CNN5':
          c5Final++;
          c5Sum += a.effectiveConfidence;
          if (a.primaryCondition == 'Healthy') c5Healthy++;
          break;
        default:
          otherFinal++;
      }
    }
    final cnn = CnnSummary(
      cnn2Count: c2Final,
      cnn5Count: c5Final,
      otherCount: otherFinal,
      cnn2AvgConf: c2TotalEvaluated > 0 ? c2Sum / c2TotalEvaluated * 100 : 0,
      cnn5AvgConf: c5Final > 0 ? c5Sum / c5Final * 100 : 0,
      uncertainCount: dbPending.length,
      cnn2HealthyCount: c2Healthy,
      cnn5HealthyCount: c5Healthy,
    );

    BatchFocus? focus;
    if (currentBatch != null) {
      final dist = currentBatch.healthDistribution;
      String dom = 'Nenhuma';
      int domN = 0;
      dist.forEach((k, v) {
        if (k != 'Healthy' && v > domN) {
          domN = v;
          dom = k;
        }
      });
      final healthy = dist['Healthy'] ?? 0;
      final pool = [...currentBatch.apples];
      pool.shuffle(math.Random()); // Baralha para garantir amostras ao calhas em cada geração
      final diverseWorst = <Apple>[];

      // 1. One Healthy (High confidence)
      final healthyApples = pool.where((a) => a.primaryCondition == 'Healthy').toList();
      if (healthyApples.isNotEmpty) {
        diverseWorst.add(healthyApples.first);
        pool.remove(healthyApples.first);
      }
      
      // 2. One Rot
      final rot = pool.where((a) => a.primaryCondition == 'Rot').toList();
      if (rot.isNotEmpty) {
        diverseWorst.add(rot.first);
        pool.remove(rot.first);
      }
      
      // 3. One other pathology (Scab, Blotch, Anthracnose)
      final other = pool.where((a) => !['Healthy', 'Rot'].contains(a.primaryCondition)).toList();
      if (other.isNotEmpty) {
        diverseWorst.add(other.first);
        pool.remove(other.first);
      }
      
      // 4. One with mid/lower confidence (~75-95%)
      final midConf = pool.where((a) => a.effectiveConfidence >= 0.70 && a.effectiveConfidence <= 0.95).toList();
      if (midConf.isNotEmpty) {
        diverseWorst.add(midConf.first);
        pool.remove(midConf.first);
      }
      
      // 5. Fill the rest up to 5 completely at random
      for (final a in pool) {
        if (diverseWorst.length >= 5) break;
        diverseWorst.add(a);
      }
      
      final worst = diverseWorst.map((a) => TopApple(id: a.id, condition: a.primaryCondition, confidence: a.effectiveConfidence)).toList();
      final avgConf = currentBatch.apples.isEmpty
          ? 0.0
          : currentBatch.apples.fold(0.0, (s, a) => s + a.effectiveConfidence) / currentBatch.apples.length * 100;
      focus = BatchFocus(
        id: currentBatch.id,
        location: currentBatch.location,
        dominant: dom,
        total: currentBatch.totalApples,
        healthy: healthy,
        approval: currentBatch.totalApples > 0 ? healthy / currentBatch.totalApples * 100 : 0.0,
        urgency: currentBatch.urgencyScore,
        avgConf: avgConf,
        distribution: dist,
        worst: worst,
      );
    }

    IotSummary? iot;
    if (iotHb != null && iotHb.mode != 'offline' && iotHb.timestamp.millisecondsSinceEpoch > 0) {
      iot = IotSummary(
        online: iotHb.isOnline,
        mode: iotHb.mode,
        cpuTemp: iotHb.cpuTemp,
        cameraFps: iotHb.cameraFps,
        lastBlur: iotHb.lastBlurScore,
        inferenceCount: iotHb.inferenceCount,
        blurWarning: iotHb.blurWarning,
        uptime: iotHb.uptimeDisplay,
      );
    }

    // Detalhe CNN (bandas de decisão + gatekeeper) e secção económica: os
    // mesmos payloads memoizados que alimentam os gráficos do Cap.2/Cap.3.
    final bi = ref.watch(biChartsProvider);

    final u = bi.uncertainty;
    final gk = bi.gatekeeper;
    final cnnDetail = CnnDecisionDetail(
      bandAccept: u.bandAccept,
      bandTriage: u.bandTriage,
      bandAutoOthers: u.bandAutoOthers,
      routedTotal: u.routedTotal,
      acceptThresholdPct: u.top1Threshold * 100,
      cnn2Healthy: gk.totalCnn2Healthy,
      cnn5Healthy: gk.totalCnn5Healthy,
      cnn5Disease: gk.totalCnn5Disease,
      avgDiseaseConfPct: gk.avgDiseaseConfidence * 100,
    );

    // Mapeamento unificado em 4 classes (a dashboard mantém os seus 2
    // mapeamentos; aqui Descarte = countTotal menos as 3 classes com valor,
    // ou seja Rot/Anthracnose/outros). BiAdapters.harvestValue é a fonte
    // única do mapeamento e dos preços; chamado por lote com [b] para as
    // linhas por lote sem duplicar a regra.
    EconomicSummary? economic;
    final h = bi.harvest;
    if (h.countTotal > 0) {
      final descCount = h.countTotal - h.countA - h.countB - h.countC;
      double pctOf(int c) => c / h.countTotal * 100;
      double precoUn(double valor, int count, double fallback) =>
          count > 0 ? valor / count : fallback;

      final sortedBatches = [...batches]..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));
      final perBatch = sortedBatches.take(15).map((b) {
        final hb = BiAdapters.harvestValue([b]);
        final descB = hb.countTotal - hb.countA - hb.countB - hb.countC;
        double pctB(int c) => hb.countTotal > 0 ? c / hb.countTotal * 100 : 0;
        return BatchCommercialRow(
          location: b.location,
          total: hb.countTotal,
          pctI: pctB(hb.countA),
          pctII: pctB(hb.countB),
          pctInd: pctB(hb.countC),
          pctDesc: pctB(descB),
        );
      }).toList();

      economic = EconomicSummary(
        valorTotal: h.valorTotal,
        capacityValue: h.capacityValue,
        metaValue: h.metaValue,
        classes: [
          EconomicClassRow(label: 'Classe I (Premium)', count: h.countA, pct: pctOf(h.countA), precoUn: precoUn(h.valorA, h.countA, 0.60), valor: h.valorA),
          EconomicClassRow(label: 'Classe II (Segunda escolha)', count: h.countB, pct: pctOf(h.countB), precoUn: precoUn(h.valorB, h.countB, 0.40), valor: h.valorB),
          EconomicClassRow(label: 'Indústria (Transformação)', count: h.countC, pct: pctOf(h.countC), precoUn: precoUn(h.valorC, h.countC, 0.20), valor: h.valorC),
          EconomicClassRow(label: 'Descarte (Rot/Anthracnose/outros)', count: descCount, pct: pctOf(descCount), precoUn: 0.0, valor: 0.0),
        ],
        perBatch: perBatch,
      );
    }

    final recommendations = _buildRecommendations(stats, batchRisks, cnn, iot);
    final scopeLabel = 'Pomar completo · ${batches.length} lote${batches.length == 1 ? '' : 's'}';

    return ReportData(
      generatedAt: DateTime.now(),
      periodLabel: periodLabel,
      generatedBy: generatedBy,
      scopeLabel: scopeLabel,
      totalApples: stats.totalApples,
      totalFrames: stats.totalFrames,
      totalHealthy: stats.totalHealthy,
      totalAnomalies: stats.totalAnomalies,
      batchCount: batches.length,
      globalApproval: stats.globalApproval,
      avgConf: stats.avgConf,
      automationRate: stats.automationRate,
      healthScore: healthScore.toDouble(),
      deltaPp: stats.delta,
      humanQueue: stats.humanQueue,
      dominantAnomaly: stats.dominantAnomaly,
      dominantAnomalyCount: stats.dominantAnomalyCount,
      distribution: stats.anomalyDistribution,
      batchRisks: batchRisks,
      cnn: cnn,
      cnnDetail: cnnDetail,
      economic: economic,
      iot: iot,
      focus: focus,
      statusLabel: statusLabel,
      recommendations: recommendations,
    );
  }

  static String _statusLabel(double score) =>
      score >= 85 ? 'Excelente' : score >= 70 ? 'Saudável' : score >= 50 ? 'Requer Atenção' : 'Crítico';

  List<ActionItem> _buildRecommendations(GlobalStats s, List<BatchRiskRow> risks, CnnSummary cnn, IotSummary? iot) {
    final items = <ActionItem>[];
    final dom = s.dominantAnomaly;
    final topUrg = risks.isEmpty ? 0.0 : (risks.map((r) => r.urgency).reduce(math.max));

    if (dom != 'Nenhuma' && dom != 'Healthy' && _diseaseActions.containsKey(dom)) {
      items.add(ActionItem(
        title: 'Mitigação de ${AppColors.displayName(dom)}',
        action: _diseaseActions[dom]!,
        citation: _diseaseCitations[dom],
        severity: topUrg >= 0.7 ? 'critico' : topUrg >= 0.3 ? 'alerta' : 'info',
      ));
    }

    final critical = risks.where((r) => r.urgency >= 0.7).toList();
    if (critical.isNotEmpty) {
      final ids = critical.take(3).map((r) => r.id).join(', ');
      items.add(ActionItem(
        title: 'Isolamento de lotes críticos',
        action: 'Lote(s) com urgência ≥ 70%: $ids. Priorizar inspeção física, isolar do fluxo de expedição e reavaliar após tratamento.',
        severity: 'critico',
      ));
    }

    if (s.automationRate < 90 && s.totalApples > 0) {
      items.add(ActionItem(
        title: 'Otimização da automação',
        action: 'A taxa de automação (${s.automationRate.toStringAsFixed(1)}%) está abaixo da meta de 90%. '
            'Rever limiares de decisão e considerar re-treino do modelo com as ${cnn.uncertainCount} amostras incertas acumuladas.',
        severity: 'info',
      ));
    }

    if (s.humanQueue > 500) {
      items.add(ActionItem(
        title: 'Reforço da equipa de triagem',
        action: 'A fila de revisão manual (${s.humanQueue} maçãs) está elevada. Reforçar operadores ou aumentar o limiar de confiança para reduzir a carga.',
        severity: 'alerta',
      ));
    }

    if (iot != null && iot.blurWarning) {
      items.add(ActionItem(
        title: 'Manutenção do sistema de captura',
        action: 'Deteção de nitidez baixa no nó de captura. Limpar a lente e recalibrar o foco para preservar a qualidade das inferências.',
        severity: 'alerta',
      ));
    }

    if (iot != null && !iot.online) {
      items.add(ActionItem(
        title: 'Nó de captura offline',
        action: 'O Raspberry Pi 5 não reporta há mais de 15 segundos. Verificar alimentação e ligação de rede para retomar a inspeção em tempo real.',
        severity: 'critico',
      ));
    }

    return items;
  }



}

class _CollapsibleSection extends StatefulWidget {
  final String title;
  final Widget child;

  const _CollapsibleSection({
    required this.title,
    required this.child,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
                  color: Colors.transparent, // Ensures click area fills
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title.toUpperCase(),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Container(),
          secondChild: widget.child,
          crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
          alignment: Alignment.topCenter,
        ),
      ],
    );
  }
}
