
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/donut_chart_widget.dart';
import '../../widgets/apple_grid_view.dart';

class MatrixDashboardView extends ConsumerWidget {
  const MatrixDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(batchProvider);
    final filteredApples = ref.watch(filteredApplesProvider);
    final filter = ref.watch(selectedConditionFilterProvider);
    final user = ref.watch(authProvider);
    final isAdmin = user?.role == UserRole.admin;

    if (batch == null) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: ElevatedButton.icon(
                onPressed: () => ref
                    .read(currentPageProvider.notifier)
                    .setPage('Lote Dashboard'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Voltar ao Lote'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.isDark ? Colors.grey[800] : Colors.grey[200],
                  foregroundColor: AppColors.textPrimary,
                ),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left side: Analytics
                const Expanded(flex: 2, child: DonutChartWidget()),
                const SizedBox(width: 16),
                // Right side: Apple Grid
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Matriz de Inspeção: ${batch.id}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            filter.isEmpty
                                ? 'A mostrar todos (${filteredApples.length})'
                                : 'Filtrado por: ${filter.join(', ')} (${filteredApples.length})',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: AppleGridView(apples: filteredApples),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

