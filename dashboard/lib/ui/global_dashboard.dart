import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import 'dart:ui' as ui show TextDirection;
import 'package:google_fonts/google_fonts.dart';

import '../widgets/glass_card.dart';
import '../models/models.dart';
import '../providers/dashboard_provider.dart';
import '../utils/constants.dart';
import '../widgets/skeleton_card.dart';
import '../widgets/hybrid_image.dart';
import '../widgets/pulsing_kpi_card.dart';
import '../widgets/urgency_formula_card.dart';
import '../widgets/apple_card.dart';
// Fusão dos 3 conceitos BI aproveitados (SPC, Sankey de reclassificação,
// Zona de Incerteza), widgets isolados + payloads memoizados.
import '../providers/bi_charts_provider.dart';
import '../data/mappers/bi_adapters.dart';
import 'charts_v2/bi_charts.dart';
import '../widgets/brush_zoom_viewer.dart';
// Fusão por tema: reutiliza os gráficos de lote (funções/classes públicas das
// libraries lote/*) dentro da dashboard unificada. Prefixo `lote` evita colisões.
// (As libraries lote/* são importadas diretamente, imports não são transitivos.)


// Uma subpasta por capítulo da tela: visao_global (estado do pomar),
// visao_lote (comparação entre lotes) e visao_computacional (performance
// da CNN). `part of` + extension porque tudo isto lê o estado privado
// de _GlobalDashboardState e chama setState directamente.
part 'global/global_shell.dart';
part 'global/global_outbreak_popup.dart';
part 'global/visao_global/visao_global_kpi.dart';
part 'global/visao_global/visao_global_charts.dart';
part 'global/visao_global/visao_global_feed.dart';
part 'global/visao_lote/visao_lote_heatmap.dart';
part 'global/visao_lote/visao_lote_table.dart';
part 'global/visao_lote/visao_lote_severity.dart';
part 'global/visao_lote/visao_lote_risk_scatter.dart';
part 'global/visao_computacional/visao_computacional_cnn.dart';
part 'global/visao_computacional/visao_computacional_flipcard.dart';
part 'global/visao_lote/visao_lote_spc_chart.dart';
part 'global/visao_lote/visao_lote_timeline.dart';
part 'global/visao_lote/visao_lote_eisenhower.dart';
part 'global/visao_lote/visao_lote_comparison.dart';
part 'global/visao_lote/visao_lote_triagem_filtro.dart';
part 'global/visao_global/visao_global_triagem_humana.dart';
part 'global/visao_computacional/visao_computacional_matrix_cell.dart';

String getDominantDiseaseENForBatch(Batch b) {
  final dist = b.healthDistribution;
  String dominant = 'Healthy';
  int maxVal = 0;
  for (final k in ['Rot', 'Scab', 'Blotch', 'Anthracnose']) {
    if ((dist[k] ?? 0) > maxVal) {
      maxVal = dist[k]!;
      dominant = k;
    }
  }
  return dominant;
}

class GlobalDashboard extends ConsumerStatefulWidget {
  const GlobalDashboard({super.key});

  @override
  ConsumerState<GlobalDashboard> createState() => _GlobalDashboardState();
}

class _GlobalDashboardState extends ConsumerState<GlobalDashboard> {
  static const double _comparativoTripleChartHeight = 420;

  String _sortColumn = 'Lote';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allBatches = ref.watch(filteredBatchesProvider);
    final corrections = ref.watch(correctionHistoryProvider);
    final stats = ref.watch(globalStatsProvider);
    final reviewsAsync = ref.watch(manualReviewsProvider);
    final bi = ref.watch(biChartsProvider); // SPC · Sankey · Zona de Incerteza

    // ── Dados de lote em foco (secções de fusão por tema) ───────────────
    // Capítulos 2 e 3: janela fixa de 7 dias, não reage ao botão 7d/30d
    // (esse botão só controla o Capítulo 1, via filteredBatchesProvider acima).
    final availableBatches = ref.watch(chapter23BatchesProvider);
    final selectedBatch = ref.watch(batchProvider);
    final batchStats = ref.watch(batchStatsProvider);
    final triFilter = ref.watch(batchTriagemFilterProvider);
    final uncertain = ref.watch(uncertainApplesProvider);

    if (allBatches.isEmpty || stats == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonCard(height: 80),
            const SizedBox(height: 28),
            Row(
              children: List.generate(
                5,
                (index) => const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.0),
                    child: SkeletonCard(height: 100),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: const [
                Expanded(flex: 3, child: SkeletonCard(height: 300)),
                SizedBox(width: 16),
                Expanded(flex: 2, child: SkeletonCard(height: 300)),
              ],
            ),
          ],
        ),
      );
    }

    // Mesma janela fixa de 7 dias que `availableBatches` acima, só que
    // ordenada para as tabelas/gráficos dos Capítulos 2 e 3.
    final sortedUnfiltered = [...availableBatches];
    sortedUnfiltered.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case 'Lote':
          cmp = a.id.compareTo(b.id);
          break;
        case 'Local':
          cmp = a.location.compareTo(b.location);
          break;
        case 'Volume':
          cmp = a.totalApples.compareTo(b.totalApples);
          break;
        case 'Aprovação':
          cmp = _bApproval(a).compareTo(_bApproval(b));
          break;
        case 'Contaminação':
          cmp = a.contaminationScore.compareTo(b.contaminationScore);
          break;
        case 'Gravidade':
          cmp = a.severityScore.compareTo(b.severityScore);
          break;
        case 'Tendência':
          cmp = a.growthRate.compareTo(b.growthRate);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    // Batches for Chapter 1
    final batches = [...allBatches];
    batches.sort((a, b) => a.date.compareTo(b.date));

    final dismissedIds = ref.watch(dismissedOutbreaksProvider);
    final isDismissed = ref.watch(outbreaksPopupDismissedProvider);
    final riskBatches = sortedUnfiltered.where((b) {
      final dom = getDominantDiseaseENForBatch(b);
      return dom != 'Healthy' && b.urgencyScore > 0.05 && !dismissedIds.contains(b.id);
    }).toList();
    final showSystemSurge = stats.surgeAlert != 'Estável' && !dismissedIds.contains('SYSTEM_SURGE');

    // Derivados do lote em foco. batchProvider guarda o lote COMPLETO (todas
    // as datas, é o mesmo objeto que alimenta a Triagem Manual, que não pode
    // perder pendentes antigos). Aqui usamos a versão já recortada aos 7 dias
    // vinda de chapter23BatchesProvider, para o detalhe do lote respeitar a
    // mesma janela do resto do Capítulo 2.
    final Batch? windowedBatch = selectedBatch == null
        ? null
        : availableBatches.where((b) => b.id == selectedBatch.id).firstOrNull;

    final bool loteReady = windowedBatch != null && batchStats != null;
    final List<Apple> filteredApples =
        loteReady ? filterApplesByTriagem(windowedBatch.apples, triFilter) : const <Apple>[];
    final double quantityScale = triFilter == '1t' ? 0.2 : 1.0;
    final Batch? filteredBatch = loteReady ? Batch(
      id: windowedBatch.id,
      name: windowedBatch.name,
      date: windowedBatch.date,
      apples: filteredApples,
      location: windowedBatch.location,
    ) : null;
    final List<CorrectionHistory> loteCorrections =
        loteReady ? corrections.where((c) => c.batchId == windowedBatch.id).toList() : const <CorrectionHistory>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        return OverflowBox(
          maxWidth: constraints.maxWidth / 0.75,
          minWidth: constraints.maxWidth / 0.75,
          maxHeight: constraints.hasBoundedHeight ? constraints.maxHeight / 0.75 : double.infinity,
          minHeight: constraints.hasBoundedHeight ? constraints.maxHeight / 0.75 : 0.0,
          alignment: Alignment.topCenter,
          child: Transform.scale(
            scale: 0.75,
            alignment: Alignment.topCenter,
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(ref, stats, sortedUnfiltered),
              const SizedBox(height: 24),

          // ══════════════════ CAPÍTULO 1 · VISÃO GLOBAL ══════════════════
          // Resumo executivo, sempre global (não reage à seleção de lote).
          _chapterHeader('1', 'Visão Global', 'Estado geral da produção · sempre global', const Color(0xff10B981)),
          const SizedBox(height: 20),
          _kpiRow(stats, batches),
          const SizedBox(height: 20),
          // 1.B SPC de cadência movido para cima (primeiro gráfico a aparecer)
          _card(
            'Cronograma de Triagem de Lotes (SPC)',
            'Sessões de triagem por lote, em ordem cronológica · últimos 7 dias em destaque',
            320,
            SpcCadenceChart(data: BiAdapters.cadenciaSanidade(batches)),
            tooltip: 'Cada barra é uma sessão de triagem de um lote num dia (o mesmo lote reaparece noutros dias). '
                'A altura da barra é a média de maçãs por hora ativa dessa sessão (horas sem triagem não contam). '
                'A linha é a percentagem de maçãs doentes; a faixa cinzenta representa os limites normais. '
                'Se a linha sair da faixa, o desvio é estatisticamente significativo. '
                'A cor de cada ponto identifica a patologia predominante da sessão. Passa o rato para ver o período real.\n\n'
                'Na vista de 30 dias, os últimos 7 dias ficam à direita da linha tracejada e ocupam pelo menos 60% '
                'da largura, com uma barra por sessão. O histórico anterior aparece esbatido e condensado em blocos '
                '(cada bloco junta várias sessões seguidas), para dar contexto sem roubar espaço ao que é recente. '
                'Os limites de controlo são sempre calculados sobre as sessões individuais, e só estas assinalam '
                'desvio: um bloco agregado é uma média e não serve para esse teste.',
          ),
          const SizedBox(height: 16),
          // Evolução de Anomalias (área simples por patologia + média móvel) ·
          // 1.C Funil 2.0 (segmentado por doença)
          SizedBox(
            height: 380,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _diseaseAreaChart(stats.dailyBatches)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _automationFunnel2(batches.expand((b) => b.apples).toList(), corrections)),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // ═════════ CAPÍTULO 2 · ANÁLISE & COMPARAÇÃO DE LOTES ═════════
          // Comparação entre lotes + seleção do "lote em foco" (driver do funil).
          _chapterHeader('2', 'Análise & Comparação de Lotes',
              'Compare lotes e padrões · escolha o lote em foco', const Color(0xffF59E0B)),
          const SizedBox(height: 16),
          // 2.A Trajetórias de Risco (scatter + trilhas temporais) + 2.B Heatmap
          // Lote×Patologia (incidência simples por lote). As barras de Severidade
          // Global ficam em largura total logo acima da tabela.
          SizedBox(
            height: 420,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _InteractiveRiscoChart(batches: sortedUnfiltered)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _heatmap(sortedUnfiltered)),
              ],
            ),
          ),
          SizedBox(
            height: 380,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 7,
                  child: _globalSeverityAreaChart(sortedUnfiltered),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: _card(
                    'Valor da Colheita Económica',
                    'Copo: Classe I (0,60€), Classe II (0,40€) e Indústria (0,20€)',
                    380,
                    HarvestValueChart(data: bi.harvest),
                    tooltip: 'Copo de valor económico da colheita, mede a composição REAL do pomar:\n\n'
                        'Classe I: vendidas como premium (0,60€/un).\n'
                        'Classe II: defeitos ligeiros vendáveis como "segunda escolha" (0,40€/un).\n'
                        'Indústria: defeitos estruturais para sumo/processamento (0,20€/un).\n\n'
                        'O restante (Refugo/Infecciosos) fica fora das bandas coloridas mas conta para o total (por isso o copo não enche a 100%).\n\n'
                        'A altura de cada banda é a percentagem REAL no pomar.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ═════ BARREIRA: comparação entre lotes (M:N, acima) vs. detalhe
          // de UM lote (1:N, abaixo) ═════
          // Bug: usava `batches` (janela do Capítulo 1, reage ao botão 7d/30d),
          // fazendo a tabela de comparação do Capítulo 2 mudar sozinha ao
          // clicar no botão. Deve usar a janela fixa dos Capítulos 2/3.
          _loteGate(sortedUnfiltered, ref),
          const SizedBox(height: 32),

          // ═════════ DETALHE DO LOTE EM FOCO (dentro do Capítulo 2) ═════════
          if (loteReady) ...[
            Align(alignment: Alignment.centerLeft, child: buildTriagemToggle(ref, triFilter)),
            const SizedBox(height: 12),
            // Consolidação BI, 4 gráficos: 3.A Timeline+ (banda P25–P75 absorve
            // o ridgeline) · 3.D Matriz de Ação (badge absorve o gauge) ·
            // 3.C Carta CEP (chips absorvem os z-scores) · 3.B Radar (coluna
            // Δ Pomar absorve o dumbbell). Antigos preservados sem uso:
            // batchVsPomarProfile, phytosanitaryPressureGauge, ridgeline,
            // HullPlot (dispersão migrou p/ Zona de Incerteza), cnnCostMatrix
            // (custo migrou p/ chips do Sankey), batchDriftZScore.
            masterTimeline(windowedBatch),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: eisenhowerMatrix(filteredBatch!, corrections: loteCorrections)),
              const SizedBox(width: 16),
              Expanded(
                child: SpcControlChart(
                  batchId: windowedBatch.id,
                  currentApples: filteredApples,
                  allBatches: availableBatches,
                  corrections: corrections,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            BatchComparisonShowcase(
              currentBatch: filteredBatch!,
              allBatches: availableBatches,
              onBatchSelected: (b) => ref.read(batchProvider.notifier).setBatch(b),
              quantityTargetScale: quantityScale,
            ),
          ] else
            _loteEmptyHint(),
          const SizedBox(height: 40),

          // ═════════ CAPÍTULO 3 · PERFORMANCE DA CNN ═════════
          // Só gráficos sobre o CNN + feed de produção em tempo real no fundo.
          _chapterHeader('3', 'Performance da CNN',
              'Confiança e evolução do modelo', const Color(0xff06B6D4)),
          const SizedBox(height: 16),

          // ── Consolidação BI: Sankey+ (destaque) e Zona de Incerteza+ (apoio).
          // (O SPC de cadência migrou para o Cap 1, é operação, não CNN.)
          SizedBox(
            height: 500,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _FlipCard(
                    front: _card(
                      'Fluxo de Reclassificação',
                      'CNN original → correção humana · fitas fora da diagonal expõem os vícios do modelo',
                      500,
                      ReclassSankeyChart(data: bi.sankey),
                      tooltip: '• Cada fita liga a classe que o CNN previu (esquerda) à classe que o \n'
                          'operador confirmou na Triagem Manual (direita). \n '
                          '• Fitas grossas fora da diagonal revelam vícios do modelo (ex.: Antracnose confundida com Podridão). \n'
                          '• As fitas ténues na diagonal (mesma cor) são confirmações.',
                    ),
                    back: _confidenceClassMatrix(reviewsAsync, height: 500),
                    frontLabel: 'Sankey',
                    backLabel: 'Matriz',
                    frontTooltip: 'Virar para a Matriz Confiança x Classificação',
                    backTooltip: 'Virar para o Fluxo de Reclassificação',
                    height: 500,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _card(
                    'Decisão do Modelo (Gatekeeper)',
                    'Distribuição do volume de maçãs pelas três zonas de confiança (Rejeição, Triagem e Aceitação).',
                    500,
                    UncertaintyZoneChart(data: bi.uncertainty),
                    tooltip: 'Esta barra de distribuição a 100% mostra exatamente como as maçãs foram triadas pelo '
                        'motor de confiança da CNN5.\n\n'
                        '• Rejeição (Vermelho): Confiança <30%, Encaminhadas automaticamente para "Outros"\n'
                        '• Triagem Manual (Amarelo): Confiança 30%–80%, Encaminhadas para validação humana\n'
                        '• Aceitação Automática (Verde): Confiança ≥80%, Aprovadas no sistema sem revisão.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Nenhum destes 2 precisa da largura completa do cartão, ficam
          // lado a lado (Evolução/Calibração à esquerda, mosaico à direita).
          SizedBox(
            height: 380,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _FlipCard(
                    // stats.dailyBatches reage ao botão 7d/30d (Capítulo 1);
                    // aqui usamos a janela fixa de 7 dias dos Capítulos 2/3.
                    front: _cnnEvolutionPlus(ref.watch(chapter3DailyBatchesProvider), reviewsAsync),
                    back: _calibrationByBand(reviewsAsync),
                    frontLabel: 'Evolução',
                    backLabel: 'Calibração',
                    frontTooltip: 'Virar para a Evolução Temporal (deriva do modelo)',
                    backTooltip: 'Virar para a Calibração por Faixa (onde pôr o corte da triagem)',
                    height: 380,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _card(
                    'CNN2 vs CNN5: Quem Decide?',
                    'Contorno verde = mosaico CNN2 · contorno âmbar = mosaico CNN5 · linha divisória = fronteira entre os dois',
                    380,
                    GatekeeperEfficiencyChart(data: bi.gatekeeper),
                    tooltip: 'Pergunta de arquitetura do pipeline, não de precisão. Ponto-chave: o CNN2 é um '
                        'gatekeeper binário que só regista \'Healthy\' como veredito final, sempre que suspeita de '
                        'doença, escala ao CNN5 e nunca decide qual é. Por isso a comparação certa não é '
                        '"CNN2 vs CNN5" a 50/50, mas sim 3 categorias:\n\n'
                        '• CNN2 → Healthy: resolvido de imediato pelo gatekeeper.\n'
                        '• CNN5 → Healthy: escalado por precaução, mas confirmado saudável, a "falsa suspeita" do '
                        'CNN2, i.e. escalada desperdiçada ao classificador mais caro.\n'
                        '• CNN5 → Doença: diagnóstico real, colorido por doença; a opacidade é a confiança média '
                        'desse diagnóstico no lote (mais esbatido = menos confiante).\n\n'
                        'A largura de cada coluna é proporcional ao volume do lote. O contorno agrupa visualmente '
                        'tudo o que passou pelo CNN5 (Healthy-confirmado + doenças) como um único bloco.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _scopeLabel('Pomar · tempo real'),
          const SizedBox(height: 12),
          _productionFeed(ref),
          const SizedBox(height: 32),
          humanTriageActivity(context, uncertain.where((a) => a.frames.isNotEmpty).toList(), corrections),
          const SizedBox(height: 32),
        ],
          ),
        ),
        if ((riskBatches.isNotEmpty || showSystemSurge) && !isDismissed)
          Positioned(
            top: 24,
            right: 32,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 1.0, end: 0.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(400 * value, 0),
                  child: child,
                );
              },
              child: _OutbreakAlertPopup(
                riskBatches: riskBatches,
                showSystemSurge: showSystemSurge,
                onDismiss: () => ref.read(outbreaksPopupDismissedProvider.notifier).setDismissed(true),
              ),
            ),
          ),
      ],
    )));
      },
    );
  }

  /// Sub-rótulo de âmbito dentro de uma secção temática (Pomar vs Lote).
  Widget _scopeLabel(String text) => Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(text.toUpperCase(),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
        ],
      );

  Widget _loteEmptyHint() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('Selecione um lote em foco (Capítulo 2) para ver o detalhe e a performance da CNN.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );

  /// Cabeçalho de capítulo do funil top-down (número grande + título + subtítulo).
  Widget _chapterHeader(String number, String title, String subtitle, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(number, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
            Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(child: Divider(color: color.withValues(alpha: 0.25), thickness: 1)),
      ],
    );
  }

  /// Tabela de lotes como "barreira" visual: separa a comparação M:N (acima,
  /// âmbar) do detalhe de UM lote em foco (abaixo, ciano, inclui o radar
  /// 1:N do BatchComparisonShowcase, que compara esse lote com os outros).
  Widget _loteGate(List<Batch> batches, WidgetRef ref) {
    final selected = ref.watch(batchProvider);
    const amber = Color(0xffF59E0B);
    const cyan = Colors.cyanAccent;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Faixa superior, zona de comparação entre lotes (M:N).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: amber.withOpacity(0.10),
              border: Border(bottom: BorderSide(color: amber.withOpacity(0.35), width: 1)),
            ),
            child: Row(children: [
              Icon(Icons.compare_arrows, size: 14, color: amber),
              const SizedBox(width: 8),
              Text('COMPARAÇÃO ENTRE LOTES',
                  style: TextStyle(color: amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const Spacer(),
              Text('todos × todos', style: TextStyle(color: amber.withOpacity(0.7), fontSize: 10)),
            ]),
          ),
          _table(batches, ref),
          // Faixa inferior, transição para o detalhe do lote em foco (1:N).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: cyan.withOpacity(0.08),
              border: Border(top: BorderSide(color: cyan.withOpacity(0.35), width: 1)),
            ),
            child: Row(children: [
              Icon(Icons.arrow_downward, size: 14, color: cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected != null
                      ? 'Detalhe abaixo: ${selected.id} (1 lote vs. os restantes)'
                      : 'Clique em "Focar" acima para ver o detalhe de um lote abaixo',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cyan, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// Cap 3 · Matriz 2×2 Confiança × Classificação, GLOBAL (todas as revisões
  /// manuais do pomar). x = confiança CNN (<80% / ≥80%, corte de aceitação
  /// automática) · y = correto segundo o operador. Reutiliza `matrixCell`.
  Widget _confidenceClassMatrix(AsyncValue<List<Map<String, dynamic>>> reviewsAsync, {double height = 380}) {
    Widget shell(Widget child) => GlassCard(padding: const EdgeInsets.all(20), height: height, child: child);

    return reviewsAsync.when(
      loading: () => shell(const Center(child: CircularProgressIndicator())),
      error: (_, __) => shell(Center(
        child: Text('Erro ao carregar revisões manuais',
            style: TextStyle(color: AppColors.textSecondary)),
      )),
      data: (rows) {
        if (rows.isEmpty) {
          return shell(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.grid_view_rounded, color: AppColors.textSecondary, size: 32),
            const SizedBox(height: 12),
            Text('Matriz Confiança × Classificação, Sem revisões manuais',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Esta matriz cruza a confiança CNN (x) com a correção do operador (y).\n'
              'Aparece quando existem correções na triagem humana.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ]));
        }

        // x=0 = conf <80% · x=1 = conf ≥80%  |  y=0 = incorreto · y=1 = correto
        int c00 = 0, c01 = 0, c10 = 0, c11 = 0;
        for (final r in rows) {
          if (r['status'] != 'completed') continue; // Apenas revisões concluídas
          final orig = r['original_class'] as String? ?? '';
          if (orig.isEmpty) continue;
          final corr = r['corrected_class'] as String?;
          final confVal = ((r['original_confidence'] ?? 0) as num).toDouble();
          final confPct = confVal <= 1.0 ? confVal * 100 : confVal;
          final highConf = confPct >= 80.0; // corte de aceitação automática
          final isCorrect = corr == null || corr.isEmpty || corr == orig;

          if (!highConf && !isCorrect) {
            c00++;
          } else if (!highConf && isCorrect) {
            c01++;
          } else if (highConf && !isCorrect) {
            c10++;
          } else {
            c11++;
          }
        }
        final total = c00 + c01 + c10 + c11;
        String pctStr(int c) => total > 0 ? '${(c / total * 100).round()}%' : '0%';

        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Row(children: [
              Icon(Icons.grid_view_rounded, color: Colors.orangeAccent, size: 20),
              SizedBox(width: 8),
              Text('Matriz Confiança × Classificação',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
            Tooltip(
              message: 'x = confiança CNN  (0 = <80% · 1 = ≥80%)\n'
                  'y = classificação   (0 = incorreta · 1 = correta, segundo o operador)\n\n'
                  'Confiança ≥80% passa normalmente na triagem automática (sem revisão manual).\n\n'
                  '(0,1)  baixa conf + correto    → conservador, sem custo\n'
                  '(1,1)  alta conf + correto     → ideal, sem custo\n'
                  '(0,0)  baixa conf + incorreto  → esperado, custo ×1\n'
                  '(1,0)  alta conf + incorreto   → grave, custo ×3\n\n'
                  'Total: $total revisões (todo o pomar)',
              padding: const EdgeInsets.all(12),
              textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
              decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
              ),
              child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 15),
            ),
          ]),
          Text('x = confiança CNN (<80% / ≥80%)  ·  y = correto segundo operador  ·  $total revisões · global',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 12),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text('Classificação (y)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              Expanded(
                child: Column(children: [
                  Expanded(
                    child: Row(children: [
                      Expanded(child: matrixCell('(0,1)', c01, pctStr(c01), 'Baixa conf.\nCorreto', Colors.teal)),
                      const SizedBox(width: 6),
                      Expanded(child: matrixCell('(1,1)', c11, pctStr(c11), 'Alta conf.\nCorreto', AppColors.healthy)),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Row(children: [
                      Expanded(child: matrixCell('(0,0)', c00, pctStr(c00), 'Baixa conf.\nIncorreto', Colors.amber)),
                      const SizedBox(width: 6),
                      Expanded(child: matrixCell('(1,0)', c10, pctStr(c10), 'Alta conf.\nIncorreto ×3', Colors.redAccent)),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: Center(child: Text('x=0 (Conf. <80%)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)))),
                    const SizedBox(width: 6),
                    Expanded(child: Center(child: Text('x=1 (Conf. ≥80%)', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)))),
                  ]),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Column(children: [
                  Expanded(child: Center(child: RotatedBox(quarterTurns: 1, child: Text('y=1', style: TextStyle(color: AppColors.textSecondary, fontSize: 9))))),
                  const SizedBox(height: 6),
                  Expanded(child: Center(child: RotatedBox(quarterTurns: 1, child: Text('y=0', style: TextStyle(color: AppColors.textSecondary, fontSize: 9))))),
                  const SizedBox(height: 22),
                ]),
              ),
            ]),
          ),
        ]));
      },
    );
  }

}

/// Sparkline minimalista para os KPI cards (polilinha + ponto final).
class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparkPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    double lo = values.first, hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : (hi - lo);
    final dx = size.width / (values.length - 1);
    double xOf(int i) => i * dx;
    double yOf(double v) => size.height - ((v - lo) / range) * size.height;

    final path = Path()..moveTo(xOf(0), yOf(values.first));
    for (int i = 1; i < values.length; i++) {
      path.lineTo(xOf(i), yOf(values[i]));
    }
    // Área suave sob a linha.
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    // Ponto final.
    canvas.drawCircle(Offset(xOf(values.length - 1), yOf(values.last)), 2.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values || old.color != color;
}
