import 'dart:math' as math;

import '../../models/models.dart';
import '../../ui/charts_v2/_chart_kit.dart' show kClassOrder;
import '../../ui/charts_v2/bi_charts.dart';

/// ════════════════════════════════════════════════════════════════════════
/// ADAPTADORES BI, agregação pura para os 3 gráficos fundidos na página
/// "Controlo do Pomar". Sem Flutter, sem I/O. Single-pass O(n).
/// ════════════════════════════════════════════════════════════════════════
class BiAdapters {
  BiAdapters._();

  static const List<String> _diseases = ['Rot', 'Scab', 'Anthracnose', 'Blotch'];

  static String _two(int v) => v.toString().padLeft(2, '0');

  static List<Map<String, dynamic>> _completed(List<Map<String, dynamic>> reviews) => [
        for (final r in reviews)
          if (r['status'] == 'completed' && r['original_class'] != null && r['corrected_class'] != null) r,
      ];

  // Rótulos livres escritos por humanos (corrected_class) variam em
  // maiúsculas/minúsculas e em sufixos ("Frost damage", "Stinkbug damage") -
  // sem isto cada variante vira um nó a mais no Sankey em vez de somar à
  // mesma família. 'startsWith' apanha os sufixos; o mapa cobre sinónimos
  // que não são meros sufixos (ex.: "Frozen" → "Frost").
  static const Map<String, String> _labelFamilies = {
    'frost': 'Frost',
    'frozen': 'Frost',
    'stink bug': 'Stinkbug',
    'stinkbug': 'Stinkbug',
  };

  static String _titleCase(String s) => s
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');

  static String _canonicalLabel(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return trimmed;
    final lower = trimmed.toLowerCase();
    for (final known in kClassOrder) {
      if (lower == known.toLowerCase()) return known;
    }
    for (final entry in _labelFamilies.entries) {
      if (lower.startsWith(entry.key)) return entry.value;
    }
    return _titleCase(trimmed);
  }

  static String _domDisease(Map<String, int> classCounts) {
    String dom = 'Healthy';
    int best = 0;
    for (final c in _diseases) {
      final v = classCounts[c] ?? 0;
      if (v > best) {
        best = v;
        dom = c;
      }
    }
    return dom;
  }

  // ── 1 · Cronograma de triagem de lotes (SPC por lote × dia) ──────────────
  // Cada barra é uma sessão de triagem: um lote (talhão) num dia. O eixo X são
  // os lotes por ordem cronológica de início (o mesmo lote reaparece noutro
  // dia). A barra é a MÉDIA de maçãs por hora ATIVA da sessão (horas sem
  // triagem não entram no divisor). Múltiplas triagens do mesmo lote no mesmo
  // dia colapsam numa só barra para não inchar o eixo.
  static String _loteShort(String location) {
    final m = RegExp(r'(\d+)').allMatches(location);
    if (m.isNotEmpty) return 'T-${_two(int.parse(m.last.group(1)!))}';
    final letters = location.trim();
    return letters.isEmpty ? 'N/D' : letters.substring(0, math.min(3, letters.length)).toUpperCase();
  }

  static CadenciaSanidadeData cadenciaSanidade(List<Batch> batches) {
    // Chave = "location|yyyy-mm-dd". Um bucket = uma sessão (lote nesse dia).
    final buckets = <String, ({
      String loc,
      DateTime minTs,
      DateTime maxTs,
      int total,
      int sick,
      Map<String, int> byClass,
      Set<int> activeHours,
    })>{};
    for (final b in batches) {
      for (final a in b.apples) {
        final t = a.timestamp;
        final key = '${b.location}|${t.year}-${_two(t.month)}-${_two(t.day)}';
        final cur = buckets[key] ??
            (
              loc: b.location,
              minTs: t,
              maxTs: t,
              total: 0,
              sick: 0,
              byClass: <String, int>{},
              activeHours: <int>{},
            );
        final cond = a.primaryCondition;
        if (cond != 'Healthy') cur.byClass[cond] = (cur.byClass[cond] ?? 0) + 1;
        cur.activeHours.add(t.hour);
        buckets[key] = (
          loc: cur.loc,
          minTs: t.isBefore(cur.minTs) ? t : cur.minTs,
          maxTs: t.isAfter(cur.maxTs) ? t : cur.maxTs,
          total: cur.total + 1,
          sick: cur.sick + (cond != 'Healthy' ? 1 : 0),
          byClass: cur.byClass,
          activeHours: cur.activeHours,
        );
      }
    }
    if (buckets.isEmpty) {
      return const CadenciaSanidadeData(points: [], meanRate: 0, ucl: 1, lcl: 0);
    }
    // Ordem cronológica pelo início da sessão: resolve ordem entre dias e
    // dentro do mesmo dia de uma só vez.
    final sessions = [
      for (final b in buckets.values)
        (
          loc: b.loc,
          minTs: b.minTs,
          maxTs: b.maxTs,
          total: b.total,
          sick: b.sick,
          byClass: b.byClass,
          activeH: b.activeHours.length,
          nSessions: 1,
        )
    ]..sort((a, b) => a.minTs.compareTo(b.minTs));

    // Limites de controlo SPC calculados SEMPRE ao nível da sessão original,
    // antes de qualquer agregação: descrevem a variação sessão a sessão. Se
    // fossem recalculados sobre os blocos agregados, a média dentro de cada
    // bloco esconderia a dispersão e a faixa normal encolhia artificialmente.
    final grandTotal = sessions.fold<int>(0, (s, b) => s + b.total);
    final grandSick = sessions.fold<int>(0, (s, b) => s + b.sick);
    final mu = grandTotal == 0 ? 0.0 : grandSick / grandTotal;
    final nBar = grandTotal / sessions.length;
    final sigma = nBar <= 0 ? 0.0 : math.sqrt(mu * (1 - mu) / nBar);
    final ucl = (mu + 3 * sigma).clamp(0.0, 1.0);
    final lcl = (mu - 3 * sigma).clamp(0.0, 1.0);

    // ── Foco + contexto ────────────────────────────────────────────────────
    // Os últimos 7 dias são sempre o que importa, mesmo na vista de 30 dias.
    // Em vez de distorcer o eixo (que falsearia a leitura do tempo), mantemos
    // as sessões recentes em resolução total e condensamos as antigas em menos
    // blocos, até o recente ocupar pelo menos `_kSpcRecentShare` da largura.
    // Como as fatias do eixo são de largura igual, a quota de largura é
    // simplesmente a quota de pontos.
    final recentFrom = DateTime.now().subtract(const Duration(days: 7));
    final splitAt = sessions.indexWhere((s) => s.minTs.isAfter(recentFrom));

    final oldOnes = splitAt <= 0 ? const [] : sessions.sublist(0, splitAt);
    final recentOnes = splitAt < 0 ? sessions : sessions.sublist(splitAt < 0 ? 0 : splitAt);

    // recent / (recent + maxOld) >= share  ⇒  maxOld <= recent * (1-share)/share
    final maxOld = oldOnes.isEmpty
        ? 0
        : math.max(1, (recentOnes.length * (1 - _kSpcRecentShare) / _kSpcRecentShare).floor());

    final laidOut = [
      if (oldOnes.length > maxOld)
        // Junta sessões consecutivas em `maxOld` blocos de tamanho equilibrado.
        for (int j = 0; j < maxOld; j++)
          _mergeSessions(oldOnes.sublist(
            (j * oldOnes.length / maxOld).floor(),
            ((j + 1) * oldOnes.length / maxOld).floor(),
          ))
      else
        ...oldOnes,
      ...recentOnes,
    ];

    final firstRecent = laidOut.length - recentOnes.length;

    return CadenciaSanidadeData(
      meanRate: mu,
      ucl: ucl,
      lcl: lcl,
      recentFromIndex: oldOnes.isEmpty ? 0 : firstRecent,
      points: [
        for (final s in laidOut)
          () {
            final rate = s.total == 0 ? 0.0 : s.sick / s.total;
            final activeH = math.max(1, s.activeH);
            final ratePerHour = s.total / activeH;
            final merged = s.nSessions > 1;
            final label = merged
                ? '${_two(s.minTs.day)}/${_two(s.minTs.month)}'
                : _loteShort(s.loc);
            final period = merged
                ? '${_two(s.minTs.day)}/${_two(s.minTs.month)} a ${_two(s.maxTs.day)}/${_two(s.maxTs.month)} · '
                    '${s.nSessions} sessões agregadas · ${activeH}h ativas · ${s.total} maçãs'
                : '${_two(s.minTs.day)}/${_two(s.minTs.month)} · ${_two(s.minTs.hour)}h–${_two(s.maxTs.hour)}h · '
                    '${s.activeH}h ativas · ${s.total} maçãs';
            return SpcPoint(
              label,
              ratePerHour,
              rate,
              dominantClass: _domDisease(s.byClass),
              // Só as sessões individuais podem sinalizar desvio: um bloco
              // agregado é uma média, compará-lo com limites de sessão daria
              // falsos negativos silenciosos.
              breach: !merged && rate > ucl,
              period: period,
              aggregated: merged,
            );
          }(),
      ],
    );
  }

  /// Quota mínima de largura do eixo reservada aos últimos 7 dias na vista
  /// de 30 dias. 0.6 = 60%.
  static const double _kSpcRecentShare = 0.6;

  /// Funde sessões consecutivas num só bloco de contexto. As horas ativas
  /// somam-se (sessões de dias/lotes diferentes não partilham horas), por isso
  /// o throughput do bloco continua a ser maçãs por hora efetivamente ativa.
  static ({
    String loc,
    DateTime minTs,
    DateTime maxTs,
    int total,
    int sick,
    Map<String, int> byClass,
    int activeH,
    int nSessions,
  }) _mergeSessions(List<dynamic> group) {
    final byClass = <String, int>{};
    var minTs = group.first.minTs as DateTime;
    var maxTs = group.first.maxTs as DateTime;
    int total = 0, sick = 0, activeH = 0, nSessions = 0;

    for (final s in group) {
      final sMin = s.minTs as DateTime;
      final sMax = s.maxTs as DateTime;
      if (sMin.isBefore(minTs)) minTs = sMin;
      if (sMax.isAfter(maxTs)) maxTs = sMax;
      total += s.total as int;
      sick += s.sick as int;
      activeH += s.activeH as int;
      nSessions += s.nSessions as int;
      (s.byClass as Map<String, int>).forEach((k, v) => byClass[k] = (byClass[k] ?? 0) + v);
    }

    return (
      loc: group.first.loc as String,
      minTs: minTs,
      maxTs: maxTs,
      total: total,
      sick: sick,
      byClass: byClass,
      activeH: activeH,
      nSessions: nSessions,
    );
  }

  /// original_confidence vem em escala 0–100 (bigint na BD); normaliza p/ 0..1.
  static double _reviewConf(Map<String, dynamic> r) {
    final raw = (r['original_confidence'] as num?)?.toDouble() ?? 0.0;
    return (raw > 1.0 ? raw / 100.0 : raw).clamp(0.0, 1.0);
  }

  // ── 2 · Fluxo de Reclassificação (Sankey + chips de custo) ───────────────
  // Os chips absorvem o antigo cnnCostMatrixChart (2×2 confiança×acerto):
  // o erro de ALTA confiança (≥75%) é o mais caro, fruta má aprovada com convicção.
  static SankeyData reclassSankey(List<Map<String, dynamic>> reviews) {
    final flows = <String, double>{};
    final nodeSet = <String>{};
    int confirmations = 0, highConfErrors = 0, lowConfErrors = 0;
    for (final r in _completed(reviews)) {
      final a = _canonicalLabel(r['original_class'] as String);
      final b = _canonicalLabel(r['corrected_class'] as String);

      // Ignorar se a CNN gerou uma doença que não conhece (dados espúrios/mock bad state)
      if (!_diseases.contains(a) && a != 'Healthy') continue;
      
      nodeSet..add(a)..add(b);
      flows['$a→$b'] = (flows['$a→$b'] ?? 0) + 1;
      if (a == b) {
        confirmations++;
      } else if (_reviewConf(r) >= 0.80) {
        // Acima do limiar de aceitação automática, o erro mais caro.
        highConfErrors++;
      } else {
        lowConfErrors++;
      }
    }
    // Extras (rótulos só de correção humana, ex.: Frost, Stinkbug, Lixo) em
    // ordem alfabética, mas "Lixo" sempre no fundo, não é uma patologia,
    // é descarte por má qualidade/falso, não faz sentido competir por posição
    // com as doenças reais.
    final extras = nodeSet.where((n) => !kClassOrder.contains(n)).toList()
      ..sort((a, b) {
        final aLixo = a.toLowerCase() == 'lixo';
        final bLixo = b.toLowerCase() == 'lixo';
        if (aLixo != bLixo) return aLixo ? 1 : -1;
        return a.compareTo(b);
      });
    final nodes = [
      ...kClassOrder.where(nodeSet.contains),
      ...extras,
    ];
    return SankeyData(
      nodes: nodes,
      links: [
        for (final e in flows.entries) SankeyLink(e.key.split('→')[0], e.key.split('→')[1], e.value),
      ],
      confirmations: confirmations,
      highConfErrors: highConfErrors,
      lowConfErrors: lowConfErrors,
    );
  }

  // ── 3 · Zona de Incerteza+: grelha 0.1 (1 bolha/célula) ──────────────────
  // Absorve: bandas 30/70 do _openSetRadar (régua marginal), pares top1↔top2
  // do _cnn5CoConfusionMatrix (chips + tooltip) e a dispersão entre vistas do
  // ConfidenceSeverityHullPlot (contorno tracejado nas células instáveis).
  static UncertaintyData uncertaintyZone(
    List<Batch> batches, {
    // Regra real de produção: ≥80% aceite automático (80–85% com auditoria
    // de 5%); <80% triagem manual; <30% auto-"Outros".
    double top1Threshold = 0.80,
    double marginThreshold = 0.15,
  }) {
    const grid = 0.1;
    final cellClass = <String, Map<String, int>>{}; // célula -> classe -> n
    final cellPair = <String, Map<String, int>>{}; // célula -> par -> n
    final cellDispSum = <String, double>{}; // célula -> Σ dispersão entre vistas
    final cellTotal = <String, int>{};
    final globalPairs = <String, int>{};
    int total = 0, openset = 0;
    int bandAccept = 0, bandTriage = 0, bandAutoOthers = 0, routedTotal = 0;

    for (final b in batches) {
      for (final a in b.apples) {
        // Régua de bandas de decisão: maçãs encaminhadas ao CNN5 pelo gatekeeper.
        if (a.modelName == 'CNN5') {
          routedTotal++;
          final conf = a.effectiveConfidence;
          if (conf >= 0.80) {
            bandAccept++;
          } else if (conf >= 0.30) {
            bandTriage++;
          } else {
            bandAutoOthers++;
          }
        }

        final probs = a.worstFrame?.probabilities;
        if (probs == null || probs.length < 2) continue;
        final entries = probs.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
        final top1 = entries[0].value.clamp(0.0, 1.0);
        final margin = (entries[0].value - entries[1].value).clamp(0.0, 1.0);
        final cls = entries[0].key;
        final pair = '${entries[0].key}↔${entries[1].key}';

        // Dispersão entre vistas da classe primária (do antigo hull plot).
        double disp = 0.0;
        if (a.frames.length >= 2) {
          final cond = a.primaryCondition;
          double mn = double.infinity, mx = -double.infinity;
          for (final f in a.frames) {
            final p = f.probabilities[cond] ?? 0.0;
            mn = math.min(mn, p);
            mx = math.max(mx, p);
          }
          disp = (mx - mn).clamp(0.0, 1.0);
        }

        total++;
        if (top1 < top1Threshold || margin < marginThreshold) openset++;
        globalPairs[pair] = (globalPairs[pair] ?? 0) + 1;
        final key = '${(top1 / grid).round()}|${(margin / grid).round()}';
        (cellClass[key] ??= {})[cls] = ((cellClass[key]![cls]) ?? 0) + 1;
        (cellPair[key] ??= {})[pair] = ((cellPair[key]![pair]) ?? 0) + 1;
        cellDispSum[key] = (cellDispSum[key] ?? 0) + disp;
        cellTotal[key] = (cellTotal[key] ?? 0) + 1;
      }
    }

    String domOf(Map<String, int> m) {
      String dom = '';
      int best = -1;
      m.forEach((k, v) {
        if (v > best) {
          best = v;
          dom = k;
        }
      });
      return dom;
    }

    final cells = <UncertaintyCell>[];
    cellTotal.forEach((key, n) {
      final parts = key.split('|');
      cells.add(UncertaintyCell(
        top1: (int.parse(parts[0]) * grid).clamp(0.0, 1.0),
        margin: (int.parse(parts[1]) * grid).clamp(0.0, 1.0),
        topClass: domOf(cellClass[key]!),
        topPair: domOf(cellPair[key] ?? const {}),
        avgDispersion: n == 0 ? 0.0 : (cellDispSum[key] ?? 0) / n,
        n: n,
      ));
    });

    final topPairs = globalPairs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return UncertaintyData(
      cells: cells,
      total: total,
      opensetCount: openset,
      top1Threshold: top1Threshold,
      marginThreshold: marginThreshold,
      bandAccept: bandAccept,
      bandTriage: bandTriage,
      bandAutoOthers: bandAutoOthers,
      routedTotal: routedTotal,
      topPairs: [for (final e in topPairs.take(3)) (pair: e.key, n: e.value)],
    );
  }

  // ── 4 · Valor Económico da Colheita: Categoria A vs B ─────────────────────
  // Categoria A = Healthy (premium) · Categoria B = Blotch+Scab (patologias de
  // superfície, ainda vendáveis a preço reduzido, "segunda escolha"). Rot e
  // Anthracnose ficam fora das categorias coloridas, mas CONTAM para o total
  // do pomar, as percentagens (e portanto a altura das bandas do copo)
  // refletem a composição REAL do pomar, não só da população A+B. Por isso
  // o copo não enche a 100%: o espaço vazio acima representa Rot+Anthracnose
  // (+ eventual "Outros"). `capacityValue` é o valor hipotético se TODO o
  // pomar fosse Categoria A.
  static HarvestValueData harvestValue(
    List<Batch> batches, {
    double precoPremium = 0.60,
    double precoSegunda = 0.40,
    double precoIndustria = 0.20,
    double metaPct = 0.80,
  }) {
    int countA = 0, countB = 0, countC = 0, countTotal = 0;
    for (final b in batches) {
      countA += b.healthDistribution['Healthy'] ?? 0;
      countB += (b.healthDistribution['Blotch'] ?? 0) +
                (b.healthDistribution['Sooty Blotch'] ?? 0) +
                (b.healthDistribution['Sunburn'] ?? 0);
      countC += (b.healthDistribution['Scab'] ?? 0) +
                (b.healthDistribution['Brown Rot'] ?? 0) +
                (b.healthDistribution['Stinkbug'] ?? 0) +
                (b.healthDistribution['Stink Bug'] ?? 0) +
                (b.healthDistribution['Frost'] ?? 0);
      countTotal += b.totalApples;
    }
    final pctA = countTotal == 0 ? 0.0 : countA / countTotal;
    final pctB = countTotal == 0 ? 0.0 : countB / countTotal;
    final pctC = countTotal == 0 ? 0.0 : countC / countTotal;
    final valorA = countA * precoPremium;
    final valorB = countB * precoSegunda;
    final valorC = countC * precoIndustria;
    final capacityValue = countTotal * precoPremium;

    return HarvestValueData(
      countA: countA,
      countB: countB,
      countC: countC,
      countTotal: countTotal,
      pctA: pctA,
      pctB: pctB,
      pctC: pctC,
      valorA: valorA,
      valorB: valorB,
      valorC: valorC,
      capacityValue: capacityValue,
      metaValue: capacityValue * metaPct,
    );
  }

  // ── 5 · CNN2 vs CNN5: Quem Decide? ────────────────────────────────────────
  // Pergunta de arquitetura/eficiência do pipeline, não de precisão. Ponto
  // chave: CNN2 é um gatekeeper BINÁRIO, só regista 'Healthy' como veredito
  // final; sempre que suspeita de doença, escala ao CNN5 e nunca fica com a
  // palavra final sobre qual doença é (ver models.dart / Apple.fromJson).
  // Por isso "CNN2 resolveu X%" só é meaningful para o lado saudável, o que
  // interessa mesmo é: (a) quantas maçãs o CNN2 resolveu logo como Healthy,
  // (b) quantas foram escaladas por precaução e o CNN5 confirmou Healthy na
  // mesma (a "falsa suspeita" do gatekeeper, escalada desperdiçada), e (c)
  // quantas o CNN5 diagnosticou mesmo com doença, e com que confiança.
  static GatekeeperData gatekeeperEfficiency(List<Batch> batches) {
    final chronological = [...batches]..sort((a, b) => a.date.compareTo(b.date));
    final points = <GatekeeperPoint>[];
    int totalCnn2Healthy = 0, totalCnn5Healthy = 0, totalCnn5Disease = 0, totalCnn5DiseaseHighConf = 0;
    double diseaseConfSum = 0;

    for (final b in chronological) {
      int cnn2Healthy = 0, cnn5Healthy = 0;
      final diseaseCounts = <String, int>{};
      final diseaseConfSum2 = <String, double>{};
      for (final a in b.apples) {
        if (a.modelName == 'CNN2') {
          cnn2Healthy++; // CNN2 só finaliza 'Healthy', nunca uma doença.
        } else if (a.modelName == 'CNN5') {
          final cond = a.primaryCondition;
          if (cond == 'Healthy') {
            cnn5Healthy++; // Escalado por precaução, CNN5 confirmou saudável.
          } else {
            diseaseCounts[cond] = (diseaseCounts[cond] ?? 0) + 1;
            diseaseConfSum2[cond] = (diseaseConfSum2[cond] ?? 0) + a.effectiveConfidence;
            diseaseConfSum += a.effectiveConfidence;
            if (a.effectiveConfidence >= 0.80) totalCnn5DiseaseHighConf++;
          }
        }
      }
      final total = b.apples.length;
      if (total == 0) continue;
      totalCnn2Healthy += cnn2Healthy;
      totalCnn5Healthy += cnn5Healthy;
      final diseaseTotalHere = diseaseCounts.values.fold<int>(0, (s, v) => s + v);
      totalCnn5Disease += diseaseTotalHere;
      points.add(GatekeeperPoint(
        label: b.id,
        total: total,
        cnn2HealthyCount: cnn2Healthy,
        cnn5HealthyCount: cnn5Healthy,
        cnn5DiseaseCounts: diseaseCounts,
        cnn5DiseaseAvgConf: {
          for (final e in diseaseCounts.entries) e.key: diseaseConfSum2[e.key]! / e.value,
        },
      ));
    }

    return GatekeeperData(
      points: points,
      totalApples: totalCnn2Healthy + totalCnn5Healthy + totalCnn5Disease,
      totalCnn2Healthy: totalCnn2Healthy,
      totalCnn5Healthy: totalCnn5Healthy,
      totalCnn5Disease: totalCnn5Disease,
      totalCnn5DiseaseHighConf: totalCnn5DiseaseHighConf,
      avgDiseaseConfidence: totalCnn5Disease == 0 ? 0.0 : diseaseConfSum / totalCnn5Disease,
    );
  }
}
