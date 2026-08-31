part of '../../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// VISÃO LOTE · FILTRO DE TRIAGEM
// Filtro do lote por estado de triagem e o respetivo seletor.
// ═══════════════════════════════════════════════════════════

List<Apple> filterApplesByTriagem(List<Apple> apples, String filter) {
    if (apples.isEmpty) return apples;
    final sorted = [...apples]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final dates = <String>{};
    for (final a in sorted) {
      dates.add('${a.timestamp.year}-${a.timestamp.month.toString().padLeft(2, '0')}-${a.timestamp.day.toString().padLeft(2, '0')}');
    }
    final limit = filter == '1t' ? 1 : 5;
    final allowed = dates.take(limit).toSet();
    return sorted.where((a) {
      final key = '${a.timestamp.year}-${a.timestamp.month.toString().padLeft(2, '0')}-${a.timestamp.day.toString().padLeft(2, '0')}';
      return allowed.contains(key);
    }).toList();
  }

Widget buildTriagemToggle(WidgetRef ref, String current) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          triBtn(ref, '1t', '1 Triagem', current),
          triBtn(ref, '5t', '5 Triagens', current),
        ],
      ),
    );
  }

Widget triBtn(WidgetRef ref, String val, String label, String current) {
    final selected = current == val;
    return GestureDetector(
      onTap: () => ref.read(batchTriagemFilterProvider.notifier).setFilter(val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceBright : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: selected ? const Color(0xff10B981) : AppColors.textSecondary,
            fontSize: 9,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ── Z-Score de Desvio Inter-Lote (Batch Drift Score) ──────────────────────
  // Compara o lote/triagem atual com μ e σ dos últimos lotes finalizados.


  // ── Confiança por Patologia (Ridgeline / Joyplot) ─────────────────────────
  // Fusão de "Distribuição por Doença" + "Distribuição de Confiança por Doença":
  // uma crista de densidade por patologia mostra a FORMA completa da distribuição
  // de confiança CNN (não só médias/buckets), cristas estreitas e altas = diagnóstico
  // consistente; largas ou bimodais = incerteza real nessa patologia.
