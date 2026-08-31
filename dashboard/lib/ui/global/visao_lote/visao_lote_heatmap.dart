part of '../../global_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// VISÃO LOTE · HEATMAP
// Heatmap interativo lote × patologia e a sua legenda.
// ═══════════════════════════════════════════════════════════

extension _VisaoLoteHeatmap on _GlobalDashboardState {
  // ═══ HEATMAP INTERATIVO: LOTE × PATOLOGIA ═══
  Widget _heatmap(List<Batch> batches) {
    final ds = ['Rot', 'Scab', 'Blotch', 'Anthracnose'];

    // Normalização por coluna: a célula mais escura de cada doença = o pior lote
    // dessa doença (contraste muito melhor do que escala fixa a 15%).
    final colMax = <String, double>{};
    for (final c in ds) {
      double mx = 0;
      for (final b in batches) {
        final v = b.totalApples > 0 ? (b.healthDistribution[c] ?? 0) / b.totalApples * 100 : 0.0;
        if (v > mx) mx = v;
      }
      colMax[c] = mx < 3 ? 3 : mx; // piso para não exagerar quando tudo é baixo
    }
    final focusedId = ref.read(batchProvider)?.id;

    return _card(
      'Heatmap: Lote × Patologia',
      '% de incidência da doença por lote individual (passe o rato/toque para detalhes)',
      _GlobalDashboardState._comparativoTripleChartHeight,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eixo X: Cabeçalho das Colunas
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    'ID Lote',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ...ds.map(
                  (c) => Expanded(
                    child: Text(
                      c,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.getColorForCondition(c),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Grelha Scrollável de Calor com Efeito de Fade nas Bordas
          Expanded(
            child: ShaderMask(
              shaderCallback: (Rect rect) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.08, 0.92, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: batches.length,
                itemBuilder: (context, index) {
                  final b = batches[index];
                  final focused = b.id == focusedId;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: focused
                        ? BoxDecoration(
                            color: Colors.cyanAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.cyanAccent.withOpacity(0.45)),
                          )
                        : null,
                    child: Row(
                      children: [
                        // Eixo Y: Etiqueta do Lote
                        SizedBox(
                          width: 90,
                          child: Text(
                            b.id,
                            style: TextStyle(
                              color: focused ? Colors.cyanAccent : AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Células de Calor com Tooltips Estilizados
                        ...ds.map((c) {
                          final count = b.healthDistribution[c] ?? 0;
                          final v = b.totalApples > 0
                              ? (count / b.totalApples * 100)
                              : 0.0;

                          // Intensidade normalizada por coluna (worst-of-column = 1.0).
                          final intensity = (v / (colMax[c] ?? 15.0)).clamp(0.0, 1.0);
                          final isColMax = v > 0 && v >= (colMax[c] ?? 1e9) - 0.05;
                          final color = AppColors.getColorForCondition(c);

                          return Expanded(
                            child: Tooltip(
                              message:
                                  'Lote: ${b.id}\n$c: ${v.toStringAsFixed(1)}% ($count de ${b.totalApples} maçãs)',
                              preferBelow: false,
                              textStyle: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: color.withOpacity(0.4),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Container(
                                height: 32,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(
                                    intensity * 0.82 + 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isColMax
                                        ? Colors.white.withOpacity(0.85)
                                        : intensity > 0.5
                                            ? color.withOpacity(0.6)
                                            : (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.04),
                                    width: isColMax ? 1.5 : 1,
                                  ),
                                  boxShadow: intensity > 0.55
                                      ? [
                                          BoxShadow(
                                            color: color.withOpacity(0.3),
                                            blurRadius: 5,
                                            spreadRadius: 0.5,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '${v.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: intensity > 0.4
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary,
                                      fontSize: 9,
                                      fontWeight: intensity > 0.5
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // Barra de Escala (Legenda)
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Intensidade (por doença): ',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
              ),
              const SizedBox(width: 4),
              _legendTile('menor', Colors.orangeAccent.withOpacity(0.12)),
              _legendTile('', Colors.orangeAccent.withOpacity(0.38)),
              _legendTile('', Colors.orangeAccent.withOpacity(0.62)),
              _legendTile('pior lote', Colors.orangeAccent.withOpacity(0.88)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendTile(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.03)),
        ),
        child: Text(
          label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 8),
        ),
      ),
    );
  }

  // ═══ GLOBAL AUTOMATION FUNNEL (FUNIL DE TRIAGEM & AUTOMAÇÃO GLOBAL) ═══
  // ═══ 2.B · HEATMAP PATOLÓGICO 2.0 ═══
  // Fusão: _heatmap (incidência Lote×Patologia) + _globalSeverityAreaChart
  // (gravidade): o glifo central de cada célula tem diâmetro proporcional à
  // fração de casos SEVEROS dessa doença nesse lote, célula clara com glifo
  // grande = "pouca doença mas avançada" (problema logístico, não de campo).
  // Coluna final Σ = urgencyScore (ponte com a tabela de lotes).

}
