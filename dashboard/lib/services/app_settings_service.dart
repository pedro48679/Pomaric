import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

/// Definições persistentes leves da app (SharedPreferences, funciona em web
/// via localStorage, ao contrário de LocalCacheService que usa dart:io File
/// e por isso não persiste nada numa build web).
///
/// Hoje só guarda o URL do servidor MLOps: `AppConstants.mlopsUrl` é fixo em
/// localhost, o que só funciona quando o Flutter e o mlops_server.py correm
/// na mesma máquina. Isto dá um valor por omissão igual, mas alterável em
/// runtime pela página MLOps sem precisar de recompilar a app.
class AppSettingsService {
  static const _mlopsUrlKey = 'mlops_url';

  static String mlopsUrl = AppConstants.mlopsUrl;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mlopsUrl = prefs.getString(_mlopsUrlKey) ?? AppConstants.mlopsUrl;
    } catch (_) {
      // SharedPreferences pode falhar em contextos sem storage (ex.: alguns
      // testes), mantém o valor por omissão em vez de rebentar o arranque.
    }
  }

  static Future<void> setMlopsUrl(String url) async {
    final trimmed = url.trim();
    mlopsUrl = trimmed.isEmpty ? AppConstants.mlopsUrl : trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mlopsUrlKey, mlopsUrl);
    } catch (_) {}
  }
}
