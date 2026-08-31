import 'package:flutter/material.dart';
import '../../../utils/constants.dart';
import '../mlops_models.dart';
import '../mlops_painters.dart';

class MlopsStatusPanel extends StatelessWidget {
  final TrainingStatus status;
  final String liveMetric;
  final ValueChanged<String> onLiveMetricChanged;
  final ScrollController statusPanelScroll;
  final ScrollController logScroll;
  final VoidCallback onShowModelsHistory;
  final VoidCallback? onSkipEpoch;

  const MlopsStatusPanel({
    super.key,
    required this.status,
    required this.liveMetric,
    required this.onLiveMetricChanged,
    required this.statusPanelScroll,
    required this.logScroll,
    required this.onShowModelsHistory,
    this.onSkipEpoch,
  });

  static const List<({String label, String key, bool hasTrain, bool isLoss})> liveMetrics = [
    (label: 'Accuracy', key: 'acc', hasTrain: true, isLoss: false),
    (label: 'Loss', key: 'loss', hasTrain: false, isLoss: true),
    (label: 'F1', key: 'f1', hasTrain: false, isLoss: false),
    (label: 'Precisão', key: 'precision', hasTrain: false, isLoss: false),
    (label: 'Recall', key: 'recall', hasTrain: false, isLoss: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress card (sempre visível quando activo ou recentemente
        // terminado). Scrollable com barra visível: com o gráfico live de
        // épocas o cartão pode exceder a altura disponível do painel.
        if (status.state != 'idle')
          Expanded(
            child: Scrollbar(
              controller: statusPanelScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: statusPanelScroll,
                padding: const EdgeInsets.only(right: 10),
                child: _buildProgressCard(context),
              ),
            ),
          )
        else
          const Spacer(),

        const SizedBox(height: 10),

        Align(
          alignment: Alignment.bottomRight,
          child: ElevatedButton.icon(
            icon: Icon(Icons.history, color: AppColors.background),
            label: Text('Ver Modelos Guardados',
                style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onShowModelsHistory,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    Color stateColor;
    String stateLabel;
    switch (status.state) {
      case 'downloading':
        stateColor = Colors.blue;
        stateLabel = 'A descarregar imagens';
        break;
      case 'augmenting':
        stateColor = Colors.cyan;
        stateLabel = 'A balancear classes';
        break;
      case 'training':
        stateColor = AppColors.primary;
        stateLabel = 'A treinar';
        break;
      case 'saving':
        stateColor = Colors.green;
        stateLabel = 'A guardar modelo';
        break;
      case 'done':
        stateColor = Colors.green;
        stateLabel = 'Concluído';
        break;
      case 'error':
        stateColor = Colors.red;
        stateLabel = 'Erro';
        break;
      case 'cancelled':
        stateColor = Colors.orange;
        stateLabel = 'Cancelado';
        break;
      default:
        stateColor = AppColors.textSecondary;
        stateLabel = 'Idle';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: stateColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(stateLabel,
                    style: TextStyle(
                        color: stateColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
              const Spacer(),
              if (onSkipEpoch != null && status.isActive && status.epochs > 0)
                IconButton(
                  icon: Icon(Icons.fast_forward, color: AppColors.primary, size: 20),
                  onPressed: onSkipEpoch,
                  tooltip: 'Avançar Época',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              if (onSkipEpoch != null && status.isActive && status.epochs > 0)
                const SizedBox(width: 8),
              if (status.isActive && status.epochs > 0)
                Text(
                    'Época ${status.epoch}/${status.epochs}',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),

          // Métricas principais (pills)
          if (status.state == 'training' || status.state == 'done') ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _statusMetricPill('Acc Val', '${status.valAcc.toStringAsFixed(1)}%', Colors.green),
                _statusMetricPill('Acc Tr', '${status.trainAcc.toStringAsFixed(1)}%', AppColors.textSecondary),
                _statusMetricPill('F1', '${status.f1.toStringAsFixed(1)}%', AppColors.primary),
                _statusMetricPill('Prec', '${status.precision.toStringAsFixed(1)}%', Colors.cyan),
                _statusMetricPill('Recall', '${status.recall.toStringAsFixed(1)}%', Colors.amber),
                if (status.loss > 0)
                  _statusMetricPill('Loss', status.loss.toStringAsFixed(4), Colors.orange),
            ],
            ),
            const SizedBox(height: 10),
          ],

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: status.progress / 100.0,
              backgroundColor: AppColors.textSecondary.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(stateColor),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(status.message,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 10),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${status.progress}%',
                  style: TextStyle(
                      color: stateColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ],
          ),

          // Métricas por classe (F1 / Precision / Recall, barras horizontais)
          if (status.perClassF1.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildPerClassMetricBars(
              label: 'F1 por classe',
              data: status.perClassF1,
              color: (cls) => AppColors.getColorForCondition(cls),
            ),
            if (status.perClassPrecision.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildPerClassMetricBars(
                label: 'Precisão por classe',
                data: status.perClassPrecision,
                color: (cls) => AppColors.getColorForCondition(cls),
              ),
            ],
            if (status.perClassRecall.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildPerClassMetricBars(
                label: 'Recall por classe',
                data: status.perClassRecall,
                color: (cls) => AppColors.getColorForCondition(cls),
              ),
            ],
          ],

          // Gráfico live de épocas
          if (status.history.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildLiveTrainingChart(),
          ],

          if (status.logs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('Ver log completo (${status.logs.length} linhas)',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                children: [
                  Container(
                    height: 130,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ListView.builder(
                      controller: logScroll,
                      padding: const EdgeInsets.all(6),
                      itemCount: status.logs.length,
                      itemBuilder: (ctx, i) {
                        final log = status.logs[i] as Map<String, dynamic>;
                        return Text(
                          '[${log['time']}] ${log['msg']}',
                          style: TextStyle(
                              color: AppColors.textSecondary.withOpacity(0.8),
                              fontSize: 9,
                              fontFamily: 'monospace'),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPerClassMetricBars({
    required String label,
    required Map<String, double> data,
    required Color Function(String cls) color,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...data.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(children: [
                  SizedBox(
                    width: 80,
                    child: Text(e.key,
                        style: TextStyle(
                            color: color(e.key),
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: e.value / 100.0,
                        backgroundColor: AppColors.textSecondary.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(color(e.key)),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 35,
                    child: Text('${e.value.toStringAsFixed(1)}%',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600),
                        textAlign: TextAlign.right),
                  ),
                ]),
              )),
        ],
      );

  Widget _statusMetricPill(String label, String value, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceBright.withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                const SizedBox(width: 4),
                Text(label.toUpperCase(),
                    style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _buildLiveTrainingChart() {
    final history = status.history;
    final sel = liveMetrics.firstWhere((m) => m.key == liveMetric, orElse: () => liveMetrics.first);

    List<Map<String, dynamic>> series(String key) =>
        [for (final e in history) {'m': (e[key] as num?)?.toDouble() ?? 0.0}];

    final List<Map<String, dynamic>> histA;
    final List<Map<String, dynamic>> histB;
    final String legendA;
    final String legendB;
    if (sel.key == 'acc') {
      histA = series('train_acc');
      histB = series('val_acc');
      legendA = 'Treino';
      legendB = 'Validação';
    } else {
      histA = series(sel.key);
      histB = const [];
      legendA = sel.isLoss ? 'Loss (treino)' : '${sel.label} (validação)';
      legendB = '';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Evolução por Época',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(),
              for (final m in liveMetrics)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => onLiveMetricChanged(m.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: liveMetric == m.key ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: liveMetric == m.key ? AppColors.primary : AppColors.glassBorder),
                      ),
                      child: Text(m.label,
                          style: TextStyle(
                              color: liveMetric == m.key ? AppColors.primary : AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: CustomPaint(
              painter: MetricCurvePainter(
                histA,
                histB,
                'm',
                colorA: AppColors.primary,
                colorB: Colors.orangeAccent,
                dynamicY: sel.isLoss,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(width: 10, height: 3, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(legendA, style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              if (legendB.isNotEmpty) ...[
                const SizedBox(width: 14),
                Container(width: 10, height: 3, color: Colors.orangeAccent),
                const SizedBox(width: 4),
                Text(legendB, style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              ],
              const Spacer(),
              Text('Época ${history.length}${status.epochs > 0 ? ' / ${status.epochs}' : ''}',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
