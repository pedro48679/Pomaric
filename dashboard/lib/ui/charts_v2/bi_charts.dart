/// ════════════════════════════════════════════════════════════════════════
/// BI CHARTS, os conceitos aproveitados e melhorados, fundidos na página
/// "Controlo do Pomar" (GlobalDashboard).
///
///   • SpcCadenceChart              , Cadência vs. Sanidade (SPC) com a
///                                     doença #1 da hora dobrada na cor do
///                                     ponto + tooltip.            [bi_flow]
///   • ReclassSankeyChart           , Fluxo de Reclassificação.     [bi_flow]
///   • UncertaintyZoneChart         , Zona de Incerteza sem sobreposição de
///                                     bolhas, faixa open-set evidente e
///                                     badge de contagem.   [bi_distribution]
///   • HarvestValueChart            , Copo de valor económico da colheita:
///                                     Classe I, Classe II e Indústria.
///                                                              [bi_harvest]
///   • GatekeeperEfficiencyChart    , Mosaico CNN2 vs CNN5: quem decide cada
///                                     maçã.                  [bi_gatekeeper]
///
/// Este ficheiro é só o barrel: cada gráfico vive no seu próprio ficheiro
/// por tema. Quem importa 'bi_charts.dart' continua a ver todos os
/// símbolos, sem alterar um único import.
/// ════════════════════════════════════════════════════════════════════════
library;

export 'bi_flow.dart';
export 'bi_distribution.dart';
export 'bi_harvest.dart';
export 'bi_gatekeeper.dart';
