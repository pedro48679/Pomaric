part of '../mlops_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// MLOPS · COMPARAR, painel
// UI do separador Comparar: selecção dos dois modelos, botão de
// comparação, estatísticas gerais e pills de modo/filtro.
// ═══════════════════════════════════════════════════════════

extension _MlopsComparePanel on MlopsPageState {
  Widget _buildComparePanel() {
    final modelNames = _models.map((m) => m.name).toList();
    final metaA = _compareResult['model_a'] as Map<String, dynamic>? ?? {};
    final metaB = _compareResult['model_b'] as Map<String, dynamic>? ?? {};
    final histA = metaA['history'] as List? ?? [];
    final histB = metaB['history'] as List? ?? [];
    final clsA = List<String>.from(metaA['classes'] as List? ?? []);
    final clsB = List<String>.from(metaB['classes'] as List? ?? []);
    final allCls = {...clsA, ...clsB}.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Seletor de modelos
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _modelDropdown('Modelo A', _compareA, modelNames,
                        (v) => setState(() => _compareA = v)),
                    _weightStatsPreview(_compareA),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('vs',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _modelDropdown('Modelo B', _compareB, modelNames,
                        (v) => setState(() => _compareB = v)),
                    _weightStatsPreview(_compareB),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: (_compareA == null || _compareB == null || _compareA == _compareB || _loadingCompare)
                    ? null
                    : _loadCompare,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                child: _loadingCompare
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.surface))
                    : Text('Comparar',
                        style: TextStyle(
                            color: AppColors.surface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Tipo de gráfico (Curva por época | Curva de Discriminação)
        if (_compareResult.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _chartModePill('Curva por Época', 'epoch'),
                const SizedBox(width: 6),
                _chartModePill('Curva de Discriminação', 'discrimination'),
              ],
            ),
          ),
        ],

        // Seletor de métrica (cascade pills), só relevante para curva por época
        if (_compareResult.isNotEmpty && _compareChartMode == 'epoch') ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _metricPill('Accuracy',  'val_acc'),
                const SizedBox(width: 6),
                _metricPill('F1-Score',  'f1'),
                const SizedBox(width: 6),
                _metricPill('Precisão',  'precision'),
                const SizedBox(width: 6),
                _metricPill('Recall',    'recall'),
              ],
            ),
          ),
        ],

        if (_compareResult.isEmpty)
          Expanded(
            child: Center(
              child: Text('Seleciona dois modelos e clica em Comparar',
                  style: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.5),
                      fontSize: 13)),
            ),
          )
        else if (_compareChartMode == 'discrimination')
          Expanded(
            child: _buildRocPrPanel(metaA, metaB, allCls),
          )
        else
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildMetricCurve(histA, histB, metaA, metaB, _compareMetric)),
                const SizedBox(width: 12),
                Expanded(child: _buildClassErrorMatrix(metaA, metaB)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chartModePill(String label, String mode) {
    final active = _compareChartMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _compareChartMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.primary : AppColors.glassBorder),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  Widget _rocPrToggle(String label, bool valueIsRoc) {
    final active = _discriminationIsRoc == valueIsRoc;
    return GestureDetector(
      onTap: () => setState(() => _discriminationIsRoc = valueIsRoc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? AppColors.primary : AppColors.glassBorder),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? AppColors.primary : AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _classFilterChip(String label, String? value) {
    final active = _curveClassFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _curveClassFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? AppColors.primary : AppColors.glassBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _modelDropdown(String label, String? value, List<String> items,
      ValueChanged<String?> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: value,
            dropdownColor: AppColors.surface,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.glassBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.glassBorder)),
            ),
            hint: Text('Selecionar...',
                style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.5),
                    fontSize: 11)),
            items: items
                .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      );

  Widget _compareStat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 9)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      );
}
