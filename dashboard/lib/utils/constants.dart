import 'package:flutter/material.dart';

class AppColors {
  // Foundational colors from Stitch Audit System (High-End Clinical Dark Mode - Forest Green Theme)
  static const Color background = Color(0xFF050E0C); // Forest Black
  static const Color surface = Color(0xFF0E1A16); // Deep Sage
  static const Color surfaceBright = Color(0xFF1A2E28); // Bright Sage
  static const Color glassBackground = Color(0xCC0E1A16); // Sage Glass
  static const Color glassBorder = Color(0x1F10B981); // Emerald tinted translucent border
  
  static const Color primary = Color(0xFF00FFC4); // Radiant Neon Mint-Cyan
  static const Color accent = Color(0xFF10B981); // Emerald Green
  
  static const Color healthy = Color(0xFF10B981);
  static const Color rot = Color(0xFFFF4D6D); // Vibrant Neon Red
  static const Color blotch = Color(0xFF8B5CF6); // Violet
  static const Color scab = Color(0xFFF59E0B); // Amber
  static const Color anthracnose = Color(0xFFEC4899); // Pink
  
  static const Color textPrimary = Color(0xFFE2F1EC); // Soft Sage Off-White
  static const Color textSecondary = Color(0xFF8CA59D); // Sleek Sage Gray

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
