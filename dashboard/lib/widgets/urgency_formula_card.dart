import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../utils/constants.dart';

Widget urgencyFormulaCard(Batch batch) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.08)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calculate, color: Colors.cyanAccent, size: 22),
                const SizedBox(width: 12),
                Text(
                  'Indicador de Urgência Operacional',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'A urgência determina a prioridade de triagem e remoção do lote das linhas de processamento com base no risco biológico e comercial:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),
            
            // Formula Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.15)),
              ),
              child: Center(
                child: Text(
                  'Urgência = (Contaminação × 40%) + (Severidade × 60%)',
                  style: GoogleFonts.firaCode(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Detailed metrics comparison
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '1. Contaminação',
                        style: GoogleFonts.inter(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Risco de contágio biológico rápido:\n'
                    '• Scab: 90%  ·  Blotch: 80\%\n'
                    '• Anthracnose: 50%  ·  Rot: 25%',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 10, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '2. Severidade',
                        style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Danos comerciais irreversíveis:\n'
                    '• Anthracnose/Rot: 100% (Descarte)\n'
                    '• Scab/Blotch: 40% (Sumo/Polpa)',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 10, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
