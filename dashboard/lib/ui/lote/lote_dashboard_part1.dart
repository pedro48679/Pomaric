
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
import '../../widgets/pulsing_kpi_card.dart';
import '../../widgets/urgency_formula_card.dart';

Widget headerMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }



  // ── Throughput Quality Chart Removed (Fundido no Mapeamento Térmico de Qualidade Operacional) ──

  // ── Evolução de Qualidade na Sessão ─────────────────────────────────────

void _showSuggestionDialog(BuildContext context, String dominant, Batch batch) {
    final Map<String, String> diseaseAlerts = {
      'Rot': 'Surto de Podridão: Isolar lote, higienizar caixas de colheita, manter armazenamento rigoroso a 0.5-1.5°C para abrandar propagação de esporos.',
      'Scab': 'Detetada Sarna: Para futuras colheitas deste talhão, aplicar pulverizações de Cálcio e Silício para fortalecer a epiderme. Arejar ramos (poda) e remover folhas caídas.',
      'Blotch': 'Alerta de Sooty Blotch: Fator crítico de humidade detetado. Garantir secagem rápida pós-lavagem, reduzir humidade relativa na câmara e forçar ventilação de ar.',
      'Anthracnose': 'Risco de Antracnose: Foco fúngico ativo. Higienizar linhas de triagem com desinfetante ativo e planear tratamentos preventivos com cobre no pomar de origem.',
    };
    final Map<String, String> diseaseCitations = {
      'Rot': 'Diretrizes de armazenamento e sanidade baseadas em: UC Davis Postharvest Technology Center & WSU Tree Fruit Research.',
      'Scab': 'Práticas de mitigação foliar suportadas por: Cornell University (CALS) e Penn State Extension.',
      'Blotch': 'Controlo ambiental de pós-colheita fundamentado por: Diretrizes FAO e Penn State Extension.',
      'Anthracnose': 'Protocolos de profilaxia hídrica baseados no: Pacific Northwest Plant Disease Management Handbook (OSU).',
    };
    final alert = diseaseAlerts[dominant] ?? 'Lote estável. Elevado padrão de conformidade detetado.';
    final citation = diseaseCitations[dominant];
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: AppColors.getColorForCondition(dominant)),
            const SizedBox(width: 8),
            Text('Plano de Ação Recomendado', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(alert, style: TextStyle(color: AppColors.getColorForCondition(dominant), fontSize: 14)),
            if (citation != null) ...[
              const SizedBox(height: 16),
              Text(citation, style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
            ]
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Fechar', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

Widget section1Kpis(BuildContext context, Batch batch, String dominant, int domCount, int pending) {
    final healthyCount = batch.healthDistribution['Healthy'] ?? 0;
    final totalAnomalies = batch.totalApples - healthyCount;
    final approvalRate = batch.totalApples == 0 ? 100.0 : (healthyCount / batch.totalApples * 100);
    
    final avgConfVal = batch.totalApples == 0 
        ? 0.0 
        : batch.apples.map((a) => a.effectiveConfidence).reduce((x, y) => x + y) / batch.totalApples * 100.0;
    final score = ((approvalRate * 0.4) + (avgConfVal * 0.3) + ((1 - batch.urgencyScore) * 100 * 0.3)).clamp(0.0, 100.0);
    
    final isOutbreak = dominant != 'Healthy' && batch.urgencyScore > 0.15;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          kpi('Total Inspecionado', '${batch.totalApples}', Icons.scale, Colors.blueAccent),
          const SizedBox(width: 12),
          kpi('Saúde do Lote', '${score.toStringAsFixed(0)}%', Icons.favorite,
              score > 75 ? AppColors.healthy : score > 50 ? Colors.amber : Colors.redAccent,
              'Média de qualidade integrada'),
          const SizedBox(width: 12),
          PulsingKpiCard(
            title: 'Urgência',
            value: '${(batch.urgencyScore * 100).toStringAsFixed(1)}%',
            subtitle: 'Índice de prioridade',
            icon: Icons.priority_high,
            color: batch.urgencyScore >= 0.70 ? Colors.redAccent : batch.urgencyScore >= 0.40 ? Colors.orangeAccent : AppColors.healthy,
            isPulsing: batch.urgencyScore >= 0.70,
            buttonText: 'Detalhes',
            showButtonAlways: true,
            onSuggestionTap: () => _showUrgencyDialog(context, batch),
          ),
          const SizedBox(width: 12),
          PulsingKpiCard(
            title: 'Doença Dominante',
            value: dominant,
            subtitle: '$domCount casos detetados',
            icon: Icons.warning_amber,
            color: AppColors.getColorForCondition(dominant),
            isPulsing: isOutbreak,
            onSuggestionTap: () => _showSuggestionDialog(context, dominant, batch),
          ),
          const SizedBox(width: 12),
          kpi('Total com Patologia', '$totalAnomalies', Icons.dangerous,
              totalAnomalies > 50 ? Colors.redAccent : totalAnomalies > 0 ? Colors.orangeAccent : AppColors.healthy,
              'Frutos com patologias detetadas'),
        ],
      ),
    );
  }

  // ═══ UTILS ═══
  void _showUrgencyDialog(BuildContext context, Batch batch) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500, // Make it a compact card instead of full width
          child: Stack(
            children: [
              urgencyFormulaCard(batch),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Taxa de Conformidade (Acumulada) ──────────────────────────────────────



Widget sectionHeader(String title, Color color) {
    return Row(children: [
      Text(
        title.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(width: 16),
      const Expanded(child: Divider(color: Color(0x0fffffff), thickness: 1)),
    ]);
  }

Widget btn(WidgetRef ref, String label, String page, Color bg) {
    return ElevatedButton(
      onPressed: () => ref.read(currentPageProvider.notifier).setPage(page),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: Text(label),
    );
  }

Widget kpi(String title, String value, IconData icon, Color color, [String? sub, String? tooltip]) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 26),
              if (tooltip != null)
                Tooltip(
                  message: tooltip,
                  padding: const EdgeInsets.all(12),
                  textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.info_outline, color: color.withValues(alpha: 0.6), size: 18),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.bold)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 11)),
          ],
        ]),
      ),
    );
  }

  // ── CNN Efficacy ──────────────────────────────────────────────────────────

Widget batchRiskDecomposition(Batch batch) {
    final dist = batch.healthDistribution;
    final total = batch.totalApples > 0 ? batch.totalApples : 1;
    final urgency = batch.urgencyScore;

    // Contamination and severity weights per disease (same as Batch model)
    const diseaseContWeights = {'Scab': 0.9, 'Blotch': 0.7, 'Anthracnose': 0.5, 'Rot': 0.25};
    const diseaseSevWeights = {'Anthracnose': 1.0, 'Rot': 1.0, 'Scab': 0.4, 'Blotch': 0.4};

    int humanReview = 0;
    for (final a in batch.apples) {
      final prob = a.effectiveConfidence;
      if (prob < 0.80) {
        humanReview++;
      } else if (prob < 0.85) {
        if ((a.id.hashCode % 100) < 5) humanReview++;
      }
    }
    final autoApproved = total - humanReview;

    // Calculate per-disease average confidence
    final Map<String, double> avgConfPerDisease = {};
    for (final d in ['Rot', 'Scab', 'Blotch', 'Anthracnose']) {
      final apples = batch.apples.where((a) => a.primaryCondition == d).toList();
      if (apples.isEmpty) {
        avgConfPerDisease[d] = 0.0;
      } else {
        avgConfPerDisease[d] = apples.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / apples.length;
      }
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Risco por Doença: Propagação vs Dano Comercial',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
            Tooltip(
              message: 'Cálculo de Urgência = (Índice de Contágio × 40%) + (Impacto Económico × 60%)\n\n'
                       'Índice de Contágio (laranja, esquerda):\n'
                       '  Taxa de transmissibilidade da patologia para a restante produção.\n'
                       '  Scab=0.9 · Blotch=0.7 · Anthracnose=0.5 · Rot=0.25\n\n'
                       'Impacto Económico (vermelho, direita):\n'
                       '  Desvalorização de mercado projetada por unidade afetada.\n'
                       '  Rot/Anthracnose=1.0 (perda total) · Scab/Blotch=0.4 (perda parcial)\n\n'
                       'Risco Ponderado: contribuição aferida pela fiabilidade do modelo preditivo (CNN).',
              padding: const EdgeInsets.all(12),
              textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
              decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
            ),
            child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 14),
          ),
        ]),
        Text('← Propagação (risco de alastramento)     Dano Comercial (perda de valor) →',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        const SizedBox(height: 24),
        // Table Header
        Row(children: [
          Expanded(flex: 5, child: Text('Propagação ← (alastramento)', style: TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
          const SizedBox(width: 12),
          SizedBox(width: 80, child: Text('Doença', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          const SizedBox(width: 12),
          Expanded(flex: 5, child: Text('Dano Comercial → (perda de valor)', style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.left)),
          const SizedBox(width: 12),
          SizedBox(width: 90, child: Text('Urgência\nAjustada', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ]),
        const SizedBox(height: 10),
        ...['Rot', 'Scab', 'Blotch', 'Anthracnose'].where((d) => (dist[d] ?? 0) > 0).map((disease) {
          final count = dist[disease] ?? 0;
          final contW = diseaseContWeights[disease] ?? 0;
          final sevW = diseaseSevWeights[disease] ?? 0;
          final contContrib = (count * contW / total).clamp(0.0, 1.0);
          final sevContrib = (count * sevW / total).clamp(0.0, 1.0);
          final diseaseColor = AppColors.getColorForCondition(disease);
          
          // Certeza e cálculo de risco ajustado
          final cnnConf = avgConfPerDisease[disease] ?? 0.0;
          final rawContrib = ((count * contW * 0.4) + (count * sevW * 0.6)) / total;
          final adjustedRisk = rawContrib * cnnConf;

          // Color for adjusted risk badge
          final riskColor = adjustedRisk > 0.15 
              ? Colors.redAccent 
              : adjustedRisk > 0.05 
                  ? Colors.orangeAccent 
                  : AppColors.healthy;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              // Left bar (Contaminação)
              Expanded(
                flex: 5,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${(contContrib * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: contContrib,
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.orangeAccent.withValues(alpha: 0.1), Colors.orangeAccent],
                              begin: Alignment.centerLeft, end: Alignment.centerRight,
                            ),
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              // Center Label (Doença)
              SizedBox(
                width: 80,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: diseaseColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: diseaseColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      disease,
                      style: TextStyle(color: diseaseColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Right bar (Severidade)
              Expanded(
                flex: 5,
                child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: sevContrib,
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.redAccent, Colors.redAccent.withValues(alpha: 0.1)],
                              begin: Alignment.centerLeft, end: Alignment.centerRight,
                            ),
                            borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${(sevContrib * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(width: 12),
              // Risk badge
              SizedBox(
                width: 90,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: riskColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: riskColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${(adjustedRisk * 100).toStringAsFixed(1)}%',
                      style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ]),
          );
        }).toList(),
        const SizedBox(height: 16),
        const Divider(height: 1, thickness: 0.5),
        const SizedBox(height: 12),
        Wrap(spacing: 20, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_outline, color: AppColors.healthy, size: 14),
            const SizedBox(width: 6),
            Text('Auto-aprovadas (certeza ≥80%): ', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            Text('$autoApproved (${(autoApproved / total * 100).toStringAsFixed(1)}%)',
                style: TextStyle(color: AppColors.healthy, fontSize: 11, fontWeight: FontWeight.bold)),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_outline, color: Colors.amber, size: 14),
            const SizedBox(width: 6),
            Text('Revisão humana (<80% e amostras): ', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            Text('$humanReview (${(humanReview / total * 100).toStringAsFixed(1)}%)',
                style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
          ]),
        ]),
      ]),
    );
  }

