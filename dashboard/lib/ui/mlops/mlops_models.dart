class ClassInfo {
  final String name;
  final int count;

  /// Imagens triadas manualmente (train_dataset): ouro, entram no treino
  /// com peso reforçado. É o número amarelo do painel de classes.
  final int gold;

  /// Casos difíceis NÃO triados (frames de baixa confiança, rótulo
  /// automático): excluídos do treino, reservados para avaliação.
  final int hardCases;
  const ClassInfo(this.name, this.count, {this.gold = 0, this.hardCases = 0});
}

class ModelInfo {
  final String name;
  final double sizeMb;
  final double valAccuracy;
  final double bestF1;
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
    required this.bestF1,
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
        bestF1: (j['best_f1'] as num?)?.toDouble() ?? 0,
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

  /// Série de épocas até agora (train_acc/val_acc/loss/f1/... por entrada),
  /// enviada pelo train_cnn.py a cada época: alimenta o gráfico live.
  final List<Map<String, dynamic>> history;

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
    this.history = const [],
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
        history: (j['history'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );

  bool get isActive =>
      state == 'downloading' || state == 'augmenting' || state == 'training' || state == 'saving';
}
