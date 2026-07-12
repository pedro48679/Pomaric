import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/local_cache_service.dart';
import '../utils/constants.dart';

class AvailableBatchesNotifier extends Notifier<List<Batch>> {
  @override
  List<Batch> build() => [];
  
  void setBatches(List<Batch> batches) {
    state = batches;
  }
}

final availableBatchesProvider = NotifierProvider<AvailableBatchesNotifier, List<Batch>>(AvailableBatchesNotifier.new);

class DateRangeFilterNotifier extends Notifier<String> {
  @override
  String build() => '30d';

  void setRange(String range) {
    state = range;
  }
}

final dateRangeFilterProvider = NotifierProvider<DateRangeFilterNotifier, String>(DateRangeFilterNotifier.new);

final filteredBatchesProvider = Provider<List<Batch>>((ref) {
  final allBatches = ref.watch(availableBatchesProvider);
  final range = ref.watch(dateRangeFilterProvider);
  
  if (allBatches.isEmpty) return [];
  
  final now = DateTime.now();
  final threshold = range == '7d' 
      ? now.subtract(const Duration(days: 7)) 
      : now.subtract(const Duration(days: 30));
      
  return allBatches.where((b) => b.date.isAfter(threshold)).toList();
});

final loadDataFutureProvider = FutureProvider<void>((ref) async {
  final batches = await SupabaseService.getBatches();
  ref.read(availableBatchesProvider.notifier).setBatches(batches);
  if (batches.isNotEmpty) {
    ref.read(batchProvider.notifier).setBatch(batches.first);
  }
});

class BatchNotifier extends Notifier<Batch?> {
  Timer? _timer;

  @override
  Batch? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  Batch _todayOnly(Batch b) {
    // Como os dados da cache podem ser de dias anteriores (ex: ontem),
    // remover o filtro restrito de "hoje" permite ver os dados no Lote Dashboard.
    // Em produção, se quiseres ver apenas hoje, podes repor o filtro.
    return b;
  }

  void setBatch(Batch batch) {
    state = _todayOnly(batch);
    ref.read(selectedConditionFilterProvider.notifier).resetFilter();
    _startSimulation();
  }

  void _startSimulation() {
    _timer?.cancel();
    // Em mock mode o intervalo é maior — dados já estáveis, evita re-renders desnecessários
    final interval = SupabaseService.isMockMode
        ? const Duration(seconds: 60)
        : const Duration(seconds: 5);
    _timer = Timer.periodic(interval, (timer) async {
      try {
        final newBatches = await SupabaseService.getBatches();
        ref.read(availableBatchesProvider.notifier).setBatches(newBatches);
        
        if (state != null && newBatches.isNotEmpty) {
          // Try to keep the same batch selected, but updated
          final updatedBatch = newBatches.where((b) => b.id == state!.id).firstOrNull;
          if (updatedBatch != null) {
            state = _todayOnly(updatedBatch);
          }
        }
      } catch (e) {
        debugPrint('Erro na atualização automática: $e');
      }
    });
  }

  void updateAppleDiagnosis(String appleId, String newLabel) {
    if (state == null) return;
    
    final updatedApples = state!.apples.map((apple) {
      if (apple.id == appleId) {
        final updatedFrames = apple.frames.map((frame) {
          final newProbs = <String, double>{newLabel: 1.0};
          return frame.copyWith(
            probabilities: newProbs,
            diseaseSum: newLabel == 'Healthy' ? 0.0 : 1.0,
          );
        }).toList();
        return apple.copyWith(frames: updatedFrames);
      }
      return apple;
    }).toList();

    state = Batch(
      id: state!.id,
      name: state!.name,
      date: state!.date,
      apples: updatedApples,
      location: state!.location,
    );

    // 1. Update the cache on disk immediately
    LocalCacheService.updateAppleInCache(appleId, newLabel);

    // 2. Update availableBatchesProvider to prevent reversion on the next timer poll
    final updatedBatches = ref.read(availableBatchesProvider).map((b) {
      if (b.id == state!.id) {
        return state!;
      }
      return b;
    }).toList();
    ref.read(availableBatchesProvider.notifier).setBatches(updatedBatches);
  }
}

final batchProvider = NotifierProvider<BatchNotifier, Batch?>(BatchNotifier.new);

class SelectedConditionFilterNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggleFilter(String filter) {
    if (state.contains(filter)) {
      state = {...state}..remove(filter);
    } else {
      state = {...state, filter};
    }
  }

  void resetFilter() => state = {};
}

final selectedConditionFilterProvider = NotifierProvider<SelectedConditionFilterNotifier, Set<String>>(SelectedConditionFilterNotifier.new);

final filteredApplesProvider = Provider<List<Apple>>((ref) {
  final batch = ref.watch(batchProvider);
  final activeFilters = ref.watch(selectedConditionFilterProvider);

  if (batch == null) return [];
  
  // Filtramos maçãs com pelo menos 1 frame com imagem real no Storage.
  // Maçãs antigas importadas (image_url=NULL) ficam fora da grelha
  // mas continuam nos dados para gráficos e KPIs.
  final validApples = batch.apples
      .where((a) => a.frames.any((f) => f.url.isNotEmpty))
      .toList();

  if (activeFilters.isEmpty) return validApples;

  return validApples.where((apple) => activeFilters.contains(apple.primaryCondition)).toList();
});

class CurrentPageNotifier extends Notifier<String> {
  @override
  String build() => 'Controlo do Pomar'; 
  
  void setPage(String page) {
    state = page;
  }
}

final currentPageProvider = NotifierProvider<CurrentPageNotifier, String>(CurrentPageNotifier.new);

class SessionActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setActive(bool isActive) {
    state = isActive;
  }
}

final sessionActiveProvider = NotifierProvider<SessionActiveNotifier, bool>(SessionActiveNotifier.new);

class ForcedTriageNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggleForced(String appleId) {
    final newState = Set<String>.from(state);
    if (newState.contains(appleId)) {
      newState.remove(appleId);
    } else {
      newState.add(appleId);
    }
    state = newState;
  }
}

final forcedTriageProvider = NotifierProvider<ForcedTriageNotifier, Set<String>>(ForcedTriageNotifier.new);

final uncertainApplesProvider = Provider<List<Apple>>((ref) {
  final batch = ref.watch(batchProvider);
  final forced = ref.watch(forcedTriageProvider);
  if (batch == null) return [];

  return batch.apples.where((apple) {
    if (forced.contains(apple.id)) return true;

    final frame = apple.worstFrame;
    if (frame == null) return false;
    final primaryCond = apple.primaryCondition;
    final prob = frame.probabilities[primaryCond] ?? 1.0;
    
    if (primaryCond == 'Healthy') return false;
    
    // Regra: Incerteza real < 80%
    if (prob < 0.80) return true;
    
    // Regra: Auditoria de qualidade (5% das imagens entre 80% e 85%)
    if (prob < 0.85) {
      return (apple.id.hashCode % 100) < 5;
    }
    
    return false;
  }).toList();
});

class CorrectionHistoryNotifier extends Notifier<List<CorrectionHistory>> {
  @override
  List<CorrectionHistory> build() => [];

  void upsertCorrection(CorrectionHistory correction) {
    final existingIndex = state.indexWhere((c) => c.appleId == correction.appleId);
    if (existingIndex != -1) {
      final newList = [...state];
      newList[existingIndex] = correction;
      state = newList;
    } else {
      state = [...state, correction];
    }
  }
}

final correctionHistoryProvider = NotifierProvider<CorrectionHistoryNotifier, List<CorrectionHistory>>(CorrectionHistoryNotifier.new);

/// Registos de `manual_review` (todas as validações humanas).
/// Fonte única para a matriz de confusão, o gráfico de calibração e o KPI de
/// fila humana — evita queries duplicadas. Refaz o fetch sempre que uma nova
/// correção é registada na sessão.
final manualReviewsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(correctionHistoryProvider);
  return SupabaseService.getManualReviews();
});

/// Feed da tabela `producao_atual` — últimos resultados finais da linha.
/// Polling: 10s em produção, 60s em mock (dados estáveis).
final producaoAtualProvider = FutureProvider.autoDispose<List<ProducaoRecord>>((ref) async {
  final interval = SupabaseService.isMockMode
      ? const Duration(seconds: 60)
      : const Duration(seconds: 10);
  final timer = Timer(interval, () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);
  return SupabaseService.getProducaoAtual();
});

/// Confiança média do lote: 1 - diseaseSum (em percentagem)
final avgConfidenceProvider = Provider<double>((ref) {
  final batch = ref.watch(batchProvider);
  if (batch == null || batch.apples.isEmpty) return 0.0;
  
  final totalConf = batch.apples.fold(0.0, (sum, a) => sum + a.effectiveConfidence);
  final avg = totalConf / batch.apples.length;
  
  return (avg * 100).clamp(0.0, 100.0);
});

/// Maçãs doentes inspecionadas: todas com condição != Healthy
final diseasedApplesProvider = Provider<List<Apple>>((ref) {
  final batch = ref.watch(batchProvider);
  if (batch == null) return [];
  return batch.apples.where((a) => a.primaryCondition != 'Healthy').toList()
    ..sort((a, b) => (b.worstFrame?.diseaseSum ?? b.effectiveConfidence).compareTo(a.worstFrame?.diseaseSum ?? a.effectiveConfidence));
});

class GlobalStats {
  final int totalApples;
  final int totalFrames;
  final int totalHealthy;
  final int totalAnomalies;
  final double globalApproval;
  final double avgConf;
  final String dominantAnomaly;
  final int dominantAnomalyCount;
  final Map<String, int> anomalyDistribution;
  final Batch? urgentBatch;
  final int humanQueue;
  final String surgeAlert;
  final double automationRate;
  final List<Batch> dailyBatches;
  final double delta;

  GlobalStats({
    required this.totalApples,
    required this.totalFrames,
    required this.totalHealthy,
    required this.totalAnomalies,
    required this.globalApproval,
    required this.avgConf,
    required this.dominantAnomaly,
    required this.dominantAnomalyCount,
    required this.anomalyDistribution,
    required this.urgentBatch,
    required this.humanQueue,
    required this.surgeAlert,
    required this.automationRate,
    required this.dailyBatches,
    required this.delta,
  });
}

final globalStatsProvider = Provider<GlobalStats?>((ref) {
  final allBatches = ref.watch(filteredBatchesProvider);
  final corrections = ref.watch(correctionHistoryProvider);
  final reviewsAsync = ref.watch(manualReviewsProvider);

  if (allBatches.isEmpty) return null;

  final batches = [...allBatches]..sort((a, b) => a.location.compareTo(b.location));

  final allApples = batches.expand((b) => b.apples).toList();
  Map<String, List<Apple>> applesByDay = {};
  for (var a in allApples) {
    String dateKey = "${a.timestamp.year}-${a.timestamp.month.toString().padLeft(2, '0')}-${a.timestamp.day.toString().padLeft(2, '0')}";
    if (!applesByDay.containsKey(dateKey)) applesByDay[dateKey] = [];
    applesByDay[dateKey]!.add(a);
  }

  List<Batch> dailyBatches = applesByDay.entries.map((e) {
    e.value.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Batch(
      id: e.key,
      name: e.key,
      date: e.value.first.timestamp,
      apples: e.value,
      location: 'Global',
    );
  }).toList();
  dailyBatches.sort((a, b) => a.date.compareTo(b.date));

  int totalApples = 0, totalHealthy = 0, totalAnomalies = 0, totalFrames = 0, confCount = 0;
  double sumConf = 0;
  final gDist = <String, int>{'Healthy': 0, 'Rot': 0, 'Scab': 0, 'Blotch': 0, 'Anthracnose': 0};

  for (final b in batches) {
    totalApples += b.totalApples;
    totalFrames += b.totalFrames;
    b.healthDistribution.forEach((k, v) => gDist[k] = (gDist[k] ?? 0) + v);
    totalHealthy += b.healthDistribution['Healthy'] ?? 0;
    for (final a in b.apples) {
      sumConf += a.effectiveConfidence;
      confCount++;
      if (a.primaryCondition != 'Healthy') totalAnomalies++;
    }
  }

  final globalApproval = totalApples > 0 ? (totalHealthy / totalApples * 100) : 0.0;
  final avgConf = confCount > 0 ? (sumConf / confCount * 100) : 0.0;

  String gDom = 'Nenhuma';
  int gDomN = 0;
  gDist.forEach((k, v) {
    if (k != 'Healthy' && v > gDomN) {
      gDomN = v;
      gDom = k;
    }
  });

  final urgentBatch = batches.isNotEmpty ? ([...batches]..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore))).first : null;

  double groupApproval(List<Batch> bs) {
    if (bs.isEmpty) return 0;
    int t = bs.fold(0, (s, b) => s + b.totalApples);
    int h = bs.fold(0, (s, b) => s + (b.healthDistribution['Healthy'] ?? 0));
    return t > 0 ? (h / t) * 100 : 0.0;
  }

  final mid = dailyBatches.isNotEmpty ? (dailyBatches.length ~/ 2 == 0 ? 1 : dailyBatches.length ~/ 2) : 1;
  final d1 = groupApproval(dailyBatches.sublist(0, mid > dailyBatches.length ? dailyBatches.length : mid));
  final d2 = groupApproval(dailyBatches.sublist(mid > dailyBatches.length ? dailyBatches.length : mid));
  final delta = d2 - d1;

  // Fila humana real: contagem de manual_review pendentes. Enquanto a query
  // não devolve dados (loading/erro), usa a heurística de amostragem (4,5%).
  final reviews = reviewsAsync.value;
  final int humanQueue;
  if (reviews != null) {
    humanQueue = reviews.where((r) => (r['status'] as String? ?? '') == 'pending').length;
  } else {
    final int humanQ = (totalApples * 0.045).toInt() - corrections.length;
    humanQueue = humanQ < 0 ? 0 : humanQ;
  }
  final surgeAlert = gDom == 'Nenhuma' || gDom == 'Healthy' ? 'Estável' : '$gDom (+14%)';
  final automationRate = totalApples > 0 ? ((totalApples - corrections.length - humanQueue) / totalApples) * 100 : 0.0;

  return GlobalStats(
    totalApples: totalApples,
    totalFrames: totalFrames,
    totalHealthy: totalHealthy,
    totalAnomalies: totalAnomalies,
    globalApproval: globalApproval,
    avgConf: avgConf,
    dominantAnomaly: gDom,
    dominantAnomalyCount: gDomN,
    anomalyDistribution: gDist,
    urgentBatch: urgentBatch,
    humanQueue: humanQueue,
    surgeAlert: surgeAlert,
    automationRate: automationRate,
    dailyBatches: dailyBatches,
    delta: delta,
  );
});

class BatchStats {
  final String dominantAnomaly;
  final int dominantAnomalyCount;
  final double approvalRate;
  
  BatchStats({
    required this.dominantAnomaly,
    required this.dominantAnomalyCount,
    required this.approvalRate,
  });
}

final batchStatsProvider = Provider<BatchStats?>((ref) {
  final batch = ref.watch(batchProvider);
  if (batch == null) return null;

  final distribution = batch.healthDistribution;
  
  String dominant = 'Nenhuma';
  int domCount = 0;
  distribution.forEach((k, v) {
    if (k != 'Healthy' && v > domCount) {
      domCount = v;
      dominant = k;
    }
  });

  final approvalRate = batch.totalApples > 0
      ? (distribution['Healthy']! / batch.totalApples * 100)
      : 0.0;

  return BatchStats(
    dominantAnomaly: dominant,
    dominantAnomalyCount: domCount,
    approvalRate: approvalRate,
  );
});

class ThemeNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() {
    state = !state;
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, bool>(ThemeNotifier.new);

class BatchTriagemFilterNotifier extends Notifier<String> {
  @override
  String build() => '5t';
  void setFilter(String f) => state = f;
}
final batchTriagemFilterProvider = NotifierProvider<BatchTriagemFilterNotifier, String>(BatchTriagemFilterNotifier.new);

class DismissedOutbreaksNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void dismiss(String batchId) {
    state = {...state, batchId};
  }

  void reset() {
    state = {};
  }
}

final dismissedOutbreaksProvider = NotifierProvider<DismissedOutbreaksNotifier, Set<String>>(DismissedOutbreaksNotifier.new);

class OutbreaksPopupDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setDismissed(bool value) {
    state = value;
  }
}

final outbreaksPopupDismissedProvider = NotifierProvider<OutbreaksPopupDismissedNotifier, bool>(
  OutbreaksPopupDismissedNotifier.new,
);

// ---------------------------------------------------------------------------
// Raspberry Pi 5 Heartbeat Provider
// Faz polling a http://localhost:8766/heartbeat a cada 5 segundos.
// O ws_server.py serve esse endpoint com o último heartbeat recebido do Pi.
// ---------------------------------------------------------------------------

final raspberryHeartbeatProvider = FutureProvider.autoDispose<RaspberryHeartbeat>((ref) async {
  final timer = Timer(const Duration(seconds: 5), () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);

  // Mock: devolve um heartbeat simulado (Pi ligado e ativo)
  if (SupabaseService.isMockMode) {
    await Future.delayed(const Duration(milliseconds: 200));
    return RaspberryHeartbeat(
      deviceId: 'pi5-mock',
      timestamp: DateTime.now(),
      cpuTemp: 52.3,
      cpuPercent: 18.5,
      ramUsedMb: 1823,
      ramTotalMb: 4096,
      diskUsedGb: 14.2,
      diskTotalGb: 64.0,
      mode: 'active',
      uptimeSeconds: 86400,
      inferenceCount: 1247,
      cameraFps: 4.2,
      lastBlurScore: 312.5,
      blurWarning: false,
    );
  }

  try {
    final response = await http
        .get(Uri.parse(AppConstants.heartbeatUrl))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] == 'offline') return RaspberryHeartbeat.offline();
      return RaspberryHeartbeat.fromJson(json);
    }
  } catch (_) {}
  return RaspberryHeartbeat.offline();
});

// ---------------------------------------------------------------------------
// Configuração da câmara — partilhada entre o painel de sliders e o botão RESTART
// ---------------------------------------------------------------------------

class CameraConfig {
  final double lensPosition;   // dpt (0 = autofocus)
  final double shutterUs;      // µs de exposição
  final double burst;          // n.º de fotos em rajada
  final double burstInterval;  // ms entre fotos
  final double motionThreshold;// sensibilidade ao movimento (px)
  final double triggerDelay;   // segundos após deteção de movimento
  final double sharpness;
  final double contrast;
  final double saturation;
  final double noiseReduction; // 0-4

  const CameraConfig({
    this.lensPosition = 0.0,
    this.shutterUs = 8000,
    this.burst = 1,
    this.burstInterval = 150,
    this.motionThreshold = 12,
    this.triggerDelay = 0.1,
    this.sharpness = 1.5,
    this.contrast = 1.2,
    this.saturation = 1.2,
    this.noiseReduction = 1,
  });

  CameraConfig copyWith({
    double? lensPosition, double? shutterUs, double? burst, double? burstInterval,
    double? motionThreshold, double? triggerDelay, double? sharpness,
    double? contrast, double? saturation, double? noiseReduction,
  }) => CameraConfig(
    lensPosition: lensPosition ?? this.lensPosition,
    shutterUs: shutterUs ?? this.shutterUs,
    burst: burst ?? this.burst,
    burstInterval: burstInterval ?? this.burstInterval,
    motionThreshold: motionThreshold ?? this.motionThreshold,
    triggerDelay: triggerDelay ?? this.triggerDelay,
    sharpness: sharpness ?? this.sharpness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    noiseReduction: noiseReduction ?? this.noiseReduction,
  );

  Map<String, dynamic> toFlags() => {
    '--lens-position': double.parse(lensPosition.toStringAsFixed(2)),
    '--shutter-us': shutterUs.round(),
    '--burst': burst.round(),
    '--burst-interval': burstInterval.round(),
    '--motion-threshold': motionThreshold.round(),
    '--trigger-delay': double.parse(triggerDelay.toStringAsFixed(2)),
    '--sharpness': double.parse(sharpness.toStringAsFixed(1)),
    '--contrast': double.parse(contrast.toStringAsFixed(1)),
    '--saturation': double.parse(saturation.toStringAsFixed(1)),
    '--noise-reduction': noiseReduction.round(),
  };
}

class CameraConfigNotifier extends Notifier<CameraConfig> {
  @override
  CameraConfig build() => const CameraConfig();

  void update(CameraConfig Function(CameraConfig) fn) => state = fn(state);
}

final cameraConfigProvider =
    NotifierProvider<CameraConfigNotifier, CameraConfig>(CameraConfigNotifier.new);

// ---------------------------------------------------------------------------
// Shadow CNN — estado global (badge persistente no header, visível em
// qualquer página, independente de a página MLOps estar aberta).
// Faz polling a /shadow/status a cada 10s enquanto o header estiver visível.
// ---------------------------------------------------------------------------
final shadowGlobalStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final timer = Timer(const Duration(seconds: 10), () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);

  if (SupabaseService.isMockMode) {
    return {'state': 'idle', 'model': null, 'apples_processed': 0};
  }
  try {
    final r = await http
        .get(Uri.parse('${AppConstants.mlopsUrl}/shadow/status'))
        .timeout(const Duration(seconds: 4));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
  } catch (_) {}
  return {'state': 'idle', 'model': null, 'apples_processed': 0};
});

class HeaderVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setVisible(bool visible) {
    if (state != visible) {
      state = visible;
    }
  }
}

final headerVisibleProvider = NotifierProvider<HeaderVisibleNotifier, bool>(HeaderVisibleNotifier.new);

