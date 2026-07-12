import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import 'probability_bar.dart';
import 'hybrid_image.dart';

import 'package:google_fonts/google_fonts.dart';
import '../widgets/glass_card.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';

class AppleCard extends ConsumerWidget {
  final Apple apple;

  const AppleCard({Key? key, required this.apple}) : super(key: key);

  static void showGradCamDialog(BuildContext context, String imageUrl, String id) {
    // Calcula a rota dinâmica da imagem térmica baseada na original
    final gradcamUrl = imageUrl.replaceFirst('.png', '_gradcam.png')
                              .replaceFirst('.jpg', '_gradcam.jpg')
                              .replaceFirst('.jpeg', '_gradcam.jpeg');
                              
    showDialog(
      context: context,
      builder: (context) => GlassCard(
        width: 340,
        height: 400,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Foco de Inferência', style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('ID: $id', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 20),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(gradcamUrl, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar Detalhe'),
            ),
          ],
        ),
      ),
    );
  }

  static void showAppleDetails(BuildContext context, Apple apple) {
    final PageController pageController = PageController();
    bool showHeatmap = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 450,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detalhes: ${apple.id}',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.65 > 540 ? 540 : MediaQuery.of(context).size.height * 0.65,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PageView.builder(
                        controller: pageController,
                        itemCount: apple.frames.length,
                        itemBuilder: (context, index) {
                          final frame = apple.frames[index];
                          final gradcamUrl = frame.url.replaceFirst('.png', '_gradcam.png')
                                                    .replaceFirst('.jpg', '_gradcam.jpg')
                                                    .replaceFirst('.jpeg', '_gradcam.jpeg');

                          return SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 280,
                                      height: 280,
                                      color: Colors.black26,
                                      child: Stack(
                                        children: [
                                          // Imagem Original (sempre na base para transição limpa)
                                          HybridImage(
                                            localUrl: frame.url,
                                            cloudUrl: null,
                                            width: 280,
                                            height: 280,
                                            fit: BoxFit.cover,
                                          ),
                                          // Heatmap Overlay
                                          if (showHeatmap)
                                            Positioned.fill(
                                              child: Image.network(
                                                gradcamUrl, 
                                                fit: BoxFit.cover, 
                                                errorBuilder: (c,e,s) => Container(
                                                  color: Colors.black54,
                                                  child: Center(child: Text('Heatmap não disponível', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)))
                                                ),
                                                loadingBuilder: (context, child, loadingProgress) {
                                                  if (loadingProgress == null) return child;
                                                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: Text(
                                    'Soma Doença: ${(frame.diseaseSum * 100).toStringAsFixed(1)}%',
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TextButton.icon(
                                  icon: Icon(showHeatmap ? Icons.layers_clear : Icons.layers, color: Colors.orangeAccent, size: 16),
                                  label: Text(showHeatmap ? 'Ocultar Heatmap' : 'Ver Heatmap (Grad-CAM)', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                                  onPressed: () => setDialogState(() => showHeatmap = !showHeatmap),
                                ),
                                const SizedBox(height: 8),
                                Text('Probabilidades das Patologias:', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                ...frame.probabilities.entries.where((e) => e.value > 0.05).map((e) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Container(width: 12, height: 12, color: AppColors.getColorForCondition(e.key)),
                                              const SizedBox(width: 8),
                                              Text(e.key, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                            ],
                                          ),
                                          Text('${(e.value * 100).toStringAsFixed(1)}%', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    )),
                              ],
                            ),
                          );
                        },
                      ),
                      if (apple.frames.length > 1)
                        Positioned(
                          left: 0,
                          top: 120,
                          child: IconButton(
                            icon: Icon(Icons.chevron_left, color: AppColors.textPrimary, size: 40),
                            onPressed: () {
                              pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                            },
                          ),
                        ),
                      if (apple.frames.length > 1)
                        Positioned(
                          right: 0,
                          top: 120,
                          child: IconButton(
                            icon: Icon(Icons.chevron_right, color: AppColors.textPrimary, size: 40),
                            onPressed: () {
                              pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                if (apple.frames.length > 1)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text('Swipe para mais frames', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      pageController.dispose();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Fechar'),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final borderColor = AppColors.getColorForCondition(apple.primaryCondition);
    final isHealthy = apple.primaryCondition == 'Healthy';
    final isForced = ref.watch(forcedTriageProvider).contains(apple.id);
    
    return GestureDetector(
      onTap: () => AppleCard.showAppleDetails(context, apple),
      child: GlassCard(
        borderRadius: 12,
        opacity: 0.4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HybridImage(
                    localUrl: apple.worstFrameUrl,
                    cloudUrl: null,
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      color: Colors.white.withOpacity(0.05),
                      child: const Center(child: Icon(Icons.apple, color: Colors.white10, size: 40)),
                    ),
                  ),
                  Positioned(
                    top: 8, right: 8,
                    child: GestureDetector(
                      onTap: () {
                        ref.read(forcedTriageProvider.notifier).toggleForced(apple.id);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(isForced ? 'Removido da triagem.' : 'Enviado para triagem manual.'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isForced 
                            ? Colors.amber 
                            : (isHealthy ? AppColors.healthy : borderColor).withOpacity(0.8),
                          shape: BoxShape.circle,
                          boxShadow: isForced ? [BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 8)] : null,
                        ),
                        child: Icon(
                          isForced 
                            ? Icons.priority_high 
                            : (isHealthy ? Icons.check : Icons.warning_amber_rounded), 
                          color: AppColors.textPrimary, 
                          size: 16
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.glassBorder, width: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    apple.id,
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                  if ((apple.worstFrame?.probabilities.length ?? 0) > 1) ...[
                    const SizedBox(height: 4),
                    ...apple.worstFrame!.probabilities.entries.where((e) => e.value > 0.05).map((e) => Text(
                      '${e.key}: ${(e.value * 100).toStringAsFixed(1)}%',
                      style: TextStyle(color: AppColors.getColorForCondition(e.key), fontSize: 9, fontWeight: FontWeight.bold),
                    )),
                  ],
                  const SizedBox(height: 6),
                  ProbabilityBar(probabilities: apple.worstFrame?.probabilities ?? {apple.primaryCondition: apple.effectiveConfidence}),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}