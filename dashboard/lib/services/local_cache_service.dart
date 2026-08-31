import 'dart:convert';
import 'dart:io';
import '../models/models.dart';

class LocalCacheService {
  static const String cacheDir = 'local_db';
  static const String cacheFile = '$cacheDir/apples_cache_fixed.json';

  static List<Apple> inMemoryApples = [];
  static bool _isLoaded = false;

  /// Cursor de sincronização incremental de `manual_review` (ver
  /// `getManualReviewsSince` em supabase_service.dart), persistido aqui, ao
  /// lado das maçãs, para que o polling de correções/triagem nunca precise de
  /// refazer um SELECT * completo depois do primeiro carregamento da sessão.
  static String? lastManualReviewSync;

  /// Loads apples (and the manual_review sync cursor) from the local JSON file into memory.
  static Future<void> loadFromDisk() async {
    if (_isLoaded) return; // Only load once per session

    final file = File(cacheFile);
    if (!await file.exists()) {
      _isLoaded = true;
      return;
    }

    try {
      final jsonString = await file.readAsString();
      if (jsonString.trim().isEmpty) return;

      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        // Formato antigo (array simples de maçãs, sem cursor), migração
        // silenciosa: mantém as maçãs já em cache, cursor fica null (a
        // próxima sincronização de manual_review busca tudo uma única vez).
        inMemoryApples = decoded.map((e) => Apple.fromJson(e as Map<String, dynamic>)).toList();
      } else if (decoded is Map<String, dynamic>) {
        final apples = decoded['apples'] as List? ?? [];
        inMemoryApples = apples.map((e) => Apple.fromJson(e as Map<String, dynamic>)).toList();
        lastManualReviewSync = decoded['lastManualReviewSync'] as String?;
      }
      _isLoaded = true;
      print('[LocalCache] Carregadas ${inMemoryApples.length} maçãs do disco.');
    } catch (e) {
      print('[LocalCache] Erro ao carregar cache do disco: $e');
    }
  }

  /// Saves the current in-memory apples (and manual_review sync cursor) to the local JSON file.
  static Future<void> saveToDisk() async {
    try {
      final dir = Directory(cacheDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Purge apples older than 30 days to prevent infinite file growth
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      inMemoryApples.removeWhere((a) => a.timestamp.isBefore(thirtyDaysAgo));

      final file = File(cacheFile);
      final jsonString = jsonEncode({
        'apples': inMemoryApples.map((a) => a.toJson()).toList(),
        'lastManualReviewSync': lastManualReviewSync,
      });

      await file.writeAsString(jsonString);
      print('[LocalCache] Gravadas ${inMemoryApples.length} maçãs no disco.');
    } catch (e) {
      print('[LocalCache] Erro ao gravar cache no disco: $e');
    }
  }

  /// Merges new apples from Supabase into memory and triggers a disk save.
  static Future<void> mergeNewApples(List<Apple> newApples) async {
    if (newApples.isEmpty) return;

    final existingIds = {for (var a in inMemoryApples) a.id: a};
    bool hasChanges = false;
    
    for (final newApple in newApples) {
      if (!existingIds.containsKey(newApple.id)) {
        hasChanges = true;
      }
      existingIds[newApple.id] = newApple;
    }

    if (!hasChanges) return; // Se nenhuma maçã nova entrou, não grava no disco

    inMemoryApples = existingIds.values.toList();
    // Sort by timestamp descending
    inMemoryApples.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    // Asynchronously save to disk so we don't block the UI
    saveToDisk();
  }

  /// Gets the most recent timestamp present in the local cache.
  static String? getLatestTimestamp() {
    if (inMemoryApples.isEmpty) return null;
    
    // Ensure we find the absolute max timestamp just in case
    DateTime latest = inMemoryApples.first.timestamp;
    for (final a in inMemoryApples) {
      if (a.timestamp.isAfter(latest)) {
        latest = a.timestamp;
      }
    }
    
    // Subtract 5 minutes as a safety buffer for delta fetching
    return latest.subtract(const Duration(minutes: 5)).toIso8601String();
  }

  /// Updates a single apple's diagnosis in the memory cache. `persist:false`
  /// permite aplicar várias correções em lote (ex.: sincronização periódica
  /// de manual_review) e só gravar em disco uma vez no fim do lote.
  static void updateAppleInCache(String appleId, String newLabel, {bool persist = true}) {
    for (int i = 0; i < inMemoryApples.length; i++) {
      if (inMemoryApples[i].id == appleId) {
        final apple = inMemoryApples[i];
        final updatedFrames = apple.frames.map((frame) {
          final newProbs = <String, double>{newLabel: 1.0};
          return frame.copyWith(
            probabilities: newProbs,
            diseaseSum: newLabel == 'Healthy' ? 0.0 : 1.0,
          );
        }).toList();

        final updatedPreds = apple.cnnPredictions.map((pred) {
          final mName = pred['model_name'] as String?;
          if (mName == 'CNN5' || mName == 'CNN2') {
            return {
              ...pred,
              'label': newLabel,
              'confidence': 1.0,
            };
          }
          return pred;
        }).toList();

        inMemoryApples[i] = apple.copyWith(
          frames: updatedFrames,
          cnnPredictions: updatedPreds,
        );
        break;
      }
    }
    if (persist) saveToDisk();
  }

  /// Clears the local JSON cache file and memory state.
  static Future<void> clearCache() async {
    final file = File(cacheFile);
    if (await file.exists()) {
      await file.delete();
    }
    inMemoryApples = [];
    _isLoaded = false;
  }
}
