part of '../../global_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// VISÃO GLOBAL · KPIs
// Grelha de KPIs executivos e os diálogos de urgência e sugestão que se abrem a partir dela.
// ═══════════════════════════════════════════════════════════

extension _VisaoGlobalKpi on _GlobalDashboardState {
  void _showGlobalUrgencyDialog(Batch urgentBatch) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500, // Make it a compact card instead of full width
          child: Stack(
            children: [
              urgencyFormulaCard(urgentBatch),
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
  void _showGlobalSuggestionDialog(String dominant) {
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
    final alert = diseaseAlerts[dominant] ?? 'Estado estável. Elevado padrão de conformidade detetado globalmente.';
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


  // ═══ KPIs ═══
  Widget _kpiRow(GlobalStats stats, List<Batch> batches) {
    final tot = stats.totalApples;
    final anom = stats.totalAnomalies;
    final cnt = batches.length;
    final dom = stats.dominantAnomaly;
    final domN = stats.dominantAnomalyCount;
    final urgent = stats.urgentBatch!;
    final daily = stats.dailyBatches;

    List<double> lastN(List<double> xs, [int n = 7]) =>
        xs.length <= n ? xs : xs.sublist(xs.length - n);
    final volSpark = lastN(daily.map((b) => b.totalApples.toDouble()).toList());
    final appSpark = lastN(daily.map((b) {
      final t = b.totalApples > 0 ? b.totalApples : 1;
      return (b.healthDistribution['Healthy'] ?? 0) / t * 100;
    }).toList());
    final anomSpark = lastN(daily
        .map((b) => (b.totalApples - (b.healthDistribution['Healthy'] ?? 0)).toDouble())
        .toList());
    final urgSpark = lastN(daily.map((b) => b.urgencyScore * 100).toList());
    final domSpark = lastN(daily.map((b) {
      final t = b.totalApples > 0 ? b.totalApples : 1;
      return (b.healthDistribution[dom] ?? 0) / t * 100;
    }).toList());
    Widget sparkOf(List<double> s, Color c) => s.length > 1
        ? SizedBox(height: 20, width: double.infinity, child: CustomPaint(painter: _SparkPainter(s, c)))
        : const SizedBox.shrink();
    return Row(
      children: [
        _kpi(
          'Total Inspec.',
          '$tot',
          '$cnt lotes',
          Icons.scale,
          Colors.blueAccent,
          spark: volSpark,
        ),
        const SizedBox(width: 8),
        _kpi(
          'Saudáveis',
          '${stats.globalApproval.toStringAsFixed(0)}%',
          'maçãs saudáveis',
          Icons.favorite,
          // Cor fixa (verde), deixa de variar por limiar para não colidir com
          // as cores da Doença Principal (roxo/vermelho/rosa/amarelo).
          AppColors.healthy,
          spark: appSpark,
        ),
        const SizedBox(width: 8),
        PulsingKpiCard(
          title: 'Urgência',
          value: '${(urgent.urgencyScore * 100).toStringAsFixed(1)}%',
          subtitle: 'Lote: ${urgent.id}',
          icon: Icons.priority_high,
          // Cor fixa (ciano), distinta das 4 cores de doença; a pulsação já
          // comunica a urgência sem precisar de mudar de cor.
          color: Colors.cyanAccent,
          isPulsing: urgent.urgencyScore >= 0.70,
          buttonText: 'Fórmula',
          showButtonAlways: true,
          onSuggestionTap: () => _showGlobalUrgencyDialog(urgent),
          sparkline: sparkOf(urgSpark, Colors.cyanAccent),
        ),
        const SizedBox(width: 8),
        PulsingKpiCard(
          title: 'Doença Dominante',
          value: dom,
          subtitle: '$domN casos',
          icon: Icons.warning_amber,
          color: AppColors.getColorForCondition(dom),
          isPulsing: dom != 'Healthy',
          onSuggestionTap: () => _showGlobalSuggestionDialog(dom),
          sparkline: sparkOf(domSpark, AppColors.getColorForCondition(dom)),
        ),
        const SizedBox(width: 8),
        _kpi(
          'Frutos com Patologias',
          '$anom',
          'com patologias',
          Icons.dangerous,
          // Cor fixa (azul-acinzentado), distinta das restantes 4 cores de KPI
          // e das 4 cores de doença (roxo/vermelho/rosa/amarelo já ocupadas).
          Colors.blueGrey,
          spark: anomSpark,
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
    List<double>? spark,
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
                  textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
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
            style: TextStyle(
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
              style: TextStyle(
                color: AppColors.textPrimary,
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
          if (spark != null && spark.length > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 20,
              width: double.infinity,
              child: CustomPaint(painter: _SparkPainter(spark, c)),
            ),
          ],
        ],
      ),
    ),
  );
}
