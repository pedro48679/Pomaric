import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mappers/bi_adapters.dart';
import '../ui/charts_v2/bi_charts.dart';
import 'dashboard_provider.dart';

/// ════════════════════════════════════════════════════════════════════════
/// Payloads dos gráficos BI fundidos em "Controlo do Pomar".
///
/// Memoiza a agregação (a cache tem ~40k maçãs): só recalcula quando os
/// lotes filtrados ou as revisões manuais mudam, NÃO reage à ordenação
/// local da tabela nem a popups (que fazem setState na página).
///
/// Usa chapter23BatchesProvider (janela fixa de 7 dias): estes gráficos
/// alimentam os Capítulos 2 e 3, que não reagem ao botão 7d/30d do
/// Capítulo 1.
/// ════════════════════════════════════════════════════════════════════════

typedef BiChartsPayload = ({
  CadenciaSanidadeData spc,
  SankeyData sankey,
  UncertaintyData uncertainty,
  HarvestValueData harvest,
  GatekeeperData gatekeeper,
});

final biChartsProvider = Provider<BiChartsPayload>((ref) {
  final batches = ref.watch(chapter23BatchesProvider);
  final reviews = ref.watch(manualReviewsProvider).value ?? const [];
  return (
    spc: BiAdapters.cadenciaSanidade(batches),
    sankey: BiAdapters.reclassSankey(reviews),
    uncertainty: BiAdapters.uncertaintyZone(batches),
    harvest: BiAdapters.harvestValue(batches),
    gatekeeper: BiAdapters.gatekeeperEfficiency(batches),
  );
});
