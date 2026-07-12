import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/dashboard_provider.dart';
import '../utils/constants.dart';

class DonutChartWidget extends ConsumerWidget {
  const DonutChartWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(batchProvider);
    final activeFilters = ref.watch(selectedConditionFilterProvider);

    if (batch == null) return const Center(child: CircularProgressIndicator());

    final distribution = batch.healthDistribution;
    final Map<String, int> activeDistribution = {};
    
    // remove zero values
    distribution.forEach((key, value) {
      if (value > 0) activeDistribution[key] = value;
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Text(
            'Distribuição do Lote',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Stack(
              children: [
                PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          return;
                        }

                        // Fix jitter: Only toggle state exactly on TAP release (FlTapUpEvent)
                        // This prevents mouse hover from continuously resetting chart layouts due to radius changes
                        if (event is FlTapUpEvent) {
                          final index = pieTouchResponse.touchedSection!.touchedSectionIndex;
                          if (index >= 0 && index < activeDistribution.length) {
                            final condition = activeDistribution.keys.elementAt(index);
                            ref.read(selectedConditionFilterProvider.notifier).toggleFilter(condition);
                          }
                        }
                      },
                    ),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 4,
                    centerSpaceRadius: 60,
                    sections: activeDistribution.entries.map((entry) {
                      final condition = entry.key;
                      final count = entry.value;
                      final isSelected = activeFilters.contains(condition);
                      final radius = isSelected ? 50.0 : 40.0;
                      final color = AppColors.getColorForCondition(condition);

                      return PieChartSectionData(
                        color: color,
                        value: count.toDouble(),
                        title: '${((count / batch.totalApples) * 100).toStringAsFixed(1)}%',
                        radius: radius,
                        titleStyle: TextStyle(
                          fontSize: isSelected ? 18.0 : 14.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                      Text(
                        '${batch.totalApples}',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: activeDistribution.entries.map((entry) {
              final condition = entry.key;
              final isSelected = activeFilters.contains(condition);
              return InkWell(
                onTap: () {
                  ref.read(selectedConditionFilterProvider.notifier).toggleFilter(condition);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.getColorForCondition(condition).withOpacity(0.2) : Colors.transparent,
                    border: Border.all(
                      color: AppColors.getColorForCondition(condition),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.getColorForCondition(condition),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$condition (${entry.value})',
                        style: TextStyle(
                          color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          )
        ],
      ),
    );
  }
}