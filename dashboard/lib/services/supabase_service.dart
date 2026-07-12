import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bcrypt/bcrypt.dart';
import '../models/models.dart';
import 'local_cache_service.dart';

class SupabaseService {
  static final _supabase = Supabase.instance.client;
  static bool isMockMode = false;

  /// Gera dados falsos para alimentar a Dashboard em modo Mock offline
  static List<Batch> generateMockBatches() {
    // Semente fixa → dados estáveis a cada chamada (evita refresh visual em mock mode)
    final rand = Random(42);
    final batches = <Batch>[];
    final locations = ['Norte', 'Sul', 'Oeste', 'Este'];
    final conditions = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];
    
    final now = DateTime.now();

    for (int b = 0; b < 10; b++) {
      final batchDate = now.subtract(Duration(days: b * 2));
      final loc = locations[b % locations.length];
      final numApples = 100 + rand.nextInt(300); // 100 a 400 maçãs por lote
      
      final apples = <Apple>[];
      for (int a = 0; a < numApples; a++) {
        // 80\% chance de ser saudável
        final isHealthy = rand.nextDouble() < 0.7;
        final condition = isHealthy ? 'Healthy' : conditions[1 + rand.nextInt(conditions.length - 1)];
        
        final frames = <FrameData>[];
        final numFrames = 3 + rand.nextInt(4); // 3 a 6 frames
        
        for (int f = 0; f < numFrames; f++) {
          double conf = 0.70 + rand.nextDouble() * 0.29; // 0.70 a 0.99
          Map<String, double> probs = {'Healthy': 0.1, 'Rot': 0.1, 'Scab': 0.1, 'Blotch': 0.1, 'Anthracnose': 0.1};
          probs[condition] = conf;
          
          // Ajuste para somar 1.0 (aproximadamente)
          double rest = (1.0 - conf) / 4;
          probs.forEach((k, v) { if (k != condition) probs[k] = rest; });
          
          frames.add(FrameData(
            id: a * 10 + f,
            url: 'mock_apples/$condition.png', // Imagem real como placeholder
            diseaseSum: condition == 'Healthy' ? 0.0 : 0.15 + rand.nextDouble() * 0.8,
            probabilities: probs,
          ));
        }
        
        final double cnn2ConfVal = condition == 'Healthy' 
            ? 0.90 + rand.nextDouble() * 0.08 
            : 0.72 + rand.nextDouble() * 0.20;
        final double cnn5ConfVal = condition == 'Healthy'
            ? 0.10 + rand.nextDouble() * 0.15
            : 0.80 + rand.nextDouble() * 0.18;

        final List<Map<String, dynamic>> mockPreds = [
          {
            'model_name': 'CNN2',
            'label': condition == 'Healthy' ? 'Healthy' : 'Unknown',
            'confidence': cnn2ConfVal,
            'is_worst_case': true,
          },
          {
            'model_name': 'CNN5',
            'label': condition,
            'confidence': cnn5ConfVal,
            'is_worst_case': true,
          }
        ];

        apples.add(Apple(
          id: 'APP-${b}x${a}',
          location: loc,
          timestamp: batchDate.subtract(Duration(days: rand.nextInt(7))).add(Duration(minutes: rand.nextInt(1440))),
          cnn2Label: condition,
          cnn2Confidence: cnn2ConfVal,
          modelName: condition == 'Healthy' ? 'CNN2' : 'CNN5',
          frames: frames,
          cnnPredictions: mockPreds,
        ));
      }
      
      batches.add(Batch(
        id: 'LT-${loc.toUpperCase()}-0${b}',
        name: 'Lote $loc $b',
        date: batchDate,
        apples: apples,
        location: loc,
      ));
    }
    
    return batches;
  }

  /// Fetch all apples and frames, then group them into Batches for the UI
  static Future<List<Batch>> getBatches({int maxRetries = 1}) async {
    // Se estivermos em modo de teste/mock, devolvemos os dados falsos instantaneamente e evitamos chamadas à BD
    if (isMockMode) {
      return generateMockBatches();
    }

    int attempts = 0;
    while (attempts <= maxRetries) {
      try {
        // Load local cache if not loaded
        await LocalCacheService.loadFromDisk();

        final lastSyncDate = LocalCacheService.getLatestTimestamp() ?? 
            DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

        List<dynamic> newApplesData = [];
        int from = 0;
        int to = 999;
        bool hasMore = true;
        const int maxTotal = 10000;

        // 1. Fetch APENAS maçãs novas (Delta Sync)
        while (hasMore && newApplesData.length < maxTotal) {
          final List<dynamic> chunk = await _supabase
              .from('apples')
              .select('*')
              .gte('timestamp', lastSyncDate)
              .order('timestamp', ascending: false)
              .range(from, to);

          newApplesData.addAll(chunk);
          
          if (chunk.length < 1000) {
            hasMore = false;
          } else {
            from += 1000;
            to += 1000;
            if (from >= maxTotal) hasMore = false;
          }
        }

        if (newApplesData.isNotEmpty) {
          List<String> newAppleIds = newApplesData.map((a) => a['apple_id'] as String).toList();
          
          // 2. Fetch cnn_predictions APENAS para os novos IDs
          Map<String, List<dynamic>> predictionsMap = {};
          for (int i = 0; i < newAppleIds.length; i += 50) {
            final end = (i + 50 < newAppleIds.length) ? i + 50 : newAppleIds.length;
            final chunkIds = newAppleIds.sublist(i, end);
            
            final predsChunk = await _supabase
                .from('cnn_predictions')
                .select('*')
                .inFilter('apple_id', chunkIds);
                
            for (var p in predsChunk) {
              final aId = p['apple_id'] as String;
              if (!predictionsMap.containsKey(aId)) predictionsMap[aId] = [];
              predictionsMap[aId]!.add(p);
            }
          }

          for (var a in newApplesData) {
            final aId = a['apple_id'] as String;
            a['cnn_predictions'] = predictionsMap[aId] ?? [];
          }

          List<Apple> rawNewApples = newApplesData.map((row) => Apple.fromJson(row as Map<String, dynamic>)).toList();

          // 3. Fetch frames APENAS para os novos IDs
          List<dynamic> allNewFrames = [];
          List<dynamic> allMultiConf = [];
          for (int i = 0; i < newAppleIds.length; i += 50) {
            final end = (i + 50 < newAppleIds.length) ? i + 50 : newAppleIds.length;
            final chunkIds = newAppleIds.sublist(i, end);
            
            final framesChunk = await _supabase
                .from('frames')
                .select('*')
                .inFilter('apple_id', chunkIds);
            allNewFrames.addAll(framesChunk);
            
            final confChunk = await _supabase
                .from('cnn5_multi_confidence')
                .select('*')
                .inFilter('apple_id', chunkIds);
            allMultiConf.addAll(confChunk);
          }

          Map<int, Map<String, double>> multiConfMap = {};
          for (var c in allMultiConf) {
            final fId = c['frame_id'] as int;
            final label = c['class_label'] as String;
            final conf = (c['confidence'] as num).toDouble();
            if (!multiConfMap.containsKey(fId)) multiConfMap[fId] = {};
            multiConfMap[fId]![label] = conf;
          }

          Map<String, List<FrameData>> framesMap = {};
          for (var f in allNewFrames) {
            final fId = f['id'] as int;
            if (multiConfMap.containsKey(fId)) {
                f['probabilities'] = multiConfMap[fId];
            }
            final frameData = FrameData.fromJson(f as Map<String, dynamic>);
            final aId = f['apple_id'] as String;
            if (!framesMap.containsKey(aId)) framesMap[aId] = [];
            framesMap[aId]!.add(frameData);
          }

          for (int i = 0; i < rawNewApples.length; i++) {
            if (framesMap.containsKey(rawNewApples[i].id)) {
              rawNewApples[i] = rawNewApples[i].copyWith(frames: framesMap[rawNewApples[i].id]);
            }
          }

          // Merge new data with Local Cache
          await LocalCacheService.mergeNewApples(rawNewApples);
        }

        // Obtém a lista completa do Cache para processar a UI
        final allApples = LocalCacheService.inMemoryApples;
        if (allApples.isEmpty) return [];

        // 4. Agrupar por Localização (ignorando CROP_AUTOMATICO e CROPPED_IMAGE)
        Map<String, List<Apple>> grouped = {};
        for (var a in allApples) {
          final locUpper = a.location.toUpperCase();
          if (locUpper.contains('CROP_AUTOMATICO') || locUpper.contains('CROP_AUTOMÁTICO') || locUpper.contains('CROPPED_IMAGE')) continue;
          
          String key = a.location;
          if (!grouped.containsKey(key)) grouped[key] = [];
          grouped[key]!.add(a);
        }

        List<Batch> batches = [];
        grouped.forEach((key, appleList) {
          String loc = appleList.first.location;
          appleList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          
          batches.add(Batch(
            id: 'LT-${key.toUpperCase().replaceAll(' ', '_')}',
            name: 'Lote $loc',
            date: appleList.first.timestamp,
            apples: appleList,
            location: loc,
          ));
        });

        batches.sort((a, b) => b.date.compareTo(a.date));
        
        // Garante que o lote 'Cropped_image' ou derivados nunca cheguem à UI
        batches.removeWhere((b) => 
          b.id.toLowerCase().contains('cropped_image') || 
          b.location.toLowerCase().contains('cropped_image') || 
          b.name.toLowerCase().contains('cropped_image') ||
          b.id.toLowerCase().contains('cropped') ||
          b.location.toLowerCase().contains('cropped') ||
          b.name.toLowerCase().contains('cropped')
        );
        
        return batches;
      } catch (e) {
        attempts++;
        print('Erro ao carregar dados do Supabase: $e');
        if (attempts <= maxRetries) {
          print('A tentar novamente em 10 segundos... (Tentativa $attempts de $maxRetries)');
          await Future.delayed(const Duration(seconds: 10));
        } else {
          // Failsafe: BD inacessível após todas as tentativas — usa dados de demonstração
          print('[FAILSAFE] BD inacessível — a usar dados de demonstração.');
          isMockMode = true;
          return generateMockBatches();
        }
      }
    }
    return generateMockBatches();
  }

  /// Persistir uma anotação manual (Foco)
  static Future<void> saveAnnotation(ManualAnnotation annotation) async {
    if (isMockMode) return; // No-op em mock mode
    try {
      await _supabase.from('circles_manual').upsert(annotation.toJson());
    } catch (e) {
      print('Erro ao guardar anotação: $e');
    }
  }

  /// Obter anotações de uma maçã
  static Future<List<ManualAnnotation>> getAnnotations(String appleId) async {
    if (isMockMode) return []; // Sem anotações em mock mode
    try {
      final res = await _supabase.from('circles_manual').select().eq('apple_id', appleId);
      return (res as List).map((e) => ManualAnnotation.fromJson(e)).toList();
    } catch (e) {
      print('Erro ao obter anotações: $e');
      return [];
    }
  }

  /// Enviar maçã para a fila de revisão (Triagem)
  static Future<void> flagForReview(Apple apple) async {
    if (isMockMode) return; // No-op em mock mode
    try {
      await _supabase.from('manual_review').insert({
        'apple_id': apple.id,
        'updated_at': DateTime.now().toIso8601String(),
        'original_class': apple.primaryCondition,
        'original_confidence': (apple.effectiveConfidence * 100).toInt(),
        'status': 'pending',
      });
    } catch (e) {
      print('Erro ao enviar para revisão: $e');
    }
  }

  /// Exportar para o dataset de treino (Active Learning)
  static Future<void> exportToTraining({
    required String appleId,
    required String pathologyClass,
    List<ManualAnnotation> circles = const [],
  }) async {
    if (isMockMode) return; // No-op em mock mode
    try {
      await _supabase.from('train_dataset').insert({
        'apple_id': appleId,
        'class': pathologyClass,
      });

      for (var circle in circles) {
        if (circle.crop != null && circle.crop != 'none') {
          await _supabase.from('train_dataset').insert({
            'apple_id': '${appleId}_crop_${circle.circleIndex}',
            'class': circle.disease,
          });
        }
      }
    } catch (e) {
      print('Erro ao exportar para treino: $e');
    }
  }

  /// Marcar triagem como concluída e registar quem o fez (Lógica Completa)
  static Future<void> completeReview({
    required String appleId,
    required String decision,
    required String username,
    required String role,
    required List<ManualAnnotation> circles,
    required String originalClass,
    required int originalConfidence,
    String? originalImageUrl,
  }) async {
    if (isMockMode) return; // No-op em mock mode
    try {
      final now = DateTime.now().toIso8601String();
      await _supabase.from('manual_annotation').upsert({
        'apple_id': appleId,
        'primary_apple_disease': decision,
        'updated_by': username,
        'updated_at': now,
      }, onConflict: 'apple_id');

      await _supabase.from('circles_manual').delete().eq('apple_id', appleId);

      if (circles.isNotEmpty) {
        await _supabase.from('circles_manual').insert(
          circles.map((c) => c.toJson()).toList()
        );
      }

      await _supabase.from('manual_review').update({
        'status': 'completed',
        'original_class': originalClass,
        'original_confidence': originalConfidence,
        'corrected_class': decision,
        'updated_by': username,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('apple_id', appleId);

      if (role == 'manager') {
        await exportToTraining(
          appleId: appleId,
          pathologyClass: decision,
          circles: circles,
        );
      }
    } catch (e) {
      print('Erro ao concluir triagem: $e');
    }
  }

  /// Recupera entradas de `manual_review` opcionalmente filtradas por lote
  static Future<List<Map<String, dynamic>>> getManualReviews({String? batchId}) async {
    try {
      if (isMockMode) {
        final batches = generateMockBatches();
        if (batches.isEmpty) return [];

        final List<Batch> targets = [];
        if (batchId != null) {
          final target = batches.firstWhere((b) => b.id == batchId, orElse: () => batches.first);
          targets.add(target);
        } else {
          targets.addAll(batches);
        }

        // Semente fixa → reviews estáveis entre chamadas (coerente com generateMockBatches)
        final rand = Random(7);
        final classes = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];
        final users = ['admin', 'ana', 'joao', 'maria'];
        final List<Map<String, dynamic>> rows = [];

        for (final target in targets) {
          final maxRows = min(6, target.apples.length);
          for (int i = 0; i < maxRows; i++) {
            final apple = target.apples[i];
            final orig = apple.primaryCondition;
            final origConf = (apple.effectiveConfidence * 100).round();

            String? corr;
            // Probabilidades: maçãs com alta confiança têm maior chance de correção
            if ((origConf >= 85 && rand.nextDouble() < 0.5) || rand.nextDouble() < 0.15) {
              final opts = classes.where((c) => c != orig).toList();
              corr = opts[rand.nextInt(opts.length)];
            }

            rows.add({
              'apple_id': apple.id,
              'original_class': orig,
              'corrected_class': corr,
              'original_confidence': origConf,
              'status': corr != null ? 'completed' : 'pending',
              'updated_at': DateTime.now().subtract(Duration(minutes: rand.nextInt(1440))).toIso8601String(),
              'updated_by': corr != null ? users[rand.nextInt(users.length)] : '',
              'batch_id': target.id,
            });
          }
        }

        return rows;
      }

      // A coluna batch_id não existe na tabela manual_review no Supabase, 
      // portanto buscamos todos os reviews e (opcionalmente) poderíamos filtrar na RAM se necessário.
      final List<dynamic> rows = await _supabase
          .from('manual_review')
          .select('apple_id,original_class,corrected_class,original_confidence,status,updated_at,updated_by');
          
      var mappedRows = rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      
      // Se tivermos os Batches cacheados, podemos filtrar localmente os reviews que pertencem ao lote
      if (batchId != null && LocalCacheService.inMemoryApples.isNotEmpty) {
        final targetApples = LocalCacheService.inMemoryApples;
        // Na falta de batch_id direto, podemos inferir o lote através da localização das maçãs 
        // ou ignorar o filtro de lote temporariamente. Por agora devolvemos todos, 
        // ou filtramos pela lista de IDs se conhecêssemos o mapeamento lote->apples.
      }
      
      return mappedRows;
    } catch (e) {
      print('Erro ao buscar manual_review: $e');
      return [];
    }
  }

  /// Últimos registos da tabela `producao_atual` (resultado final da linha),
  /// ordenados do mais recente para o mais antigo.
  static Future<List<ProducaoRecord>> getProducaoAtual({int limit = 20}) async {
    if (isMockMode) {
      // Deriva um feed sintético estável a partir dos lotes mock (sem Random
      // não semeado — evita refresh visual entre polls)
      final batches = generateMockBatches();
      final apples = batches.expand((b) => b.apples).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return apples.take(limit).toList().asMap().entries.map((e) {
        final a = e.value;
        return ProducaoRecord(
          id: e.key,
          appleId: a.id,
          timestamp: a.timestamp,
          location: a.location,
          finalClass: a.primaryCondition,
          finalConfidence: a.effectiveConfidence,
          finalSource: a.id.hashCode % 5 == 0 ? 'manual' : 'IA',
          frameThumbnail: a.worstFrameUrl,
        );
      }).toList();
    }

    try {
      final List<dynamic> rows = await _supabase
          .from('producao_atual')
          .select('*')
          .order('timestamp', ascending: false)
          .limit(limit);
      return rows
          .map((r) => ProducaoRecord.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      print('Erro ao buscar producao_atual: $e');
      return [];
    }
  }

  /// ═══ AUTENTICAÇÃO ═══

  /// Hash de password usando bcrypt (10 rounds)
  static String hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 10));
  }

  /// Verifica se o password corresponde ao hash
  static bool verifyPassword(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } catch (e) {
      print('Erro ao verificar password: $e');
      return false;
    }
  }

  /// Faz login seguro (produção com Supabase)
  static Future<Worker?> loginProduction(String username, String password) async {
    try {
      final List<dynamic> result = await _supabase
          .from('workers')
          .select()
          .eq('username', username.trim().toLowerCase())
          .eq('is_active', true)
          .limit(1);

      if (result.isEmpty) return null;

      final workerData = result.first as Map<String, dynamic>;
      final passwordHash = workerData['password_hash'] as String;

      if (!verifyPassword(password, passwordHash)) {
        return null;
      }

      return Worker.fromJson(workerData);
    } catch (e) {
      print('Erro ao fazer login: $e');
      return null;
    }
  }

  /// Faz login em modo mock (para desenvolvimento)
  static Worker? loginMock(String username, String password) {
    // Mock database com credenciais de teste
    final mockWorkers = {
      'admin': {
        'password': 'admin',
        'role': 'admin',
      },
      'ana': {
        'password': 'password123',
        'role': 'operator',
      },
      'joao': {
        'password': 'password123',
        'role': 'operator',
      },
      'maria': {
        'password': 'password123',
        'role': 'operator',
      },
    };

    final userKey = username.trim().toLowerCase();
    if (!mockWorkers.containsKey(userKey)) return null;

    final userData = mockWorkers[userKey]!;
    if (userData['password'] != password) return null;

    return Worker(
      id: userKey,
      username: userKey,
      role: userData['role']!,
      isActive: true,
      createdAt: DateTime.now(),
    );
  }

  /// Faz login (escolhe entre mock ou produção baseado em isMockMode)
  static Future<Worker?> login(String username, String password) async {
    if (isMockMode) {
      return loginMock(username, password);
    }
    return await loginProduction(username, password);
  }

  /// Lê o "lote" (location) atualmente ativo, escolhido pelo operador após o
  /// login. Se a tabela 'active_lote' estiver vazia, cai para a location da
  /// maçã mais recente em 'apples'; se não houver nenhuma, devolve null.
  static Future<String?> getActiveLote() async {
    if (isMockMode) return 'Linha 1';

    try {
      final row = await _supabase
          .from('active_lote')
          .select('location')
          .eq('id', 1)
          .maybeSingle();
      final location = row?['location'] as String?;
      if (location != null && location.isNotEmpty) return location;
    } catch (_) {
      // tabela pode ainda não existir ou estar vazia — cai para o fallback abaixo
    }

    try {
      final rows = await _supabase
          .from('apples')
          .select('location')
          .order('timestamp', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        return rows.first['location'] as String?;
      }
    } catch (_) {}

    return null;
  }

  /// Grava (upsert) o lote ativo. Chamado pelo operador logo após o login.
  static Future<void> setActiveLote(String location, {required String setBy}) async {
    if (isMockMode) return;
    await _supabase.from('active_lote').upsert({
      'id': 1,
      'location': location,
      'set_by': setBy,
      'set_at': DateTime.now().toIso8601String(),
    });
  }
}
