import 'package:flutter/material.dart';
import '../utils/constants.dart';

class ProbabilityBar extends StatelessWidget {
  final Map<String, double> probabilities;

  const ProbabilityBar({Key? key, required this.probabilities}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (probabilities.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 8,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: probabilities.entries.map((entry) {
          return Expanded(
            flex: (entry.value * 100).toInt(),
            child: Container(
              color: AppColors.getColorForCondition(entry.key),
            ),
          );
        }).toList(),
      ),
    );
  }
}
