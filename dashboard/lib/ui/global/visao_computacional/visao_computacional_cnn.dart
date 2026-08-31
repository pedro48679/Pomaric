part of '../../global_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// VISÃO COMPUTACIONAL · CNN
// Evolução CNN2/CNN5 e pipeline, calibração por faixa de confiança e os helpers de confiança por lote que os alimentam.
// ═══════════════════════════════════════════════════════════

extension _VisaoComputacionalCnn on _GlobalDashboardState {
  double _bConf(Batch b) {
    if (b.apples.isEmpty) return 0;
    double s = 0;
    for (final a in b.apples) {
      s += a.effectiveConfidence;
    }
    return s / b.apples.length * 100;
  }

  // Cada maçã tem várias linhas em cnn_predictions por modelo (uma por frame:
  // original + rotações), mas só uma delas, a do "pior frame", é a que o
  // pipeline usa de facto como diagnóstico oficial (gera a miniatura, o
  // Grad-CAM e o final_confidence gravado em producao_atual). Usar a média
  // das 3 misturaria vistas rotacionadas que nunca foram a decisão real: na
  // CNN2 o pior frame é o de MENOR confiança de saudável (seleção
  // conservadora), na CNN5 é o de MAIOR confiança de doença (deteção mais
  // forte), por isso a média inflacionava a CNN2 e diluía a CNN5.
  double _bConfForModel(Batch b, String modelName) {
    double s = 0.0;
    int valid = 0;
    for (final a in b.apples) {
      final matches = a.cnnPredictions.where((p) => p['model_name'] == modelName).toList();
      if (matches.isEmpty) continue;
      final wfId = a.worstFrame?.id;
      final pred = matches.firstWhere(
        (p) => p['frame_id'] == wfId,
        orElse: () => matches.first,
      );
      final raw = (pred['confidence'] as num?)?.toDouble();
      if (raw == null || raw <= 0) continue;
      s += raw > 1.0 ? raw : raw * 100.0;
      valid++;
    }
    if (valid == 0) return 0.0;
    return s / valid;
  }

  double _bConfCNN2(Batch b) => _bConfForModel(b, 'CNN2');
  double _bConfCNN5(Batch b) => _bConfForModel(b, 'CNN5');

  double _bConfPipeline(Batch b) {
    double s = 0.0;
    int valid = 0;
    for (final a in b.apples) {
      final wfId = a.worstFrame?.id;
      final c2Matches = a.cnnPredictions.where((p) => p['model_name'] == 'CNN2').toList();
      final c5Matches = a.cnnPredictions.where((p) => p['model_name'] == 'CNN5').toList();
      
      double? c5Conf;
      if (c5Matches.isNotEmpty) {
        final pred = c5Matches.firstWhere((p) => p['frame_id'] == wfId, orElse: () => c5Matches.first);
        final raw = (pred['confidence'] as num?)?.toDouble();
        if (raw != null && raw > 0) c5Conf = raw > 1.0 ? raw : raw * 100.0;
      }
      
      double? c2Conf;
      if (c2Matches.isNotEmpty) {
        final pred = c2Matches.firstWhere((p) => p['frame_id'] == wfId, orElse: () => c2Matches.first);
        final raw = (pred['confidence'] as num?)?.toDouble();
        if (raw != null && raw > 0) c2Conf = raw > 1.0 ? raw : raw * 100.0;
      }

      if (c5Conf != null) {
        s += c5Conf;
        valid++;
      } else if (c2Conf != null) {
        s += c2Conf;
        valid++;
      } else if (a.effectiveConfidence > 0) {
        final fallback = a.effectiveConfidence > 1.0 ? a.effectiveConfidence : a.effectiveConfidence * 100.0;
        s += fallback;
        valid++;
      }
    }
    if (valid == 0) return 0.0;
    return s / valid;
  }



  // ═══ CNN EVOLUTION ═══
  // ═══ 4.C (Face A) · EVOLUÇÃO CNN2/CNN5 + PIPELINE ═══
  Widget _cnnEvolutionPlus(List<Batch> batches, AsyncValue<List<Map<String, dynamic>>> reviewsAsync) {
    final cs = <FlSpot>[];
    final as = <FlSpot>[];
    final ps = <FlSpot>[];
    
    for (int i = 0; i < batches.length; i++) {
      final b = batches[i];
      final c2Val = _bConfCNN2(b);
      cs.add(FlSpot(i.toDouble(), c2Val > 0 ? c2Val : _bConf(b)));
      
      final c5Val = _bConfCNN5(b);
      as.add(FlSpot(i.toDouble(), c5Val > 0 ? c5Val : _bConf(b)));

      final pVal = _bConfPipeline(b);
      ps.add(FlSpot(i.toDouble(), pVal > 0 ? pVal : _bConf(b)));
    }

    double minVal = 100.0, maxVal = 0.0;
    for (final spot in [...cs, ...as, ...ps]) {
      if (spot.y < minVal) minVal = spot.y;
      if (spot.y > maxVal) maxVal = spot.y;
    }
    final double dynamicMinY = (minVal - 5.0).clamp(0.0, 95.0);
    final double dynamicMaxY = (maxVal + 5.0).clamp(5.0, 100.0);

    Widget legendSwatch(String label, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 3, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
        ]);

    return _card(
      'Evolução & Deriva do Modelo',
      'Confiança CNN2 / CNN5 vs Confiança Final da Pipeline',
      380,
      tooltip: 'Linha ciano = confiança do gatekeeper CNN2.\n\n'
          'Linha tracejada laranja = confiança do modelo profundo CNN5.\n\n'
          'Linha de destaque = Confiança Final da Pipeline (combinação real usada na decisão de cada maçã).',
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
                    color: Colors.cyanAccent.withOpacity(0.6),
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: as,
                    isCurved: true,
                    color: Colors.orangeAccent.withOpacity(0.6),
                    barWidth: 2,
                    dashArray: [4, 4],
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: ps,
                    isCurved: true,
                    color: AppColors.textPrimary,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: AppColors.textPrimary.withOpacity(0.05)),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
                    getTooltipItems: (s) => s.map((sp) {
                      final i = sp.x.toInt();
                      final b = batches[i];
                      final labels = ['Confiança CNN2', 'Confiança CNN5', 'Confiança Pipeline'];
                      final colors = [Colors.cyanAccent, Colors.orangeAccent, AppColors.textPrimary];
                      final idx = sp.barIndex.clamp(0, 2);
                      return LineTooltipItem(
                        '${b.id}\n${labels[idx]}: ${sp.y.toStringAsFixed(1)}%',
                        TextStyle(color: colors[idx], fontSize: 11),
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
              legendSwatch('CNN2', Colors.cyanAccent.withOpacity(0.6)),
              const SizedBox(width: 18),
              legendSwatch('CNN5', Colors.orangeAccent.withOpacity(0.6)),
              const SizedBox(width: 18),
              legendSwatch('Pipeline Final', AppColors.textPrimary),
            ],
          ),
        ],
      ),
    );
  }

  // ═══ 4.C (Face B) · CALIBRAÇÃO POR FAIXA DE CONFIANÇA ═══
  // Substitui o _pipelineCalibrationChart: calculada exclusivamente de
  // manual_review (validações humanas), sem decomposição por modelo, a
  // fonte dos erros de dados do cartão antigo. Barras = nº de validações
  // por faixa de confiança declarada; linha = % de erro real na faixa.
  Widget _calibrationByBand(AsyncValue<List<Map<String, dynamic>>> reviewsAsync) {
    const bandLabels = ['<60%', '60-70%', '70-80%', '80-90%', '90%+'];
    const title = 'Calibração por Faixa de Confiança';
    const sub = 'Reliability diagram: confiança declarada vs. precisão real por faixa · linha tracejada = ECE';

    final rows = reviewsAsync.value ?? const <Map<String, dynamic>>[];
    final volume = List<int>.filled(5, 0);
    final wrong = List<int>.filled(5, 0);
    final confSum = List<double>.filled(5, 0.0);
    for (final r in rows) {
      if (r['status'] != 'completed' || r['corrected_class'] == null || r['original_class'] == null) continue;
      final raw = (r['original_confidence'] as num?)?.toDouble() ?? 0.0;
      final conf = (raw > 1.0 ? raw / 100.0 : raw).clamp(0.0, 1.0);
      final band = conf < 0.60 ? 0 : conf < 0.70 ? 1 : conf < 0.80 ? 2 : conf < 0.90 ? 3 : 4;
      volume[band]++;
      confSum[band] += conf;
      if (r['corrected_class'] != r['original_class']) wrong[band]++;
    }
    final totalReviews = volume.fold<int>(0, (s, v) => s + v);

    if (totalReviews == 0) {
      return _card(title, sub, 380,
          Center(child: Text('Sem validações humanas concluídas no período',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12))));
    }

    // Confiança média declarada e ECE (Expected Calibration Error) por faixa:
    // |precisão real − confiança declarada|, ponderado pelo volume da faixa -
    // mede a distância entre o que o modelo diz e o que de facto acontece.
    final avgConf = List<double>.generate(5, (i) => volume[i] == 0 ? 0.0 : confSum[i] / volume[i]);
    final accuracy = List<double>.generate(5, (i) => volume[i] == 0 ? 0.0 : 1 - wrong[i] / volume[i]);
    double ece = 0.0;
    for (int i = 0; i < 5; i++) {
      if (volume[i] == 0) continue;
      ece += (volume[i] / totalReviews) * (accuracy[i] - avgConf[i]).abs();
    }

    final maxVol = volume.reduce(max).toDouble() * 1.2;
    const int n = 5;

    // Camada base (LineChart): faixa de erro + limiar 80% + eixo direito.
    final lineLayer = LineChart(
      LineChartData(
        minX: -0.5,
        maxX: n - 0.5,
        minY: 0,
        maxY: 100,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(verticalLines: [
          VerticalLine(
            x: 2.5, // fronteira entre 70-80% e 80-90% = limiar de aceitação
            color: AppColors.primary.withOpacity(0.6),
            strokeWidth: 1.2,
            dashArray: [6, 4],
            label: VerticalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold),
              labelResolver: (_) => 'limiar 80%',
            ),
          ),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          // Reserva simétrica com a camada de barras (widgets vazios).
          leftTitles: AxisTitles(
            axisNameWidget: const SizedBox.shrink(),
            axisNameSize: 14,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) => const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) => const SizedBox.shrink(),
            ),
          ),
          rightTitles: AxisTitles(
            axisNameWidget: Text('% erro', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
            axisNameSize: 14,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 25,
              getTitlesWidget: (v, _) =>
                  Text('${v.toInt()}%', style: TextStyle(color: AppColors.textSecondary, fontSize: 8)),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < n; i++)
                FlSpot(i.toDouble(), volume[i] == 0 ? 0 : wrong[i] / volume[i] * 100),
            ],
            isCurved: false,
            barWidth: 2.2,
            color: Colors.redAccent,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, i) => FlDotCirclePainter(
                radius: 3.4,
                color: Colors.redAccent,
                strokeWidth: 1,
                strokeColor: AppColors.background,
              ),
            ),
          ),
          // Confiança média declarada por faixa (0-100%, mesmo eixo direito da
          // taxa de erro), a distância vertical entre esta linha e a precisão
          // real da faixa é o que o ECE resume num único número.
          LineChartBarData(
            spots: [
              for (int i = 0; i < n; i++) FlSpot(i.toDouble(), avgConf[i] * 100),
            ],
            isCurved: false,
            barWidth: 2,
            dashArray: [5, 4],
            color: AppColors.primary,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, i) => FlDotCirclePainter(
                radius: 3,
                color: AppColors.primary,
                strokeWidth: 1,
                strokeColor: AppColors.background,
              ),
            ),
          ),
        ],
      ),
    );

    // Camada de barras (volume de validações), spaceAround alinha os centros
    // dos grupos com os x inteiros da camada de linha.
    final barLayer = BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: maxVol,
        barGroups: [
          for (int i = 0; i < n; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: volume[i].toDouble(),
                width: 26,
                color: (i >= 3 ? AppColors.healthy : Colors.amber).withOpacity(0.35),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ]),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppColors.textSecondary.withOpacity(0.12), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          // Reserva simétrica com a camada de linha (eixo direito vazio).
          rightTitles: AxisTitles(
            axisNameWidget: const SizedBox.shrink(),
            axisNameSize: 14,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, _) => const SizedBox.shrink(),
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget:
                Text('nº validações', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
            axisNameSize: 14,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) =>
                  Text(v.toInt().toString(), style: TextStyle(color: AppColors.textSecondary, fontSize: 8)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) {
                final i = v.round();
                if (i < 0 || i >= n) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(bandLabels[i],
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface.withOpacity(0.95),
            getTooltipItem: (group, gi, rod, ri) {
              final i = group.x;
              final errPct = volume[i] == 0 ? 0.0 : wrong[i] / volume[i] * 100;
              final globalErr = totalReviews == 0
                  ? 0.0
                  : wrong.fold<int>(0, (s, v) => s + v) / totalReviews * 100;
              return BarTooltipItem(
                'Faixa ${bandLabels[i]}\n${volume[i]} validações\n'
                'Precisão real: ${(accuracy[i] * 100).toStringAsFixed(1)}%\n'
                'Confiança média declarada: ${(avgConf[i] * 100).toStringAsFixed(1)}%\n'
                'Erro na faixa: ${errPct.toStringAsFixed(1)}%\nErro global: ${globalErr.toStringAsFixed(1)}%',
                TextStyle(color: AppColors.textPrimary, fontSize: 10, height: 1.4),
              );
            },
          ),
        ),
      ),
    );

    return _card(
      title,
      sub,
      380,
      tooltip: 'Reliability diagram: responde a "quando o modelo declara X% de confiança, com que '
          'frequência acerta de facto?", quanto mais perto a linha ciano (confiança declarada) estiver '
          'da precisão real de cada faixa, melhor calibrado está o modelo.\n\n'
          'ECE (Expected Calibration Error): média ponderada da diferença absoluta entre precisão real e '
          'confiança declarada por faixa, 0% seria calibração perfeita.\n\n'
          'Fonte: exclusivamente validações humanas concluídas (manual_review).\n'
          'A linha vertical marca o limiar de aceitação automática (80%): a taxa de erro '
          'à direita do limiar deve ser residual, caso contrário, o corte deve subir.',
      Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Confiança declarada vs. precisão real', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (ece > 0.10 ? Colors.redAccent : (ece > 0.05 ? Colors.amber : AppColors.healthy)).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (ece > 0.10 ? Colors.redAccent : (ece > 0.05 ? Colors.amber : AppColors.healthy)).withOpacity(0.4)),
                ),
                child: Text('ECE: ${(ece * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                        color: ece > 0.10 ? Colors.redAccent : (ece > 0.05 ? Colors.amber : AppColors.healthy),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(child: Stack(children: [barLayer, lineLayer])),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: AppColors.healthy.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 5),
              Text('Volume (≥80%)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
              const SizedBox(width: 14),
              Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 5),
              Text('Volume (<80%)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
              const SizedBox(width: 14),
              Container(width: 12, height: 2.5, color: Colors.redAccent),
              const SizedBox(width: 5),
              Text('Taxa de erro', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
              const SizedBox(width: 14),
              Container(width: 12, height: 2.5, color: AppColors.primary),
              const SizedBox(width: 5),
              Text('Confiança declarada', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
            ],
          ),
        ],
      ),
    );
  }

}
