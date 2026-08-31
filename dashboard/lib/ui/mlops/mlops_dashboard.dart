
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/constants.dart';
import '../../services/supabase_service.dart';
import '../../services/app_settings_service.dart';
import '../charts_v2/_chart_kit.dart' show hoverTooltipOverlay;
import '../../widgets/hybrid_image.dart';
import 'mlops_models.dart';
import 'mlops_painters.dart';
import 'treino/mlops_config_panel.dart';
import 'treino/mlops_status_panel.dart';

// Este ficheiro é a biblioteca; os painéis de cada separador e a camada
// de rede vivem em part files. `part of` + extension em vez de widgets
// separados porque tudo isto lê e escreve campos privados do estado
// (_compareA, _shadowState, _status, ...) e chama setState directamente.
part 'mlops_data_loaders.dart';
part 'mlops_actions.dart';
part 'compara/mlops_compare_panel.dart';
part 'compara/mlops_compare_charts.dart';
part 'sombra/mlops_shadow_panel.dart';
part 'sombra/mlops_shadow_charts.dart';

class MlopsPage extends ConsumerStatefulWidget {
  const MlopsPage({super.key});

  @override
  MlopsPageState createState() => MlopsPageState();
}

class MlopsPageState extends ConsumerState<MlopsPage> {
  List<ClassInfo> _classes = [];
  List<ModelInfo> _models = [];
  TrainingStatus _status = const TrainingStatus();
  bool _serverOnline = false;
  bool _loading = true;
  bool _isReplaying = false; // Impede que o _pollTimer apague o estado do replay
  Completer<void>? _replayDelayCompleter;

  void _skipReplayEpoch() {
    if (_replayDelayCompleter != null && !_replayDelayCompleter!.isCompleted) {
      _replayDelayCompleter!.complete();
    }
  }

  // Config
  Set<String> _selectedClasses = {};
  Set<String> _selectedDiseases = {}; // CNN2: which diseases are included in "Unhealthy"
  String _architecture = 'resnet50';
  int _epochs = 50;
  double _hardThreshold = 0.75;
  int _minImages = 20;
  int _maxImages = 2000;
  int _batchSize = 16;
  double _lr = 0.00001; // 1e-5 (CNN5 Multiclasse)
  bool _isBinary = false;

  // Comparação de modelos
  int _tabIndex = 0;        // 0 = Treinar, 1 = Comparar, 2 = Shadow
  String? _compareA;
  String? _compareB;
  Map<String, dynamic> _compareResult = {};
  bool _loadingCompare = false;
  String _compareMetric = 'val_acc'; // val_acc | f1 | precision | recall
  String _compareChartMode = 'epoch'; // epoch | discrimination
  bool _discriminationIsRoc = true; // dentro do modo 'discrimination': ROC (default) ou PR
  String? _curveClassFilter; // null = todas as classes sobrepostas
  String? _errMatrixHovered; // classe verdadeira em hover na matriz de erros A/B
  Offset? _errMatrixHoverPos;

  // Shadow
  Map<String, dynamic> _shadowState = {};
  List<Map<String, dynamic>> _shadowHistory = [];
  int _shadowPromoteAfter = 1000;

  // Publicar no Raspberry (export ONNX + scp)
  bool _publishing = false;

  Timer? _pollTimer;
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logScroll.dispose();
    _statusPanelScroll.dispose();
    super.dispose();
  }

  /// true enquanto um _pollStatus está a decorrer, o Timer.periodic de 2s
  /// não espera pelo anterior, e o backend (HTTPServer) serve 1 pedido de
  /// cada vez: sem este guard, polls lentos empilhavam-se e o badge
  /// "online" piscava durante treinos/demos.
  bool _polling = false;

  @override
  Widget build(BuildContext context) {
    final totalImages = _classes.fold(0, (s, c) => s + c.count);
    final totalGold = _classes.fold(0, (s, c) => s + c.gold);
    
    // Filtrar os modelos com base no modo atual (Binário vs Multiclasse)
    final bestModels = _models.where((m) => _isBinary ? m.classes.length == 2 : m.classes.length > 2).toList();
    final bestAcc = bestModels.isNotEmpty
        ? bestModels.map((m) => m.valAccuracy).reduce((a, b) => a > b ? a : b)
        : 0.0;
        
    final activeClasses = _classes.where((c) => c.count >= _minImages).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (SupabaseService.isMockMode)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Modo Demonstração (Mock Mode) ativo. A Dashboard não conseguiu conectar à Base de Dados. A página MLOps apresenta apenas dados estáticos simulados.',
                      style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          // Header
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MLOps & Ciclo de Vida da IA',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  Text('Treino de CNN com dados do Supabase',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
              const Spacer(),
              // Indicador servidor
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (_serverOnline ? Colors.green : Colors.red)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (_serverOnline ? Colors.green : Colors.red)
                          .withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _serverOnline ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _serverOnline ? 'MLOps Online' : 'Servidor Offline',
                      style: TextStyle(
                          color: _serverOnline ? Colors.green : Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.refresh, color: AppColors.textSecondary, size: 18),
                onPressed: _refresh,
                tooltip: 'Atualizar',
              ),
            ],
          ),
          const SizedBox(height: 14),

          // KPIs
          Row(
            children: [
              _kpi('Total Imagens', totalImages.toString(), Icons.photo_library_outlined, AppColors.primary),
              const SizedBox(width: 10),
              _kpi('Classes Ativas', activeClasses.toString(), Icons.category_outlined, AppColors.accent),
              const SizedBox(width: 10),
              _kpi('Triadas (Ouro)', totalGold.toString(), Icons.verified_outlined, Colors.amber),
              const SizedBox(width: 10),
              _kpi(_isBinary ? 'Melhor Binário' : 'Melhor Multi', bestAcc > 0 ? '${bestAcc.toStringAsFixed(1)}%' : 'n/d',
                  Icons.emoji_events_outlined, Colors.purpleAccent),
            ],
          ),
          const SizedBox(height: 14),

          if (!_serverOnline && !_loading)
            _offlineBanner()
          else ...[
            // Tab bar
            Row(
              children: [
                _tabBtn('Treinar', 0, Icons.model_training),
                const SizedBox(width: 8),
                _tabBtn('Comparar', 1, Icons.compare_arrows),
                const SizedBox(width: 8),
                _tabBtn('Shadow CNN', 2, Icons.visibility_outlined),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _tabIndex == 0
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 260,
                          child: MlopsConfigPanel(
                            parentContext: context,
                            classes: _classes,
                            selectedClasses: _selectedClasses,
                            selectedDiseases: _selectedDiseases,
                            isBinary: _isBinary,
                            epochs: _epochs,
                            hardThreshold: _hardThreshold,
                            minImages: _minImages,
                            maxImages: _maxImages,
                            batchSize: _batchSize,
                            lr: _lr,
                            status: _status,
                            serverOnline: _serverOnline,
                            architecture: _architecture,
                            onSelectedClassesChanged: (val) => setState(() => _selectedClasses = val),
                            onSelectedDiseasesChanged: (val) => setState(() => _selectedDiseases = val),
                            onSelectCnn2: () => setState(() {
                              _isBinary = true;
                              _batchSize = 32;
                              _epochs = 35;
                              _lr = 0.0001; // 1e-4
                              _selectedClasses = _classes.map((c) => c.name).toSet();
                            }),
                            onSelectCnn5: () => setState(() {
                              _isBinary = false;
                              _batchSize = 16;
                              _epochs = 50;
                              _lr = 0.00001; // 1e-5
                              if (_selectedClasses.isEmpty) {
                                _selectedClasses = _classes.map((c) => c.name).toSet();
                              }
                            }),
                            onArchitectureChanged: (val) => setState(() => _architecture = val),
                            onEpochsChanged: (val) => setState(() => _epochs = val),
                            onHardThresholdChanged: (val) => setState(() => _hardThreshold = val),
                            onMinImagesChanged: (val) => setState(() => _minImages = val),
                            onMaxImagesChanged: (val) => setState(() => _maxImages = val),
                            onBatchSizeChanged: (val) => setState(() => _batchSize = val),
                            onStartTraining: _startTraining,
                            onCancelTraining: _cancelTraining,
                          ),
                        ),
                          Expanded(
                            child: MlopsStatusPanel(
                              status: _status,
                              liveMetric: _liveMetric,
                              onLiveMetricChanged: (val) => setState(() => _liveMetric = val),
                              statusPanelScroll: _statusPanelScroll,
                              logScroll: _logScroll,
                              onShowModelsHistory: _showModelsBottomSheet,
                              onSkipEpoch: _isReplaying ? _skipReplayEpoch : null,
                            ),
                          ),
                      ],
                    )
                  : _tabIndex == 1
                      ? _buildComparePanel()
                      : _buildShadowPanel(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int index, IconData icon) => GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _tabIndex == index
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _tabIndex == index
                  ? AppColors.primary.withOpacity(0.5)
                  : AppColors.glassBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: _tabIndex == index
                      ? AppColors.primary
                      : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: _tabIndex == index
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: _tabIndex == index
                          ? FontWeight.w700
                          : FontWeight.normal)),
            ],
          ),
        ),
      );

  // --------------------------------------------------------------------------
  // --------------------------------------------------------------------------
  // Status / History panel
  // --------------------------------------------------------------------------
  final ScrollController _statusPanelScroll = ScrollController();

  void _showModelsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            children: [
              // "Pega" para fechar
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: _buildModelsHistory(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _liveMetric = 'acc';

  /// Pill de métrica na progress card do treino (mostra valor + cor)

  ModelInfo? _findModel(String? name) {
    if (name == null) return null;
    for (final m in _models) {
      if (m.name == name) return m;
    }
    return null;
  }

  /// Cartão compacto de estatísticas, mostrado assim que um peso é
  /// selecionado (em vez de só depois de o correr/comparar), lido
  /// diretamente de `_models`, já carregado, sem pedido de rede novo.
  Widget _weightStatsPreview(String? modelName) {
    final model = _findModel(modelName);
    if (model == null) return const SizedBox.shrink();

    Widget stat(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceBright.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        children: [
          stat('Val. Accuracy', '${model.valAccuracy.toStringAsFixed(1)}%'),
          stat('F1', '${model.bestF1.toStringAsFixed(1)}%'),
          stat('Arquitetura', model.architecture),
          stat('Imagens', '${model.totalImages}'),
          stat('Épocas', '${model.epochs}'),
          stat('Classes', '${model.classes.length}'),
        ],
      ),
    );
  }

  /// Campo do URL do servidor MLOps, por omissão `AppConstants.mlopsUrl`
  /// (localhost), mas editável e persistido (AppSettingsService), para
  /// funcionar quando o Flutter e o mlops_server.py não correm na mesma
  /// máquina (ex.: dashboard num PC, servidor MLOps junto do Raspberry).
  Widget _mlopsServerUrlField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.dns_outlined, color: AppColors.textSecondary, size: 14),
        const SizedBox(width: 6),
        Text('Servidor MLOps',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            initialValue: AppSettingsService.mlopsUrl,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'http://IP:8767',
              hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.6), fontSize: 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppColors.glassBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppColors.glassBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppColors.primary)),
            ),
            onFieldSubmitted: (v) async {
              await AppSettingsService.setMlopsUrl(v);
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'URL do servidor MLOps (mlops_server.py). Só precisa de mudar se '
              'não correr na mesma máquina que esta app. Prime Enter para guardar.',
          padding: const EdgeInsets.all(10),
          textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 14),
        ),
      ],
    );
  }

  Widget _buildModelsHistory() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.history, color: AppColors.primary, size: 16),
                const SizedBox(width: 6),
                Text('Modelos Guardados',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${_models.length} modelo(s)',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Divider(color: AppColors.glassBorder, height: 1),
          if (_models.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Nenhum modelo treinado ainda.\nClica em "Treinar Novo Modelo" para começar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.5),
                      fontSize: 12),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(10),
                itemCount: _models.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _modelCard(_models[i], isNew: i == 0),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modelCard(ModelInfo m, {bool isNew = false}) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop(); // Fechar bottom sheet
        _replayTraining(m);          // Iniciar o replay!
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceBright,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isNew
                  ? AppColors.primary.withOpacity(0.4)
                  : AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              if (isNew)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('NOVO',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                ),
              if (isNew) const SizedBox(width: 6),
              Expanded(
                child: Text(m.name,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${m.valAccuracy.toStringAsFixed(1)}%',
                    style: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip(m.architecture, AppColors.accent),
              _chip('${m.totalImages} imgs', AppColors.textSecondary),
              _chip('${m.epochs} épocas', AppColors.textSecondary),
              _chip('${m.sizeMb} MB', AppColors.textSecondary),
              ...m.classes
                  .map((c) => _chip(c, AppColors.getColorForCondition(c))),
            ],
          ),
        ],
      ), // closes Column
    ), // closes Container
  ); // closes InkWell
}

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w600)),
      );

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------
  Widget _kpi(String label, String value, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text(label,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _offlineBanner() => Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off,
                  color: AppColors.textSecondary.withOpacity(0.4), size: 48),
              const SizedBox(height: 12),
              Text('Servidor MLOps offline',
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Inicia o servidor com:\n  python ONXX/mlops_server.py --port 8767',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      );

  Widget _metricPill(String label, String key) {
    final active = _compareMetric == key;
    return GestureDetector(
      onTap: () => setState(() => _compareMetric = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.glassBorder,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

