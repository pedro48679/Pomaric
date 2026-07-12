import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../utils/constants.dart';
import '../../services/pdf_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RELATÓRIO DE ESTADO DO POMAR
// Documento formal, orientado a tabelas de dados (sem gráficos, sem prosa
// gerada), que consolida a informação de toda a dashboard (KPIs globais,
// distribuição de patologias, lotes, pipeline CNN, foco no lote selecionado
// e estado do equipamento). As secções aparecem/desaparecem consoante o
// estado real dos dados. O mesmo modelo (ReportData) alimenta o ecrã e o PDF.
// ═══════════════════════════════════════════════════════════════════════════

Widget buildReportsContent(BuildContext context, WidgetRef ref) {
  return const _ReportsView();
}

// Planos de ação por patologia (guia de tratamento pós-colheita/agronómico).
const Map<String, String> _diseaseActions = {
  'Rot':
      'Isolar o lote, higienizar caixas de colheita e manter armazenamento rigoroso a 0.5–1.5 °C para abrandar a propagação de esporos.',
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

class _ReportsView extends ConsumerWidget {
  const _ReportsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(filteredBatchesProvider);
    final stats = ref.watch(globalStatsProvider);

    if (batches.isEmpty || stats == null) {
      return _emptyState();
    }

    final data = _assemble(ref, batches, stats);

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
                      _sectionHeader('1. Resumo Quantitativo'),
                      _summaryTable(data),
                      const SizedBox(height: 22),
                      _sectionHeader('2. Distribuição por Patologia'),
                      _distributionTable(data),
                      const SizedBox(height: 22),
                      _sectionHeader('3. Detalhe por Lote'),
                      _batchTable(data),
                      const SizedBox(height: 22),
                      _sectionHeader('4. Desempenho dos Modelos de Classificação'),
                      _cnnTable(data),
                      if (data.focus != null) ...[
                        const SizedBox(height: 22),
                        _sectionHeader('5. Lote em Foco: ${data.focus!.id}'),
                        _focusTables(data.focus!),
                      ],
                      if (data.iot != null) ...[
                        const SizedBox(height: 22),
                        _sectionHeader('6. Equipamento de Captura'),
                        _iotTable(data.iot!),
                      ],
                      const SizedBox(height: 22),
                      _sectionHeader('7. Observações e Ações Recomendadas'),
                      _recommendationsTable(data),
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
  // ASSEMBLER — providers → ReportData (partilhado entre ecrã e PDF)
  // ─────────────────────────────────────────────────────────────────────────
  ReportData _assemble(WidgetRef ref, List<Batch> batches, GlobalStats stats) {
    final user = ref.watch(authProvider);
    final range = ref.watch(dateRangeFilterProvider);
    final currentBatch = ref.watch(batchProvider);
    final iotHb = ref.watch(raspberryHeartbeatProvider).value;
    final uncertain = ref.watch(uncertainApplesProvider);

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
    int c2 = 0, c5 = 0, other = 0;
    double c2Sum = 0, c5Sum = 0;
    for (final a in allApples) {
      switch (a.modelName) {
        case 'CNN2':
          c2++;
          c2Sum += a.cnn2Confidence;
          break;
        case 'CNN5':
          c5++;
          c5Sum += a.effectiveConfidence;
          break;
        default:
          other++;
      }
    }
    final cnn = CnnSummary(
      cnn2Count: c2,
      cnn5Count: c5,
      otherCount: other,
      cnn2AvgConf: c2 > 0 ? c2Sum / c2 * 100 : 0,
      cnn5AvgConf: c5 > 0 ? c5Sum / c5 * 100 : 0,
      uncertainCount: uncertain.length,
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
      final diseased = [...currentBatch.apples.where((a) => a.primaryCondition != 'Healthy')]
        ..sort((a, b) => (b.worstFrame?.diseaseSum ?? b.effectiveConfidence).compareTo(a.worstFrame?.diseaseSum ?? a.effectiveConfidence));
      final worst = diseased.take(5).map((a) => TopApple(id: a.id, condition: a.primaryCondition, confidence: a.effectiveConfidence)).toList();
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

  // ─────────────────────────────────────────────────────────────────────────
  // TOOLBAR
  // ─────────────────────────────────────────────────────────────────────────
  Widget _toolbar(BuildContext context, WidgetRef ref, ReportData data) {
    final range = ref.watch(dateRangeFilterProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 10),
          Text('Relatório de Estado do Pomar',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(children: [
              _rangeOption(ref, range, '7d', '7 DIAS'),
              _rangeOption(ref, range, '30d', '30 DIAS'),
            ]),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Imprimir'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(color: AppColors.glassBorder),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: () => PdfService.generateAndPrintPdf(data),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Exportar PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.isDark ? Colors.black : Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: () => _showPdfPreview(context, data),
          ),
        ],
      ),
    );
  }

  Widget _rangeOption(WidgetRef ref, String active, String val, String label) {
    final selected = active == val;
    return GestureDetector(
      onTap: () => ref.read(dateRangeFilterProvider.notifier).setRange(val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceBright : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              letterSpacing: 0.5,
            )),
      ),
    );
  }

  void _showPdfPreview(BuildContext context, ReportData data) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        backgroundColor: Colors.grey[900],
        child: SizedBox(
          width: 900,
          height: MediaQuery.of(ctx).size.height * 0.9,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  const Text('Pré-visualização do Relatório', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(ctx).pop()),
                ]),
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) => PdfService.generatePdfBytes(data),
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  pdfFileName: 'relatorio_pomar_${DateFormat('yyyyMMdd_HHmm').format(data.generatedAt)}.pdf',
                  useActions: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CABEÇALHO DO DOCUMENTO
  // ─────────────────────────────────────────────────────────────────────────
  Widget _documentHeader(ReportData d) {
    final color = _statusColor(d.healthScore);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RELATÓRIO DE ESTADO DO POMAR',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 21, fontWeight: FontWeight.bold, letterSpacing: -0.2)),
                    const SizedBox(height: 4),
                    Text(d.scopeLabel, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('CLASSIFICAÇÃO', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, letterSpacing: 1)),
                  const SizedBox(height: 2),
                  Text('${d.statusLabel} · ${d.healthScore.toStringAsFixed(0)}%',
                      style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.glassBorder, height: 1),
          const SizedBox(height: 14),
          Wrap(spacing: 32, runSpacing: 10, children: [
            _headMeta('PERÍODO', d.periodLabel),
            _headMeta('GERADO EM', DateFormat('dd/MM/yyyy · HH:mm').format(d.generatedAt)),
            _headMeta('RESPONSÁVEL', d.generatedBy),
          ]),
        ],
      ),
    );
  }

  Widget _headMeta(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 9, letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Color _statusColor(double score) =>
      score >= 85 ? AppColors.healthy : score >= 70 ? AppColors.healthy : score >= 50 ? AppColors.scab : AppColors.rot;

  Color _urgencyColor(double urgency) =>
      urgency >= 0.7 ? AppColors.rot : urgency >= 0.3 ? AppColors.scab : AppColors.healthy;

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION / TABLE HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.glassBorder))),
        child: Text(title.toUpperCase(),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
      ),
    );
  }

  Widget _tableContainer(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }

  Widget _headerRow(List<String> labels, {List<int>? flexes, List<TextAlign>? aligns}) {
    return Container(
      color: AppColors.surfaceBright.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: List.generate(labels.length, (i) {
          return Expanded(
            flex: flexes != null ? flexes[i] : 1,
            child: Text(labels[i],
                textAlign: aligns != null ? aligns[i] : TextAlign.left,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
          );
        }),
      ),
    );
  }

  Widget _dataRow(List<Widget> cells, {List<int>? flexes, bool zebra = false}) {
    return Container(
      decoration: BoxDecoration(
        color: zebra ? AppColors.surfaceBright.withOpacity(0.18) : Colors.transparent,
        border: Border(top: BorderSide(color: AppColors.glassBorder.withOpacity(0.5))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: List.generate(cells.length, (i) => Expanded(flex: flexes != null ? flexes[i] : 1, child: cells[i])),
      ),
    );
  }

  Widget _cellText(String text, {Color? color, bool bold = false, TextAlign align = TextAlign.left}) {
    return Text(text,
        textAlign: align,
        style: TextStyle(color: color ?? AppColors.textPrimary, fontSize: 12.5, fontWeight: bold ? FontWeight.bold : FontWeight.normal));
  }

  // ─── 1. RESUMO ───
  Widget _summaryTable(ReportData d) {
    final rows = <List<String>>[
      ['Maçãs Inspecionadas', '${d.totalApples}'],
      ['Frames Capturados', '${d.totalFrames}'],
      ['Lotes no Período', '${d.batchCount}'],
      ['Aprovação Global', '${d.globalApproval.toStringAsFixed(1)}%'],
      ['Confiança Média da IA', '${d.avgConf.toStringAsFixed(1)}%'],
      ['Taxa de Automação', '${d.automationRate.toStringAsFixed(1)}%'],
      ['Anomalias Detetadas', '${d.totalAnomalies}'],
      ['Fila de Revisão Manual', '${d.humanQueue}'],
      ['Doença Predominante', d.dominantAnomaly == 'Nenhuma' ? '— (sem casos)' : '${AppColors.displayName(d.dominantAnomaly)} (${d.dominantAnomalyCount} casos)'],
      ['Variação de Aprovação', '${d.deltaPp >= 0 ? "+" : ""}${d.deltaPp.toStringAsFixed(1)} pp'],
      ['Índice de Saúde Global', '${d.healthScore.toStringAsFixed(0)}% — ${d.statusLabel}'],
    ];
    return _tableContainer([
      _headerRow(['Métrica', 'Valor'], flexes: [3, 2], aligns: [TextAlign.left, TextAlign.right]),
      for (int i = 0; i < rows.length; i++)
        _dataRow([
          _cellText(rows[i][0]),
          _cellText(rows[i][1], bold: true, align: TextAlign.right),
        ], flexes: const [3, 2], zebra: i.isOdd),
    ]);
  }

  // ─── 2. DISTRIBUIÇÃO ───
  Widget _distributionTable(ReportData d) {
    final total = d.totalApples > 0 ? d.totalApples : 1;
    final entries = d.distribution.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return _emptyPanel('Sem dados de distribuição disponíveis.');
    return _tableContainer([
      _headerRow(['Condição', 'Nº Maçãs', '% do Total'], flexes: const [3, 2, 2], aligns: const [TextAlign.left, TextAlign.right, TextAlign.right]),
      for (int i = 0; i < entries.length; i++)
        _dataRow([
          _cellText(AppColors.displayName(entries[i].key), color: AppColors.getColorForCondition(entries[i].key), bold: true),
          _cellText('${entries[i].value}', align: TextAlign.right),
          _cellText('${(entries[i].value / total * 100).toStringAsFixed(1)}%', align: TextAlign.right),
        ], flexes: const [3, 2, 2], zebra: i.isOdd),
      Container(
        color: AppColors.surfaceBright.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Expanded(flex: 3, child: _cellText('TOTAL', bold: true)),
          Expanded(flex: 2, child: _cellText('$total', bold: true, align: TextAlign.right)),
          Expanded(flex: 2, child: _cellText('100.0%', bold: true, align: TextAlign.right)),
        ]),
      ),
    ]);
  }

  // ─── 3. LOTES ───
  Widget _batchTable(ReportData d) {
    final rows = [...d.batchRisks]..sort((a, b) => b.urgency.compareTo(a.urgency));
    if (rows.isEmpty) return _emptyPanel('Sem lotes no período selecionado.');
    final top = rows.take(15).toList();
    const flexes = [2, 2, 3, 2, 2, 2];
    return Column(children: [
      _tableContainer([
        _headerRow(['Lote', 'Localização', 'Doença Predom.', 'Maçãs', 'Aprovação', 'Urgência'],
            flexes: flexes, aligns: const [TextAlign.left, TextAlign.left, TextAlign.left, TextAlign.right, TextAlign.right, TextAlign.right]),
        for (int i = 0; i < top.length; i++)
          _dataRow([
            _cellText(top[i].id, bold: true),
            _cellText(top[i].location),
            _cellText(top[i].dominant == 'Nenhuma' ? '—' : AppColors.displayName(top[i].dominant), color: AppColors.getColorForCondition(top[i].dominant)),
            _cellText('${top[i].total}', align: TextAlign.right),
            _cellText('${top[i].approval.toStringAsFixed(0)}%', align: TextAlign.right),
            _cellText('${(top[i].urgency * 100).toStringAsFixed(0)}%', color: _urgencyColor(top[i].urgency), bold: true, align: TextAlign.right),
          ], flexes: flexes, zebra: i.isOdd),
      ]),
      if (rows.length > top.length) ...[
        const SizedBox(height: 6),
        Text('Mostrando os ${top.length} lotes de maior urgência de um total de ${rows.length}.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
      ],
    ]);
  }

  // ─── 4. CNN ───
  Widget _cnnTable(ReportData d) {
    final c = d.cnn;
    if (!c.hasData) return _emptyPanel('Sem classificações registadas pelo pipeline de IA no período.');
    final total = c.total > 0 ? c.total : 1;
    final rows = <List<String>>[
      ['CNN2 (Gatekeeper — deteção de saudável)', '${c.cnn2Count}', '${(c.cnn2Count / total * 100).toStringAsFixed(0)}%', '${c.cnn2AvgConf.toStringAsFixed(1)}%'],
      ['CNN5 (Multiclasse — classificação de patologia)', '${c.cnn5Count}', '${(c.cnn5Count / total * 100).toStringAsFixed(0)}%', '${c.cnn5AvgConf.toStringAsFixed(1)}%'],
    ];
    const flexes = [4, 2, 2, 2];
    return Column(children: [
      _tableContainer([
        _headerRow(['Modelo', 'Nº Classif.', '% do Fluxo', 'Confiança Média'],
            flexes: flexes, aligns: const [TextAlign.left, TextAlign.right, TextAlign.right, TextAlign.right]),
        for (int i = 0; i < rows.length; i++)
          _dataRow([
            _cellText(rows[i][0]),
            _cellText(rows[i][1], align: TextAlign.right),
            _cellText(rows[i][2], align: TextAlign.right),
            _cellText(rows[i][3], bold: true, align: TextAlign.right),
          ], flexes: flexes, zebra: i.isOdd),
      ]),
      const SizedBox(height: 6),
      Text('Fila de revisão humana (confiança < 80% ou amostragem de auditoria): ${c.uncertainCount} maçãs.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
    ]);
  }

  // ─── 5. FOCO NO LOTE ───
  Widget _focusTables(BatchFocus f) {
    final total = f.total > 0 ? f.total : 1;
    final entries = f.distribution.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.glassBorder)),
          child: Wrap(spacing: 28, runSpacing: 12, children: [
            _headMeta('LOCALIZAÇÃO', f.location),
            _headMeta('APROVAÇÃO', '${f.approval.toStringAsFixed(1)}%'),
            _headMeta('URGÊNCIA', '${(f.urgency * 100).toStringAsFixed(0)}%'),
            _headMeta('CONFIANÇA MÉDIA', '${f.avgConf.toStringAsFixed(1)}%'),
          ]),
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 14),
          _tableContainer([
            _headerRow(['Condição', 'Nº Maçãs', '% do Lote'], flexes: const [3, 2, 2], aligns: const [TextAlign.left, TextAlign.right, TextAlign.right]),
            for (int i = 0; i < entries.length; i++)
              _dataRow([
                _cellText(AppColors.displayName(entries[i].key), color: AppColors.getColorForCondition(entries[i].key), bold: true),
                _cellText('${entries[i].value}', align: TextAlign.right),
                _cellText('${(entries[i].value / total * 100).toStringAsFixed(1)}%', align: TextAlign.right),
              ], flexes: const [3, 2, 2], zebra: i.isOdd),
          ]),
        ],
        if (f.worst.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Amostras de maior risco', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _tableContainer([
            _headerRow(['ID Maçã', 'Condição', 'Confiança'], flexes: const [3, 2, 2], aligns: const [TextAlign.left, TextAlign.left, TextAlign.right]),
            for (int i = 0; i < f.worst.length; i++)
              _dataRow([
                _cellText(f.worst[i].id),
                _cellText(AppColors.displayName(f.worst[i].condition), color: AppColors.getColorForCondition(f.worst[i].condition)),
                _cellText('${(f.worst[i].confidence * 100).toStringAsFixed(1)}%', bold: true, align: TextAlign.right),
              ], flexes: const [3, 2, 2], zebra: i.isOdd),
          ]),
        ],
      ],
    );
  }

  // ─── 6. IOT ───
  Widget _iotTable(IotSummary iot) {
    final color = iot.online ? AppColors.healthy : AppColors.rot;
    final rows = <List<String>>[
      ['Estado', iot.online ? iot.mode.toUpperCase() : 'OFFLINE'],
      ['Temperatura CPU', iot.cpuTemp != null ? '${iot.cpuTemp!.toStringAsFixed(0)}°C' : '—'],
      ['Câmara', iot.cameraFps != null ? '${iot.cameraFps!.toStringAsFixed(1)} fps' : '—'],
      ['Nitidez (Laplacian)', iot.lastBlur != null ? iot.lastBlur!.toStringAsFixed(0) : '—'],
      ['Total de Inferências', '${iot.inferenceCount}'],
      ['Uptime', iot.uptime],
    ];
    return Column(children: [
      _tableContainer([
        for (int i = 0; i < rows.length; i++)
          _dataRow([
            _cellText(rows[i][0]),
            _cellText(rows[i][1], color: rows[i][0] == 'Estado' ? color : AppColors.textPrimary, bold: true, align: TextAlign.right),
          ], flexes: const [3, 2], zebra: i.isOdd),
      ]),
      if (iot.blurWarning) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.scab.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.scab.withOpacity(0.4))),
          child: Row(children: [
            Icon(Icons.warning_amber, color: AppColors.scab, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('Nitidez baixa — lente possivelmente suja ou descalibrada.', style: TextStyle(color: AppColors.scab, fontSize: 12, fontWeight: FontWeight.bold))),
          ]),
        ),
      ],
    ]);
  }

  // ─── 7. RECOMENDAÇÕES ───
  Widget _recommendationsTable(ReportData d) {
    if (d.recommendations.isEmpty) {
      return _tableContainer([
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.check_circle_outline, color: AppColors.healthy, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('Sem observações críticas. Manter os protocolos operacionais atuais.', style: TextStyle(color: AppColors.textPrimary, fontSize: 13))),
          ]),
        ),
      ]);
    }
    return _tableContainer([
      for (int i = 0; i < d.recommendations.length; i++) _recRow(d.recommendations[i], zebra: i.isOdd),
    ]);
  }

  Widget _recRow(ActionItem r, {bool zebra = false}) {
    final color = r.severity == 'critico' ? AppColors.rot : r.severity == 'alerta' ? AppColors.scab : AppColors.healthy;
    final tag = r.severity == 'critico' ? 'CRÍTICO' : r.severity == 'alerta' ? 'ALERTA' : 'INFO';
    return Container(
      decoration: BoxDecoration(
        color: zebra ? AppColors.surfaceBright.withOpacity(0.18) : Colors.transparent,
        border: Border(top: BorderSide(color: AppColors.glassBorder.withOpacity(0.5))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(tag, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
          ),
          SizedBox(
            width: 170,
            child: Text(r.title, style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.action, style: TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.4)),
                if (r.citation != null) ...[
                  const SizedBox(height: 3),
                  Text('Fonte: ${r.citation!}', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPanel(String text) {
    return _tableContainer([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
      ),
    ]);
  }

  Widget _reportFooter(ReportData d) {
    return Column(children: [
      Divider(color: AppColors.glassBorder),
      const SizedBox(height: 8),
      Text(
        'Documento gerado automaticamente pelo sistema de inspeção de qualidade em ${DateFormat('dd/MM/yyyy HH:mm').format(d.generatedAt)}. '
        'Os valores refletem o estado dos dados no momento da geração.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 11, height: 1.4),
      ),
    ]);
  }

  Widget _emptyState() {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, color: AppColors.textSecondary.withOpacity(0.4), size: 56),
            const SizedBox(height: 16),
            Text('Sem dados para gerar o relatório', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 6),
            Text('Aguarde a chegada de inspeções ou ajuste o período.', style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
