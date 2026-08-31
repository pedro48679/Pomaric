part of '../../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// VISÃO GLOBAL · AUDITORIA HUMANA
// Fila de revisão pendente e registo de correções do operador, num só cartão.
// ═══════════════════════════════════════════════════════════

Widget humanTriageActivity(BuildContext context, List<Apple> uncertain, List<CorrectionHistory> corrections) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      height: 340,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.fact_check_outlined, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 8),
          Text('Auditoria Humana (Controlo Qualidade)', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        Text('Auditoria Pendente e Correções Aplicadas',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: triageQueuePanel(context, uncertain)),
            Container(width: 1, height: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 18), color: AppColors.glassBorder),
            Expanded(flex: 2, child: correctionsPanel(corrections)),
          ]),
        ),
      ]),
    );
  }

Widget triageQueuePanel(BuildContext context, List<Apple> uncertain) {
    const maxRows = 8;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(uncertain.isEmpty ? Icons.check_circle : Icons.pending_actions,
            color: uncertain.isEmpty ? AppColors.healthy : Colors.amber, size: 15),
        const SizedBox(width: 6),
        Text(
          uncertain.isEmpty ? 'Fila de Revisão · Tudo validado' : 'Fila de Revisão · ${uncertain.length} pendente${uncertain.length != 1 ? "s" : ""}',
          style: TextStyle(color: uncertain.isEmpty ? AppColors.healthy : Colors.amber, fontSize: 12.5, fontWeight: FontWeight.bold),
        ),
      ]),
      const SizedBox(height: 8),
      if (uncertain.isEmpty)
        Expanded(child: Center(child: Text('Nenhuma maçã necessita de revisão.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11))))
      else
        Expanded(
          child: ListView.builder(
            itemCount: min(uncertain.length, maxRows),
            itemBuilder: (context, i) {
              final apple = uncertain[i];
              final cond = apple.primaryCondition;
              final conf = apple.effectiveConfidence;
              final confColor = conf > 0.7 ? Colors.amber : Colors.orangeAccent;
              return InkWell(
                onTap: () => AppleCard.showAppleDetails(context, apple),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.getColorForCondition(cond), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(apple.id, style: TextStyle(color: AppColors.textPrimary, fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                    Text(AppColors.displayName(cond), style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                    const SizedBox(width: 8),
                    Text('${(conf * 100).toStringAsFixed(0)}%', style: TextStyle(color: confColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 14),
                  ]),
                ),
              );
            },
          ),
        ),
      if (uncertain.length > maxRows)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+ ${uncertain.length - maxRows} mais na fila completa', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
        ),
    ]);
  }

Widget correctionsPanel(List<CorrectionHistory> corrections) {
    const maxRows = 8;
    final sorted = [...corrections]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.history, color: Colors.purpleAccent, size: 15),
        const SizedBox(width: 6),
        Text(
          corrections.isEmpty ? 'Correções · Nenhuma' : 'Correções · ${corrections.length}',
          style: const TextStyle(color: Colors.purpleAccent, fontSize: 12.5, fontWeight: FontWeight.bold),
        ),
      ]),
      const SizedBox(height: 8),
      if (corrections.isEmpty)
        Expanded(child: Center(child: Text('Sem correções nesta sessão.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11))))
      else
        Expanded(
          child: ListView.builder(
            itemCount: min(sorted.length, maxRows),
            itemBuilder: (context, i) {
              final c = sorted[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.getColorForCondition(c.label), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(AppColors.displayName(c.label), style: TextStyle(color: AppColors.textPrimary, fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                  Text(c.correctedBy, style: TextStyle(color: AppColors.textSecondary, fontSize: 10), overflow: TextOverflow.ellipsis),
                  const SizedBox(width: 6),
                  Text(DateFormat('HH:mm').format(c.timestamp), style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ]),
              );
            },
          ),
        ),
      if (sorted.length > maxRows)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+ ${sorted.length - maxRows} mais no histórico completo', style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
        ),
    ]);
  }
