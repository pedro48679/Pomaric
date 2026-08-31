part of '../mlops_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// MLOPS · COMPARAR, gráficos
// Curvas ROC/PR, legenda AUC, curva por época, barras por classe
// e matriz de erros A/B.
// ═══════════════════════════════════════════════════════════

extension _MlopsCompareCharts on MlopsPageState {
  /// Painel único "Curva de Discriminação": ROC por omissão, com toggle
  /// interno para Precision-Recall. Ambas vêm das mesmas probabilidades -
  /// não faziam sentido como 2 modos de topo separados. As curvas já
  /// incluem casos difíceis reais + amostra representativa de produção
  /// misturados com o teste normal (ver eval_composition/train_cnn.py) —
  /// não há um segundo modo "casos difíceis" à parte: só um gráfico.
  Widget _buildRocPrPanel(Map<String, dynamic> metaA, Map<String, dynamic> metaB,
      List<String> allCls) {
    final isRoc = _discriminationIsRoc;
    final key = isRoc ? 'roc_curves' : 'pr_curves';
    final curvesA = (metaA[key] as Map<String, dynamic>?) ?? {};
    final curvesB = (metaB[key] as Map<String, dynamic>?) ?? {};

    final filterClasses = allCls.where((c) => curvesA.containsKey(c) || curvesB.containsKey(c)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _rocPrToggle('ROC', true),
            const SizedBox(width: 6),
            _rocPrToggle('Precision-Recall', false),
          ],
        ),
        const SizedBox(height: 8),
        // Filtro de classe
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _classFilterChip('Todas', null),
              ...filterClasses.map((c) => _classFilterChip(c, c)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: (curvesA.isEmpty && curvesB.isEmpty)
                ? Center(
                    child: Text(
                      isRoc
                          ? 'Sem dados de curva ROC. Apenas modelos treinados após esta atualização guardam estas curvas.'
                          : 'Sem dados de curva Precision-Recall. Apenas modelos treinados após esta atualização guardam estas curvas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary.withOpacity(0.6), fontSize: 12),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isRoc ? 'Curva ROC (TPR vs FPR)' : 'Curva Precision-Recall',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        isRoc
                            ? 'Quanto mais perto do canto superior esquerdo, melhor a separação entre classes.'
                            : 'Quanto mais perto do canto superior direito, melhor o equilíbrio entre precisão e recall.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: CustomPaint(
                          painter: RocPrCurvePainter(
                            curvesA: curvesA,
                            curvesB: curvesB,
                            classFilter: _curveClassFilter,
                            isRoc: isRoc,
                            isDark: AppColors.isDark,
                          ),
                          child: Container(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildAucLegend(curvesA, curvesB, filterClasses),
                      _buildEvalCompositionCaveat(metaA, metaB),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// Legenda de apoio à curva: quantas imagens vieram do teste normal vs.
  /// de casos difíceis reais/produção misturados, e que fração destas já
  /// era ambígua na própria captura (confiança <80%) — contexto para não
  /// ler o accuracy/AUC como "bom" ou "mau" isolado do que foi avaliado.
  Widget _buildEvalCompositionCaveat(Map<String, dynamic> metaA, Map<String, dynamic> metaB) {
    final ecA = metaA['eval_composition'] as Map<String, dynamic>?;
    final ecB = metaB['eval_composition'] as Map<String, dynamic>?;
    if (ecA == null && ecB == null) return const SizedBox.shrink();

    String line(Map<String, dynamic>? ec) {
      if (ec == null) return '';
      final testN = ec['test_count'];
      final hardN = ec['hard_mixed_count'];
      final pctLow = ec['pct_low_confidence_in_mixed'];
      final ambig = (hardN is int && hardN > 0 && pctLow != null)
          ? ' ($pctLow% destas já ambígua na captura)'
          : '';
      return '$testN teste + $hardN difíceis/produção$ambig';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          if (ecA != null)
            Text('Modelo A: ${line(ecA)}',
                style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w600)),
          if (ecB != null)
            Text('Modelo B: ${line(ecB)}',
                style: const TextStyle(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildAucLegend(Map<String, dynamic> curvesA, Map<String, dynamic> curvesB, List<String> classes) {
    final shown = _curveClassFilter != null ? [_curveClassFilter!] : classes;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: shown.expand((cls) {
        final aucA = (curvesA[cls]?['auc'] as num?)?.toDouble();
        final aucB = (curvesB[cls]?['auc'] as num?)?.toDouble();
        return [
          if (aucA != null)
            Text('$cls (A) AUC=${aucA.toStringAsFixed(3)}',
                style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w600)),
          if (aucB != null)
            Text('$cls (B) AUC=${aucB.toStringAsFixed(3)}',
                style: const TextStyle(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.w600)),
        ];
      }).toList(),
    );
  }

  /// Curva da métrica selecionada ao longo das épocas
  Widget _buildMetricCurve(List histA, List histB,
      Map<String, dynamic> metaA, Map<String, dynamic> metaB, String metricKey) {
    final metricLabels = {
      'val_acc': 'Val Accuracy', 'f1': 'F1-Score',
      'precision': 'Precisão', 'recall': 'Recall',
    };
    final title = metricLabels[metricKey] ?? metricKey;

    String statKey(String m) => m == 'val_acc' ? 'val_accuracy' : m == 'f1' ? 'best_f1' : m;
    
    String getVal(Map<String, dynamic> meta, List hist, String mKey) {
      final v = meta[statKey(mKey)] as num?;
      if (v != null) return v.toStringAsFixed(1);
      if (hist.isNotEmpty) {
        final raw = (hist.last as Map)[mKey] as num?;
        if (raw != null) {
          final adjusted = raw <= 1.0 ? raw * 100.0 : raw;
          return adjusted.toStringAsFixed(1);
        }
      }
      return 'n/d';
    }

    final valA = getVal(metaA, histA, metricKey);
    final valB = getVal(metaB, histB, metricKey);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Curva $title por Época',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              // Nomes de modelo reais (ficheiro .pth) podem ser muito
              // compridos e faziam a linha ultrapassar a largura do cartão;
              // aqui só "A"/"B" (mesmo padrão da matriz de erros abaixo),
              // com o nome completo no Tooltip.
              Tooltip(
                message: metaA['name'] as String? ?? 'Modelo A',
                child: _legendDot(AppColors.primary, 'A'),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: metaB['name'] as String? ?? 'Modelo B',
                child: _legendDot(Colors.orange, 'B'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: histA.isEmpty && histB.isEmpty
                ? Center(
                    child: Text('Sem histórico de treino',
                        style: TextStyle(
                            color: AppColors.textSecondary.withOpacity(0.5),
                            fontSize: 12)))
                : CustomPaint(
                    // Eixo dinâmico: com um modelo já muito bom (ex.: 99.1%
                    // vs 99.4%), um eixo fixo 0-100% comprime tudo numa
                    // linha reta perto do topo e esconde a evolução real.
                    painter: MetricCurvePainter(histA, histB, metricKey,
                        colorA: AppColors.primary, colorB: Colors.orange, dynamicY: true),
                    size: Size.infinite,
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _compareStat('$title A', '$valA%', AppColors.primary),
              const Spacer(),
              _compareStat('$title B', '$valB%', Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  /// Matriz de erros por classe: uma coluna por doença (classe verdadeira),
  /// cada coluna um bloco único dividido em 2 cores empilhadas, Modelo A
  /// (fundo) e Modelo B (topo), com um divisor sólido entre os dois, a
  /// mesma linguagem visual do mosaico CNN2/CNN5 do Controlo do Pomar.
  /// Passa o rato/toca numa coluna para ver os apple_ids específicos e para
  /// que doença cada modelo confundiu essa classe. Dados de
  /// `misclassified_samples` (train_cnn.py), só modelos treinados depois
  /// desta funcionalidade têm esta informação; modelos mais antigos mostram
  /// um estado vazio explícito em vez de um ecrã quebrado.
  Widget _buildClassErrorMatrix(Map<String, dynamic> metaA, Map<String, dynamic> metaB) {
    List<Map<String, dynamic>> samplesOf(Map<String, dynamic> meta) =>
        (meta['misclassified_samples'] as List? ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();

    Map<String, List<Map<String, dynamic>>> groupByTrueClass(List<Map<String, dynamic>> samples) {
      final map = <String, List<Map<String, dynamic>>>{};
      for (final s in samples) {
        final cls = s['true_class'] as String? ?? 'Desconhecida';
        map.putIfAbsent(cls, () => []).add(s);
      }
      return map;
    }

    final samplesA = samplesOf(metaA);
    final samplesB = samplesOf(metaB);
    final byClassA = groupByTrueClass(samplesA);
    final byClassB = groupByTrueClass(samplesB);
    final classes = {...byClassA.keys, ...byClassB.keys}.toList()..sort();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Erros por Classe (A vs B)',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              _legendDot(AppColors.primary, 'A'),
              const SizedBox(width: 8),
              _legendDot(Colors.orange, 'B'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Imagens mal classificadas por doença: passa o rato numa coluna para ver quais',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5),
          ),
          const SizedBox(height: 10),
          if (classes.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  samplesA.isEmpty && samplesB.isEmpty
                      ? 'Sem dados de erros por imagem: só modelos treinados\napós esta funcionalidade têm esta informação.'
                      : 'Nenhum erro registado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary.withOpacity(0.5), fontSize: 11),
                ),
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (_, box) {
                  final size = Size(box.maxWidth, box.maxHeight);
                  return MouseRegion(
                    onHover: (e) => setState(() {
                      _errMatrixHovered = _classAt(e.localPosition, size, classes);
                      _errMatrixHoverPos = e.localPosition;
                    }),
                    onExit: (_) => setState(() {
                      _errMatrixHovered = null;
                      _errMatrixHoverPos = null;
                    }),
                    child: GestureDetector(
                      onTapDown: (e) => setState(() {
                        _errMatrixHovered = _classAt(e.localPosition, size, classes);
                        _errMatrixHoverPos = e.localPosition;
                      }),
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: size,
                            painter: ClassErrorMatrixPainter(
                              classes: classes,
                              byClassA: byClassA,
                              byClassB: byClassB,
                              hovered: _errMatrixHovered,
                              colorA: AppColors.primary,
                              colorB: Colors.orange,
                            ),
                          ),
                          if (_errMatrixHovered != null && _errMatrixHoverPos != null)
                            hoverTooltipOverlay(
                              pos: _errMatrixHoverPos!,
                              containerSize: size,
                              maxWidth: 300,
                              child: _errMatrixInfoCard(_errMatrixHovered!, byClassA, byClassB),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String? _classAt(Offset local, Size size, List<String> classes) {
    final plot = classErrorPlotRect(size);
    if (local.dy < plot.top || local.dy > plot.bottom) return null;
    final rects = classErrorColumnRects(classes.length, plot);
    for (int i = 0; i < classes.length; i++) {
      if (local.dx >= rects[i].left && local.dx <= rects[i].right) return classes[i];
    }
    return null;
  }

  /// Cartão do hover da matriz de erros: mostra as MAÇÃS em si (miniaturas),
  /// não só o apple_id em texto — pedido do utilizador para reconhecer o
  /// caso de imediato em vez de ter de procurar o ID.
  Widget _errMatrixInfoCard(String cls, Map<String, List<Map<String, dynamic>>> byClassA,
      Map<String, List<Map<String, dynamic>>> byClassB) {
    Widget describe(String label, Color color, List<Map<String, dynamic>> samples) {
      if (samples.isEmpty) {
        return Text('$label: sem erros',
            style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w600));
      }
      final shown = samples.take(6).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ${samples.length} erros',
              style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in shown)
                Tooltip(
                  message: '${s['apple_id']}: confundida com ${s['predicted_class']}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: HybridImage(
                      cloudUrl: s['url'] as String?,
                      localUrl: null,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorWidget: Container(
                        width: 84,
                        height: 84,
                        color: AppColors.background,
                        child: Icon(Icons.apple, color: AppColors.textSecondary.withOpacity(0.4), size: 24),
                      ),
                    ),
                  ),
                ),
              if (samples.length > shown.length)
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('+${samples.length - shown.length}',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      );
    }

    final a = byClassA[cls] ?? const [];
    final b = byClassB[cls] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(cls, style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        describe('Modelo A', AppColors.primary, a),
        const SizedBox(height: 8),
        describe('Modelo B', Colors.orange, b),
      ],
    );
  }

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 10)),
        ],
      );
}
