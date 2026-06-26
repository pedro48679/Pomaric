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
    final label = json['label'] as String? ?? 'Healthy';
    final conf = (json['confidence'] as num?)?.toDouble() ?? 0.0;
    
    return FrameData(
      id: json['id'] as int? ?? 0,
      url: json['image_url'] as String? ?? '',
      diseaseSum: label == 'Healthy' ? 0.0 : conf,
      probabilities: {label: conf},
      isWorstCase: json['is_worst_case'] as bool? ?? false,
      frameIdx: json['frame_idx'] as int? ?? 1,
    );
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

  String get modelName => _modelName ?? 'Unknown';

  Apple({
    required this.id,
    required this.frames,
    this.location = 'Geral',
    DateTime? timestamp,
    this.cnn2Label = 'Healthy',
    this.cnn2Confidence = 0.0,
    String? modelName = 'Unknown',
  }) : _modelName = modelName,
       timestamp = timestamp ?? DateTime.now();

  factory Apple.fromJson(Map<String, dynamic> json) {
    var framesList = <FrameData>[];
    if (json['frames'] != null) {
      framesList = (json['frames'] as List).map((e) => FrameData.fromJson(e)).toList();
    }

    // Extrair predição da lista aninhada de cnn_predictions
    String c2Label = 'Healthy';
    double c2Conf = 0.0;
    String model = 'Unknown';
    
    if (json['cnn_predictions'] != null) {
      final preds = json['cnn_predictions'] as List;
      
      // Tenta procurar por CNN5 primeiro (se houver doença)
      var pred = preds.firstWhere(
        (p) => p['model_name'] == 'CNN5' && p['label'] != 'Unknown',
        orElse: () => null,
      );
      
      // Se não encontrar, procura por CNN2 (geralmente healthy)
      pred ??= preds.firstWhere(
        (p) => p['model_name'] == 'CNN2' && p['label'] != 'Unknown',
        orElse: () => null,
      );

      if (pred != null) {
        c2Label = pred['label'] as String? ?? 'Healthy';
        c2Conf = (pred['confidence'] as num?)?.toDouble() ?? 0.0;
        model = pred['model_name'] as String? ?? 'Unknown';
      }
    }
    
    return Apple(
      id: json['apple_id'] as String? ?? 'APP-?',
      location: json['location'] as String? ?? 'Geral',
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp'].toString()) : DateTime.now(),
      cnn2Label: c2Label,
      cnn2Confidence: c2Conf,
      modelName: model,
      frames: framesList,
    );
  }

  Apple copyWith({List<FrameData>? frames, String? location}) {
    return Apple(
      id: id,
      frames: frames ?? this.frames,
      location: location ?? this.location,
      timestamp: timestamp,
      cnn2Label: cnn2Label,
      cnn2Confidence: cnn2Confidence,
      modelName: modelName,
    );
  }

  FrameData? get worstFrame {
    if (frames.isEmpty) return null;
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

  final double growthRate; 

  Batch({
    required this.id,
    required this.name,
    required this.date,
    required this.apples,
    this.location = 'Pomar Geral',
    this.growthRate = 0.0,
  });

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
    double score = (dist['Scab']! * 0.9) + (dist['Blotch']! * 0.7) + (dist['Anthracnose']! * 0.5) + (dist['Rot']! * 0.25);
    return score / total;
  }

  double get severityScore {
    final dist = healthDistribution;
    final total = totalApples;
    if (total == 0) return 0.0;
    double score = (dist['Anthracnose']! * 1.0) + (dist['Rot']! * 1.0) + (dist['Scab']! * 0.4) + (dist['Blotch']! * 0.4);
    return score / total;
  }

  double get urgencyScore {
    return (contaminationScore * 0.4) + (severityScore * 0.6);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Batch && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
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
    disease: json['disease'] as String? ?? 'Unknown',
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    radius: (json['radius'] as num).toDouble(),
    updatedBy: json['updated_by'] as String?,
    crop: json['crop'] as String?,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
  );

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

class TriageAnnotation {
  final String appleId;
  final String primaryAppleDisease;
  final String updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TriageAnnotation({
    required this.appleId,
    required this.primaryAppleDisease,
    required this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'apple_id': appleId,
    'primary_apple_disease': primaryAppleDisease,
    'updated_by': updatedBy,
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
