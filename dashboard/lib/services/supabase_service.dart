import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class SupabaseService {
  static final _supabase = Supabase.instance.client;
  static bool isMockMode = false;

  /// Gera dados falsos para alimentar a Dashboard em modo Mock offline
  static List<Batch> generateMockBatches() {
    final rand = Random();
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
        // 70% chance de ser saudável
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
        
        apples.add(Apple(
          id: 'APP-${b}x${a}',
          location: loc,
          timestamp: batchDate.subtract(Duration(days: rand.nextInt(7))).add(Duration(minutes: rand.nextInt(1440))),
          cnn2Label: condition,
          cnn2Confidence: condition == 'Healthy' 
              ? 0.90 + rand.nextDouble() * 0.08 
              : 0.72 + rand.nextDouble() * 0.20,
          modelName: condition == 'Healthy' ? 'CNN2' : 'CNN5',
          frames: frames,
        ));
      }
      
      batches.add(Batch(
        id: 'LT-${loc.toUpperCase()}-0${b}',
        name: 'Lote $loc $b',
        date: batchDate,
        apples: apples,
        location: loc,
        growthRate: -5.0 + rand.nextDouble() * 10.0, // -5% a +5%
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
        List<dynamic> allApplesData = [];
        int from = 0;
        int to = 999;
        bool hasMore = true;
        const int maxTotal = 10000;
        final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

        // 1. Fetch APENAS maçãs (sem joins) dos últimos 30 dias para evitar timeout
        while (hasMore && allApplesData.length < maxTotal) {
          final List<dynamic> chunk = await _supabase
              .from('apples')
              .select('*')
              .gte('timestamp', thirtyDaysAgo)
              .order('timestamp', ascending: false)
              .range(from, to);

          allApplesData.addAll(chunk);
          
          if (chunk.length < 1000) {
            hasMore = false;
          } else {
            from += 1000;
            to += 1000;
            if (from >= maxTotal) hasMore = false;
          }
        }

        if (allApplesData.isEmpty) return [];

        List<String> allAppleIds = allApplesData.map((a) => a['apple_id'] as String).toList();
        
        // 2. Fetch das cnn_predictions (em blocos de 50 para não dar timeout e não atingir limite de 1000 linhas)
        Map<String, List<dynamic>> predictionsMap = {};
        for (int i = 0; i < allAppleIds.length; i += 50) {
          final end = (i + 50 < allAppleIds.length) ? i + 50 : allAppleIds.length;
          final chunkIds = allAppleIds.sublist(i, end);
          
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

        // Fazer merge das predições nos dados brutos das maçãs
        for (var a in allApplesData) {
          final aId = a['apple_id'] as String;
          a['cnn_predictions'] = predictionsMap[aId] ?? [];
        }

        List<Apple> rawApples = allApplesData.map((row) => Apple.fromJson(row as Map<String, dynamic>)).toList();

        // 3. Descobrir o dia mais recente e carregar as imagens (frames) SÓ para esse dia
        final latestDate = rawApples.first.timestamp;
        final startOfLatestDay = DateTime(latestDate.year, latestDate.month, latestDate.day);
        
        final recentApples = rawApples.where((a) => a.timestamp.isAfter(startOfLatestDay) || a.timestamp.isAtSameMomentAs(startOfLatestDay)).toList();
        final recentAppleIds = recentApples.map((a) => a.id).toList();

        // Buscar frames em blocos de 50 para não exceder limites do PostgREST
        List<dynamic> allRecentFrames = [];
        for (int i = 0; i < recentAppleIds.length; i += 50) {
          final end = (i + 50 < recentAppleIds.length) ? i + 50 : recentAppleIds.length;
          final chunkIds = recentAppleIds.sublist(i, end);
          
          final framesChunk = await _supabase
              .from('frames')
              .select('*')
              .inFilter('apple_id', chunkIds);
          allRecentFrames.addAll(framesChunk);
        }

        Map<String, List<FrameData>> framesMap = {};
        for (var f in allRecentFrames) {
          final frameData = FrameData.fromJson(f as Map<String, dynamic>);
          final aId = f['apple_id'] as String;
          if (!framesMap.containsKey(aId)) framesMap[aId] = [];
          framesMap[aId]!.add(frameData);
        }

        for (int i = 0; i < rawApples.length; i++) {
          if (framesMap.containsKey(rawApples[i].id)) {
            rawApples[i] = rawApples[i].copyWith(frames: framesMap[rawApples[i].id]);
          }
        }

        // 4. Agrupar por Localização (ignorando CROP_AUTOMATICO e CROPPED_IMAGE)
        Map<String, List<Apple>> grouped = {};
        for (var a in rawApples) {
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
            growthRate: 0.0,
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
          return [];
        }
      }
    }
    return [];
  }

  /// Persistir uma anotação manual (Foco)
  static Future<void> saveAnnotation(ManualAnnotation annotation) async {
    try {
      await _supabase.from('circles_manual').upsert(annotation.toJson());
    } catch (e) {
      print('Erro ao guardar anotação: $e');
    }
  }

  /// Obter anotações de uma maçã
  static Future<List<ManualAnnotation>> getAnnotations(String appleId) async {
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
    try {
      await _supabase.from('manual_review').insert({
        'apple_id': apple.id,
        'updated_timestamp': DateTime.now().toIso8601String(),
        'original_class': apple.primaryCondition,
        'original_confidence': (apple.effectiveConfidence * 100).toInt(),
        'status': 'pending',
      });
    } catch (e) {
      print('Erro ao enviar para revisão: $e');
    }
  }

  /// Exportar para o dataset de treino (Active Learning)
  /// Agora envia a imagem original e todos os crops gerados
  static Future<void> exportToTraining({
    required String appleId,
    required String pathologyClass,
    List<ManualAnnotation> circles = const [],
  }) async {
    try {
      // 1. Inserimos a imagem original
      // Removido 'image_url' pois não existe na tabela train_dataset
      await _supabase.from('train_dataset').insert({
        'apple_id': appleId,
        'class': pathologyClass,
      });

      // 2. Inserimos cada crop como uma nova entrada de treino
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
    try {
      final now = DateTime.now().toIso8601String();
      await _supabase.from('manual_annotation').upsert({
        'apple_id': appleId,
        'primary_apple_disease': decision,
        'updated_by': username,
        'updated_at': now,
      }, onConflict: 'apple_id');

      // 2. Gravar os círculos na circles_manual
      // Primeiro limpamos círculos antigos desta maçã
      await _supabase.from('circles_manual').delete().eq('apple_id', appleId);
      
      if (circles.isNotEmpty) {
        await _supabase.from('circles_manual').insert(
          circles.map((c) => c.toJson()).toList()
        );
      }

      // 3. Atualizar o status na tabela de revisão (Garantindo todos os campos solicitados)
      await _supabase.from('manual_review').update({
        'status': 'completed',
        'original_class': originalClass,
        'original_confidence': originalConfidence,
        'corrected_class': decision,
        'updated_by': username,
        'updated_timestamp': DateTime.now().toIso8601String(),
      }).eq('apple_id', appleId);

      // 4. Se for Gestor, exportar para treino
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

        Batch? target;
        if (batchId != null) {
          target = batches.firstWhere((b) => b.id == batchId, orElse: () => batches.first);
        } else {
          target = batches.first;
        }

        final rand = Random();
        final classes = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'];
        final users = ['admin', 'ana', 'joao', 'maria'];
        final List<Map<String, dynamic>> rows = [];

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
            'updated_timestamp': DateTime.now().subtract(Duration(minutes: rand.nextInt(1440))).toIso8601String(),
            'updated_by': corr != null ? users[rand.nextInt(users.length)] : '',
            'batch_id': target.id,
          });
        }

        return rows;
      }

      if (batchId != null) {
        final List<dynamic> rows = await _supabase
            .from('manual_review')
            .select('apple_id,original_class,corrected_class,original_confidence,status,updated_timestamp,updated_by')
            .eq('batch_id', batchId);
        return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      } else {
        final List<dynamic> rows = await _supabase
            .from('manual_review')
            .select('apple_id,original_class,corrected_class,original_confidence,status,updated_timestamp,updated_by');
        return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      }
    } catch (e) {
      print('Erro ao buscar manual_review: $e');
      return [];
    }
  }
}
