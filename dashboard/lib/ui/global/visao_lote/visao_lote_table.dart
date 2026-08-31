part of '../../global_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// VISÃO LOTE · TABELA
// Tabela comparativa de lotes, ordenação e badge de estado.
// ═══════════════════════════════════════════════════════════

extension _VisaoLoteTable on _GlobalDashboardState {
  double _bApproval(Batch b) => b.totalApples == 0
      ? 0
      : (b.healthDistribution['Healthy'] ?? 0) / b.totalApples * 100;

  void _onSort(String colName, bool ascending) {
    setState(() {
      _sortColumn = colName;
      _sortAscending = ascending;
    });
  }

  int? _sortColumnIndex() {
    switch (_sortColumn) {
      case 'Lote': return 0;
      case 'Local': return 1;
      case 'Volume': return 2;
      case 'Aprovação': return 3;
      case 'Contaminação': return 5;
      case 'Gravidade': return 6;
      case 'Tendência': return 7;
      default: return null;
    }
  }

  Widget _buildStateBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.healthy.withOpacity(0.12)
            : (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? AppColors.healthy.withOpacity(0.3) : (AppColors.isDark ? Colors.white24 : Colors.black26),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.healthy,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            isActive ? 'ATIVO' : 'CONCLUÍDO',
            style: TextStyle(
              color: isActive ? AppColors.healthy : AppColors.textSecondary,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ═══ TABLE ═══
  Widget _table(List<Batch> batches, WidgetRef ref) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: DataTable(
      sortColumnIndex: _sortColumnIndex(),
      sortAscending: _sortAscending,
      headingTextStyle: TextStyle(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
      dataTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
      columnSpacing: 16,
      columns: [
        DataColumn(
          label: const Text('Lote'),
          onSort: (colIdx, asc) => _onSort('Lote', asc),
        ),
        DataColumn(
          label: const Text('Local'),
          onSort: (colIdx, asc) => _onSort('Local', asc),
        ),
        DataColumn(
          label: const Text('Volume'),
          onSort: (colIdx, asc) => _onSort('Volume', asc),
        ),
        DataColumn(
          label: const Text('Aprovação'),
          onSort: (colIdx, asc) => _onSort('Aprovação', asc),
        ),
        const DataColumn(label: Text('Doença Principal')),
        DataColumn(
          label: const Text('Contaminação'),
          onSort: (colIdx, asc) => _onSort('Contaminação', asc),
        ),
        DataColumn(
          label: const Text('Gravidade'),
          onSort: (colIdx, asc) => _onSort('Gravidade', asc),
        ),
        DataColumn(
          label: const Text('Tendência'),
          onSort: (colIdx, asc) => _onSort('Tendência', asc),
        ),
        const DataColumn(label: Text('Urgência')),
        const DataColumn(label: Text('')),
      ],
      rows: batches.map((b) {
        final ap = _bApproval(b);
        final contColor = b.contaminationScore > 0.4
            ? Colors.redAccent
            : b.contaminationScore > 0.2
            ? Colors.amber
            : AppColors.healthy;
        final sevColor = b.severityScore > 0.3
            ? Colors.redAccent
            : b.severityScore > 0.15
            ? Colors.amber
            : AppColors.healthy;

        final isActive = b.isActive;

        return DataRow(
          color: WidgetStateProperty.resolveWith<Color?>((states) {
            if (b.id == ref.read(batchProvider)?.id) {
              return Colors.cyanAccent.withOpacity(0.14);
            }
            if (isActive) {
              return AppColors.healthy.withOpacity(0.08);
            }
            return null;
          }),
          cells: [
            DataCell(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(b.id, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    _buildStateBadge(isActive),
                  ],
                ),
              ),
            ),
            DataCell(
              Text(
                b.location,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
            ),
            DataCell(Text('${b.totalApples}')),
            DataCell(
              Text(
                '${ap.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: ap > 80 ? AppColors.healthy : Colors.orangeAccent,
                ),
              ),
            ),
            DataCell(Builder(builder: (_) {
              final dom = getDominantDiseaseENForBatch(b);
              final c = AppColors.getColorForCondition(dom);
              final n = b.healthDistribution[dom] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.withOpacity(0.3)),
                ),
                child: Text(
                  dom == 'Healthy' ? 'Healthy' : '${AppColors.displayName(dom)} ($n)',
                  style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              );
            })),
            DataCell(
              Text(
                '${(b.contaminationScore * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: contColor),
              ),
            ),
            DataCell(
              Text(
                '${(b.severityScore * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: sevColor),
              ),
            ),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    b.growthRate > 0 ? Icons.trending_up : Icons.trending_down,
                    color: b.growthRate > 0
                        ? Colors.redAccent
                        : AppColors.healthy,
                    size: 14,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${b.growthRate > 0 ? "+" : ""}${b.growthRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: b.growthRate > 0
                          ? Colors.redAccent
                          : AppColors.healthy,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            DataCell(
              Text(
                '${(b.urgencyScore * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.firaCode(
                  color: b.urgencyScore > 0.3 ? Colors.redAccent : b.urgencyScore > 0.10 ? Colors.amber : AppColors.healthy,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataCell(
              TextButton(
                onPressed: () => ref.read(batchProvider.notifier).setBatch(b),
                child: Text(
                  b.id == ref.read(batchProvider)?.id ? '● Em foco' : 'Focar →',
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    ),
  );
}
