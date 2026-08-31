
String _normalizeCondition(String condition) {
  final c = condition.toLowerCase().trim();
  
  if (c == 'healthy') return 'Healthy';
  
  if (c.contains('frost') || c.contains('frozen') || c.contains('freeze')) {
    return 'Frost';
  }
  
  if (c.contains('sunburn') || c.contains('sun burned') || c.contains('sun burn')) {
    return 'Sunburn';
  }
  
  if (c.contains('stinkbug') || c.contains('stink bug')) {
    return 'Stinkbug';
  }
  
  if (c.contains('blotch')) {
    return 'Blotch'; // Is visually converted to 'Sooty Blotch' in UI later
  }
  
  if (c == 'brown rot' || c == 'brownrot') return 'Brown Rot';
  if (c == 'bitter rot' || c == 'bitterrot') return 'Bitter Rot';
  
  return c.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

class FrameData {
  final int id;
  final String url;
  final double diseaseSum; 
  final Map<String, double> probabilities;
  final bool? _isWorstCase;
  final int? _frameIdx;

  bool get isWorstCase => _isWorstCase ?? false;
  int get frameIdx => _frameIdx ?? 1;

  FrameData({
    required this.id,
    required this.url,
    required this.diseaseSum,
    required this.probabilities,
    bool? isWorstCase = false,
    int? frameIdx = 1,
  }) : _isWorstCase = isWorstCase,
       _frameIdx = frameIdx;

  factory FrameData.fromJson(Map<String, dynamic> json) {
    // DB format compat
    final rawLabel = json['label'] as String? ?? 'Healthy';
    final label = _normalizeCondition(rawLabel);
    final conf = (json['confidence'] as num?)?.toDouble() ?? 0.0;
    
    // Local cache format support
    Map<String, double>? probs;
    if (json['probabilities'] != null) {
      probs = Map<String, double>.from(
        (json['probabilities'] as Map).map((k, v) => MapEntry(_normalizeCondition(k as String), (v as num).toDouble())),
      );
    }
    
    return FrameData(
      id: json['id'] as int? ?? 0,
      url: json['image_url'] as String? ?? '',
      diseaseSum: json['diseaseSum'] != null ? (json['diseaseSum'] as num).toDouble() : (label == 'Healthy' ? 0.0 : conf),
      probabilities: probs ?? {label: conf},
      isWorstCase: json['is_worst_case'] as bool? ?? false,
      frameIdx: json['frame_idx'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'image_url': url,
      'diseaseSum': diseaseSum,
      'probabilities': probabilities,
      'is_worst_case': isWorstCase,
      'frame_idx': frameIdx,
    };
  }

  FrameData copyWith({
    Map<String, double>? probabilities,
    double? diseaseSum,
    bool? isWorstCase,
    int? frameIdx,
  }) {
    return FrameData(
      id: id,
      url: url,
      diseaseSum: diseaseSum ?? this.diseaseSum,
      probabilities: probabilities ?? this.probabilities,
      isWorstCase: isWorstCase ?? this.isWorstCase,
      frameIdx: frameIdx ?? this.frameIdx,
    );
  }
}

class Apple {
  final String id;
  final List<FrameData> frames;
  final String location;
  final DateTime timestamp;
  final String cnn2Label;
  final double cnn2Confidence;
  final String? _modelName;
  final List<Map<String, dynamic>> cnnPredictions;

  String get modelName => _modelName ?? 'Unknown';

  Apple({
    required this.id,
    required this.frames,
    this.location = 'Geral',
    DateTime? timestamp,
    this.cnn2Label = 'Healthy',
    this.cnn2Confidence = 0.0,
    String? modelName = 'Unknown',
    this.cnnPredictions = const [],
  }) : _modelName = modelName,
       timestamp = timestamp ?? DateTime.now();

  factory Apple.fromJson(Map<String, dynamic> json) {
    var framesList = <FrameData>[];
    if (json['frames'] != null) {
      framesList = (json['frames'] as List).map((e) => FrameData.fromJson(e)).toList();
    }

    String c2Label = 'Healthy';
    double c2Conf = 0.0;
    String model = 'Unknown';
    final List<Map<String, dynamic>> predsList = [];
    
    if (json['cnn_predictions'] != null) {
      final preds = json['cnn_predictions'] as List;
      for (final p in preds) {
        if (p is Map) {
          predsList.add(Map<String, dynamic>.from(p));
        }
      }
      
      var pred = predsList.where(
        (p) => p['model_name'] == 'CNN5' && p['label'] != 'Unknown',
      ).firstOrNull;
      
      pred ??= predsList.where(
        (p) => p['model_name'] == 'CNN2' && p['label'] != 'Unknown',
      ).firstOrNull;

      if (pred != null) {
        c2Label = _normalizeCondition(pred['label'] as String? ?? 'Healthy');
        c2Conf = (pred['confidence'] as num?)?.toDouble() ?? 0.0;
        model = pred['model_name'] as String? ?? 'Unknown';
      }
    }

    // Local cache fast-path
    if (json['cnn2Label'] != null) {
      c2Label = _normalizeCondition(json['cnn2Label']);
      c2Conf = (json['cnn2Confidence'] as num).toDouble();
      model = json['modelName'] ?? 'Unknown';
    }
    
    return Apple(
      id: json['apple_id'] as String? ?? 'APP-?',
      location: json['location'] as String? ?? 'Geral',
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp'].toString()) : DateTime.now(),
      cnn2Label: c2Label,
      cnn2Confidence: c2Conf,
      modelName: model,
      frames: framesList,
      cnnPredictions: predsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apple_id': id,
      'location': location,
      'timestamp': timestamp.toIso8601String(),
      'cnn2Label': cnn2Label,
      'cnn2Confidence': cnn2Confidence,
      'modelName': modelName,
      'frames': frames.map((f) => f.toJson()).toList(),
      'cnn_predictions': cnnPredictions,
    };
  }

  Apple copyWith({List<FrameData>? frames, String? location, List<Map<String, dynamic>>? cnnPredictions}) {
    return Apple(
      id: id,
      frames: frames ?? this.frames,
      location: location ?? this.location,
      timestamp: timestamp,
      cnn2Label: cnn2Label,
      cnn2Confidence: cnn2Confidence,
      modelName: modelName,
      cnnPredictions: cnnPredictions ?? this.cnnPredictions,
    );
  }

  FrameData? get worstFrame {
    if (frames.isEmpty) return null;
    // Prefere o frame marcado explicitamente como is_worst_case na BD.
    final marked = frames.where((f) => f.isWorstCase).firstOrNull;
    if (marked != null) return marked;
    return frames.reduce((a, b) => a.diseaseSum > b.diseaseSum ? a : b);
  }

  String get worstFrameUrl => worstFrame?.url ?? '';

  String get primaryCondition {
    final wf = worstFrame;
    if (wf == null) {
      return (cnn2Label != 'Unknown') ? cnn2Label : 'Healthy';
    }
    
    String highestCondition = 'Healthy';
    double highestProb = 0.0;

    wf.probabilities.forEach((condition, prob) {
      if (prob > highestProb) {
        highestProb = prob;
        highestCondition = condition;
      }
    });

    return highestCondition;
  }

  double get effectiveConfidence {
    if (cnn2Label == 'Healthy' && cnn2Confidence >= 0.85) {
      return cnn2Confidence;
    } else {
      final wf = worstFrame;
      if (wf == null) return cnn2Confidence;
      final cond = primaryCondition;
      return wf.probabilities[cond] ?? 0.0;
    }
  }
}

class Batch {
  final String id;
  final String name;
  final DateTime date;
  final List<Apple> apples;
  final String location;

  Batch({
    required this.id,
    required this.name,
    required this.date,
    required this.apples,
    this.location = 'Pomar Geral',
  });

  /// Tendência de anomalias em pontos percentuais: taxa de não-saudáveis na
  /// metade mais recente do lote vs. a metade mais antiga (por timestamp).
  /// Positivo = incidência a aumentar (pior), negativo = a melhorar.
  double get growthRate {
    if (apples.length < 4) return 0.0;
    final sorted = [...apples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final mid = sorted.length ~/ 2;
    double anomalyRate(List<Apple> list) {
      if (list.isEmpty) return 0.0;
      final sick = list.where((a) => a.primaryCondition != 'Healthy').length;
      return sick / list.length * 100;
    }
    return anomalyRate(sorted.sublist(mid)) - anomalyRate(sorted.sublist(0, mid));
  }

  int get totalApples => apples.length;

  bool get isActive {
    if (apples.isEmpty) return false;
    final lastAppleTime = apples.map((a) => a.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
    return DateTime.now().difference(lastAppleTime).inMinutes <= 5;
  }

  int get totalFrames {
    return apples.fold(0, (sum, apple) => sum + apple.frames.length);
  }

  Map<String, int> get healthDistribution {
    Map<String, int> distribution = {
      'Healthy': 0,
      'Rot': 0,
      'Blotch': 0,
      'Scab': 0,
      'Anthracnose': 0,
    };

    for (var apple in apples) {
      final condition = apple.primaryCondition;
      if (distribution.containsKey(condition)) {
        distribution[condition] = distribution[condition]! + 1;
      } else {
        distribution[condition] = 1;
      }
    }

    return distribution;
  }

  double get contaminationScore {
    final dist = healthDistribution;
    final total = totalApples;
    if (total == 0) return 0.0;
    double score = (dist['Rot']! * 0.90) + (dist['Anthracnose']! * 0.75) + (dist['Scab']! * 0.35) + (dist['Blotch']! * 0.20);
    return score / total;
  }

  double get severityScore {
    final dist = healthDistribution;
    final total = totalApples;
    if (total == 0) return 0.0;
    double score = (dist['Rot']! * 1.0) + (dist['Anthracnose']! * 1.0) + (dist['Scab']! * 0.4) + (dist['Blotch']! * 0.4);
    return score / total;
  }

  double get healthyRatio {
    final total = totalApples;
    if (total == 0) return 0.0;
    return (healthDistribution['Healthy'] ?? 0) / total;
  }

  double get urgencyScore {
    final rawUrgency = (contaminationScore * 0.4) + (severityScore * 0.6);
    // Amortecimento biológico por taxa de fruta sã no lote (- 20% * %Saudáveis)
    final dampened = rawUrgency - (healthyRatio * 0.20);
    return dampened.clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Batch && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ---------------------------------------------------------------------------
// Raspberry Pi 5 Heartbeat
// ---------------------------------------------------------------------------

class RaspberryHeartbeat {
  final String deviceId;
  final DateTime timestamp;
  final double? cpuTemp;
  final double? cpuPercent;
  final double? ramUsedMb;
  final double? ramTotalMb;
  final double? diskUsedGb;
  final double? diskTotalGb;
  /// 'active' | 'idle' | 'sleep' | 'offline'
  final String mode;
  final int? uptimeSeconds;
  final int inferenceCount;
  final double? cameraFps;
  /// Variância de Laplacian do último burst, mede nitidez da lente.
  final double? lastBlurScore;
  /// true se [lastBlurScore] < 80 (lente possivelmente suja ou descalibrada).
  final bool blurWarning;
  /// Config efetiva do script no Pi (chaves snake_case, ex: 'lens_position').
  /// Usada para fazer seed dos sliders do painel de configuração.
  final Map<String, dynamic>? config;

  RaspberryHeartbeat({
    required this.deviceId,
    required this.timestamp,
    this.cpuTemp,
    this.cpuPercent,
    this.ramUsedMb,
    this.ramTotalMb,
    this.diskUsedGb,
    this.diskTotalGb,
    required this.mode,
    this.uptimeSeconds,
    this.inferenceCount = 0,
    this.cameraFps,
    this.lastBlurScore,
    this.blurWarning = false,
    this.config,
  });

  /// Considera offline se não houve heartbeat nos últimos 15 segundos.
  bool get isOnline =>
      mode != 'offline' && DateTime.now().difference(timestamp).inSeconds < 15;

  factory RaspberryHeartbeat.fromJson(Map<String, dynamic> json) {
    return RaspberryHeartbeat(
      deviceId: json['device_id'] as String? ?? 'raspberry5',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      cpuTemp: (json['cpu_temp'] as num?)?.toDouble(),
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble(),
      ramUsedMb: (json['ram_used_mb'] as num?)?.toDouble(),
      ramTotalMb: (json['ram_total_mb'] as num?)?.toDouble(),
      diskUsedGb: (json['disk_used_gb'] as num?)?.toDouble(),
      diskTotalGb: (json['disk_total_gb'] as num?)?.toDouble(),
      mode: json['mode'] as String? ?? 'idle',
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt(),
      inferenceCount: (json['inference_count'] as num?)?.toInt() ?? 0,
      cameraFps: (json['camera_fps'] as num?)?.toDouble(),
      lastBlurScore: (json['last_blur'] as num?)?.toDouble(),
      blurWarning: json['blur_warning'] as bool? ?? false,
      config: json['config'] as Map<String, dynamic>?,
    );
  }

  static RaspberryHeartbeat offline() => RaspberryHeartbeat(
    deviceId: 'raspberry5',
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    mode: 'offline',
  );

  String get ramDisplay {
    if (ramUsedMb == null || ramTotalMb == null) return '--';
    final used = (ramUsedMb! / 1024).toStringAsFixed(1);
    final total = (ramTotalMb! / 1024).toStringAsFixed(1);
    return '$used / $total GB';
  }

  String get diskDisplay {
    if (diskUsedGb == null || diskTotalGb == null) return '--';
    return '${diskUsedGb!.toStringAsFixed(1)} / ${diskTotalGb!.toStringAsFixed(1)} GB';
  }

  String get uptimeDisplay {
    if (uptimeSeconds == null) return '--';
    final h = uptimeSeconds! ~/ 3600;
    final m = (uptimeSeconds! % 3600) ~/ 60;
    return '${h}h ${m}m';
  }
}

class ManualAnnotation {
  final int? id;
  final String appleId;
  final int circleIndex;
  final String disease;
  final double x;
  final double y;
  final double radius;
  final String? updatedBy;
  final String? crop;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ManualAnnotation({
    this.id,
    required this.appleId,
    required this.circleIndex,
    required this.disease,
    required this.x,
    required this.y,
    required this.radius,
    this.updatedBy,
    this.crop,
    this.createdAt,
    this.updatedAt,
  });

  factory ManualAnnotation.fromJson(Map<String, dynamic> json) => ManualAnnotation(
    id: json['id'] as int?,
    appleId: json['apple_id'] as String,
    circleIndex: json['circle_index'] as int? ?? 0,
    disease: _normalizeCondition(json['disease'] as String? ?? 'Unknown'),
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    radius: (json['radius'] as num).toDouble(),
    updatedBy: json['updated_by'] as String?,
    crop: json['crop'] as String?,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
  );

  ManualAnnotation copyWith({
    String? appleId,
    int? circleIndex,
    String? disease,
    double? x,
    double? y,
    double? radius,
    String? updatedBy,
    String? crop,
  }) {
    return ManualAnnotation(
      id: id,
      appleId: appleId ?? this.appleId,
      circleIndex: circleIndex ?? this.circleIndex,
      disease: disease ?? this.disease,
      x: x ?? this.x,
      y: y ?? this.y,
      radius: radius ?? this.radius,
      updatedBy: updatedBy ?? this.updatedBy,
      crop: crop ?? this.crop,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'apple_id': appleId,
    'circle_index': circleIndex,
    'disease': disease,
    'x': x,
    'y': y,
    'radius': radius,
    'updated_by': updatedBy,
    'crop': crop ?? 'none',
  };
}

class CorrectionHistory {
  final String batchId;
  final String appleId;
  final String frameUrl;
  final List<ManualAnnotation> annotations;
  final String label;
  final String correctedBy;
  final DateTime timestamp;

  CorrectionHistory({
    required this.batchId,
    required this.appleId,
    required this.frameUrl,
    required this.annotations,
    required this.label,
    required this.correctedBy,
    required this.timestamp,
  });
}

/// Registo da tabela `producao_atual`, resultado final de cada maçã na linha
/// (classe final, confiança, origem da decisão e thumbnail do frame).
class ProducaoRecord {
  final int id;
  final String appleId;
  final DateTime timestamp;
  final String? location;
  final String finalClass;
  /// Normalizada para 0.0–1.0.
  final double finalConfidence;
  /// Origem da decisão final (ex.: 'IA', 'manual', nome do modelo…).
  final String finalSource;
  final String? frameThumbnail;

  ProducaoRecord({
    required this.id,
    required this.appleId,
    required this.timestamp,
    this.location,
    required this.finalClass,
    required this.finalConfidence,
    required this.finalSource,
    this.frameThumbnail,
  });

  /// true se a decisão final veio de um operador humano.
  bool get isHuman {
    final s = finalSource.toLowerCase();
    return s.contains('manual') || s.contains('human') || s.contains('operador');
  }

  factory ProducaoRecord.fromJson(Map<String, dynamic> json) {
    final rawConf = (json['final_confidence'] as num?)?.toDouble() ?? 0.0;
    return ProducaoRecord(
      id: json['id'] as int? ?? 0,
      appleId: json['apple_id'] as String? ?? 'APP-?',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      location: json['location'] as String?,
      finalClass: _normalizeCondition(json['final_class'] as String? ?? 'Healthy'),
      finalConfidence: rawConf > 1.0 ? rawConf / 100.0 : rawConf,
      finalSource: json['final_source'] as String? ?? 'IA',
      frameThumbnail: json['frame_thumbnail'] as String?,
    );
  }
}

class Worker {
  final String id;
  final String username;
  final String role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Worker({
    required this.id,
    required this.username,
    required this.role,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  factory Worker.fromJson(Map<String, dynamic> json) => Worker(
    id: json['id'] as String,
    username: json['username'] as String,
    role: json['role'] as String,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
  );
}
