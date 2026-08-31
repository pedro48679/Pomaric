import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

/// Recorta os lotes a uma janela temporal, AO NÍVEL DA MAÇÃ.
///
/// Um "lote" (`Batch`) aqui não é uma colheita datada: `getBatches` agrupa as
/// maçãs por LOCALIZAÇÃO, por isso um lote é um sítio permanente que acumula
/// maçãs de todas as datas, e `batch.date` é apenas o timestamp da maçã mais
/// recente desse sítio. Filtrar com `b.date.isAfter(threshold)` testava só
/// essa única maçã: bastava o sítio ter uma maçã recente para entrar inteiro,
/// arrastando maçãs de semanas atrás. Como todos os sítios ativos têm maçãs
/// recentes, o filtro não excluía nada e 7d e 30d davam exatamente o mesmo.
///
/// Todos os gráficos consomem `batch.apples` (totalApples, healthDistribution,
/// contaminationScore, etc. derivam daí), por isso a janela tem de ser aplicada
/// às maçãs. Lotes que fiquem sem maçãs na janela são removidos, e `date` é
/// recalculada a partir das maçãs que restam.
List<Batch> _batchesWithinWindow(List<Batch> batches, Duration window) {
  if (batches.isEmpty) return const [];
  final threshold = DateTime.now().subtract(window);

  final result = <Batch>[];
  for (final b in batches) {
    final kept = b.apples.where((a) => a.timestamp.isAfter(threshold)).toList();
    if (kept.isEmpty) continue;

    kept.sort((x, y) => y.timestamp.compareTo(x.timestamp));
    result.add(Batch(
      id: b.id,
      name: b.name,
      date: kept.first.timestamp,
      apples: kept,
      location: b.location,
    ));
  }

  result.sort((a, b) => b.date.compareTo(a.date));
  return result;
}

// Reage ao botão 7d/30d do cabeçalho. Usado SÓ pelo Capítulo 1 · Visão
// Global (KPIs, SPC de cadência, evolução de anomalias). Os Capítulos 2 e 3
// não devem reagir a este botão, usam sempre chapter23BatchesProvider.
final filteredBatchesProvider = Provider<List<Batch>>((ref) {
  final allBatches = ref.watch(availableBatchesProvider);
  final range = ref.watch(dateRangeFilterProvider);

  return _batchesWithinWindow(
    allBatches,
    range == '7d' ? const Duration(days: 7) : const Duration(days: 30),
  );
});

// Janela fixa de 7 dias, independente do botão 7d/30d (esse botão só
// controla o Capítulo 1). Padrão para todos os gráficos dos Capítulos 2
// (Análise & Comparação de Lotes) e 3 (Performance da CNN).
final chapter23BatchesProvider = Provider<List<Batch>>((ref) {
  final allBatches = ref.watch(availableBatchesProvider);
  return _batchesWithinWindow(allBatches, const Duration(days: 7));
});

/// Agrupa maçãs de vários lotes por dia de captura, um "lote sintético" por
/// dia (usado nos gráficos de evolução temporal).
List<Batch> _groupBatchesByDay(List<Batch> batches) {
  final Map<String, List<Apple>> applesByDay = {};
  for (final a in batches.expand((b) => b.apples)) {
    final dateKey =
        "${a.timestamp.year}-${a.timestamp.month.toString().padLeft(2, '0')}-${a.timestamp.day.toString().padLeft(2, '0')}";
    applesByDay.putIfAbsent(dateKey, () => []).add(a);
  }

  final dailyBatches = applesByDay.entries.map((e) {
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
  return dailyBatches;
}

// Evolução temporal do Capítulo 3 (ex.: gráfico "Evolução" do CNN), sempre
// na janela fixa de 7 dias, NÃO reage ao botão 7d/30d do Capítulo 1.
final chapter3DailyBatchesProvider = Provider<List<Batch>>((ref) {
  final batches = ref.watch(chapter23BatchesProvider);
  return _groupBatchesByDay(batches);
});

final loadDataFutureProvider = FutureProvider<void>((ref) async {
  // Semear a fila de pendentes ANTES de publicar os lotes, evita que
  // globalStatsProvider (que reage a availableBatchesProvider) calcule
  // humanQueue=0 por instantes até este fetch terminar.
  final pendingIds = await SupabaseService.getPendingReviewIds();
  ref.read(dbPendingReviewProvider.notifier).setAll(pendingIds);

  final batches = await SupabaseService.getBatches();
  // getBatches pode ter acionado o failsafe (BD inacessível), espelhar
  // já para a UI mostrar o banner desde o primeiro ecrã.
  ref.read(failsafeMockProvider.notifier).sync();
  ref.read(availableBatchesProvider.notifier).setBatches(batches);
  if (batches.isNotEmpty) {
    ref.read(batchProvider.notifier).setBatch(batches.first);
  }
  
  // Carregar histórico de correções prévias
  final reviews = await SupabaseService.getManualReviews();
  final List<CorrectionHistory> historyList = [];
  
  final Map<String, Apple> appleLookup = {};
  final Map<String, String> batchLookup = {};
  for (final b in batches) {
    for (final a in b.apples) {
      appleLookup[a.id] = a;
      batchLookup[a.id] = b.id;
    }
  }
  
  for (final r in reviews) {
    if (r['status'] == 'completed') {
      final aId = r['apple_id'] as String;
      final apple = appleLookup[aId];
      if (apple != null) {
        historyList.add(CorrectionHistory(
          batchId: batchLookup[aId] ?? 'unknown',
          appleId: aId,
          frameUrl: apple.worstFrameUrl,
          annotations: const [], // Não carregamos circles_manual para não pesar na RAM, mas o histórico fica visível
          label: r['corrected_class'] as String? ?? 'Desconhecido',
          correctedBy: r['updated_by'] as String? ?? 'Desconhecido',
          timestamp: r['updated_at'] != null ? DateTime.parse(r['updated_at'] as String) : DateTime.now(),
        ));
      }
    }
  }
  
  historyList.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  ref.read(correctionHistoryProvider.notifier).setAll(historyList);
});

class BatchNotifier extends Notifier<Batch?> {
  Timer? _timer;
  int _tickCount = 0;

  // A cada 12 ticks (~60s a 5s/tick), reconciliação completa (mas barata,
  // só `apple_id` de linhas 'pending') de `dbPendingReviewProvider`. Cobre
  // remoções (DELETE, em `unflagForReview`) que o sync incremental por
  // `updated_at` nunca vê (um DELETE não deixa rasto num delta-fetch).
  static const int _pendingReconcileEveryNTicks = 12;

  // A cada 6 ticks (~30s a 5s/tick) em modo failsafe, tentar reconectar à
  // BD real. Em sucesso, loadDataFutureProvider é invalidado e a app volta
  // sozinha a dados reais (o banner desaparece via failsafeMockProvider).
  static const int _reconnectEveryNTicks = 6;

  // Correções 'completed' recebidas pelo delta cuja maçã ainda não estava na
  // cache local (corrida maçã-nova/correção, ou maçã purgada >30d). O cursor
  // já avançou, sem isto ficavam ignoradas para sempre. Tentadas de novo a
  // cada tick, depois do getBatches (que pode entretanto trazer a maçã).
  final Map<String, Map<String, dynamic>> _correcoesPorAplicar = {};

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
    // Em mock mode o intervalo é maior, dados já estáveis, evita re-renders desnecessários
    final interval = SupabaseService.isMockMode
        ? const Duration(seconds: 60)
        : const Duration(seconds: 5);
    // Com o timer lento (60s, mock), tentar reconectar em todos os ticks;
    // com o rápido (5s), só a cada _reconnectEveryNTicks.
    final isSlowTick = interval.inSeconds >= 60;
    _timer = Timer.periodic(interval, (timer) async {
      try {
        _tickCount++;

        // Reconexão automática do failsafe (nunca do mock explícito).
        if (SupabaseService.isFailsafeMock &&
            (isSlowTick || _tickCount % _reconnectEveryNTicks == 0)) {
          if (await SupabaseService.tryReconnect()) {
            // Recarrega tudo real (batches, histórico, pendentes), também
            // reinicia este timer no intervalo rápido, via setBatch.
            ref.invalidate(loadDataFutureProvider);
          }
        }

        await _syncManualReviews();

        if (!SupabaseService.isMockMode && _tickCount % _pendingReconcileEveryNTicks == 0) {
          final pendingIds = await SupabaseService.getPendingReviewIds();
          ref.read(dbPendingReviewProvider.notifier).setAll(pendingIds);
        }

        final newBatches = await SupabaseService.getBatches();
        ref.read(availableBatchesProvider.notifier).setBatches(newBatches);

        if (state != null && newBatches.isNotEmpty) {
          // Try to keep the same batch selected, but updated
          final updatedBatch = newBatches.where((b) => b.id == state!.id).firstOrNull;
          if (updatedBatch != null) {
            state = _todayOnly(updatedBatch);
          }
        }

        _retryPendingCorrections();
      } catch (e) {
        debugPrint('Erro na atualização automática: $e');
      } finally {
        // getBatches pode ter acabado de flippar o failsafe (BD caiu) ou a
        // reconexão acima de o limpar, espelhar para a UI (banner).
        ref.read(failsafeMockProvider.notifier).sync();
      }
    });
  }

  /// Sincronização incremental de `manual_review`, por cursor `updated_at`
  /// (`LocalCacheService.lastManualReviewSync`), nunca um SELECT * completo.
  /// Aplica correções concluídas (incluindo reedições posteriores de uma
  /// linha já 'completed') ao cache local e mantém `dbPendingReviewProvider`
  /// atualizado, para que a matriz e a fila de triagem reflitam mudanças
  /// feitas por qualquer sessão/dispositivo dentro de um ciclo do timer.
  Future<void> _syncManualReviews() async {
    if (SupabaseService.isMockMode) return;

    final newRows = await SupabaseService.getManualReviewsSince(LocalCacheService.lastManualReviewSync);
    if (newRows.isEmpty) return;

    final appleLookup = {for (final a in LocalCacheService.inMemoryApples) a.id: a};
    final batchLookup = <String, String>{};
    for (final b in ref.read(availableBatchesProvider)) {
      for (final a in b.apples) {
        batchLookup[a.id] = b.id;
      }
    }

    DateTime? maxUpdatedAt;
    bool cacheChanged = false;
    final pendingToAdd = <String>{};
    final pendingToRemove = <String>{};

    for (final row in newRows) {
      final appleId = row['apple_id'] as String?;
      if (appleId == null) continue;
      final status = row['status'] as String? ?? '';
      final updatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');
      if (updatedAt != null && (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt))) {
        maxUpdatedAt = updatedAt;
      }

      if (status == 'pending') {
        pendingToAdd.add(appleId);
        // Voltou a pendente, uma correção antiga guardada já não é a última palavra.
        _correcoesPorAplicar.remove(appleId);
      } else {
        pendingToRemove.add(appleId);
      }

      if (status == 'completed') {
        final correctedClass = row['corrected_class'] as String?;
        if (correctedClass != null) {
          final apple = appleLookup[appleId];
          if (apple != null) {
            _applyCompletedRow(row, apple, batchLookup);
            cacheChanged = true;
            _correcoesPorAplicar.remove(appleId);
          } else {
            _correcoesPorAplicar[appleId] = row;
          }
        }
      }
    }

    if (pendingToAdd.isNotEmpty || pendingToRemove.isNotEmpty) {
      ref.read(dbPendingReviewProvider.notifier).apply(add: pendingToAdd, remove: pendingToRemove);
    }
    if (cacheChanged) {
      LocalCacheService.saveToDisk();
    }
    if (maxUpdatedAt != null) {
      // Cursor exato (sem margem de segurança): getManualReviewsSince usa
      // `.gt`, não `.gte`, por isso qualquer subtração aqui faria o cursor
      // nunca avançar depois da última linha real, refetch infinito da
      // mesma linha em todos os ticks seguintes.
      LocalCacheService.lastManualReviewSync = maxUpdatedAt.toIso8601String();
      if (!cacheChanged) LocalCacheService.saveToDisk();
    }
  }

  /// Aplica uma linha 'completed' de manual_review ao cache local e ao
  /// histórico de correções (partilhado entre o sync incremental e a fila
  /// de retry _correcoesPorAplicar).
  void _applyCompletedRow(Map<String, dynamic> row, Apple apple, Map<String, String> batchLookup) {
    final appleId = row['apple_id'] as String;
    final correctedClass = row['corrected_class'] as String;
    final updatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');
    LocalCacheService.updateAppleInCache(appleId, correctedClass, persist: false);
    ref.read(correctionHistoryProvider.notifier).upsertCorrection(CorrectionHistory(
      batchId: batchLookup[appleId] ?? 'unknown',
      appleId: appleId,
      frameUrl: apple.worstFrameUrl,
      annotations: const [],
      label: correctedClass,
      correctedBy: row['updated_by'] as String? ?? 'Desconhecido',
      timestamp: updatedAt ?? DateTime.now(),
    ));
  }

  /// Reaplica correções que chegaram antes da respetiva maçã (ver
  /// _correcoesPorAplicar), chamado a cada tick DEPOIS do getBatches.
  void _retryPendingCorrections() {
    if (_correcoesPorAplicar.isEmpty) return;
    final appleLookup = {for (final a in LocalCacheService.inMemoryApples) a.id: a};
    final batchLookup = <String, String>{};
    for (final b in ref.read(availableBatchesProvider)) {
      for (final a in b.apples) {
        batchLookup[a.id] = b.id;
      }
    }
    bool applied = false;
    for (final appleId in _correcoesPorAplicar.keys.toList()) {
      final apple = appleLookup[appleId];
      if (apple == null) continue;
      _applyCompletedRow(_correcoesPorAplicar[appleId]!, apple, batchLookup);
      _correcoesPorAplicar.remove(appleId);
      applied = true;
    }
    if (applied) LocalCacheService.saveToDisk();
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

class MultiClassFilterNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void set(bool value) => state = value;
}

final multiClassFilterProvider = NotifierProvider<MultiClassFilterNotifier, bool>(MultiClassFilterNotifier.new);

final filteredApplesProvider = Provider<List<Apple>>((ref) {
  final batch = ref.watch(batchProvider);
  final activeFilters = ref.watch(selectedConditionFilterProvider);
  final onlyMultiClass = ref.watch(multiClassFilterProvider);

  if (batch == null) return [];
  
  final validApples = batch.apples
      .where((a) => a.frames.any((f) => f.url.isNotEmpty))
      .toList();

  return validApples.where((apple) {
    if (apple.primaryCondition.toLowerCase() == 'lixo') return false;
    final probs = apple.worstFrame?.probabilities ?? {};
    
    if (onlyMultiClass) {
      int activePathologies = 0;
      for (var p in probs.values) {
        if (p > 0.05) activePathologies++;
      }
      if (activePathologies < 2) return false;
    }
    
    if (activeFilters.isNotEmpty) {
      if (onlyMultiClass) {
        // AND logic: apple must contain ALL selected filters with prob > 5%
        for (final filter in activeFilters) {
           if ((probs[filter] ?? 0.0) <= 0.05) {
              return false;
           }
        }
      } else {
        // OR logic: apple's primary condition must be one of the selected filters
        if (!activeFilters.contains(apple.primaryCondition)) {
          return false;
        }
      }
    }
    
    return true;
  }).toList();
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

/// IDs de maçãs com uma linha `manual_review` 'pending' na BD, cross-device,
/// ao contrário de `forcedTriageProvider` (só a sessão local). Semeado uma
/// vez no arranque (`loadDataFutureProvider`) e depois mantido de forma
/// incremental pelo polling em `BatchNotifier` (`_syncManualReviews`), nunca
/// por um novo full-fetch.
class DbPendingReviewNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void setAll(Set<String> ids) => state = ids;

  void apply({Set<String> add = const {}, Set<String> remove = const {}}) {
    if (add.isEmpty && remove.isEmpty) return;
    state = (Set<String>.from(state)..addAll(add)..removeAll(remove));
  }
}

final dbPendingReviewProvider = NotifierProvider<DbPendingReviewNotifier, Set<String>>(DbPendingReviewNotifier.new);

/// Espelho reativo de `SupabaseService.isFailsafeMock` (um static bool não
/// dispara rebuilds). O `DashboardScreen` observa isto para mostrar o banner
/// "dados de demonstração"; `sync()` é chamado após cada operação que pode
/// mudar o flag (ticks do BatchNotifier, carga inicial).
class FailsafeMockNotifier extends Notifier<bool> {
  @override
  bool build() => SupabaseService.isFailsafeMock;

  void sync() {
    if (state != SupabaseService.isFailsafeMock) {
      state = SupabaseService.isFailsafeMock;
    }
  }
}

final failsafeMockProvider = NotifierProvider<FailsafeMockNotifier, bool>(FailsafeMockNotifier.new);

/// Seed de auditoria: gerada uma única vez por sessão da app (não observa
/// nenhum outro provider, por isso o Riverpod calcula-a uma vez e mantém em
/// cache, nunca usar `.autoDispose` aqui, senão a seed reiniciava sempre que
/// a página fosse desmontada). Combinada com o ID da maçã em `isUncertainApple`,
/// dá uma amostra de auditoria de 5% estável dentro da sessão (a mesma maçã
/// não "pisca" entre re-renders) mas diferente a cada lançamento da app -
/// antes disto, `apple.id.hashCode % 100 < 5` escolhia sempre as mesmas maçãs,
/// para sempre, disfarçado de amostra aleatória.
final auditSampleSeedProvider = Provider<int>((ref) => Random().nextInt(1 << 32));

/// Regra partilhada de "esta maçã precisa de revisão humana?", usada tanto
/// por este provider (lote em foco) como pelo Funil de Triagem (pomar
/// inteiro), que antes reimplementava a mesma regra de forma independente.
bool isUncertainApple(Apple apple, int auditSeed) {
  final frame = apple.worstFrame;
  if (frame == null) return false;
  final primaryCond = apple.primaryCondition;
  final prob = frame.probabilities[primaryCond] ?? 1.0;

  // Regra: Incerteza real < 80%
  if (prob < 0.80) return true;

  // Regra: Auditoria de qualidade (5% das imagens entre 80% e 85%)
  if (prob < 0.85) {
    return Random(apple.id.hashCode ^ auditSeed).nextInt(100) < 5;
  }

  return false;
}

final uncertainApplesProvider = Provider<List<Apple>>((ref) {
  final batch = ref.watch(batchProvider);
  final forced = ref.watch(forcedTriageProvider);
  final dbPending = ref.watch(dbPendingReviewProvider);
  final auditSeed = ref.watch(auditSampleSeedProvider);
  if (batch == null) return [];

  final matched = batch.apples.where((apple) {
    if (apple.primaryCondition.toLowerCase() == 'lixo') return false;
    if (forced.contains(apple.id) || dbPending.contains(apple.id)) return true;
    return isUncertainApple(apple, auditSeed);
  }).toList();

  return orderTriageQueue(matched, forced, dbPending);
});

/// Ordena a fila de triagem. As maçãs enviadas explicitamente para triagem
/// (badge na Grelha = `forced`, ou marcadas 'pending' na BD) sobem ao topo; as
/// incertas por heurística ficam abaixo, na ordem cronológica do lote. Dentro
/// das forçadas, a última a ser escolhida fica em primeiro, para a maçã que o
/// operador acabou de escolher na Grelha aparecer logo no topo da stack (em vez
/// de na posição que ocupava no lote). `matched` já vem na ordem do lote.
List<Apple> orderTriageQueue(
  List<Apple> matched,
  Set<String> forced,
  Set<String> dbPending,
) {
  final forcedNewestFirst = forced.toList().reversed.toList();
  final batchIndex = {for (var i = 0; i < matched.length; i++) matched[i].id: i};
  int rank(Apple a) {
    final fi = forcedNewestFirst.indexOf(a.id);
    if (fi != -1) return fi;                       // 0..n-1: forçadas, recente no topo
    if (dbPending.contains(a.id)) return 1 << 20;  // depois, as pending da BD
    return 1 << 21;                                // por fim, as incertas por heurística
  }
  final ordered = [...matched];
  ordered.sort((a, b) {
    final ra = rank(a), rb = rank(b);
    if (ra != rb) return ra.compareTo(rb);
    return batchIndex[a.id]!.compareTo(batchIndex[b.id]!); // estável dentro do grupo
  });
  return ordered;
}

class CorrectionHistoryNotifier extends Notifier<List<CorrectionHistory>> {
  @override
  List<CorrectionHistory> build() => [];

  void setAll(List<CorrectionHistory> items) {
    state = items;
  }

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
/// fila humana, evita queries duplicadas. Refaz o fetch sempre que uma nova
/// correção é registada na sessão.
final manualReviewsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(correctionHistoryProvider);
  return SupabaseService.getManualReviews();
});

/// Feed da tabela `producao_atual`, últimos resultados finais da linha.
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
  final dbPending = ref.watch(dbPendingReviewProvider);

  if (allBatches.isEmpty) return null;

  final batches = [...allBatches]..sort((a, b) => a.location.compareTo(b.location));

  final dailyBatches = _groupBatchesByDay(batches);

  int totalApples = 0, totalHealthy = 0, totalAnomalies = 0, totalFrames = 0, confCount = 0;
  double sumConf = 0;
  final gDist = <String, int>{'Healthy': 0, 'Rot': 0, 'Scab': 0, 'Blotch': 0, 'Anthracnose': 0};

  for (final b in batches) {
    totalApples += b.totalApples;
    totalFrames += b.totalFrames;
    b.healthDistribution.forEach((k, v) {
      if (k.toLowerCase() != 'lixo') {
        gDist[k] = (gDist[k] ?? 0) + v;
      }
    });
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

  // Fila humana real: dbPendingReviewProvider é semeado (getPendingReviewIds)
  // antes de availableBatchesProvider publicar os lotes em loadDataFutureProvider,
  // por isso já está pronto sempre que allBatches deixa de estar vazio acima.
  final int humanQueue = dbPending.length;
  final surgeAlert = gDom == 'Nenhuma' || gDom == 'Healthy' ? 'Estável' : '$gDom (+14%)';
  // clamp: corrections (histórico acumulado) + humanQueue (pendentes globais)
  // podem exceder totalApples (janela de 30d), sem isto o KPI ficava negativo.
  final automationRate = totalApples > 0
      ? (((totalApples - corrections.length - humanQueue) / totalApples) * 100).clamp(0.0, 100.0)
      : 0.0;

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
    if (k != 'Healthy' && k.toLowerCase() != 'lixo' && v > domCount) {
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
      final hb = RaspberryHeartbeat.fromJson(json);
      // Nota: NÃO fazemos seed dos sliders a partir da config viva do Pi. Os
      // sliders representam sempre o "padrão" (de fábrica ou o guardado pelo
      // Produtor), para que reabrir a dashboard volte ao padrão. A config viva
      // do Pi continua disponível em hb.config para quem a queira mostrar.
      return hb;
    }
  } catch (_) {}
  return RaspberryHeartbeat.offline();
});

// ---------------------------------------------------------------------------
// Configuração da câmara, partilhada entre o painel de sliders e o botão RESTART
// ---------------------------------------------------------------------------

class CameraConfig {
  /// Nomes dos modos de redução de ruído aceites pelo script no Pi.
  static const noiseReductionModes = ['off', 'fast', 'highquality'];

  final double lensPosition;   // dpt (0 = autofocus)
  final double shutterUs;      // µs de exposição (0 = auto)
  final double analogueGain;   // ISO / ganho analógico (0 = auto, 1.0 a 12.0)
  final double burst;          // n.º de fotos em rajada
  final double burstInterval;  // ms entre fotos
  final double motionThreshold;// sensibilidade ao movimento (px)
  final double triggerDelay;   // ms após deteção de movimento
  final double sharpness;
  final double contrast;
  final double saturation;
  final double noiseReduction; // índice em [noiseReductionModes]: 0=off, 1=fast, 2=highquality

  // Defaults alinhados com o argparse de raspberry_camera_format_FUNCIONA.py
  const CameraConfig({
    this.lensPosition = 0.0,
    this.shutterUs = 0,
    this.analogueGain = 0.0,
    this.burst = 1,
    this.burstInterval = 150,
    this.motionThreshold = 500,
    this.triggerDelay = 100,
    this.sharpness = 1.5,
    this.contrast = 1.2,
    this.saturation = 1.2,
    this.noiseReduction = 1,
  });

  /// Constrói a partir do mapa 'config' reportado pelo heartbeat do Pi
  /// (chaves snake_case; noise_reduction chega como string).
  factory CameraConfig.fromPiConfig(Map<String, dynamic> c) {
    double numOr(String key, double fallback) =>
        (c[key] as num?)?.toDouble() ?? fallback;
    final nrIdx = noiseReductionModes.indexOf(c['noise_reduction'] as String? ?? 'fast');
    const d = CameraConfig();
    return CameraConfig(
      lensPosition: numOr('lens_position', d.lensPosition),
      shutterUs: numOr('shutter_us', d.shutterUs),
      analogueGain: numOr('analogue_gain', d.analogueGain),
      burst: numOr('burst', d.burst),
      burstInterval: numOr('burst_interval', d.burstInterval),
      motionThreshold: numOr('motion_threshold', d.motionThreshold),
      triggerDelay: numOr('trigger_delay', d.triggerDelay),
      sharpness: numOr('sharpness', d.sharpness),
      contrast: numOr('contrast', d.contrast),
      saturation: numOr('saturation', d.saturation),
      noiseReduction: nrIdx >= 0 ? nrIdx.toDouble() : d.noiseReduction,
    );
  }

  CameraConfig copyWith({
    double? lensPosition, double? shutterUs, double? analogueGain, double? burst, double? burstInterval,
    double? motionThreshold, double? triggerDelay, double? sharpness,
    double? contrast, double? saturation, double? noiseReduction,
  }) => CameraConfig(
    lensPosition: lensPosition ?? this.lensPosition,
    shutterUs: shutterUs ?? this.shutterUs,
    analogueGain: analogueGain ?? this.analogueGain,
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
    '--analogue-gain': double.parse(analogueGain.toStringAsFixed(1)),
    '--burst': burst.round(),
    '--burst-interval': burstInterval.round(),
    '--motion-threshold': motionThreshold.round(),
    '--trigger-delay': triggerDelay.round(),
    '--sharpness': double.parse(sharpness.toStringAsFixed(1)),
    '--contrast': double.parse(contrast.toStringAsFixed(1)),
    '--saturation': double.parse(saturation.toStringAsFixed(1)),
    '--noise-reduction': noiseReductionModes[noiseReduction.round().clamp(0, 2)],
  };

  /// Serialização para SharedPreferences (persistir o "padrão" do Produtor).
  Map<String, dynamic> toJson() => {
    'lensPosition': lensPosition, 'shutterUs': shutterUs, 'analogueGain': analogueGain, 'burst': burst,
    'burstInterval': burstInterval, 'motionThreshold': motionThreshold,
    'triggerDelay': triggerDelay, 'sharpness': sharpness, 'contrast': contrast,
    'saturation': saturation, 'noiseReduction': noiseReduction,
  };

  factory CameraConfig.fromJson(Map<String, dynamic> j) {
    const d = CameraConfig();
    double numOr(String k, double fb) => (j[k] as num?)?.toDouble() ?? fb;
    return CameraConfig(
      lensPosition: numOr('lensPosition', d.lensPosition),
      shutterUs: numOr('shutterUs', d.shutterUs),
      analogueGain: numOr('analogueGain', d.analogueGain),
      burst: numOr('burst', d.burst),
      burstInterval: numOr('burstInterval', d.burstInterval),
      motionThreshold: numOr('motionThreshold', d.motionThreshold),
      triggerDelay: numOr('triggerDelay', d.triggerDelay),
      sharpness: numOr('sharpness', d.sharpness),
      contrast: numOr('contrast', d.contrast),
      saturation: numOr('saturation', d.saturation),
      noiseReduction: numOr('noiseReduction', d.noiseReduction),
    );
  }
}

class CameraConfigNotifier extends Notifier<CameraConfig> {
  // Chave em SharedPreferences para o "padrão" gravado pelo Produtor.
  static const _prefsKey = 'camera_config_default';

  // True assim que o Produtor mexe num slider: impede que o carregamento
  // assíncrono do padrão guardado sobreponha o que ele está a editar.
  bool _userModified = false;

  @override
  CameraConfig build() {
    // Arranca no padrão de fábrica e, se existir um padrão guardado, aplica-o
    // assim que o SharedPreferences responder. Reabrir a app volta sempre a
    // este padrão (fábrica ou guardado), nunca à última config temporária.
    _loadSavedDefault();
    return const CameraConfig();
  }

  Future<void> _loadSavedDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && !_userModified) {
        state = CameraConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Sem storage (ex.: alguns testes): fica no padrão de fábrica.
    }
  }

  void update(CameraConfig Function(CameraConfig) fn) {
    _userModified = true;
    state = fn(state);
  }

  /// Grava a config atual como novo padrão persistente (mantém-se ao reabrir
  /// a dashboard). Chamado quando o Produtor confirma no diálogo de restart.
  Future<void> saveAsDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
      _userModified = false;  // já é o padrão
    } catch (_) {}
  }
}

final cameraConfigProvider =
    NotifierProvider<CameraConfigNotifier, CameraConfig>(CameraConfigNotifier.new);

// ---------------------------------------------------------------------------
// Shadow CNN, estado global (badge persistente no header, visível em
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

