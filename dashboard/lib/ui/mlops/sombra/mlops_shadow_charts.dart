part of '../mlops_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// MLOPS · SOMBRA, divergência
// Onde os dois modelos discordam: barras de concordância por
// classe e casos concretos por trás de cada divergência.
// ═══════════════════════════════════════════════════════════

extension _MlopsShadowCharts on MlopsPageState {
  // --------------------------------------------------------------------------
  // Shadow: onde divergem os dois modelos (por classe + casos concretos)
  // --------------------------------------------------------------------------
  Widget _buildShadowDivergence() {
    final perClass = (_shadowState['per_class_agreement'] as Map<String, dynamic>?) ?? {};
    final disagreements = (_shadowState['disagreements'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (perClass.isEmpty) return const SizedBox.shrink();

    final entries = perClass.entries.toList()
      ..sort((a, b) {
        // Classes com mais discordância primeiro: é onde está a informação.
        double rate(MapEntry<String, dynamic> e) {
          final m = e.value as Map<String, dynamic>;
          final total = (m['total'] as num?)?.toInt() ?? 0;
          final agree = (m['agree'] as num?)?.toInt() ?? 0;
          return total > 0 ? 1 - agree / total : 0;
        }
        return rate(b).compareTo(rate(a));
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Onde divergem? (Shadow vs decisão de produção)',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final e in entries) _shadowClassAgreementRow(e.key, e.value as Map<String, dynamic>),
        if (disagreements.isNotEmpty) ...[
          const SizedBox(height: 6),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('Últimas discordâncias (${disagreements.length})',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: disagreements.length,
                    itemBuilder: (ctx, i) {
                      final dg = disagreements[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: '${dg['apple_id']}: ',
                                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                            TextSpan(text: 'produção disse '),
                            TextSpan(
                                text: '${dg['production']}',
                                style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.w600)),
                            TextSpan(text: ', shadow disse '),
                            TextSpan(
                                text: '${dg['shadow']}',
                                style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w600)),
                            TextSpan(text: ' (conf ${dg['conf']}%)'),
                          ]),
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _shadowClassAgreementRow(String cls, Map<String, dynamic> m) {
    final total = (m['total'] as num?)?.toInt() ?? 0;
    final agree = (m['agree'] as num?)?.toInt() ?? 0;
    final disagree = total - agree;
    final pct = total > 0 ? agree / total * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Tooltip(
        message: '$cls: concorda em $agree de $total (${pct.toStringAsFixed(1)}%), diverge em $disagree',
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(cls,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Row(
                  children: [
                    if (agree > 0)
                      Expanded(
                          flex: agree,
                          child: Container(height: 9, color: AppColors.healthy.withOpacity(0.85))),
                    if (disagree > 0)
                      Expanded(
                          flex: disagree,
                          child: Container(height: 9, color: Colors.redAccent.withOpacity(0.85))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text('${pct.toStringAsFixed(0)}% · $total',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: pct >= 90 ? AppColors.healthy : (pct >= 70 ? Colors.amber : Colors.redAccent),
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
