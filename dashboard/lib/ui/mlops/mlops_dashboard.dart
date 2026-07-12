
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../utils/constants.dart';
import '../../services/supabase_service.dart';
import '../structure/dashboard_screen.dart';

Widget buildMLOpsDashboard(BuildContext context, WidgetRef ref) {
    return const MlopsPage();
  }

class ClassInfo {
  final String name;
  final int count;
  final int hardCases;
  const ClassInfo(this.name, this.count, {this.hardCases = 0});
}

class ModelInfo {
  final String name;
  final double sizeMb;
  final double valAccuracy;
  final List<String> classes;
  final String architecture;
  final String createdAt;
  final int totalImages;
  final int epochs;
  final List<dynamic> history;

  const ModelInfo({
    required this.name,
    required this.sizeMb,
    required this.valAccuracy,
    required this.classes,
    required this.architecture,
    required this.createdAt,
    required this.totalImages,
    required this.epochs,
    required this.history,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> j) => ModelInfo(
        name: j['name'] as String? ?? '',
        sizeMb: (j['size_mb'] as num?)?.toDouble() ?? 0,
        valAccuracy: (j['val_accuracy'] as num?)?.toDouble() ?? 0,
        classes: List<String>.from(j['classes'] as List? ?? []),
        architecture: j['architecture'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        totalImages: j['total_images'] as int? ?? 0,
        epochs: j['epochs'] as int? ?? 0,
        history: j['history'] as List? ?? [],
      );
}

class TrainingStatus {
  final String state;
  final int progress;
  final String message;
  final int epoch;
  final int epochs;
  final double trainAcc;
  final double valAcc;
  final double loss;
  final double f1;
  final double precision;
  final double recall;
  final Map<String, double> perClassF1;
  final Map<String, double> perClassPrecision;
  final Map<String, double> perClassRecall;
  final List<dynamic> confusionMatrix;
  final List<String> classes;
  final List<dynamic> logs;
  final String? modelPath;
  final Map<String, dynamic> metrics;

  const TrainingStatus({
    this.state = 'idle',
    this.progress = 0,
    this.message = '',
    this.epoch = 0,
    this.epochs = 0,
    this.trainAcc = 0,
    this.valAcc = 0,
    this.loss = 0,
    this.f1 = 0,
    this.precision = 0,
    this.recall = 0,
    this.perClassF1 = const {},
    this.perClassPrecision = const {},
    this.perClassRecall = const {},
    this.confusionMatrix = const [],
    this.classes = const [],
    this.logs = const [],
    this.modelPath,
    this.metrics = const {},
  });

  static Map<String, double> _parseClassMap(dynamic raw) =>
      (raw as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toDouble()));

  factory TrainingStatus.fromJson(Map<String, dynamic> j) => TrainingStatus(
        state: j['state'] as String? ?? 'idle',
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        message: j['message'] as String? ?? '',
        epoch: j['epoch'] as int? ?? 0,
        epochs: j['epochs'] as int? ?? 0,
        trainAcc: (j['train_acc'] as num?)?.toDouble() ?? 0,
        valAcc: (j['val_acc'] as num?)?.toDouble() ?? 0,
        loss: (j['loss'] as num?)?.toDouble() ?? 0,
        f1: (j['f1'] as num?)?.toDouble() ?? 0,
        precision: (j['precision'] as num?)?.toDouble() ?? 0,
        recall: (j['recall'] as num?)?.toDouble() ?? 0,
        perClassF1: _parseClassMap(j['per_class_f1']),
        perClassPrecision: _parseClassMap(j['per_class_precision']),
        perClassRecall: _parseClassMap(j['per_class_recall']),
        confusionMatrix: j['confusion_matrix'] as List? ?? [],
        classes: List<String>.from(j['classes'] as List? ?? []),
        logs: j['logs'] as List? ?? [],
        modelPath: j['model_path'] as String?,
        metrics: j['metrics'] as Map<String, dynamic>? ?? {},
      );

  bool get isActive =>
      state == 'downloading' || state == 'augmenting' || state == 'training' || state == 'saving';
}

class MlopsPage extends ConsumerStatefulWidget {
  const MlopsPage();

  @override
  MlopsPageState createState() => MlopsPageState();
}

class MlopsPageState extends ConsumerState<MlopsPage> {
  List<ClassInfo> _classes = [];
  List<ModelInfo> _models = [];
  TrainingStatus _status = const TrainingStatus();
  bool _serverOnline = false;
  bool _loading = true;

  // Config
  Set<String> _selectedClasses = {};
  Set<String> _selectedDiseases = {}; // CNN2: which diseases are included in "Unhealthy"
  String _architecture = 'resnet50';
  int _epochs = 50;
  double _hardThreshold = 0.75;
  int _minImages = 20;
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
  String _compareChartMode = 'epoch'; // epoch | roc | pr
  String? _curveClassFilter; // null = todas as classes sobrepostas

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
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    await Future.wait([_loadClasses(), _loadModels(), _pollStatus(), _loadShadowHistory()]);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadShadowHistory() async {
    if (SupabaseService.isMockMode) return;
    try {
      final r = await http
          .get(Uri.parse('${AppConstants.mlopsUrl}/shadow/history'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _shadowHistory = (data['history'] as List? ?? [])
              .map((e) => e as Map<String, dynamic>)
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadClasses() async {
    if (SupabaseService.isMockMode) {
      const mockClasses = [
        ClassInfo('Healthy',     1842, hardCases: 12),
        ClassInfo('Rot',          234, hardCases: 45),
        ClassInfo('Scab',         187, hardCases: 38),
        ClassInfo('Blotch',       156, hardCases: 29),
        ClassInfo('Anthracnose',  203, hardCases: 51),
      ];
      if (!mounted) return;
      setState(() {
        _classes = mockClasses;
        _serverOnline = true;
        if (_selectedClasses.isEmpty) {
          _selectedClasses = mockClasses.map((c) => c.name).toSet();
        }
        if (_selectedDiseases.isEmpty) {
          _selectedDiseases = mockClasses
              .where((c) => c.name.toLowerCase() != 'healthy')
              .map((c) => c.name)
              .toSet();
        }
      });
      return;
    }
    try {
      final r = await http
          .get(Uri.parse('${AppConstants.mlopsUrl}/classes'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (data['classes'] as List? ?? [])
            .map((c) => ClassInfo(
                  c['name'] as String,
                  (c['count'] as num?)?.toInt() ?? 0,
                  hardCases: (c['hard_cases'] as num?)?.toInt() ?? 0,
                ))
            .toList();
        if (!mounted) return;
        setState(() {
          _classes = list;
          _serverOnline = true;
          if (_selectedClasses.isEmpty) {
            _selectedClasses = list.map((c) => c.name).toSet();
          }
          if (_selectedDiseases.isEmpty) {
            _selectedDiseases = list
                .where((c) => c.name.toLowerCase() != 'healthy')
                .map((c) => c.name)
                .toSet();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _serverOnline = false);
    }
  }

  Future<void> _loadModels() async {
    if (SupabaseService.isMockMode) {
      if (!mounted) return;
      setState(() {
        _models = [
          ModelInfo.fromJson({
            'name': 'cnn_multi_mobilenet_5cls_acc87_f185_20260628.pth',
            'size_mb': 14.2,
            'val_accuracy': 87.4,
            'best_f1': 85.1,
            'classes': ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'],
            'architecture': 'mobilenet_v2',
            'created_at': '2026-06-28T14:32:00',
            'total_images': 2622,
            'epochs': 15,
            'history': List.generate(15, (i) => {
              'epoch': i + 1,
              'train_acc': 65.0 + i * 1.8,
              'val_acc': 62.0 + i * 1.7,
              'f1': 60.0 + i * 1.9,
            }),
          }),
          ModelInfo.fromJson({
            'name': 'cnn_binary_resnet50_2cls_acc92_f191_20260601.pth',
            'size_mb': 98.6,
            'val_accuracy': 91.8,
            'best_f1': 91.2,
            'classes': ['Healthy', 'Disease'],
            'architecture': 'resnet50',
            'created_at': '2026-06-01T09:15:00',
            'total_images': 4120,
            'epochs': 20,
            'history': List.generate(20, (i) => {
              'epoch': i + 1,
              'train_acc': 70.0 + i * 1.2,
              'val_acc': 68.0 + i * 1.2,
              'f1': 67.0 + i * 1.3,
            }),
          }),
        ];
      });
      return;
    }
    try {
      final r = await http
          .get(Uri.parse('${AppConstants.mlopsUrl}/models'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _models = (data['models'] as List? ?? [])
              .map((m) => ModelInfo.fromJson(m as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _pollStatus() async {
    if (SupabaseService.isMockMode) {
      // Em mock mode o estado é gerido localmente por _startTraining (não há servidor)
      if (!mounted) return;
      setState(() {
        _serverOnline = true;
        // Apenas inicializa shadow state se ainda não existir
        if (_shadowState.isEmpty) {
          _shadowState = {
            'model': null,
            'apples_processed': 0,
            'accuracy': null,
            'f1': null,
            'state': 'idle',
          };
        }
      });
      return;
    }
    try {
      final r = await http
          .get(Uri.parse('${AppConstants.mlopsUrl}/status'))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) {
        final newStatus = TrainingStatus.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
        final wasDone = _status.state == 'done';
        if (!mounted) return;
        setState(() {
          _status = newStatus;
          _serverOnline = true;
        });
        if (!wasDone && newStatus.state == 'done') {
          _loadModels();
        }
        if (_status.isActive && _logScroll.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_logScroll.hasClients) {
              _logScroll.animateTo(
                _logScroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    } catch (_) {}
    // Shadow state (independente do treino)
    try {
      final r = await http
          .get(Uri.parse('${AppConstants.mlopsUrl}/shadow/status'))
          .timeout(const Duration(seconds: 2));
      if (r.statusCode == 200) {
        final wasConcluded = _shadowState['state'] == 'promoted' ||
            _shadowState['state'] == 'archived';
        final newShadowState = jsonDecode(r.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() => _shadowState = newShadowState);
        final nowConcluded = newShadowState['state'] == 'promoted' ||
            newShadowState['state'] == 'archived';
        if (!wasConcluded && nowConcluded) {
          _loadShadowHistory();
          _loadModels();
        }
      }
    } catch (_) {}
  }

  Future<void> _loadCompare() async {
    if (_compareA == null || _compareB == null) return;
    if (mounted) setState(() => _loadingCompare = true);
    if (SupabaseService.isMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() {
        _compareResult = {
          'model_a': {
            'name': _compareA,
            'val_accuracy': 87.4,
            'best_f1': 85.1,
            'precision': 86.3,
            'recall': 84.0,
            'classes': ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'],
            'architecture': 'mobilenet_v2',
            'total_images': 2622,
            'epochs': 15,
            'history': List.generate(15, (i) => {
              'epoch': i+1,
              'val_acc':   42.0 + i * 3.4,
              'f1':        38.0 + i * 3.6,
              'precision': 40.0 + i * 3.5,
              'recall':    36.0 + i * 3.7,
            }),
            'per_class_f1':        {'Healthy': 92.1, 'Rot': 81.3, 'Scab': 78.5, 'Blotch': 83.2, 'Anthracnose': 80.4},
            'per_class_precision': {'Healthy': 93.0, 'Rot': 82.1, 'Scab': 79.2, 'Blotch': 84.0, 'Anthracnose': 81.3},
            'per_class_recall':    {'Healthy': 91.0, 'Rot': 80.4, 'Scab': 77.8, 'Blotch': 82.4, 'Anthracnose': 79.5},
          },
          'model_b': {
            'name': _compareB,
            'val_accuracy': 91.8,
            'best_f1': 91.2,
            'precision': 92.1,
            'recall': 90.4,
            'classes': ['Healthy', 'Disease'],
            'architecture': 'resnet50',
            'total_images': 4120,
            'epochs': 20,
            'history': List.generate(20, (i) => {
              'epoch': i+1,
              'val_acc':   50.0 + i * 2.4,
              'f1':        48.0 + i * 2.5,
              'precision': 51.0 + i * 2.3,
              'recall':    47.0 + i * 2.5,
            }),
            'per_class_f1':        {'Healthy': 94.3, 'Disease': 88.1},
            'per_class_precision': {'Healthy': 95.1, 'Disease': 89.2},
            'per_class_recall':    {'Healthy': 93.5, 'Disease': 87.0},
          },
        };
        _loadingCompare = false;
      });
      return;
    }
    try {
      final r = await http
          .get(Uri.parse(
              '${AppConstants.mlopsUrl}/compare?a=${Uri.encodeComponent(_compareA!)}&b=${Uri.encodeComponent(_compareB!)}'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        if (mounted) {
          setState(() => _compareResult =
              jsonDecode(r.body) as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingCompare = false);
  }

  Future<void> _setShadowModel(String? modelName) async {
    if (SupabaseService.isMockMode) {
      setState(() {
        _shadowState = {
          'model': modelName,
          'apples_processed': modelName != null ? 247 : 0,
          'accuracy': modelName != null ? 84.2 : null,
          'f1': modelName != null ? 82.7 : null,
          'state': modelName != null ? 'running' : 'idle',
          'last_updated': DateTime.now().toIso8601String(),
        };
      });
      return;
    }
    try {
      await http.post(
        Uri.parse('${AppConstants.mlopsUrl}/shadow/set'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model': modelName}),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Inicia o shadow_runner.py via mlops_server (sem terminal)
  Future<void> _startShadow(String modelName) async {
    if (SupabaseService.isMockMode) {
      setState(() {
        _shadowState = {
          'model': modelName,
          'apples_processed': 0,
          'accuracy': null,
          'f1': null,
          'state': 'running',
          'last_updated': DateTime.now().toIso8601String(),
        };
      });
      // Simula progresso gradual em mock mode
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _shadowState = {
            ..._shadowState,
            'apples_processed': 247,
            'accuracy': 84.2,
            'f1': 82.7,
          };
        });
      });
      return;
    }
    try {
      await http.post(
        Uri.parse('${AppConstants.mlopsUrl}/shadow/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': modelName,
          'promote_after': _shadowPromoteAfter,
          'interval': 30,
        }),
      ).timeout(const Duration(seconds: 6));
      await _pollStatus();
    } catch (_) {}
  }

  /// Para o shadow_runner.py via mlops_server
  Future<void> _stopShadow() async {
    if (SupabaseService.isMockMode) {
      setState(() {
        _shadowState = {
          ..._shadowState,
          'state': 'idle',
        };
      });
      return;
    }
    try {
      await http
          .post(Uri.parse('${AppConstants.mlopsUrl}/shadow/stop'))
          .timeout(const Duration(seconds: 5));
      await _pollStatus();
    } catch (_) {}
  }

  /// Promove o modelo shadow a produção via mlops_server
  Future<void> _promoteShadow() async {
    if (SupabaseService.isMockMode) {
      setState(() {
        _shadowState = {
          ..._shadowState,
          'state': 'promoted',
        };
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('[MOCK] Modelo promovido a produção com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    try {
      final r = await http
          .post(Uri.parse('${AppConstants.mlopsUrl}/shadow/promote'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Modelo promovido a produção com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        await _pollStatus();
      }
    } catch (_) {}
  }

  /// Pede host/pasta do Raspberry, exporta o modelo em produção para ONNX
  /// quantizado e copia-o para lá (POST /models/publish). Não reinicia nada
  /// remotamente — o Pi só passa a usar o ficheiro no próximo arranque
  /// (resolve_latest_model() em raspberry_camera_format.py).
  Future<void> _publishToRaspberry() async {
    final hostController = TextEditingController(text: 'minipc@192.168.1.50');
    final dirController = TextEditingController(text: '/home/minipc/models');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Publicar no Raspberry', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Exporta o modelo em produção (só MobileNetV2 — ResNet50 é recusado) '
              'para ONNX quantizado e copia-o para o Pi via scp. Precisas de reiniciar '
              'o script no Pi para ele passar a usar o modelo novo.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hostController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Host do Pi (user@ip)',
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dirController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Pasta remota',
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.healthy),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Publicar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (SupabaseService.isMockMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('[MOCK] Modelo publicado no Raspberry com sucesso!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      final r = await http
          .post(
            Uri.parse('${AppConstants.mlopsUrl}/models/publish'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'pi_host': hostController.text.trim(),
              'remote_dir': dirController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200 || body['error'] != null) {
        throw Exception(body['error'] ?? 'Falha ao iniciar publicação');
      }

      // A exportação + scp corre em background no servidor — faz polling do resultado.
      String state = 'exporting';
      String message = '';
      for (var i = 0; i < 30 && (state == 'exporting' || state == 'uploading'); i++) {
        await Future.delayed(const Duration(seconds: 2));
        final s = await http
            .get(Uri.parse('${AppConstants.mlopsUrl}/models/publish/status'))
            .timeout(const Duration(seconds: 5));
        final statusBody = jsonDecode(s.body) as Map<String, dynamic>;
        state = statusBody['state'] as String? ?? 'error';
        message = statusBody['message'] as String? ?? '';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state == 'done' ? message : 'Falha ao publicar: $message'),
          backgroundColor: state == 'done' ? Colors.green : Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao publicar: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _startTraining() async {
    if (_selectedClasses.isEmpty) return;

    if (SupabaseService.isMockMode) {
      // Treino animado localmente — simula epochs com métricas progressivas
      final clsList = _selectedClasses.toList();
      final totalEpochs = _epochs.clamp(3, 8); // max 8 épocas na demo para não demorar

      setState(() {
        _status = TrainingStatus(
          state: 'downloading',
          progress: 5,
          message: '[MOCK] A descarregar ${clsList.length * 120} imagens do Supabase...',
          epochs: totalEpochs,
          classes: clsList,
        );
      });
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      setState(() {
        _status = TrainingStatus(
          state: 'augmenting',
          progress: 12,
          message: '[MOCK] A equilibrar classes com augmentação...',
          epochs: totalEpochs,
          classes: clsList,
        );
      });
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      // Simula cada época com abrandamento (Plateau)
      double currentLr = _lr;
      int patience = 0;
      double trainAcc = 55.0;
      double valAcc = 50.0;
      double lossVal = 1.8;
      
      for (int ep = 1; ep <= totalEpochs; ep++) {
        if (!mounted) return;
        
        double gain = (ep > totalEpochs / 2) ? 15.0 / totalEpochs : 30.0 / totalEpochs;
        if (patience >= 2) {
          currentLr *= 0.5;
          patience = 0;
        } else if (ep > 3 && gain < 1.0) {
          patience++;
        }
        
        trainAcc = (trainAcc + gain * 1.2).clamp(0.0, 99.5);
        valAcc = (valAcc + gain).clamp(0.0, 96.0);
        lossVal = (lossVal * 0.85).clamp(0.05, 2.0);
        
        final f1Val    = (valAcc - 2.0).clamp(0.0, 100.0);
        final precVal  = (valAcc + 1.0).clamp(0.0, 100.0);
        final recallVal= (valAcc - 3.0).clamp(0.0, 100.0);
        
        final perF1   = <String, double>{};
        final perPrec = <String, double>{};
        final perRec  = <String, double>{};
        for (int ci = 0; ci < clsList.length; ci++) {
          perF1[clsList[ci]]   = (f1Val - ci * 2.5).clamp(20.0, 99.0);
          perPrec[clsList[ci]] = (precVal - ci * 2.0).clamp(20.0, 99.0);
          perRec[clsList[ci]]  = (recallVal - ci * 2.5).clamp(20.0, 99.0);
        }
        setState(() {
          _status = TrainingStatus(
            state: 'training',
            progress: (12 + ep * 80 ~/ totalEpochs).clamp(12, 90),
            message: '[MOCK] Época $ep/$totalEpochs — LR: ${currentLr.toStringAsExponential(2)} — '
                'train=${trainAcc.toStringAsFixed(1)}%  '
                'val=${valAcc.toStringAsFixed(1)}%  '
                'loss=${lossVal.toStringAsFixed(4)}',
            epoch: ep,
            epochs: totalEpochs,
            trainAcc: trainAcc,
            valAcc: valAcc,
            loss: lossVal,
            f1: f1Val,
            precision: precVal,
            recall: recallVal,
            perClassF1: perF1,
            perClassPrecision: perPrec,
            perClassRecall: perRec,
            classes: clsList,
          );
        });
        await Future.delayed(const Duration(milliseconds: 800));
      }
      if (!mounted) return;

      // Salva modelo final
      setState(() {
        _status = TrainingStatus(
          state: 'saving',
          progress: 95,
          message: '[MOCK] A guardar modelo...',
          epochs: totalEpochs,
          classes: clsList,
        );
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final arch = _isBinary ? 'binary' : 'multi';
      final mockModelName =
          'cnn_${arch}_${_architecture}_${clsList.length}cls_acc${(87 + clsList.length).clamp(0, 99)}_f185_$ts.pth';

      setState(() {
        _status = TrainingStatus(
          state: 'done',
          progress: 100,
          message: '[MOCK] Treino concluído. Modelo guardado.',
          epoch: totalEpochs,
          epochs: totalEpochs,
          trainAcc: 89.5,
          valAcc: 87.4,
          loss: 0.1812,
          f1: 85.1,
          precision: 86.3,
          recall: 84.0,
          perClassF1: {for (int ci = 0; ci < clsList.length; ci++) clsList[ci]: (85.0 - ci * 2.0).clamp(70.0, 97.0)},
          perClassPrecision: {for (int ci = 0; ci < clsList.length; ci++) clsList[ci]: (86.0 - ci * 1.8).clamp(70.0, 97.0)},
          perClassRecall: {for (int ci = 0; ci < clsList.length; ci++) clsList[ci]: (84.0 - ci * 2.2).clamp(68.0, 97.0)},
          classes: clsList,
          modelPath: 'models/$mockModelName',
        );
      });
      // Adiciona o novo modelo í  lista
      setState(() {
        _models = [
          ModelInfo.fromJson({
            'name': mockModelName,
            'size_mb': _architecture == 'resnet50' ? 98.3 : 14.2,
            'val_accuracy': 87.4,
            'best_f1': 85.1,
            'classes': clsList,
            'architecture': _architecture,
            'created_at': DateTime.now().toIso8601String(),
            'total_images': clsList.length * 120,
            'epochs': totalEpochs,
            'history': List.generate(totalEpochs, (i) => {
              'epoch': i + 1,
              'train_acc': 55.0 + i * (35.0 / totalEpochs),
              'val_acc':   50.0 + i * (32.0 / totalEpochs),
            }),
          }),
          ..._models,
        ];
      });
      return;
    }

    final trainingClasses = _isBinary
        ? ['Healthy', ..._selectedDiseases]
        : _selectedClasses.toList();

    final config = {
      'classes': trainingClasses,
      'architecture': _architecture,
      'epochs': _epochs,
      'lr': _lr,
      'hard_threshold': _hardThreshold,
      'min_images': _minImages,
      'batch_size': _batchSize,
      'is_binary': _isBinary,
    };
    try {
      await http.post(
        Uri.parse('${AppConstants.mlopsUrl}/train'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config),
      ).timeout(const Duration(seconds: 5));
      await _pollStatus();
    } catch (_) {}
  }

  Future<void> _cancelTraining() async {
    if (SupabaseService.isMockMode) {
      setState(() => _status = const TrainingStatus(
          state: 'cancelled',
          message: '[MOCK] Treino cancelado pelo utilizador.'));
      return;
    }
    try {
      await http
          .post(Uri.parse('${AppConstants.mlopsUrl}/cancel'))
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final totalImages = _classes.fold(0, (s, c) => s + c.count);
    final totalHard = _classes.fold(0, (s, c) => s + c.hardCases);
    final bestAcc = _models.isNotEmpty
        ? _models.map((m) => m.valAccuracy).reduce((a, b) => a > b ? a : b)
        : 0.0;
    final activeClasses = _classes.where((c) => c.count >= _minImages).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              _kpi('Hard Cases', totalHard.toString(), Icons.warning_amber_outlined, Colors.amber),
              const SizedBox(width: 10),
              _kpi('Melhor Modelo', bestAcc > 0 ? '${bestAcc.toStringAsFixed(1)}%' : '—',
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
                        SizedBox(width: 260, child: _buildConfigPanel()),
                        const SizedBox(width: 14),
                        Expanded(child: _buildStatusPanel()),
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
  // Config panel
  // --------------------------------------------------------------------------
  Widget _buildConfigPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Título
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                Icon(Icons.tune, color: AppColors.primary, size: 16),
                const SizedBox(width: 6),
                Text('Configuração de Treino',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Divider(color: AppColors.glassBorder, height: 1),

          // Toggle CNN2 / CNN5
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Expanded(child: _cnnModeBtn(
                  label: 'CNN2', sub: 'Binário',
                  active: _isBinary,
                  activeColor: AppColors.primary,
                  onTap: _status.isActive ? null : () => setState(() {
                    _isBinary = true;
                    _batchSize = 32;
                    _epochs = 35;
                    _lr = 0.0001; // 1e-4
                    // CNN2: auto-seleciona todas as classes existentes
                    _selectedClasses = _classes.map((c) => c.name).toSet();
                  }),
                )),
                const SizedBox(width: 8),
                Expanded(child: _cnnModeBtn(
                  label: 'CNN5', sub: 'Multiclasse',
                  active: !_isBinary,
                  activeColor: const Color(0xFF8B5CF6),
                  onTap: _status.isActive ? null : () => setState(() {
                    _isBinary = false;
                    _batchSize = 16;
                    _epochs = 50;
                    _lr = 0.00001; // 1e-5
                    if (_selectedClasses.isEmpty) {
                      _selectedClasses = _classes.map((c) => c.name).toSet();
                    }
                  }),
                )),
              ],
            ),
          ),

          Divider(color: AppColors.glassBorder, height: 1),

          // Classes a treinar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text('Classes a treinar',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
          if (_classes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Text('Sem dados. Inicia o servidor.',
                  style: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.6),
                      fontSize: 11)),
            )
          else if (_isBinary)
            _buildBinaryClassList()
          else
            ..._classes.map((cls) => _classCheckbox(cls)),

          Divider(color: AppColors.glassBorder, height: 1),

          // Arquitetura
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Arquitetura',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _architecture,
                  dropdownColor: AppColors.surface,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.glassBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.glassBorder)),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'mobilenet_v2',
                        child: Text('MobileNetV2 (rápido)')),
                    DropdownMenuItem(
                        value: 'resnet50', child: Text('ResNet50 (preciso)')),
                  ],
                  onChanged: _status.isActive
                      ? null
                      : (v) => setState(() => _architecture = v!),
                ),
              ],
            ),
          ),

          Divider(color: AppColors.glassBorder, height: 1),

          // Sliders
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Builder(
              builder: (context) {
                final totalImgs = _classes.fold(0, (s, c) => s + c.count);
                double sMin = 10;
                double sMax = totalImgs > 0 ? (totalImgs * 0.3).clamp(100.0, 5000.0) : 100.0;
                if (_minImages > sMax) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _minImages = sMax.round());
                  });
                } else if (_minImages < sMin) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _minImages = sMin.round());
                  });
                }
                int sDivs = (sMax - sMin) > 0 ? ((sMax - sMin) ~/ 10) : 90;
                if (sDivs < 1) sDivs = 1;
                if (sDivs > 200) sDivs = 200;

                return Column(
                  children: [
                    _cfgSlider('Épocas', _epochs.toDouble(), 5, 50, 45,
                        valueLabel: _epochs.toString(),
                        onChanged: (v) => setState(() => _epochs = v.round())),
                    const SizedBox(height: 8),
                    _cfgSlider(
                        'Hard Case threshold',
                        _hardThreshold,
                        0.5,
                        0.95,
                        45,
                        valueLabel: _hardThreshold.toStringAsFixed(2),
                        onChanged: (v) => setState(() => _hardThreshold = v)),
                    const SizedBox(height: 8),
                    _cfgSlider('Min. imagens/classe', _minImages.toDouble().clamp(sMin, sMax), sMin,
                        sMax, sDivs,
                        valueLabel: _minImages.toString(),
                        onChanged: (v) => setState(() => _minImages = v.round())),
                    const SizedBox(height: 8),
                    _cfgSlider(
                        'Batch size', _batchSize.toDouble(), 8, 64, 56,
                        valueLabel: _batchSize.toString(),
                        onChanged: (v) => setState(() => _batchSize = v.round())),
                  ],
                );
              },
            ),
          ),

          // Botão Treinar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: _status.isActive
                ? SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined,
                          color: Colors.red, size: 16),
                      label: const Text('CANCELAR',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _cancelTraining,
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.model_training,
                          color: AppColors.surface, size: 16),
                      label: Text(
                        'TREINAR NOVO MODELO',
                        style: TextStyle(
                            color: AppColors.surface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        disabledBackgroundColor:
                            AppColors.textSecondary.withOpacity(0.2),
                      ),
                      onPressed: (_selectedClasses.isEmpty || !_serverOnline)
                          ? null
                          : _startTraining,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _classCheckbox(ClassInfo cls) {
    final isSelected = _selectedClasses.contains(cls.name);
    final enough = cls.count >= _minImages;
    return InkWell(
      onTap: _status.isActive
          ? null
          : () => setState(() {
                if (isSelected) {
                  _selectedClasses.remove(cls.name);
                } else {
                  _selectedClasses.add(cls.name);
                }
              }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: isSelected,
                onChanged: _status.isActive
                    ? null
                    : (v) => setState(() {
                          if (v!) {
                            _selectedClasses.add(cls.name);
                          } else {
                            _selectedClasses.remove(cls.name);
                          }
                        }),
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(cls.name,
                  style: TextStyle(
                      color: enough
                          ? AppColors.textPrimary
                          : AppColors.textSecondary.withOpacity(0.5),
                      fontSize: 12)),
            ),
            Text('${cls.count}',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            if (cls.hardCases > 0) ...[
              const SizedBox(width: 4),
              Text('+${cls.hardCases}',
                  style: const TextStyle(
                      color: Colors.amber, fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }

  /// Botão de seleção de modo CNN (CNN2 / CNN5)
  Widget _cnnModeBtn({
    required String label,
    required String sub,
    required bool active,
    required Color activeColor,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? activeColor.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? activeColor : AppColors.glassBorder,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: active ? activeColor : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: (active ? activeColor : AppColors.textSecondary)
                          .withOpacity(0.7),
                      fontSize: 9)),
            ],
          ),
        ),
      );

  /// Lista de classes em modo CNN2 — Healthy (locked) + Unhealthy com sub-itens
  Widget _buildBinaryClassList() {
    final healthyCls =
        _classes.where((c) => c.name.toLowerCase() == 'healthy').firstOrNull;
    final diseaseCls =
        _classes.where((c) => c.name.toLowerCase() != 'healthy').toList();
    final selectedDiseaseCls = diseaseCls.where((c) => _selectedDiseases.contains(c.name)).toList();
    final totalCount = selectedDiseaseCls.fold(0, (s, c) => s + c.count);
    final totalHard = selectedDiseaseCls.fold(0, (s, c) => s + c.hardCases);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Healthy (locked on)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 18, height: 18,
              child: Checkbox(
                value: true, onChanged: null,
                activeColor: AppColors.healthy,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('Healthy', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))),
            Text('${healthyCls?.count ?? '—'}',
                style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
        // Unhealthy group (locked on)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 18, height: 18,
              child: Checkbox(
                value: true, onChanged: null,
                activeColor: AppColors.rot,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('Unhealthy',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
            Text('$totalCount',
                style: TextStyle(color: AppColors.rot, fontSize: 11, fontWeight: FontWeight.w600)),
            if (totalHard > 0) ...[
              const SizedBox(width: 4),
              Text('+$totalHard', style: const TextStyle(color: Colors.amber, fontSize: 10)),
            ],
          ]),
        ),
        // Sub-items indentados — checkboxes interativos para escolher doenças em "Unhealthy"
        ...diseaseCls.map((cls) {
          final checked = _selectedDiseases.contains(cls.name);
          return Padding(
            padding: const EdgeInsets.only(left: 40, right: 14, top: 1, bottom: 1),
            child: Row(children: [
              SizedBox(
                width: 9, height: 9,
                child: Checkbox(
                  value: checked,
                  onChanged: _status.isActive ? null : (v) {
                    setState(() {
                      if (v == true) {
                        _selectedDiseases.add(cls.name);
                      } else {
                        _selectedDiseases.remove(cls.name);
                      }
                    });
                  },
                  activeColor: AppColors.getColorForCondition(cls.name),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(child: Text(cls.name,
                  style: TextStyle(
                    color: checked ? AppColors.textSecondary : AppColors.textSecondary.withOpacity(0.4),
                    fontSize: 11,
                  ))),
              Text('${cls.count}',
                  style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(checked ? 0.7 : 0.3),
                    fontSize: 10,
                  )),
              if (cls.hardCases > 0) ...[
                const SizedBox(width: 3),
                Text('+${cls.hardCases}',
                    style: TextStyle(
                      color: checked ? Colors.amber : Colors.amber.withOpacity(0.3),
                      fontSize: 9,
                    )),
              ],
            ]),
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _cfgSlider(String title, double value, double min, double max,
      int divisions,
      {required String valueLabel,
      required ValueChanged<double> onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
            Text(valueLabel,
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.textSecondary.withOpacity(0.2),
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withOpacity(0.12),
            disabledThumbColor: AppColors.textSecondary.withOpacity(0.3),
            disabledActiveTrackColor: AppColors.textSecondary.withOpacity(0.3),
          ),
          child: SizedBox(
            height: 24,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: _status.isActive ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Status / History panel
  // --------------------------------------------------------------------------
  Widget _buildStatusPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress card (sempre visível quando activo ou recentemente terminado)
        if (_status.state != 'idle')
          _buildProgressCard(),

        if (_status.state != 'idle') const SizedBox(height: 12),

        // Histórico de modelos
        Expanded(child: _buildModelsHistory()),
      ],
    );
  }

  Widget _buildProgressCard() {
    Color stateColor;
    String stateLabel;
    switch (_status.state) {
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
              if (_status.isActive && _status.epochs > 0)
                Text(
                    'Época ${_status.epoch}/${_status.epochs}',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),

          // Métricas principais (pills)
          if (_status.state == 'training' || _status.state == 'done') ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _statusMetricPill('Acc Val', '${_status.valAcc.toStringAsFixed(1)}%', Colors.green),
                _statusMetricPill('Acc Tr', '${_status.trainAcc.toStringAsFixed(1)}%', AppColors.textSecondary),
                _statusMetricPill('F1', '${_status.f1.toStringAsFixed(1)}%', AppColors.primary),
                _statusMetricPill('Prec', '${_status.precision.toStringAsFixed(1)}%', Colors.cyan),
                _statusMetricPill('Recall', '${_status.recall.toStringAsFixed(1)}%', Colors.amber),
                if (_status.loss > 0)
                  _statusMetricPill('Loss', _status.loss.toStringAsFixed(4), Colors.orange),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _status.progress / 100.0,
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
                child: Text(_status.message,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 10),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${_status.progress}%',
                  style: TextStyle(
                      color: stateColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ],
          ),

          // Métricas por classe (F1 / Precision / Recall — barras horizontais)
          if (_status.perClassF1.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildPerClassMetricBars(
              label: 'F1 por classe',
              data: _status.perClassF1,
              color: (cls) => AppColors.getColorForCondition(cls),
            ),
            if (_status.perClassPrecision.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildPerClassMetricBars(
                label: 'Precisão por classe',
                data: _status.perClassPrecision,
                color: (_) => Colors.cyan,
              ),
            ],
            if (_status.perClassRecall.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildPerClassMetricBars(
                label: 'Recall por classe',
                data: _status.perClassRecall,
                color: (_) => Colors.amber,
              ),
            ],
          ],

          // Log
          if (_status.logs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.builder(
                controller: _logScroll,
                padding: const EdgeInsets.all(6),
                itemCount: _status.logs.length,
                itemBuilder: (ctx, i) {
                  final log = _status.logs[i] as Map<String, dynamic>;
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
        ],
      ),
    );
  }
  // --------------------------------------------------------------------------
  // Painel de Comparação
  // --------------------------------------------------------------------------
  Widget _buildComparePanel() {
    final modelNames = _models.map((m) => m.name).toList();
    final metaA = _compareResult['model_a'] as Map<String, dynamic>? ?? {};
    final metaB = _compareResult['model_b'] as Map<String, dynamic>? ?? {};
    final histA = metaA['history'] as List? ?? [];
    final histB = metaB['history'] as List? ?? [];
    final clsA = List<String>.from(metaA['classes'] as List? ?? []);
    final clsB = List<String>.from(metaB['classes'] as List? ?? []);
    final allCls = {...clsA, ...clsB}.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Seletor de modelos
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Expanded(child: _modelDropdown('Modelo A', _compareA, modelNames,
                  (v) => setState(() => _compareA = v))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('vs',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              Expanded(child: _modelDropdown('Modelo B', _compareB, modelNames,
                  (v) => setState(() => _compareB = v))),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: (_compareA == null || _compareB == null || _compareA == _compareB || _loadingCompare)
                    ? null
                    : _loadCompare,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                child: _loadingCompare
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.surface))
                    : Text('Comparar',
                        style: TextStyle(
                            color: AppColors.surface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Tipo de gráfico (Curva por época | ROC | Precision-Recall)
        if (_compareResult.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _chartModePill('Curva por Época', 'epoch'),
                const SizedBox(width: 6),
                _chartModePill('Curva ROC', 'roc'),
                const SizedBox(width: 6),
                _chartModePill('Precision-Recall', 'pr'),
              ],
            ),
          ),
        ],

        // Seletor de métrica (cascade pills) — só relevante para curva por época
        if (_compareResult.isNotEmpty && _compareChartMode == 'epoch') ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _metricPill('Accuracy',  'val_acc'),
                const SizedBox(width: 6),
                _metricPill('F1-Score',  'f1'),
                const SizedBox(width: 6),
                _metricPill('Precisão',  'precision'),
                const SizedBox(width: 6),
                _metricPill('Recall',    'recall'),
              ],
            ),
          ),
        ],

        if (_compareResult.isEmpty)
          Expanded(
            child: Center(
              child: Text('Seleciona dois modelos e clica em Comparar',
                  style: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.5),
                      fontSize: 13)),
            ),
          )
        else if (_compareChartMode == 'roc' || _compareChartMode == 'pr')
          Expanded(
            child: _buildRocPrPanel(metaA, metaB, allCls, isRoc: _compareChartMode == 'roc'),
          )
        else
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildMetricCurve(histA, histB, metaA, metaB, _compareMetric)),
                const SizedBox(width: 12),
                Expanded(child: _buildClassMetricComparison(allCls, metaA, metaB, _compareMetric)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chartModePill(String label, String mode) {
    final active = _compareChartMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _compareChartMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.primary : AppColors.glassBorder),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  /// Painel com curvas ROC ou Precision-Recall para os dois modelos comparados.
  Widget _buildRocPrPanel(Map<String, dynamic> metaA, Map<String, dynamic> metaB,
      List<String> allCls, {required bool isRoc}) {
    final curvesA = (metaA[isRoc ? 'roc_curves' : 'pr_curves'] as Map<String, dynamic>?) ?? {};
    final curvesB = (metaB[isRoc ? 'roc_curves' : 'pr_curves'] as Map<String, dynamic>?) ?? {};

    if (curvesA.isEmpty && curvesB.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isRoc
                ? 'Sem dados de curva ROC. Apenas modelos treinados após esta atualização guardam estas curvas.'
                : 'Sem dados de curva Precision-Recall. Apenas modelos treinados após esta atualização guardam estas curvas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary.withOpacity(0.6), fontSize: 12),
          ),
        ),
      );
    }

    final filterClasses = allCls.where((c) => curvesA.containsKey(c) || curvesB.containsKey(c)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filtro de classe
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _classFilterChip('Todas', null),
              ...filterClasses.map((c) => _classFilterChip(c, c)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isRoc ? 'Curva ROC (TPR vs FPR)' : 'Curva Precision-Recall',
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  isRoc
                      ? 'Quanto mais perto do canto superior esquerdo, melhor a separação entre classes.'
                      : 'Quanto mais perto do canto superior direito, melhor o equilíbrio entre precisão e recall.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: CustomPaint(
                    painter: RocPrCurvePainter(
                      curvesA: curvesA,
                      curvesB: curvesB,
                      classFilter: _curveClassFilter,
                      isRoc: isRoc,
                      isDark: AppColors.isDark,
                    ),
                    child: Container(),
                  ),
                ),
                const SizedBox(height: 8),
                _buildAucLegend(curvesA, curvesB, filterClasses),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _classFilterChip(String label, String? value) {
    final active = _curveClassFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _curveClassFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? AppColors.primary : AppColors.glassBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _buildAucLegend(Map<String, dynamic> curvesA, Map<String, dynamic> curvesB, List<String> classes) {
    final shown = _curveClassFilter != null ? [_curveClassFilter!] : classes;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: shown.expand((cls) {
        final aucA = (curvesA[cls]?['auc'] as num?)?.toDouble();
        final aucB = (curvesB[cls]?['auc'] as num?)?.toDouble();
        return [
          if (aucA != null)
            Text('$cls (A) AUC=${aucA.toStringAsFixed(3)}',
                style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w600)),
          if (aucB != null)
            Text('$cls (B) AUC=${aucB.toStringAsFixed(3)}',
                style: const TextStyle(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.w600)),
        ];
      }).toList(),
    );
  }

  /// Barras horizontais por classe para uma métrica (F1, Precisão, Recall)
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
                            color: AppColors.textSecondary, fontSize: 10),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (e.value / 100).clamp(0.0, 1.0),
                        backgroundColor: AppColors.textSecondary.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(color(e.key)),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${e.value.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ]),
              )),
        ],
      );

  /// Pill de métrica na progress card do treino (mostra valor + cor)
  Widget _statusMetricPill(String label, String value, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            Text(label,
                style: TextStyle(
                    color: color.withOpacity(0.7), fontSize: 8)),
          ],
        ),
      );

  /// Pill de seleção de métrica na tab Comparar
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

  Widget _modelDropdown(String label, String? value, List<String> items,
      ValueChanged<String?> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: value,
            dropdownColor: AppColors.surface,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.glassBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.glassBorder)),
            ),
            hint: Text('Selecionar...',
                style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.5),
                    fontSize: 11)),
            items: items
                .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      );

  /// Curva da métrica selecionada ao longo das épocas
  Widget _buildMetricCurve(List histA, List histB,
      Map<String, dynamic> metaA, Map<String, dynamic> metaB, String metricKey) {
    final metricLabels = {
      'val_acc': 'Val Accuracy', 'f1': 'F1-Score',
      'precision': 'Precisão', 'recall': 'Recall',
    };
    final title = metricLabels[metricKey] ?? metricKey;

    String statKey(String m) => m == 'val_acc' ? 'val_accuracy' : m == 'f1' ? 'best_f1' : m;
    final valA = (metaA[statKey(metricKey)] as num?)?.toStringAsFixed(1) ?? '—';
    final valB = (metaB[statKey(metricKey)] as num?)?.toStringAsFixed(1) ?? '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Curva $title por Época',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              _legendDot(AppColors.primary, metaA['name'] as String? ?? 'A'),
              const SizedBox(width: 10),
              _legendDot(Colors.orange, metaB['name'] as String? ?? 'B'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: histA.isEmpty && histB.isEmpty
                ? Center(
                    child: Text('Sem histórico de treino',
                        style: TextStyle(
                            color: AppColors.textSecondary.withOpacity(0.5),
                            fontSize: 12)))
                : CustomPaint(
                    painter: MetricCurvePainter(histA, histB, metricKey,
                        colorA: AppColors.primary, colorB: Colors.orange),
                    size: Size.infinite,
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _compareStat('$title A', '$valA%', AppColors.primary),
              const Spacer(),
              _compareStat('$title B', '$valB%', Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  /// Comparação por classe da métrica selecionada
  Widget _buildClassMetricComparison(List<String> classes,
      Map<String, dynamic> metaA, Map<String, dynamic> metaB, String metricKey) {
    final pcKey = metricKey == 'val_acc'
        ? 'per_class_f1'   // accuracy não tem per-class direto, usa f1 como proxy
        : 'per_class_$metricKey'; // per_class_precision, per_class_recall, per_class_f1

    final metricLabels = {
      'val_acc': 'F1 por Classe',
      'f1': 'F1 por Classe',
      'precision': 'Precisão por Classe',
      'recall': 'Recall por Classe',
    };
    final title = metricLabels[metricKey] ?? metricKey;

    Map<String, double> extractPerClass(Map<String, dynamic> meta) {
      // 1. Tenta dict direto no metadata (ex: per_class_f1: {Healthy: 92.1})
      final direct = meta[pcKey] as Map<String, dynamic>?;
      if (direct != null && direct.isNotEmpty) {
        return direct.map((k, v) => MapEntry(k, (v as num).toDouble()));
      }
      // 2. Extrai da lista no último epoch do histórico
      final hist = meta['history'] as List?;
      if (hist == null || hist.isEmpty) return {};
      final last = hist.last as Map<String, dynamic>;
      final pcList = last[pcKey] as List?;
      final cls = List<String>.from(meta['classes'] as List? ?? []);
      if (pcList == null || cls.isEmpty) return {};
      return {
        for (var i = 0; i < cls.length && i < pcList.length; i++)
          cls[i]: (pcList[i] as num).toDouble() *
              (pcList[i] is double && (pcList[i] as double) <= 1.0 ? 100.0 : 1.0)
      };
    }

    final valA = extractPerClass(metaA);
    final valB = extractPerClass(metaB);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              _legendDot(AppColors.primary, 'A'),
              const SizedBox(width: 8),
              _legendDot(Colors.orange, 'B'),
            ],
          ),
          const SizedBox(height: 12),
          if (classes.isEmpty)
            Center(
              child: Text('Sem dados',
                  style: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.5),
                      fontSize: 12)),
            )
          else
            Expanded(
              child: ListView(
                children: classes.map((cls) {
                  final a = valA[cls] ?? 0.0;
                  final b = valB[cls] ?? 0.0;
                  final winner = (a - b).abs() < 0.5 ? '=' : a > b ? 'A' : 'B';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.getColorForCondition(cls),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            SizedBox(
                              width: 82,
                              child: Text(cls,
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Text(
                              winner == '=' ? '=' : '▲ $winner',
                              style: TextStyle(
                                  color: winner == 'A'
                                      ? AppColors.primary
                                      : winner == 'B'
                                          ? Colors.orange
                                          : AppColors.textSecondary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        _f1Bar(a, AppColors.primary, 'A'),
                        const SizedBox(height: 2),
                        _f1Bar(b, Colors.orange, 'B'),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _f1Bar(double val, Color color, String label) => Row(
        children: [
          SizedBox(
            width: 10,
            child: Text(label,
                style: TextStyle(color: color, fontSize: 8)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (val / 100).clamp(0.0, 1.0),
                backgroundColor: AppColors.textSecondary.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color.withOpacity(0.7)),
                minHeight: 10,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text('${val.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 10)),
        ],
      );

  Widget _compareStat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 9)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      );

  // --------------------------------------------------------------------------
  // Painel Shadow CNN
  // --------------------------------------------------------------------------
  Widget _buildShadowPanel() {
    final shadowModel = _shadowState['model'] as String?;
    final shadowState = _shadowState['state'] as String? ?? 'idle';
    final applesProcessed = _shadowState['apples_processed'] as int? ?? 0;
    final shadowAcc = _shadowState['accuracy'];
    final shadowF1 = _shadowState['f1'];
    final isRunning = shadowState == 'running' || shadowState == 'ready_to_promote';
    final readyToPromote = shadowState == 'ready_to_promote';
    final concluded = shadowState == 'promoted' || shadowState == 'archived';
    final comparison = _shadowState['comparison'] as Map<String, dynamic>? ?? {};

    final modelNames = _models.map((m) => m.name).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isRunning
                ? AppColors.primary.withOpacity(0.3)
                : AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined,
                  color: isRunning ? AppColors.primary : AppColors.textSecondary,
                  size: 18),
              const SizedBox(width: 8),
              Text('Shadow CNN',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isRunning ? Colors.green : AppColors.textSecondary)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  shadowState == 'idle'
                      ? 'Parado'
                      : shadowState == 'running'
                          ? 'A correr'
                          : shadowState == 'ready_to_promote'
                              ? 'Pronto para promover!'
                              : shadowState == 'promoted'
                                  ? 'Promovido automaticamente'
                                  : shadowState == 'archived'
                                      ? 'Arquivado (não promovido)'
                                      : shadowState,
                  style: TextStyle(
                    color: shadowState == 'promoted'
                        ? Colors.green
                        : shadowState == 'archived'
                            ? Colors.orangeAccent
                            : readyToPromote
                                ? Colors.green
                                : isRunning
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'O modelo Shadow é executado como processo independente (continua a correr mesmo que termines sessão ou mudes de página). '
            'Classifica as mesmas maçãs que o modelo de produção, sem afetar decisões reais. '
            'Ao atingir o número de maçãs configurado, compara automaticamente o seu F1 com o modelo em produção: '
            'se for melhor, promove-se a si mesmo; senão, fica arquivado no histórico.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 16),

          // Seleção do modelo shadow
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Modelo Shadow',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: shadowModel,
                      dropdownColor: AppColors.surface,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 11),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: AppColors.glassBorder)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: AppColors.glassBorder)),
                      ),
                      hint: Text('Selecionar modelo...',
                          style: TextStyle(
                              color: AppColors.textSecondary.withOpacity(0.5),
                              fontSize: 11)),
                      items: modelNames
                          .map((n) =>
                              DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: isRunning ? null : (v) {
                        setState(() => _shadowState = {
                          ..._shadowState,
                          'model': v,
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: Icon(
                    isRunning ? Icons.stop : Icons.play_arrow,
                    size: 14,
                    color: isRunning ? Colors.white : AppColors.surface),
                label: Text(isRunning ? 'Parar' : 'Iniciar',
                    style: TextStyle(
                        color: isRunning ? Colors.white : AppColors.surface,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning ? Colors.red : AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: shadowModel == null
                    ? null
                    : () => isRunning ? _stopShadow() : _startShadow(shadowModel),
              ),
            ],
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 12),

          // Config promote_after
          Row(
            children: [
              Icon(Icons.flag, color: AppColors.textSecondary, size: 14),
              const SizedBox(width: 6),
              Text('Promover após',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: _shadowPromoteAfter.toString(),
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'nº maçãs',
                    hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) {
                      setState(() => _shadowPromoteAfter = n);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('maçãs',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),

          const SizedBox(height: 16),

          // Métricas Shadow
          if (applesProcessed > 0) ...[
            Text('Resultados Shadow vs Produção',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _kpi('Maçãs', applesProcessed.toString(),
                    Icons.apple, AppColors.primary),
                const SizedBox(width: 8),
                _kpi('Acc Shadow',
                    shadowAcc != null ? '$shadowAcc%' : '—',
                    Icons.track_changes, Colors.green),
                const SizedBox(width: 8),
                _kpi('F1 Shadow',
                    shadowF1 != null ? '$shadowF1%' : '—',
                    Icons.psychology_alt, Colors.cyan),
              ],
            ),
            // Barra de progresso rumo í  promoção
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (applesProcessed / _shadowPromoteAfter).clamp(0.0, 1.0),
              backgroundColor: AppColors.glassBorder,
              valueColor: AlwaysStoppedAnimation<Color>(
                  readyToPromote ? Colors.green : AppColors.primary),
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 4),
            Text(
              readyToPromote
                  ? '✓ Limite atingido — modelo pronto para promoção!'
                  : '$applesProcessed / $_shadowPromoteAfter maçãs processadas',
              style: TextStyle(
                  color: readyToPromote ? Colors.green : AppColors.textSecondary,
                  fontSize: 10),
            ),
          ],

          const SizedBox(height: 16),

          // Botão promover manual (apenas fallback — normalmente é automático)
          if (readyToPromote)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upgrade, size: 16, color: Colors.white),
                label: const Text('Promover a Produção',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _promoteShadow,
              ),
            ),

          const SizedBox(height: 8),

          // Publica o modelo atualmente em produção no Raspberry (export ONNX + scp)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: _publishing
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.memory, size: 16),
              label: Text(_publishing ? 'A publicar...' : 'Publicar no Raspberry',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _publishing ? null : _publishToRaspberry,
            ),
          ),

          // Resultado da decisão automática mais recente
          if (concluded && comparison.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (shadowState == 'promoted' ? Colors.green : Colors.orangeAccent)
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: (shadowState == 'promoted' ? Colors.green : Colors.orangeAccent)
                        .withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    shadowState == 'promoted' ? Icons.check_circle : Icons.archive_outlined,
                    color: shadowState == 'promoted' ? Colors.green : Colors.orangeAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shadow F1 ${comparison['shadow_f1'] ?? '—'}%  vs  Produção F1 ${comparison['production_f1'] ?? '—'}%',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (comparison['reason'] as String?) ?? '',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Histórico de runs Shadow
          if (_shadowHistory.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Histórico Shadow',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...(_shadowHistory.take(8).map((h) {
              final isPromoted = h['result'] == 'promoted';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBright,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPromoted ? Icons.check_circle : Icons.archive_outlined,
                        size: 14,
                        color: isPromoted ? Colors.green : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (h['model'] as String?) ?? '',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${h['apples_processed'] ?? 0} maçãs · F1 ${h['f1'] ?? '—'}% vs prod ${h['production_f1'] ?? '—'}% · ${h['date'] ?? ''}',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        isPromoted ? 'PROMOVIDO' : 'ARQUIVADO',
                        style: TextStyle(
                            color: isPromoted ? Colors.green : AppColors.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            })),
          ],
        ],
      ),
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
    return Container(
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
      ),
    );
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
}

/// Pinta duas curvas de uma métrica de treino (por época) lado a lado.
/// [metricKey] pode ser 'val_acc', 'f1', 'precision', 'recall'.

class MetricCurvePainter extends CustomPainter {
  final List histA;
  final List histB;
  final String metricKey;
  final Color colorA;
  final Color colorB;

  const MetricCurvePainter(this.histA, this.histB, this.metricKey,
      {required this.colorA, required this.colorB});

  double _val(Map<String, dynamic> entry) =>
      (entry[metricKey] as num?)?.toDouble() ?? 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (histA.isEmpty && histB.isEmpty) return;
    final allEpochs =
        [histA.length, histB.length].reduce((a, b) => a > b ? a : b);
    if (allEpochs == 0) return;

    const minY = 0.0;
    const maxY = 100.0;
    final denom = allEpochs - 1 == 0 ? 1.0 : (allEpochs - 1).toDouble();

    // Grid lines a cada 20%
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    for (double yv = 0; yv <= 100; yv += 20) {
      final py = size.height - (yv - minY) / (maxY - minY) * size.height;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), gridPaint);
    }

    void drawCurve(List hist, Color color) {
      if (hist.isEmpty) return;
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      for (int i = 0; i < hist.length; i++) {
        final v = _val(hist[i] as Map<String, dynamic>);
        final x = i / denom * size.width;
        final y = size.height - (v - minY) / (maxY - minY) * size.height;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, linePaint);

      // Dot no último ponto
      if (hist.isNotEmpty) {
        final v = _val(hist.last as Map<String, dynamic>);
        final x = (hist.length - 1) / denom * size.width;
        final y = size.height - (v - minY) / (maxY - minY) * size.height;
        canvas.drawCircle(
            Offset(x, y), 5, Paint()..color = color.withOpacity(0.9));
      }
    }

    drawCurve(histA, colorA);
    drawCurve(histB, colorB);
  }

  @override
  bool shouldRepaint(covariant MetricCurvePainter old) =>
      old.histA != histA ||
      old.histB != histB ||
      old.metricKey != metricKey;
}

/// Pinta curvas ROC (FPR x TPR) ou Precision-Recall para duas comparações de modelos.
/// Cada classe é desenhada com uma variação de opacidade da cor base do modelo
/// (modelo A = cyan/primary, modelo B = roxo), ou apenas a classe selecionada.

class RocPrCurvePainter extends CustomPainter {
  final Map<String, dynamic> curvesA;
  final Map<String, dynamic> curvesB;
  final String? classFilter;
  final bool isRoc;
  final bool isDark;

  const RocPrCurvePainter({
    required this.curvesA,
    required this.curvesB,
    required this.classFilter,
    required this.isRoc,
    required this.isDark,
  });

  static const _colorA = Colors.cyanAccent;
  static const _colorB = Colors.purpleAccent;

  @override
  void paint(Canvas canvas, Size size) {
    final gridColor = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);
    final axisColor = isDark ? Colors.white.withOpacity(0.25) : Colors.black.withOpacity(0.25);

    // Grid 0-1 em ambos os eixos, 5 divisões
    final gridPaint = Paint()..color = gridColor..strokeWidth = 1;
    for (int i = 0; i <= 5; i++) {
      final f = i / 5;
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), gridPaint);
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), gridPaint);
    }

    // Eixos
    final axisPaint = Paint()..color = axisColor..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), axisPaint);
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), axisPaint);

    // Linha de referência diagonal (ROC: classificador aleatório)
    if (isRoc) {
      final diagPaint = Paint()
        ..color = axisColor
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      final dashPath = Path()..moveTo(0, size.height)..lineTo(size.width, 0);
      canvas.drawPath(dashPath, diagPaint);
    }

    void drawClassCurves(Map<String, dynamic> curves, Color base) {
      final entries = classFilter != null
          ? curves.entries.where((e) => e.key == classFilter)
          : curves.entries;
      int idx = 0;
      final total = entries.length.clamp(1, 999);
      for (final e in entries) {
        final data = e.value as Map<String, dynamic>;
        final xs = isRoc
            ? (data['fpr'] as List? ?? [])
            : (data['recall'] as List? ?? []);
        final ys = isRoc
            ? (data['tpr'] as List? ?? [])
            : (data['precision'] as List? ?? []);
        if (xs.isEmpty || ys.isEmpty) {
          idx++;
          continue;
        }
        final opacity = classFilter != null ? 1.0 : (0.4 + 0.6 * (idx + 1) / total);
        final paint = Paint()
          ..color = base.withOpacity(opacity)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final path = Path();
        for (int i = 0; i < xs.length; i++) {
          final x = (xs[i] as num).toDouble() * size.width;
          final y = size.height - (ys[i] as num).toDouble() * size.height;
          i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        canvas.drawPath(path, paint);
        idx++;
      }
    }

    drawClassCurves(curvesA, _colorA);
    drawClassCurves(curvesB, _colorB);
  }

  @override
  bool shouldRepaint(covariant RocPrCurvePainter old) =>
      old.curvesA != curvesA ||
      old.curvesB != curvesB ||
      old.classFilter != classFilter ||
      old.isRoc != isRoc;
}

