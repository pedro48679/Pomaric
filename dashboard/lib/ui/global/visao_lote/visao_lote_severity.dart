part of '../../global_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// VISÃO LOTE · SEVERIDADE
// Área empilhada de severidade global por lote.
// ═══════════════════════════════════════════════════════════

extension _VisaoLoteSeverity on _GlobalDashboardState {
  Widget _globalSeverityAreaChart(List<Batch> batches) {
    final colors = [AppColors.healthy, Colors.amber, Colors.orangeAccent, Colors.redAccent];
    final focusedId = ref.read(batchProvider)?.id;

    // Regra de Negócio: Traduz a Patologia detetada pela CNN em Classe Comercial
    List<int> countsFor(Batch batch) {
      final t = [0, 0, 0, 0];
      for (final apple in batch.apples) {
        final c = apple.primaryCondition;
        if (c == 'Healthy') {
          t[0]++; // Classe I
        } else if (c == 'Rot' || c == 'Anthracnose') {
          t[3]++; // Refugo (Vermelho)
        } else if (c == 'Scab' || c == 'Brown Rot' || c == 'Stinkbug') {
          t[2]++; // Indústria (Laranja)
        } else {
          t[1]++; // Classe II (Amarelo) - Blotch, Sooty Blotch, Sunburn, Frost, etc.
        }
      }
      return t;
    }

    return _card(
      'Triagem de Qualidade Comercial por Lote',
      'Conversão da patologia para a classe de venda do lote (estimativa económica)',
      380, // Height delegated to Row layout
      tooltip: '• A CNN deteta a Patologia (anomalia biológica).\n\n'
          '• O sistema aplica uma regra de negócio para estimar a Classe Comercial.\n\n'
          '• Classe I (Verde): Maçã Sã.\n'
          '• Classe II (Amarelo): Danos ligeiros ou cosméticos (Blotch, Sunburn).\n'
          '• Indústria (Laranja): Danos estruturais na casca (Scab, Brown Rot).\n'
          '• Refugo (Vermelho): Infeção grave / apodrecimento (Rot, Anthracnose).',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: batches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final b = batches[i];
                final counts = countsFor(b);
                final total = b.totalApples > 0 ? b.totalApples : 1;
                final pcts = counts.map((c) => c / total * 100).toList();
                final focused = b.id == focusedId;
                final defect = (100 - pcts[0]).clamp(0.0, 100.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(b.id,
                            style: TextStyle(
                              color: focused ? Colors.cyanAccent : AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            )),
                        const SizedBox(width: 10),
                        Text('${pcts[0].toStringAsFixed(0)}% Classe I',
                            style: TextStyle(color: AppColors.healthy, fontSize: 10)),
                        const Spacer(),
                        Text('${defect.toStringAsFixed(0)}% desclassificada',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(border: Border.all(color: AppColors.textSecondary.withOpacity(0.2))),
                        child: Row(
                          children: [
                            for (int j = 0; j < 4; j++)
                              if (pcts[j] > 0)
                                Expanded(
                                  flex: (pcts[j] * 100).toInt(),
                                  child: Container(
                                    color: colors[j],
                                    alignment: Alignment.center,
                                    child: pcts[j] >= 5
                                        ? Text('${pcts[j].toStringAsFixed(0)}%',
                                            style: const TextStyle(color: Colors.black87, fontSize: 9, fontWeight: FontWeight.bold))
                                        : null,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendIndicatorMini('Classe I', AppColors.healthy),
              _legendIndicatorMini('Classe II', Colors.amber),
              _legendIndicatorMini('Indústria', Colors.orangeAccent),
              _legendIndicatorMini('Refugo', Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendIndicatorMini(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 8)),
        ],
      ),
    );
  }
}
