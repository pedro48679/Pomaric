import 'dart:convert';
import 'package:http/http.dart' as http;

/// Resultado da classificação do CNN2 (ResNet50 local).
class Cnn2Result {
  final String topClass;
  final double confidence;
  final Map<String, double> allProbs;

  Cnn2Result({
    required this.topClass,
    required this.confidence,
    required this.allProbs,
  });

  factory Cnn2Result.fromJson(Map<String, dynamic> json) {
    final rawProbs = json['all_probs'] as Map<String, dynamic>;
    return Cnn2Result(
      topClass:   json['class'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      allProbs:   rawProbs.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }

  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';
}

/// Serviço que comunica com o servidor de inferência Python local.
class InferenceService {
  static const String _baseUrl = 'http://localhost:8000';
  static const String _classifyEndpoint = '$_baseUrl/classify';

  // Cache simples para não reclassificar a mesma imagem duas vezes
  static final Map<String, Cnn2Result> _cache = {};

  /// Classifica uma imagem dado o seu URL local.
  /// Retorna null se o servidor não estiver acessível.
  static Future<Cnn2Result?> classify(String imageUrl) async {
    // Verifica o cache primeiro
    if (_cache.containsKey(imageUrl)) {
      return _cache[imageUrl];
    }

    try {
      final response = await http
          .post(
            Uri.parse(_classifyEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image_url': imageUrl}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = Cnn2Result.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        _cache[imageUrl] = result; // Guarda no cache
        return result;
      }
    } catch (_) {
      // Servidor offline ou timeout → retorna null silenciosamente
    }

    return null;
  }

  /// Pré-classifica uma lista de URLs em paralelo (para carregar a grelha mais rápido).
  static Future<void> preclassify(List<String> imageUrls) async {
    await Future.wait(
      imageUrls.map((url) => classify(url)),
    );
  }

  static void clearCache() => _cache.clear();
}
