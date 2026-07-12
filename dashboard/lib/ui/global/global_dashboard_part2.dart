part of '../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// GLOBAL DASHBOARD — PARTE 2
// Matriz de confusão IA vs. Operador, evolução CNN2/CNN5, tabela
// de lotes ativos, severidade global, controlo de qualidade e
// calibração de confiança dos modelos.
// ═══════════════════════════════════════════════════════════

extension _GlobalDashboardPart2 on _GlobalDashboardState {
  // ═══ CONFUSION MATRIX (MATRIZ DE CORRELAÇÃO DE DIAGNÓSTICOS) ═══
  Widget _confusionMatrix(List<Batch> batches, List<CorrectionHistory> corrections, AsyncValue<List<Map<String, dynamic>>> reviewsAsync) {
    final aiLabels = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];
    final humanLabels = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose', 'Outros'];
    // Colunas estreitas — usa abreviações para nomes longos (já era o caso
    // de 'Anthracnose' → 'Anthra'; 'Blotch' agora é 'Sooty Blotch').
    String matrixLabel(String l) {
      if (l == 'Anthracnose') return 'Anthra';
      if (l == 'Blotch') return 'S.Blotch';
      return l;
    }

    final reviews = reviewsAsync.value;
    if (reviews == null) {
      return const SkeletonCard(height: 380);
    }

    final Map<String, Map<String, int>> matrix = {
      for (var l1 in aiLabels) l1: { for (var l2 in humanLabels) l2: 0 }
    };

    // Matriz construída exclusivamente a partir de validações humanas reais
    // (manual_review): linha = predição original da IA, coluna = classe
    // validada/corrigida. Sem corrected_class = predição confirmada (diagonal).
    int totalValidations = 0;
    final completedIds = <String>{};
    for (final r in reviews) {
      if ((r['status'] as String? ?? '') != 'completed') continue;
      final aiLabel = r['original_class'] as String?;
      if (aiLabel == null || !aiLabels.contains(aiLabel)) continue;
      final corr = r['corrected_class'] as String?;
      final humanLabel = (corr == null || corr.isEmpty)
          ? aiLabel
          : (humanLabels.contains(corr) ? corr : 'Outros');
      matrix[aiLabel]![humanLabel] = matrix[aiLabel]![humanLabel]! + 1;
      completedIds.add(r['apple_id'] as String? ?? '');
      totalValidations++;
    }

    // Correções feitas nesta sessão que ainda não constam da BD (ex.: mock mode)
    final allApples = batches.expand((b) => b.apples).toList();
    for (final c in corrections) {
      if (completedIds.contains(c.appleId)) continue;
      final apple = allApples.where((a) => a.id == c.appleId).firstOrNull;
      if (apple == null) continue;
      final aiLabel = apple.cnn2Label != 'Unknown' ? apple.cnn2Label : 'Healthy';
      if (!aiLabels.contains(aiLabel)) continue;
      final humanLabel = humanLabels.contains(c.label) ? c.label : 'Outros';
      matrix[aiLabel]![humanLabel] = matrix[aiLabel]![humanLabel]! + 1;
      totalValidations++;
    }

    // Escala de opacidade dinâmica em função dos valores reais
    int maxDiag = 1, maxOff = 1;
    for (final ai in aiLabels) {
      for (final h in humanLabels) {
        final v = matrix[ai]![h]!;
        if (ai == h) {
          if (v > maxDiag) maxDiag = v;
        } else {
          if (v > maxOff) maxOff = v;
        }
      }
    }

    if (totalValidations == 0) {
      return _card(
        'Matriz de Confusão: IA vs. Operador',
        'Predição Original da IA (linhas) × Validação Humana (colunas)',
        380,
        tooltip: 'A matriz é preenchida com as validações humanas reais registadas em manual_review.',
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fact_check_outlined, color: AppColors.textSecondary.withOpacity(0.4), size: 36),
              const SizedBox(height: 12),
              Text(
                'Sem validações humanas no período',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'A matriz preenche-se à medida que a triagem manual é concluída.',
                style: TextStyle(color: AppColors.textSecondary.withOpacity(0.6), fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    return _card(
      'Matriz de Confusão: IA vs. Operador',
      '$totalValidations validações reais · Predição da IA (linhas) × Validação Humana (colunas)',
      380,
      tooltip: '• Diagonal Principal: Casos em que a predição da IA foi validada e confirmada pelo operador.\n\n'
          '• Fora da Diagonal: Erros ou correções feitas manualmente no tapete. Indica o padrão de recalibração necessário.\n\n'
          '• Fonte: registos concluídos em manual_review (+ correções desta sessão).',
      Column(
        children: [
          Row(
            children: [
              SizedBox(width: 60, child: Text('IA \\ Humano', style: TextStyle(color: AppColors.textSecondary, fontSize: 8, fontWeight: FontWeight.bold))),
              ...humanLabels.expand((l) {
                final w = <Widget>[];
                if (l == 'Outros') {
                  w.add(Container(width: 1, height: 12, color: AppColors.textSecondary.withOpacity(0.4), margin: const EdgeInsets.symmetric(horizontal: 6)));
                }
                w.add(
                  Expanded(
                    child: Text(
                      matrixLabel(l),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: l == 'Outros' ? AppColors.textSecondary : AppColors.getColorForCondition(l), fontSize: 9, fontWeight: FontWeight.bold),
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
                          matrixLabel(aiLabel),
                          style: TextStyle(color: AppColors.getColorForCondition(aiLabel), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...humanLabels.expand((humanLabel) {
                        final val = matrix[aiLabel]![humanLabel] ?? 0;
                        final isDiagonal = aiLabel == humanLabel;

                        double opacity = 0.02;
                        if (val > 0) {
                          opacity = isDiagonal
                            ? (val / maxDiag * 0.7).clamp(0.1, 0.7)
                            : (val / maxOff * 0.6).clamp(0.1, 0.6);
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
                              message: 'IA previu: ${AppColors.displayName(aiLabel)}\nHumano validou: ${AppColors.displayName(humanLabel)}\nVolume: $val ocorrências',
                              preferBelow: false,
                              textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
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
                                    color: val > 0 ? color.withOpacity(0.3) : (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.02),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '$val',
                                    style: TextStyle(
                                      color: val > 0 ? AppColors.textPrimary : AppColors.textSecondary,
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
            style: TextStyle(
              color: AppColors.textSecondary,
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
      380,
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
                  touchTooltipData: LineTouchTooltipData(fitInsideHorizontally: true, fitInsideVertically: true,
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

  void _onSort(String colName, bool ascending) {
    setState(() {
      _sortColumn = colName;
      _sortAscending = ascending;
    });
  }

  int? _sortColumnIndex() {
    switch (_sortColumn) {
      case 'Lote': return 0;
      case 'Local': return 1;
      case 'Volume': return 2;
      case 'Aprovação': return 3;
      case 'Contaminação': return 5;
      case 'Gravidade': return 6;
      case 'Tendência': return 7;
      default: return null;
    }
  }

  Widget _buildStateBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.healthy.withOpacity(0.12)
            : (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? AppColors.healthy.withOpacity(0.3) : (AppColors.isDark ? Colors.white24 : Colors.black26),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.healthy,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            isActive ? 'ATIVO' : 'CONCLUÍDO',
            style: TextStyle(
              color: isActive ? AppColors.healthy : AppColors.textSecondary,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  List<FlSpot> _getBatchSparklineSpots(Batch b) {
    if (b.apples.isEmpty) return const [FlSpot(0, 0)];

    final sortedApples = [...b.apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final double chunkSize = sortedApples.length / 5.0;
    if (chunkSize <= 0) return const [FlSpot(0, 0)];

    final List<FlSpot> spots = [];
    for (int i = 0; i < 5; i++) {
      final start = (i * chunkSize).round();
      if (start >= sortedApples.length) {
        if (spots.isNotEmpty) {
          spots.add(FlSpot(i.toDouble(), spots.last.y));
        } else {
          spots.add(FlSpot(i.toDouble(), 0.0));
        }
        continue;
      }
      final end = ((start + chunkSize).round() < sortedApples.length) ? (start + chunkSize).round() : sortedApples.length;
      final chunk = sortedApples.sublist(start, end);

      if (chunk.isEmpty) {
        spots.add(FlSpot(i.toDouble(), spots.isNotEmpty ? spots.last.y : 0.0));
        continue;
      }

      final int healthy = chunk.where((a) => a.primaryCondition == 'Healthy').length;
      final double approval = (healthy / chunk.length) * 100.0;
      spots.add(FlSpot(i.toDouble(), approval));
    }
    return spots;
  }

  Widget _buildMiniSparkline(Batch b) {
    final spots = _getBatchSparklineSpots(b);
    final color = _bApproval(b) > 80 ? AppColors.healthy : Colors.orangeAccent;

    return SizedBox(
      width: 60,
      height: 24,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
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
      sortColumnIndex: _sortColumnIndex(),
      sortAscending: _sortAscending,
      headingTextStyle: TextStyle(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
      dataTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
      columnSpacing: 16,
      columns: [
        DataColumn(
          label: const Text('Lote'),
          onSort: (colIdx, asc) => _onSort('Lote', asc),
        ),
        DataColumn(
          label: const Text('Local'),
          onSort: (colIdx, asc) => _onSort('Local', asc),
        ),
        DataColumn(
          label: const Text('Volume'),
          onSort: (colIdx, asc) => _onSort('Volume', asc),
        ),
        DataColumn(
          label: const Text('Aprovação'),
          onSort: (colIdx, asc) => _onSort('Aprovação', asc),
        ),
        const DataColumn(label: Text('Doença Principal')),
        DataColumn(
          label: const Text('Contaminação'),
          onSort: (colIdx, asc) => _onSort('Contaminação', asc),
        ),
        DataColumn(
          label: const Text('Gravidade'),
          onSort: (colIdx, asc) => _onSort('Gravidade', asc),
        ),
        DataColumn(
          label: const Text('Tendência'),
          onSort: (colIdx, asc) => _onSort('Tendência', asc),
        ),
        const DataColumn(label: Text('Urgência')),
        const DataColumn(label: Text('')),
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
            if (b.id == ref.read(batchProvider)?.id) {
              return Colors.cyanAccent.withOpacity(0.14);
            }
            if (isActive) {
              return AppColors.healthy.withOpacity(0.08);
            }
            return null;
          }),
          cells: [
            DataCell(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(b.id, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    _buildStateBadge(isActive),
                  ],
                ),
              ),
            ),
            DataCell(
              Text(
                b.location,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
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
            DataCell(Builder(builder: (_) {
              final dom = getDominantDiseaseENForBatch(b);
              final c = AppColors.getColorForCondition(dom);
              final n = b.healthDistribution[dom] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.withOpacity(0.3)),
                ),
                child: Text(
                  dom == 'Healthy' ? 'Healthy' : '${AppColors.displayName(dom)} ($n)',
                  style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              );
            })),
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
              Text(
                '${(b.urgencyScore * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: b.urgencyScore > 0.3 ? Colors.redAccent : b.urgencyScore > 0.15 ? Colors.amber : AppColors.healthy,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataCell(
              TextButton(
                onPressed: () => ref.read(batchProvider.notifier).setBatch(b),
                child: Text(
                  b.id == ref.read(batchProvider)?.id ? '● Em foco' : 'Focar →',
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    ),
  );

  Widget _globalSeverityAreaChart(List<Batch> batches) {
    final colors = [AppColors.healthy, Colors.amber, Colors.orangeAccent, Colors.redAccent];
    final focusedId = ref.read(batchProvider)?.id;

    // Contagem por severidade (Healthy, Light, Moderate, Severe) por lote.
    List<int> countsFor(Batch batch) {
      final t = [0, 0, 0, 0];
      for (final apple in batch.apples) {
        if (apple.primaryCondition == 'Healthy') {
          t[0]++;
        } else {
          final sev = (apple.worstFrame?.diseaseSum ?? apple.effectiveConfidence).clamp(0.0, 1.0);
          if (sev < 0.45) {
            t[1]++;
          } else if (sev < 0.75 && apple.primaryCondition != 'Rot' && apple.primaryCondition != 'Anthracnose') {
            t[2]++;
          } else {
            t[3]++;
          }
        }
      }
      return t;
    }

    return _card(
      'Severidade Global por Lote',
      'Composição percentual de cada lote por categoria de severidade',
      _GlobalDashboardState._comparativoTripleChartHeight,
      tooltip: '• Cada barra horizontal mostra a composição por severidade do lote.\n\n• Métrica por contagem de maçãs, não por soma de probabilidades.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: batches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final b = batches[i];
                final counts = countsFor(b);
                final total = b.totalApples > 0 ? b.totalApples : 1;
                final pcts = counts.map((c) => c / total * 100).toList();
                final focused = b.id == focusedId;
                final defect = (100 - pcts[0]).clamp(0.0, 100.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(b.id,
                            style: TextStyle(
                              color: focused ? Colors.cyanAccent : AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            )),
                        const SizedBox(width: 10),
                        Text('${pcts[0].toStringAsFixed(0)}% saudável',
                            style: TextStyle(color: AppColors.healthy, fontSize: 10, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${defect.toStringAsFixed(0)}% com defeito',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: focused ? const EdgeInsets.all(2) : EdgeInsets.zero,
                      decoration: focused
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                            )
                          : null,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 24,
                          child: Row(
                            children: [
                              for (int k = 0; k < 4; k++)
                                if (pcts[k] > 0)
                                  Expanded(
                                    flex: (pcts[k] * 10).round().clamp(1, 100000),
                                    child: Container(
                                      color: colors[k],
                                      alignment: Alignment.center,
                                      child: pcts[k] >= 7
                                          ? Text('${pcts[k].toStringAsFixed(0)}%',
                                              style: TextStyle(
                                                color: Colors.black.withOpacity(0.72),
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ))
                                          : null,
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendIndicatorMini('Healthy', AppColors.healthy),
              _legendIndicatorMini('Light', Colors.amber),
              _legendIndicatorMini('Moderate', Colors.orangeAccent),
              _legendIndicatorMini('Severe', Colors.redAccent),
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
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 8)),
        ],
      ),
    );
  }

  Widget _buildGlobalComplianceChart(List<Batch> dailyBatches) {
    if (dailyBatches.isEmpty) {
      return _card(
        'Controlo de Qualidade da Produção Global',
        'Taxa de conformidade acumulada (Móvel vs Cumulativa vs Limiar 80%)',
        300,
        const Center(child: Text('Sem dados disponíveis')),
      );
    }

    final spots = <FlSpot>[];
    final movingSpots = <FlSpot>[];
    int cumTotal = 0;
    int cumHealthy = 0;

    for (int i = 0; i < dailyBatches.length; i++) {
      final b = dailyBatches[i];
      cumTotal += b.totalApples;
      cumHealthy += b.healthDistribution['Healthy'] ?? 0;
      spots.add(FlSpot(i.toDouble(), cumTotal == 0 ? 100.0 : (cumHealthy / cumTotal * 100.0)));

      int windowHealthy = 0;
      int windowTotal = 0;
      final start = i - 2 < 0 ? 0 : i - 2;
      for (int j = start; j <= i; j++) {
        final wb = dailyBatches[j];
        windowTotal += wb.totalApples;
        windowHealthy += wb.healthDistribution['Healthy'] ?? 0;
      }
      movingSpots.add(FlSpot(i.toDouble(), windowTotal == 0 ? 100.0 : (windowHealthy / windowTotal * 100.0)));
    }

    final movingColor = AppColors.isDark ? const Color(0xff06B6D4) : const Color(0xff0284C7);

    return _card(
      'Controlo de Qualidade da Produção Global',
      'Taxa de conformidade acumulada (Móvel vs Cumulativa vs Limiar 80%)',
      300,
      tooltip: 'Linha Verde: percentagem acumulada de maçãs saudáveis desde o início do período.\n\nLinha Ciano: tendência local calculada com janela móvel de 3 lotes.\n\nLinha Laranja: padrão mínimo de qualidade (80%).',
      Column(
        children: [
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.textSecondary.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: 100,
                // Reutiliza o mesmo helper de eixo-X do "Evolução de Anomalias"
                // (_ttl): define um interval explícito, evitando que o fl_chart
                // repita o mesmo dia várias vezes quando escolhe o seu próprio
                // intervalo automático.
                titlesData: _ttl(dailyBatches),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(fitInsideHorizontally: true, fitInsideVertically: true,
                    getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
                    getTooltipItems: (s) => s.map((sp) {
                      final label = sp.barIndex == 0
                          ? 'Cumulativa'
                          : sp.barIndex == 1
                              ? 'Móvel (3 lotes)'
                              : 'Limiar Alvo';
                      if (sp.barIndex == 2) return null;
                      return LineTooltipItem(
                        '$label: ${sp.y.toStringAsFixed(1)}%',
                        TextStyle(
                          color: sp.barIndex == 0 ? AppColors.healthy : movingColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10.5,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.healthy,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.healthy.withOpacity(0.08),
                    ),
                  ),
                  LineChartBarData(
                    spots: movingSpots,
                    isCurved: true,
                    color: movingColor,
                    barWidth: 1.5,
                    dashArray: [4, 4],
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: [FlSpot(0, 80), FlSpot(spots.last.x, 80)],
                    isCurved: false,
                    color: Colors.amber.withOpacity(0.5),
                    barWidth: 1,
                    dashArray: [4, 4],
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 12, height: 3, color: AppColors.healthy),
              const SizedBox(width: 6),
              Text('Cumulativa', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              const SizedBox(width: 16),
              Row(
                children: [
                  Container(width: 4, height: 2.5, color: movingColor),
                  const SizedBox(width: 2),
                  Container(width: 4, height: 2.5, color: movingColor),
                ],
              ),
              const SizedBox(width: 6),
              Text('Tendência Local', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              const SizedBox(width: 16),
              Row(
                children: [
                  Container(width: 4, height: 2.5, color: Colors.amber),
                  const SizedBox(width: 2),
                  Container(width: 4, height: 2.5, color: Colors.amber),
                ],
              ),
              const SizedBox(width: 6),
              Text('Limiar Alvo (80%)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pipelineCalibrationChart(List<Batch> dailyBatches, AsyncValue<List<Map<String, dynamic>>> reviewsAsync) {
    const labels = ['<60%', '60-70%', '70-80%', '80-90%', '90%+'];

    return Builder(
      builder: (context) {
        final rows = reviewsAsync.value;
        if (rows == null) {
          return const SkeletonCard(height: 380);
        }

        final allApples = dailyBatches.expand((b) => b.apples).toList();

        // Só modelos de produção — um shadow CNN em avaliação também escreve
        // em cnn_predictions e não deve entrar na calibração do pipeline.
        final modelsSet = <String>{};
        for (final a in allApples) {
          for (final p in a.cnnPredictions) {
            final m = p['model_name'] as String?;
            if (m != null && AppConstants.productionModels.contains(m)) {
              modelsSet.add(m);
            }
          }
        }
        final models = modelsSet.toList()..sort();
        if (models.isEmpty) {
          models.addAll(['CNN2', 'CNN5']);
        }

        final Map<String, List<int>> modelCounts = {
          for (final m in models) m: List<int>.filled(labels.length, 0)
        };
        final Map<String, List<int>> modelErrors = {
          for (final m in models) m: List<int>.filled(labels.length, 0)
        };

        for (final a in allApples) {
          for (final p in a.cnnPredictions) {
            final model = p['model_name'] as String?;
            if (model == null || !modelCounts.containsKey(model)) continue;

            final confVal = p['confidence'] as num? ?? 0.0;
            final conf = confVal > 1.0 ? confVal.toDouble() : confVal.toDouble() * 100.0;

            final idx = conf < 60 ? 0 : conf < 70 ? 1 : conf < 80 ? 2 : conf < 90 ? 3 : 4;
            modelCounts[model]![idx]++;
          }
        }

        for (final r in rows) {
          final aId = r['apple_id'] as String?;
          final corr = r['corrected_class'] as String?;
          if (aId == null || corr == null || corr.isEmpty) continue;

          final apple = allApples.where((a) => a.id == aId).firstOrNull;
          if (apple == null) continue;

          for (final p in apple.cnnPredictions) {
            final model = p['model_name'] as String?;
            if (model == null || !modelErrors.containsKey(model)) continue;

            final predLabel = p['label'] as String? ?? 'Healthy';
            if (predLabel != corr) {
              final confVal = p['confidence'] as num? ?? 0.0;
              final conf = confVal > 1.0 ? confVal.toDouble() : confVal.toDouble() * 100.0;
              final idx = conf < 60 ? 0 : conf < 70 ? 1 : conf < 80 ? 2 : conf < 90 ? 3 : 4;
              modelErrors[model]![idx]++;
            }
          }
        }

        final Map<String, Color> modelColors = {
          'CNN2': const Color(0xff06B6D4),
          'CNN5': const Color(0xffF59E0B),
          'CNN3': const Color(0xff8B5CF6),
          'CNN4': const Color(0xffEF4444),
        };

        final List<LineChartBarData> barLines = [];
        final List<LineChartBarData> errorRateLines = [];

        double maxYVal = 0.0;
        final Map<String, int> totalErrors = {
          for (final m in models) m: modelErrors[m]!.fold<int>(0, (a, b) => a + b)
        };
        final Map<String, int> totalApplesForModel = {
          for (final m in models) m: modelCounts[m]!.fold<int>(0, (a, b) => a + b)
        };

        for (final m in models) {
          final totApples = totalApplesForModel[m]!;
          for (int i = 0; i < labels.length; i++) {
            final count = modelCounts[m]![i];
            final err = modelErrors[m]![i];
            final barY = totApples == 0 ? 0.0 : (err / totApples * 100.0);
            final lineY = count == 0 ? 0.0 : (err / count * 100.0);
            if (barY > maxYVal) maxYVal = barY;
            if (lineY > maxYVal) maxYVal = lineY;
          }
        }
        final double chartMaxY = maxYVal == 0.0 ? 5.0 : maxYVal * 1.20;

        for (int mIdx = 0; mIdx < models.length; mIdx++) {
          final model = models[mIdx];
          final color = modelColors[model] ?? Colors.grey;
          final totApples = totalApplesForModel[model]!;

          double offset = 0.0;
          if (models.length == 2) {
            offset = mIdx == 0 ? -0.12 : 0.12;
          } else if (models.length > 2) {
            offset = (mIdx - (models.length - 1) / 2) * 0.16;
          }

          for (int i = 0; i < labels.length; i++) {
            final err = modelErrors[model]![i];
            final barY = totApples == 0 ? 0.0 : (err / totApples * 100.0);

            barLines.add(
              LineChartBarData(
                spots: [
                  FlSpot(i.toDouble() + offset, 0),
                  FlSpot(i.toDouble() + offset, barY),
                ],
                isCurved: false,
                color: color.withValues(alpha: 0.55),
                barWidth: 20,
                dotData: const FlDotData(show: false),
              ),
            );
          }

          final List<FlSpot> spots = [];
          for (int i = 0; i < labels.length; i++) {
            final count = modelCounts[model]![i];
            final err = modelErrors[model]![i];
            final errRate = count == 0 ? 0.0 : (err / count * 100.0);
            spots.add(FlSpot(i.toDouble(), errRate));
          }

          errorRateLines.add(
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: true),
            ),
          );
        }

        final allSeries = [...barLines, ...errorRateLines];

        return _card(
          'Calibração de Confiança dos Modelos',
          'Frequência de erro por faixa de certeza da IA',
          380,
          tooltip: 'Barras Claras: percentagem do total de erros do modelo que ocorreu nesta faixa.\n\nLinhas Sólidas: taxa de erro real da IA nesta faixa.',
          Column(
            children: [
              Expanded(
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: chartMaxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: AppColors.textSecondary.withOpacity(0.1),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: 1.0,
                          getTitlesWidget: (v, meta) {
                            final double diff = (v - v.round()).abs();
                            if (diff > 0.01) return const SizedBox();

                            final idx = v.round();
                            if (idx < 0 || idx >= labels.length) return const SizedBox();
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(labels[idx], style: TextStyle(color: AppColors.textSecondary, fontSize: 8.5)),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: TextStyle(color: AppColors.textSecondary, fontSize: 8)),
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(fitInsideHorizontally: true, fitInsideVertically: true,
                        getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
                        getTooltipItems: (s) {
                          return s.map((sp) {
                            if (sp != s.first) return null; // Apenas mostra 1 tooltip consolidado

                            final lineSpots = s.where((spot) => spot.barIndex >= barLines.length).toList();
                            if (lineSpots.isEmpty) {
                              return LineTooltipItem(
                                'Sem Dados\n',
                                TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 10.5),
                              );
                            }

                            final idx = lineSpots.first.x.toInt();
                            String text = 'Faixa: ${labels[idx]}\n';

                            for (final lSp in lineSpots) {
                              final mIdx = lSp.barIndex - barLines.length;
                              if (mIdx < 0 || mIdx >= models.length) continue;
                              final model = models[mIdx];

                              final count = modelCounts[model]![idx];
                              final err = modelErrors[model]![idx];
                              final errRate = count == 0 ? 0.0 : (err / count * 100.0);
                              final totErr = totalErrors[model]!;
                              final dist = totErr == 0 ? 0.0 : (err / totErr * 100.0);
                              final totApples = totalApplesForModel[model]!;
                              final globalPct = totApples == 0 ? 0.0 : (err / totApples * 100.0);

                              text += '\n$model · Erro Global: ${globalPct.toStringAsFixed(1)}% | Na Faixa: ${errRate.toStringAsFixed(1)}% | Dist. Erros: ${dist.toStringAsFixed(1)}% ($err/$count)';
                            }

                            return LineTooltipItem(
                              text,
                              TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 10),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    lineBarsData: allSeries,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: models.map((model) {
                  final color = modelColors[model] ?? Colors.grey;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        Container(width: 10, height: 6, decoration: BoxDecoration(color: color.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(1))),
                        const SizedBox(width: 4),
                        Container(width: 10, height: 2, color: color),
                        const SizedBox(width: 4),
                        Text(model, style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
