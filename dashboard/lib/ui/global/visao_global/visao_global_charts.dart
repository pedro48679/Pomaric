part of '../../global_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// VISÃO GLOBAL · GRÁFICOS
// Evolução de anomalias por patologia e funil de automação segmentado por doença.
// ═══════════════════════════════════════════════════════════

extension _VisaoGlobalCharts on _GlobalDashboardState {
  // ═══ NEW: GRADIENT AREA CHART (DISEASES) ═══
  Widget _diseaseAreaChart(List<Batch> batches) {
    // Ordenação cronológica local, este gráfico assume ordem temporal (a
    // média móvel só faz sentido no tempo), mas `batches` é a mesma lista que
    // a tabela comparativa do Cap.2 reordena livremente (por Aprovação,
    // Contaminação, etc). Sem esta cópia local, ordenar a tabela por qualquer
    // coluna que não seja o ID corrompe silenciosamente este gráfico.
    final chronological = [...batches]..sort((a, b) => a.date.compareTo(b.date));
    final diseases = ['Rot', 'Scab', 'Blotch', 'Anthracnose'];

    final List<LineChartBarData> lineBars = [];
    for (int dIdx = 0; dIdx < diseases.length; dIdx++) {
      final d = diseases[dIdx];
      final color = AppColors.getColorForCondition(d);
      final spots = chronological.asMap().entries.map((e) {
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
          titlesData: _ttl(chronological),
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

  // ═══ 1.C · FUNIL DE AUTOMAÇÃO 2.0 ═══
  // Fusão: _automationFunnel + composição por doença do _globalDonut dentro de
  // cada estágio (a pergunta "a fila está cheia DE QUÊ?" passa a ser visual).
  Widget _automationFunnel2(List<Apple> allApples, List<CorrectionHistory> corrections) {
    final total = allApples.length;
    if (total == 0) return const SizedBox();

    const classOrder = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];
    // Regra partilhada com uncertainApplesProvider (dashboard_provider.dart) -
    // evita a duplicação/deriva que existia antes entre este funil (pomar
    // inteiro) e a fila do lote em foco.
    final auditSeed = ref.watch(auditSampleSeedProvider);
    final correctedIds = corrections.map((c) => c.appleId).toSet();
    bool inHumanQueue(Apple a) => correctedIds.contains(a.id) || isUncertainApple(a, auditSeed);

    // Composição + confiança média por estágio, numa passagem.
    final compTotal = <String, int>{};
    final compAuto = <String, int>{};
    final compQueue = <String, int>{};
    final confSum = <String, double>{};
    int humanQueue = 0;
    for (final a in allApples) {
      final c = a.primaryCondition;
      compTotal[c] = (compTotal[c] ?? 0) + 1;
      confSum[c] = (confSum[c] ?? 0) + a.effectiveConfidence;
      if (inHumanQueue(a)) {
        humanQueue++;
        compQueue[c] = (compQueue[c] ?? 0) + 1;
      } else {
        compAuto[c] = (compAuto[c] ?? 0) + 1;
      }
    }
    final compCorr = <String, int>{};
    for (final c in corrections) {
      compCorr[c.label] = (compCorr[c.label] ?? 0) + 1;
    }

    final autoAI = total - humanQueue;
    final autoRate = autoAI / total * 100;
    final humanRate = humanQueue / total * 100;
    final correctionCount = corrections.length;
    final correctionRate = humanQueue > 0 ? correctionCount / humanQueue * 100 : 0.0;
    final bottleneck = humanRate > 25; // fila humana acima de 25% do volume = gargalo

    Widget segmentedRow(String label, String value, String desc, double pct,
        Map<String, int> comp, int stageTotal) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                Text(value, style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Stack(
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (pct / 100).clamp(0.0, 1.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          for (final c in classOrder)
                            if ((comp[c] ?? 0) > 0)
                              Expanded(
                                flex: comp[c]!,
                                child: Tooltip(
                                  message: '${AppColors.displayName(c)}: ${comp[c]} maçãs '
                                      '(${stageTotal > 0 ? (comp[c]! / stageTotal * 100).toStringAsFixed(0) : 0}% do estágio)\n'
                                      'Confiança média da classe: ${((confSum[c] ?? 0) / (compTotal[c] ?? 1) * 100).toStringAsFixed(0)}%',
                                  textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.glassBorder),
                                  ),
                                  child: Container(color: AppColors.getColorForCondition(c)),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(desc, style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      );
    }

    return _card(
      'Funil de Triagem & Automação',
      'Fluxo de inspeção segmentado por patologia · passe o rato nos segmentos',
      380,
      tooltip: '• Cada barra do funil está segmentada pelas classes que a compõem, '
          'uma fila humana dominada por uma só doença indica limiar/retreino dessa classe, não falta de operadores.\n\n'
          '• Fila Humana: confiança <80% ou amostragem de auditoria de 5% (80–85%). Este valor é uma '
          'projeção calculada pela regra de confiança atual, não a fila real da base de dados, '
          'ver "Revisão Manual" no topo da página para o número de registos efetivamente pendentes.\n\n'
          '• Alerta de gargalo: fila humana acima de 25% do volume.',
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            segmentedRow('1. Volume Total Inspecionado', '$total maçãs',
                '100% do fluxo de entrada na linha', 100.0, compTotal, total),
            segmentedRow('2. Triagem Autónoma (IA)', '$autoAI (${autoRate.toStringAsFixed(1)}%)',
                'Auto-resolvido: zero esforço humano', autoRate, compAuto, autoAI),
            if (bottleneck)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 14),
                    const SizedBox(width: 6),
                    Text('GARGALO: fila humana >25% do volume',
                        style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            segmentedRow('3. Fila Humana (Revisão)', '$humanQueue (${humanRate.toStringAsFixed(1)}%)',
                'Casos limítrofes / auditorias aleatórias', 
                humanRate < 12.0 ? 12.0 + humanRate : humanRate, 
                compQueue, humanQueue),
            segmentedRow('4. Correções Manuais', '$correctionCount (${correctionRate.toStringAsFixed(1)}% da fila)',
                'Classe FINAL atribuída pelo operador', 
                (() {
                  final totalPct = total > 0 ? (correctionCount / total * 100) : 0.0;
                  return totalPct < 6.0 ? 6.0 + totalPct : totalPct;
                })(), 
                compCorr, correctionCount),
          ],
        ),
      ),
    );
  }
}
