part of '../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// GLOBAL DASHBOARD — PARTE 1
// Utils de agregação, header, KPIs, gráfico de doenças, treemap
// (wrapper), heatmap, comparativo de risco, funil de automação e
// feed de produção em tempo real.
// ═══════════════════════════════════════════════════════════

extension _GlobalDashboardPart1 on _GlobalDashboardState {
  // ═══ UTILS ═══
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
      s += a.effectiveConfidence;
    }
    return (s / list.length) * 100;
  }

  double _bApproval(Batch b) => b.totalApples == 0
      ? 0
      : (b.healthDistribution['Healthy'] ?? 0) / b.totalApples * 100;
  Widget _header(WidgetRef ref, GlobalStats stats, List<Batch> batches) {
    final avgUrg = batches.isEmpty ? 0.0 : batches.fold(0.0, (s, b) => s + b.urgencyScore) / batches.length;
    final score = (stats.globalApproval * 0.4 + stats.avgConf * 0.3 + (1 - avgUrg) * 100 * 0.3).clamp(0.0, 100.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visão do Pomar',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
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
                  child: Text(
                    'LIVE',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Visão executiva · Foco em Contaminação & Gravidade',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            // Date Filter Bar
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  _buildFilterOption(ref, '7d', '7 dias'),
                  _buildFilterOption(ref, '30d', '30 dias'),
                ],
              ),
            ),
            const SizedBox(width: 32),
            _headerMetric('Autonomia', '${stats.automationRate.toStringAsFixed(1)}%', stats.automationRate > 90 ? AppColors.healthy : Colors.orangeAccent),
            const SizedBox(width: 24),
            _headerMetric('Confiança IA', '${stats.avgConf.toStringAsFixed(1)}%', Colors.cyanAccent),
            const SizedBox(width: 24),
            _headerMetric('Revisão Manual', '${stats.humanQueue}', stats.humanQueue > 500 ? Colors.redAccent : stats.humanQueue > 0 ? Colors.orangeAccent : AppColors.healthy),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterOption(WidgetRef ref, String val, String label) {
    final activeRange = ref.watch(dateRangeFilterProvider);
    final isSelected = activeRange == val;
    return GestureDetector(
      onTap: () => ref.read(dateRangeFilterProvider.notifier).setRange(val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceBright : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _headerMetric(String label, String value, Color color) {
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

  Widget _sec(String t, Color c) => Row(
    children: [
      Text(
        t.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(width: 16),
      const Expanded(child: Divider(color: Color(0x0fffffff), thickness: 1)),
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
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (tooltip != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: tooltip,
                padding: const EdgeInsets.all(12),
                textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
                ),
                child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
              ),
            ],
          ],
        ),
        Text(
          sub,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
        FlLine(color: AppColors.textSecondary.withOpacity(0.2), strokeWidth: 1),
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
                style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
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
            style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
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
    double score,
    List<Batch> daily,
  ) {
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
          'Saúde Global',
          '${score.toStringAsFixed(0)}%',
          'média integrada',
          Icons.favorite,
          // Cor fixa (verde) — deixa de variar por limiar para não colidir com
          // as cores da Doença Principal (roxo/vermelho/rosa/amarelo).
          AppColors.healthy,
          spark: appSpark,
        ),
        const SizedBox(width: 8),
        PulsingKpiCard(
          title: 'Urgência Top',
          value: '${(urgent.urgencyScore * 100).toStringAsFixed(1)}%',
          subtitle: 'Lote: ${urgent.id}',
          icon: Icons.priority_high,
          // Cor fixa (ciano) — distinta das 4 cores de doença; a pulsação já
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
          title: 'Doença Principal',
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
          'Total Anomalias',
          '$anom',
          'anomalias detetadas',
          Icons.dangerous,
          // Cor fixa (azul-acinzentado) — distinta das restantes 4 cores de KPI
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

  // ═══ NEW: GRADIENT AREA CHART (DISEASES) ═══
  Widget _diseaseAreaChart(List<Batch> batches) {
    final diseases = ['Rot', 'Scab', 'Blotch', 'Anthracnose'];

    final List<LineChartBarData> lineBars = [];
    for (int dIdx = 0; dIdx < diseases.length; dIdx++) {
      final d = diseases[dIdx];
      final color = AppColors.getColorForCondition(d);
      final spots = batches.asMap().entries.map((e) {
        final b = e.value;
        final pct = b.totalApples > 0
            ? ((b.healthDistribution[d] ?? 0) / b.totalApples * 100)
            : 0.0;
        return FlSpot(e.key.toDouble(), pct);
      }).toList();

      final List<FlSpot> maSpots = [];
      for (int i = 0; i < spots.length; i++) {
        double sum = 0;
        int count = 0;
        for (int j = i; j >= 0 && j > i - 3; j--) {
          sum += spots[j].y;
          count++;
        }
        maSpots.add(FlSpot(i.toDouble(), count > 0 ? sum / count : 0.0));
      }

      // Raw curve with area fill
      lineBars.add(
        LineChartBarData(
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
                color.withOpacity(0.3),
                color.withOpacity(0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      );

      // 3-point moving average dashed curve
      lineBars.add(
        LineChartBarData(
          spots: maSpots,
          isCurved: true,
          color: color.withOpacity(0.5),
          barWidth: 1.5,
          dashArray: [4, 4],
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    return _card(
      'Evolução de Anomalias',
      'Incidência (%) ao longo dos últimos dias (linha tracejada = média móvel de 3 pontos)',
      300,
      LineChart(
        LineChartData(
          minY: 0,
          gridData: _grid(),
          titlesData: _ttl(batches),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(fitInsideHorizontally: true, fitInsideVertically: true,
              getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              getTooltipItems: (s) => s.map((sp) {
                if (sp.barIndex % 2 != 0) return null;
                final dName = diseases[sp.barIndex ~/ 2];
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

  // ═══ TREEMAP E ANALYTICS DE LOTES ═══
  Widget _batchTreemap(List<Batch> batches) {
    return _card(
      'Mapa & Analytics de Lotes (Treemap)',
      'Visão geral interativa e detalhe analítico por lote',
      _GlobalDashboardState._comparativoTripleChartHeight,
      tooltip: '• Visão Treemap: Tamanho proporcional à métrica selecionada.\n'
               '• Cor: Verde (saudável) → Amarelo → Vermelho (urgência/contaminação).\n'
               '• Clique num lote para expandir os KPIs e o histórico sem sair da dashboard.',
      _BatchTreemapWidget(batches: batches),
    );
  }

  // ═══ HEATMAP INTERATIVO: LOTE × PATOLOGIA ═══
  Widget _heatmap(List<Batch> batches) {
    final ds = ['Rot', 'Scab', 'Blotch', 'Anthracnose'];

    // Normalização por coluna: a célula mais escura de cada doença = o pior lote
    // dessa doença (contraste muito melhor do que escala fixa a 15%).
    final colMax = <String, double>{};
    for (final c in ds) {
      double mx = 0;
      for (final b in batches) {
        final v = b.totalApples > 0 ? (b.healthDistribution[c] ?? 0) / b.totalApples * 100 : 0.0;
        if (v > mx) mx = v;
      }
      colMax[c] = mx < 3 ? 3 : mx; // piso para não exagerar quando tudo é baixo
    }
    final focusedId = ref.read(batchProvider)?.id;

    return _card(
      'Heatmap: Lote × Patologia',
      '% de incidência da doença por lote individual (passe o rato/toque para detalhes)',
      _GlobalDashboardState._comparativoTripleChartHeight,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eixo X: Cabeçalho das Colunas
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    'ID Lote',
                    style: TextStyle(
                      color: AppColors.textSecondary,
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
                  final focused = b.id == focusedId;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: focused
                        ? BoxDecoration(
                            color: Colors.cyanAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.cyanAccent.withOpacity(0.45)),
                          )
                        : null,
                    child: Row(
                      children: [
                        // Eixo Y: Etiqueta do Lote
                        SizedBox(
                          width: 90,
                          child: Text(
                            b.id,
                            style: TextStyle(
                              color: focused ? Colors.cyanAccent : AppColors.textSecondary,
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

                          // Intensidade normalizada por coluna (worst-of-column = 1.0).
                          final intensity = (v / (colMax[c] ?? 15.0)).clamp(0.0, 1.0);
                          final isColMax = v > 0 && v >= (colMax[c] ?? 1e9) - 0.05;
                          final color = AppColors.getColorForCondition(c);

                          return Expanded(
                            child: Tooltip(
                              message:
                                  'Lote: ${b.id}\n$c: ${v.toStringAsFixed(1)}% ($count de ${b.totalApples} maçãs)',
                              preferBelow: false,
                              textStyle: TextStyle(
                                color: AppColors.textPrimary,
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
                                height: 32,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(
                                    intensity * 0.82 + 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isColMax
                                        ? Colors.white.withOpacity(0.85)
                                        : intensity > 0.5
                                            ? color.withOpacity(0.6)
                                            : (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.04),
                                    width: isColMax ? 1.5 : 1,
                                  ),
                                  boxShadow: intensity > 0.55
                                      ? [
                                          BoxShadow(
                                            color: color.withOpacity(0.3),
                                            blurRadius: 5,
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
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary,
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
              Text(
                'Intensidade (por doença): ',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
              ),
              const SizedBox(width: 4),
              _legendTile('menor', Colors.orangeAccent.withOpacity(0.12)),
              _legendTile('', Colors.orangeAccent.withOpacity(0.38)),
              _legendTile('', Colors.orangeAccent.withOpacity(0.62)),
              _legendTile('pior lote', Colors.orangeAccent.withOpacity(0.88)),
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
          border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.03)),
        ),
        child: Text(
          label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 8),
        ),
      ),
    );
  }

  // ═══ COMPARATIVO DE RISCO ENTRE LOTES ═══
  Widget _batchRiskComparison(List<Batch> batches) {
    if (batches.isEmpty) {
      return _card(
        'Comparativo de Risco entre Lotes',
        'Sem dados disponíveis',
        380,
        const Center(child: Text('N/A')),
      );
    }

    final sorted = [...batches]..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));
    final maxVal = sorted
            .map((b) => max(b.contaminationScore, b.severityScore) * 100)
            .fold(0.0, max)
            .clamp(10.0, 100.0) +
        8;

    return _card(
      'Comparativo de Risco entre Lotes',
      'Contaminação vs Severidade — ordenado por índice de urgência',
      380,
      tooltip: '• Laranja: score de contaminação ponderado (Scab, Sooty Blotch, Rot, Anthracnose).\n'
          '• Vermelho: score de severidade clínica.\n'
          '• Lotes à esquerda concentram maior risco operacional.',
      Column(
        children: [
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: maxVal,
                alignment: BarChartAlignment.spaceAround,
                groupsSpace: 10,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(fitInsideHorizontally: true, fitInsideVertically: true,
                    getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final b = sorted[group.x.toInt()];
                      final isCont = rodIndex == 0;
                      final val = isCont ? b.contaminationScore * 100 : b.severityScore * 100;
                      return BarTooltipItem(
                        '${b.id}\n${isCont ? "Contaminação" : "Severidade"}: ${val.toStringAsFixed(1)}%\n'
                        'Urgência: ${(b.urgencyScore * 100).toStringAsFixed(1)}%',
                        TextStyle(
                          color: isCont ? Colors.orangeAccent : Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: AppColors.textSecondary.withOpacity(0.15), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, meta) => Text(
                        '${v.toInt()}%',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= sorted.length) return const SizedBox();
                        return SideTitleWidget(
                          meta: meta,
                          space: 10,
                          child: Transform.rotate(
                            angle: -0.45,
                            child: Text(
                              sorted[i].id.length > 10
                                  ? sorted[i].id.substring(0, 10)
                                  : sorted[i].id,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                barGroups: sorted.asMap().entries.map((e) {
                  final b = e.value;
                  return BarChartGroupData(
                    x: e.key,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: b.contaminationScore * 100,
                        color: Colors.orangeAccent.withOpacity(0.85),
                        width: 11,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                      BarChartRodData(
                        toY: b.severityScore * 100,
                        color: Colors.redAccent.withOpacity(0.85),
                        width: 11,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendIndicatorMini('Contaminação', Colors.orangeAccent),
              const SizedBox(width: 16),
              _legendIndicatorMini('Severidade', Colors.redAccent),
            ],
          ),
        ],
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
      if (prob < 0.80) {
        humanQueue++;
      } else if (prob < 0.85) {
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
        padding: const EdgeInsets.only(bottom: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
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
                    color: AppColors.textSecondary.withOpacity(0.2),
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
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ),
      );
    }

    return _card(
      'Funil de Triagem & Automação Global',
      'Fluxo de inspeção e nível de automação inteligente',
      360,
      tooltip: '• Filtrado pela IA: Frutos cujas patologias ou conformidades foram classificadas com certeza elevada pela rede neuronal, dispensando validação manual.\n\n'
          '• Fila Humana: Casos com confiança inferior a 80\% ou integrados na amostragem aleatória de 5% de auditoria.\n\n'
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
              'Ajustes manuais feitos pelos operadores no tapete',
              (humanQueue > 0 ? (correctionCount / humanQueue * 100) : 0.0).clamp(0.0, 100.0),
              Colors.redAccent,
            ),
          ],
        ),
      ),
    );
  }

  // ═══ FEED DE PRODUÇÃO EM TEMPO REAL (producao_atual) ═══
  Widget _productionFeed(WidgetRef ref) {
    final feedAsync = ref.watch(producaoAtualProvider);
    final records = feedAsync.value;

    return _card(
      'Últimas Classificações da Linha',
      'Veredicto final por maçã (producao_atual) — atualização automática',
      250,
      tooltip: '• Cada cartão é o resultado final de uma maçã na linha: classe, confiança e origem da decisão.\n\n'
          '• Origem IA: decisão autónoma do pipeline. Origem HUMANO: validação/correção manual na triagem.\n\n'
          '• Atualiza por polling (10s em produção, 60s em modo demo).',
      records == null
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.conveyor_belt, color: AppColors.textSecondary.withOpacity(0.4), size: 32),
                      const SizedBox(height: 10),
                      Text(
                        'Sem registos de produção',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _productionTile(context, ref, records[i]),
                ),
    );
  }

  Widget _productionTile(BuildContext context, WidgetRef ref, ProducaoRecord r) {
    final color = AppColors.getColorForCondition(r.finalClass);
    final sourceColor = r.isHuman ? Colors.amberAccent : Colors.cyanAccent;
    return GestureDetector(
      onTap: () {
        // Find the full Apple object across all loaded batches
        final allBatches = ref.read(availableBatchesProvider);
        final allApples = allBatches.expand((b) => b.apples).toList();
        final apple = allApples.firstWhere(
          (a) => a.id == r.appleId, 
          orElse: () => Apple(
            id: r.appleId, 
            timestamp: r.timestamp, 
            frames: []
          ) // fallback (shouldn't happen ideally)
        );

        if (apple.frames.isNotEmpty) {
          // Find the batch it belongs to
          try {
            final batch = allBatches.firstWhere((b) => b.apples.any((a) => a.id == r.appleId));
            ref.read(batchProvider.notifier).setBatch(batch);
            ref.read(currentPageProvider.notifier).setPage('Grelha Lote');
            
            // Wait for navigation animation then open details
            Future.delayed(const Duration(milliseconds: 100), () {
              if (context.mounted) {
                AppleCard.showAppleDetails(context, apple);
              }
            });
          } catch (e) {
            // Batch not found, skip navigation
          }
        }
      },
      child: Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceBright.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: double.infinity,
                child: HybridImage(cloudUrl: r.frameThumbnail, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            r.appleId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  AppColors.displayName(r.finalClass),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${(r.finalConfidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sourceColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  r.isHuman ? 'HUMANO' : r.finalSource.toUpperCase(),
                  style: TextStyle(color: sourceColor, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
              Text(
                _relativeTime(r.timestamp),
                style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    return 'há ${diff.inDays}d';
  }
}
