import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';

class AvailableBatchesNotifier extends Notifier<List<Batch>> {
  @override
  List<Batch> build() => [];
  
  void setBatches(List<Batch> batches) {
    state = batches;
  }
}

final availableBatchesProvider = NotifierProvider<AvailableBatchesNotifier, List<Batch>>(AvailableBatchesNotifier.new);

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
  
  void setBatch(Batch batch) {
    state = batch;
    ref.read(selectedConditionFilterProvider.notifier).resetFilter();
    _startSimulation();
  }

  void _startSimulation() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        // Pull fresh data from Supabase periodically instead of mocking
        final newBatches = await SupabaseService.getBatches();
        ref.read(availableBatchesProvider.notifier).setBatches(newBatches);
        
        if (state != null && newBatches.isNotEmpty) {
          // Try to keep the same batch selected, but updated
          final updatedBatch = newBatches.where((b) => b.id == state!.id).firstOrNull;
          if (updatedBatch != null) {
            state = updatedBatch;
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
    );
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
  
  // Filtramos apenas maçãs que já tenham pelo menos 1 frame (evita erros de sincronismo na BD)
  final validApples = batch.apples.where((a) => a.frames.isNotEmpty).toList();

  if (activeFilters.isEmpty) return validApples;

  return validApples.where((apple) => activeFilters.contains(apple.primaryCondition)).toList();
});

class CurrentPageNotifier extends Notifier<String> {
  @override
  String build() => 'Tapete'; 
  
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
    
    // Regra: Incerteza real < 70%
    if (prob < 0.70) return true;
    
    // Regra: Auditoria de qualidade (5% das imagens entre 70% e 80%)
    if (prob < 0.80) {
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
  final allBatches = ref.watch(availableBatchesProvider);
  final corrections = ref.watch(correctionHistoryProvider);

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

  final int humanQ = (totalApples * 0.045).toInt() - corrections.length;
  final humanQueue = humanQ < 0 ? 0 : humanQ;
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

