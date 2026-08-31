part of '../global_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// CONTROLO DO POMAR · ESQUELETO
// Cabeçalho da tela, filtros e o cartão base reutilizado pelos três capítulos.
// ═══════════════════════════════════════════════════════════

extension _GlobalShell on _GlobalDashboardState {
  Widget _header(WidgetRef ref, GlobalStats stats, List<Batch> batches) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visão do Pomar',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'LIVE',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Visão executiva · Foco em Contaminação & Gravidade',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            // Date Filter Bar · afeta só o Capítulo 1 (Visão Global);
            // Capítulos 2 e 3 ficam sempre nos últimos 7 dias.
            Tooltip(
              message: 'Aplica-se apenas ao Capítulo 1 · Visão Global.\n'
                  'Os Capítulos 2 e 3 mostram sempre os últimos 7 dias.',
              padding: const EdgeInsets.all(10),
              textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
              ),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    _buildFilterOption(ref, '7d', '7 dias'),
                    _buildFilterOption(ref, '30d', '30 dias'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),
            _headerMetric('Autonomia', '${stats.automationRate.toStringAsFixed(1)}%', stats.automationRate > 90 ? AppColors.healthy : Colors.orangeAccent),
            const SizedBox(width: 24),
            _headerMetric('Confiança IA', '${stats.avgConf.toStringAsFixed(1)}%', Colors.cyanAccent),
            const SizedBox(width: 24),
            _headerMetric(
              'Revisão Manual',
              '${stats.humanQueue}',
              stats.humanQueue > 500 ? Colors.redAccent : stats.humanQueue > 0 ? Colors.orangeAccent : AppColors.healthy,
              tooltip: 'Fila real de revisão manual: registos pendentes em manual_review '
                  '(ou uma estimativa de 4,5% enquanto os dados carregam).\n\n'
                  'Distinta da "Fila Humana" do Funil de Triagem, que é uma projeção calculada '
                  'a partir da regra de confiança atual, os dois números podem divergir.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterOption(WidgetRef ref, String val, String label) {
    final activeRange = ref.watch(dateRangeFilterProvider);
    final isSelected = activeRange == val;
    return GestureDetector(
      onTap: () => ref.read(dateRangeFilterProvider.notifier).setRange(val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceBright : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _headerMetric(String label, String value, Color color, {String? tooltip}) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
    if (tooltip == null) return column;
    return Tooltip(
      message: tooltip,
      textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
      ),
      child: column,
    );
  }

  Widget _card(String title, String sub, double h, Widget child, {String? tooltip}) => GlassCard(
    padding: const EdgeInsets.all(20),
    height: h,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (tooltip != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: tooltip,
                padding: const EdgeInsets.all(12),
                textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
                ),
                child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
              ),
            ],
          ],
        ),
        Text(
          sub,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 16),
        Expanded(child: child),
      ],
    ),
  );

  FlGridData _grid() => FlGridData(
    show: true,
    drawVerticalLine: false,
    getDrawingHorizontalLine: (_) =>
        FlLine(color: AppColors.textSecondary.withOpacity(0.2), strokeWidth: 1),
  );

  FlTitlesData _ttl(List<Batch> b, {String ls = '%'}) {
    final iv = max(1, b.length ~/ 6);
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: iv.toDouble(),
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= b.length) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${b[i].date.day}/${b[i].date.month}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (v, _) => Text(
            '${v.toInt()}$ls',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
          ),
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }
}
