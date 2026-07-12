import 'package:flutter/material.dart';

class AppConstants {
  /// URL do endpoint HTTP do ws_server.py que expõe o último heartbeat do Raspberry.
  /// Ajusta o IP se o ws_server correr numa máquina diferente da Flutter app.
  static const String heartbeatUrl = 'http://localhost:8766/heartbeat';

  /// URL do stream MJPEG servido diretamente pelo raspberry_camera_format.py
  /// (modo --stream) na Raspberry Pi 5 — servidor embutido, sem processo
  /// separado (mjpeg_server.py foi descontinuado: a câmara só suporta um
  /// consumidor de Picamera2 de cada vez).
  /// Ajusta o IP conforme a rede local (ex: ipconfig no PC, inet addr no Pi).
  static const String mjpegUrl = 'http://192.168.43.149:8000/stream.mjpg';

  /// URL para enviar comandos ao ws_server.py (ex: reiniciar câmara com novas flags).
  static const String commandUrl = 'http://localhost:8766/command';

  /// URL base do servidor MLOps (mlops_server.py).
  static const String mlopsUrl = 'http://localhost:8767';

  /// Modelos de produção cujas linhas em `cnn_predictions` contam para as
  /// dashboards. Um shadow CNN em avaliação (página MLOps) escreve na mesma
  /// tabela com outro model_name e não deve contaminar métricas nem gráficos.
  static const Set<String> productionModels = {'CNN2', 'CNN3', 'CNN4', 'CNN5'};
}

class AppColors {
  // Global theme flag (true = dark mode, false = light mode)
  static bool isDark = true;

  // Foundational colors from Stitch Audit System (High-End Clinical Dark Mode - Forest Green Theme)
  static Color get background => isDark ? const Color(0xFF050E0C) : const Color(0xFFF4F7F6); // Forest Black / Soft light sage
  static Color get surface => isDark ? const Color(0xFF0E1A16) : const Color(0xFFFFFFFF); // Deep Sage / White
  static Color get surfaceBright => isDark ? const Color(0xFF1A2E28) : const Color(0xFFE3ECE9); // Bright Sage / Light Sage-Gray
  static Color get glassBackground => isDark ? const Color(0xCC0E1A16) : const Color(0xB3FFFFFF); // Sage Glass / White Glass
  static Color get glassBorder => isDark ? const Color(0x1F10B981) : const Color(0x2B10B981); // Emerald tinted translucent border
  
  static Color get primary => isDark ? const Color(0xFF00FFC4) : const Color(0xFF00A383); // Radiant Neon Mint-Cyan / Bright Emerald
  static Color get accent => const Color(0xFF10B981); // Emerald Green
  
  static Color get healthy => const Color(0xFF10B981);
  static Color get rot => const Color(0xFFFF4D6D); // Vibrant Neon Red
  static Color get blotch => const Color(0xFF8B5CF6); // Violet
  static Color get scab => const Color(0xFFF59E0B); // Amber
  static Color get anthracnose => const Color(0xFFEC4899); // Pink
  
  static Color get textPrimary => isDark ? const Color(0xFFE2F1EC) : Colors.black; // Soft Sage Off-White / Dark Green
  static Color get textSecondary => isDark ? const Color(0xFF8CA59D) : const Color(0xFF333333); // Sleek Sage Gray / Slate Sage
  static Color get onSurface => isDark ? Colors.white : Colors.black;
  /// Nome a apresentar ao utilizador para uma classe de doença. A chave
  /// interna usada nos dados/DB mantém-se 'Blotch' (não mexer nisso), mas
  /// a etiqueta visível passa a ser o termo biologicamente mais preciso.
  static String displayName(String condition) {
    if (condition == 'Blotch') return 'Sooty Blotch';
    return condition;
  }

  static Color getColorForCondition(String condition) {
    switch (condition.toLowerCase()) {
      case 'healthy':
        return healthy;
      case 'rot':
        return rot;
      case 'blotch':
        return blotch;
      case 'scab':
        return scab;
      case 'anthracnose':
        return anthracnose;
      default:
        return textSecondary.withOpacity(0.2);
    }
  }
}
