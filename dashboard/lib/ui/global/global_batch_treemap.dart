part of '../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// BATCH TREEMAP WIDGET & ANALYTICS
// Mapa hierárquico interativo de lotes com vista detalhada por lote.
// ═══════════════════════════════════════════════════════════

class TreemapTile {
  final Batch batch;
  final Rect rect;
  TreemapTile({required this.batch, required this.rect});
}

class _BatchTreemapWidget extends ConsumerStatefulWidget {
  final List<Batch> batches;
  const _BatchTreemapWidget({required this.batches});

  @override
  ConsumerState<_BatchTreemapWidget> createState() => _BatchTreemapWidgetState();
}

class _BatchTreemapWidgetState extends ConsumerState<_BatchTreemapWidget> {
  String _sizeCriteria = 'Volume'; // Volume, Risco, Idade
  String? _selectedBatchId;

  List<TreemapTile> _computeTreemapLayout(List<Batch> list, Rect rect, double Function(Batch) weightFn) {
    if (list.isEmpty) return [];
    if (list.length == 1) {
      return [TreemapTile(batch: list.first, rect: rect)];
    }
    final sorted = [...list]..sort((a, b) => weightFn(b).compareTo(weightFn(a)));
    List<TreemapTile> tiles = [];
    _partition(sorted, rect, weightFn, tiles);
    return tiles;
  }

  void _partition(List<Batch> list, Rect rect, double Function(Batch) weightFn, List<TreemapTile> result) {
    if (list.isEmpty) return;
    if (list.length == 1) {
      result.add(TreemapTile(batch: list.first, rect: rect));
      return;
    }
    double totalWeight = list.fold(0.0, (sum, b) => sum + weightFn(b));
    if (totalWeight == 0) totalWeight = list.length.toDouble();

    int splitIdx = 1;
    double accum = 0;
    double halfWeight = totalWeight / 2;
    for (int i = 0; i < list.length - 1; i++) {
      final w = weightFn(list[i]);
      accum += w == 0 ? 1.0 : w;
      if (accum >= halfWeight) {
        splitIdx = i + 1;
        break;
      }
    }

    final part1 = list.sublist(0, splitIdx);
    final part2 = list.sublist(splitIdx);

    double weight1 = part1.fold(0.0, (sum, b) => sum + weightFn(b));
    if (weight1 == 0) weight1 = part1.length.toDouble();

    final ratio = weight1 / totalWeight;

    if (rect.width >= rect.height) {
      final w1 = rect.width * ratio;
      final r1 = Rect.fromLTWH(rect.left, rect.top, w1, rect.height);
      final r2 = Rect.fromLTWH(rect.left + w1, rect.top, rect.width - w1, rect.height);
      _partition(part1, r1, weightFn, result);
      _partition(part2, r2, weightFn, result);
    } else {
      final h1 = rect.height * ratio;
      final r1 = Rect.fromLTWH(rect.left, rect.top, rect.width, h1);
      final r2 = Rect.fromLTWH(rect.left, rect.top + h1, rect.width, rect.height - h1);
      _partition(part1, r1, weightFn, result);
      _partition(part2, r2, weightFn, result);
    }
  }

  Map<String, dynamic> _getRealHistoryAndTrends(Batch b, String dateRange) {
    final int days = dateRange == '30d' ? 30 : 7;
    final now = DateTime.now();
    final List<Map<String, dynamic>> history = [];
    final List<double> sparklineData = [];

    final dist = b.healthDistribution;
    final overallHealthy = dist['Healthy'] ?? 0;
    final overallTotal = b.totalApples;
    final double fallbackHealth = overallTotal == 0 ? 100.0 : (overallHealthy / overallTotal * 100.0);

    double lastValidScore = fallbackHealth;

    for (int i = days - 1; i >= 0; i--) {
      final targetDate = now.subtract(Duration(days: i));

      final dayApples = b.apples.where((a) {
        return a.timestamp.year == targetDate.year &&
               a.timestamp.month == targetDate.month &&
               a.timestamp.day == targetDate.day;
      }).toList();

      double dayScore;
      if (dayApples.isEmpty) {
        dayScore = lastValidScore;
      } else {
        final healthyCount = dayApples.where((a) => a.cnn2Label == 'Healthy').length;
        dayScore = (healthyCount / dayApples.length) * 100.0;
        lastValidScore = dayScore;
      }
      sparklineData.add(dayScore);
    }

    if (days == 7) {
      final dayOffsets = [0, 1, 3, 6];
      final dayLabels = ['Hoje', 'Ontem', 'Há 3 dias', 'Há 6 dias'];
      for (int k = 0; k < dayOffsets.length; k++) {
        final idx = (days - 1) - dayOffsets[k];
        if (idx >= 0 && idx < sparklineData.length) {
          history.add({
            'day': dayLabels[k],
            'score': sparklineData[idx],
          });
        }
      }
    } else {
      final dayOffsets = [0, 1, 7, 14, 29];
      final dayLabels = ['Hoje', 'Ontem', 'Há 1 semana', 'Há 2 semanas', 'Há 1 mês'];
      for (int k = 0; k < dayOffsets.length; k++) {
        final idx = (days - 1) - dayOffsets[k];
        if (idx >= 0 && idx < sparklineData.length) {
          history.add({
            'day': dayLabels[k],
            'score': sparklineData[idx],
          });
        }
      }
    }

    final dominantEN = _getDominantDiseaseEN(b);
    final List<String> alerts = [];
    String? citation;

    if (dominantEN != 'Healthy' && b.urgencyScore > 0.15) {
      if (dominantEN == 'Rot') {
        alerts.add('Surto de Podridão: Isolar lote, higienizar caixas de colheita, manter armazenamento rigoroso a 0.5-1.5°C para abrandar propagação de esporos.');
        citation = 'Diretrizes de armazenamento e sanidade baseadas em: UC Davis Postharvest Technology Center & WSU Tree Fruit Research.';
      } else if (dominantEN == 'Scab') {
        alerts.add('Detetada Sarna: Para futuras colheitas deste talhão, aplicar pulverizações de Cálcio e Silício para fortalecer a epiderme. Arejar ramos (poda) e remover folhas caídas.');
        citation = 'Práticas de mitigação foliar suportadas por: Cornell University (CALS) e Penn State Extension.';
      } else if (dominantEN == 'Blotch') {
        alerts.add('Alerta de Sooty Blotch: Fator crítico de humidade detetado. Garantir secagem rápida pós-lavagem, reduzir humidade relativa na câmara e forçar ventilação de ar.');
        citation = 'Controlo ambiental de pós-colheita fundamentado por: Diretrizes FAO e Penn State Extension.';
      } else if (dominantEN == 'Anthracnose') {
        alerts.add('Risco de Antracnose: Foco fúngico ativo. Higienizar linhas de triagem com desinfetante ativo e planear tratamentos preventivos com cobre no pomar de origem.');
        citation = 'Protocolos de profilaxia hídrica baseados no: Pacific Northwest Plant Disease Management Handbook (OSU).';
      }
    } else {
      alerts.add('Lote estável. Elevado padrão de conformidade detetado.');
    }

    return {
      'history': history,
      'sparkline': sparklineData,
      'alerts': alerts,
      'citation': citation,
    };
  }

  String _getElapsedTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'Há ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Há ${diff.inHours}h';
    return 'Há ${diff.inDays}d';
  }

  Widget _criteriaPill(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : (AppColors.isDark ? Colors.white10 : Colors.black12),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTileContent(Batch b, bool showDetail, bool showMedium, Color stateBorderColor, Color stateBgColor) {
    final dist = b.healthDistribution;
    final healthy = dist['Healthy'] ?? 0;
    final total = b.totalApples;
    final approvalRate = total == 0 ? 100.0 : (healthy / total * 100.0);
    final dominantDisease = _getDominantDiseaseEN(b);

    Widget healthBar({double fontSize = 8.5, double barHeight = 4}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saúde',
            style: TextStyle(color: stateBorderColor, fontSize: fontSize, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    height: barHeight,
                    color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (approvalRate / 100.0).clamp(0.0, 1.0),
                      child: Container(color: stateBorderColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${approvalRate.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: stateBorderColor,
                  fontWeight: FontWeight.bold,
                  fontSize: fontSize,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.all(showDetail ? 8 : 4),
      decoration: BoxDecoration(
        color: stateBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: stateBorderColor, width: 1.5),
      ),
      child: ClipRect(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                b.id,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: showDetail ? 12 : (showMedium ? 10 : 9),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (showDetail) ...[
                const SizedBox(height: 4),
                Text(
                  'Quantidade: $total un',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Doença: $dominantDisease',
                  style: TextStyle(
                    color: AppColors.getColorForCondition(dominantDisease),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                healthBar(),
              ] else if (showMedium) ...[
                const SizedBox(height: 2),
                Text(
                  'Quantidade: $total un',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 8),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                healthBar(fontSize: 8, barHeight: 3),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getDominantDiseaseEN(Batch b) {
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

  String _getDominantDiseasePT(Batch b) {
    final dominantEN = _getDominantDiseaseEN(b);
    switch (dominantEN) {
      case 'Rot': return 'Podridão';
      case 'Scab': return 'Sarna';
      case 'Blotch': return 'Sooty Blotch';
      case 'Anthracnose': return 'Antracnose';
      default: return 'Nenhuma';
    }
  }

  Widget _buildMiniKpi(String title, String value, IconData icon, Color color, [String? sub]) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3.5,
                  color: color,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 8.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(icon, color: color, size: 12),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(value, style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                        if (sub != null) ...[
                          const SizedBox(height: 1),
                          Text(sub, style: TextStyle(color: AppColors.textSecondary.withOpacity(0.8), fontSize: 7.5), overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKpisSection(Batch b) {
    final dist = b.healthDistribution;
    final healthyCount = dist['Healthy'] ?? 0;
    final totalAnomalies = b.totalApples - healthyCount;
    final pendingCount = b.apples.where((a) => a.effectiveConfidence < 0.85).length;

    final dominantEN = _getDominantDiseaseEN(b);
    final dominantPT = _getDominantDiseasePT(b);
    final domCount = dist[dominantEN] ?? 0;

    return Column(
      children: [
        Row(
          children: [
            _buildMiniKpi('Total Inspecionado', '${b.totalApples}', Icons.scale, Colors.blueAccent),
            const SizedBox(width: 6),
            _buildMiniKpi('Doença Dominante', dominantPT, Icons.warning_amber, AppColors.getColorForCondition(dominantEN), '$domCount casos detetados'),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _buildMiniKpi('Total Anomalias', '$totalAnomalies', Icons.dangerous, totalAnomalies > 50 ? Colors.redAccent : totalAnomalies > 0 ? Colors.orangeAccent : AppColors.healthy, 'Patologias detetadas'),
            const SizedBox(width: 6),
            _buildMiniKpi('Em Revisão Humana', '$pendingCount', Icons.pending_actions, pendingCount > 0 ? Colors.amber : AppColors.healthy, pendingCount > 0 ? 'Aguardam validação' : 'Tudo validado'),
          ],
        ),
      ],
    );
  }

  Widget _buildCnnModelInfo(Batch b, double avgConf) {
    return Row(
      children: [
        Expanded(
          child: _modelSpecCard(
            'CNN2 (Filtro Binário)',
            'MobileNetV2',
            '98.2% Acc',
            '6ms latência',
            'Triagem Inicial',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _modelSpecCard(
            'CNN5 (Multiclasse)',
            'ResNet50',
            '94.5% Acc',
            '14ms latência',
            'Classificação Fina',
          ),
        ),
      ],
    );
  }

  Widget _modelSpecCard(String title, String model, String acc, String latency, String purpose) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.primary, fontSize: 8.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _specRow('Base:', model),
          _specRow('Precisão:', acc),
          _specRow('Latência:', latency),
          _specRow('Foco:', purpose),
        ],
      ),
    );
  }

  Widget _specRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 8)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 8, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathologyBars(Batch b) {
    final dist = b.healthDistribution;
    final total = b.totalApples;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05)),
      ),
      child: Column(
        children: ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'].map((cond) {
          final count = dist[cond] ?? 0;
          final pct = total == 0 ? 0.0 : (count / total * 100.0);
          final color = AppColors.getColorForCondition(cond);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  child: Text(
                    AppColors.displayName(cond),
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 8.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final double maxW = constraints.maxWidth;
                          return Container(
                            height: 6,
                            width: pct == 0 ? 0 : (pct / 100.0 * maxW),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${pct.toStringAsFixed(0)}% ($count)',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAlertsSection(List<dynamic> alerts, String? citation) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...alerts.map((alert) {
          final text = alert.toString();
          final isWarning = !text.contains('Lote estável');
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isWarning
                  ? const Color(0xffEF4444).withOpacity(0.08)
                  : const Color(0xff10B981).withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isWarning ? const Color(0xffEF4444).withOpacity(0.2) : const Color(0xff10B981).withOpacity(0.2),
                width: 0.5,
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isWarning ? const Color(0xffEF4444) : const Color(0xff10B981),
                fontSize: 8.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }).toList(),
        if (citation != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: Text(
              citation,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 7.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistorySection(Map<String, dynamic> realData) {
    final history = realData['history'] as List<dynamic>;
    final sparklineData = realData['sparkline'] as List<double>;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: history.map((h) {
                final day = h['day'] as String;
                final score = h['score'] as double;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(day, style: TextStyle(color: AppColors.textSecondary, fontSize: 8.5)),
                      Text('${score.toStringAsFixed(0)}% Saúde', style: TextStyle(color: AppColors.textPrimary, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: SparklinePainter(
                      data: sparklineData,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text('Tendência Temporal', style: TextStyle(color: AppColors.textSecondary, fontSize: 7)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedView(Batch b, Size size) {
    final dateRange = ref.watch(dateRangeFilterProvider);
    final mockData = _getRealHistoryAndTrends(b, dateRange);
    final total = b.totalApples;

    final avgConf = total == 0
        ? 0.0
        : b.apples.map((a) => a.effectiveConfidence).reduce((a, b) => a + b) / total;

    return Container(
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lote Analítico: ${b.id}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '📍 ${b.location} • Úl. Triagem: ${DateFormat('dd/MM HH:mm').format(b.date)} (${_getElapsedTime(b.date)})',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: b.isActive
                      ? const Color(0xff10B981).withOpacity(0.12)
                      : Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: b.isActive ? const Color(0xff10B981) : Colors.grey,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  b.isActive ? '🟢 ATIVO' : '⚪ ARQUIVADO',
                  style: TextStyle(
                    color: b.isActive ? const Color(0xff10B981) : AppColors.textSecondary,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 8, thickness: 0.5),
          const SizedBox(height: 6),

          // Scrollable Body
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Métricas Principais & Tendências',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildKpisSection(b),

                  const SizedBox(height: 10),

                  Text(
                    'Especificações do Modelo CNN',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildCnnModelInfo(b, avgConf),

                  const SizedBox(height: 10),

                  Text(
                    'Distribuição de Patologias',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildPathologyBars(b),

                  const SizedBox(height: 10),

                  if (mockData['alerts'].isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          'Alertas Operacionais',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Base de Conhecimento: Recomendações geradas a partir de protocolos agronómicos internacionais, incluindo diretrizes do UC Davis Postharvest Technology Center, Washington State University (WSU) e Cornell University (CALS).',
                          padding: const EdgeInsets.all(12),
                          textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
                          ),
                          child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildAlertsSection(mockData['alerts'], mockData['citation'] as String?),
                    const SizedBox(height: 10),
                  ],

                  Text(
                    'Histórico Recente de Triage',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildHistorySection(mockData),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),

          // Back Button Footer
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.withOpacity(0.12),
                foregroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
              ),
              onPressed: () {
                setState(() {
                  _selectedBatchId = null;
                });
              },
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Voltar ao Treemap', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final batches = widget.batches;
    if (batches.isEmpty) {
      return const Center(child: Text('Sem lotes ativos.'));
    }

    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final tiles = _computeTreemap(batches, size);
      final isAnySelected = _selectedBatchId != null;

      return Stack(
        children: [
          // Header Controls (hides when expanded)
          if (!isAnySelected)
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: 40,
              child: Row(
                children: [
                  Text('Métrica do Tamanho: ', style: TextStyle(fontSize: 9.5, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  _criteriaPill('Volume 📦', _sizeCriteria == 'Volume', () => setState(() => _sizeCriteria = 'Volume')),
                  const SizedBox(width: 4),
                  _criteriaPill('Urgência ⚠️', _sizeCriteria == 'Risco', () => setState(() => _sizeCriteria = 'Risco')),
                  const SizedBox(width: 4),
                  _criteriaPill('Recente 🕒', _sizeCriteria == 'Idade', () => setState(() => _sizeCriteria = 'Idade')),
                ],
              ),
            ),

          // Render tiles using AnimatedPositioned
          for (final tile in tiles) ...[
            () {
              final b = tile.batch;
              final rect = tile.rect;
              final isSelected = b.id == _selectedBatchId;

              // Decide state colors
              final dist = b.healthDistribution;
              final healthy = dist['Healthy'] ?? 0;
              final total = b.totalApples;
              final approvalRate = total == 0 ? 100.0 : (healthy / total * 100.0);

              Color stateBorderColor;
              Color stateBgColor;
              if (total == 0) {
                stateBorderColor = AppColors.isDark ? const Color(0xff9CA3AF) : const Color(0xff6B7280);
                stateBgColor = stateBorderColor.withOpacity(0.08);
              } else if (approvalRate < 58.0 || b.urgencyScore > 0.5) {
                stateBorderColor = const Color(0xffEF4444); // Red
                stateBgColor = stateBorderColor.withOpacity(0.08);
              } else if (approvalRate < 70.0 || b.urgencyScore > 0.3) {
                stateBorderColor = const Color(0xffF59E0B); // Amber/Yellow
                stateBgColor = stateBorderColor.withOpacity(0.08);
              } else {
                stateBorderColor = const Color(0xff10B981); // Emerald/Green
                stateBgColor = stateBorderColor.withOpacity(0.08);
              }

              // Calculate target dimensions
              final targetLeft = isSelected ? 0.0 : (isAnySelected ? rect.left : rect.left);
              final targetTop = isSelected ? 0.0 : (isAnySelected ? rect.top : rect.top);
              final targetWidth = isSelected ? size.width : (isAnySelected ? 0.0 : rect.width);
              final targetHeight = isSelected ? size.height : (isAnySelected ? 0.0 : rect.height);
              final targetOpacity = isSelected ? 1.0 : (isAnySelected ? 0.0 : 1.0);

              final showDetail = rect.width > 90 && rect.height > 65;
              final showMedium = rect.width > 60 && rect.height > 40;

              return AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                left: targetLeft,
                top: targetTop,
                width: targetWidth,
                height: targetHeight,
                child: IgnorePointer(
                  ignoring: isAnySelected && !isSelected,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: targetOpacity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: GestureDetector(
                        onTap: () {
                          if (!isAnySelected) {
                            setState(() {
                              _selectedBatchId = b.id;
                            });
                          }
                        },
                        child: isSelected
                            ? _buildDetailedView(b, size)
                            : _buildTileContent(b, showDetail, showMedium, stateBorderColor, stateBgColor),
                      ),
                    ),
                  ),
                ),
              );
            }()
          ]
        ],
      );
    });
  }

  List<TreemapTile> _computeTreemap(List<Batch> list, Size size) {
    if (list.isEmpty) return [];
    double Function(Batch) weightFn;
    if (_sizeCriteria == 'Risco') {
      weightFn = (b) => b.urgencyScore * 100.0 + 1.0;
    } else if (_sizeCriteria == 'Idade') {
      weightFn = (b) => (DateTime.now().difference(b.date).inMinutes.toDouble() / 60.0).clamp(1.0, 100.0);
    } else {
      weightFn = (b) => b.totalApples.toDouble() + 1.0;
    }
    final topOffset = _selectedBatchId != null ? 0.0 : 45.0;
    final h = size.height - topOffset;
    final rect = Rect.fromLTWH(0, topOffset, size.width, h > 0 ? h : 1.0);
    return _computeTreemapLayout(list, rect, weightFn);
  }
}
