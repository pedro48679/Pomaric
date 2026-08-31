part of 'reports_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// RELATÓRIOS · TABELAS
// Contentor, linhas e células reutilizáveis, e as quatro tabelas base: resumo, distribuição, lotes e CNN.
// ═══════════════════════════════════════════════════════════

extension _ReportsTables on ReportsView {
  Widget _tableContainer(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }

  Widget _headerRow(List<String> labels, {List<int>? flexes, List<TextAlign>? aligns}) {
    return Container(
      color: AppColors.surfaceBright.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: List.generate(labels.length, (i) {
          return Expanded(
            flex: flexes != null ? flexes[i] : 1,
            child: Text(labels[i],
                textAlign: aligns != null ? aligns[i] : TextAlign.left,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
          );
        }),
      ),
    );
  }

  Widget _dataRow(List<Widget> cells, {List<int>? flexes, bool zebra = false}) {
    return Container(
      decoration: BoxDecoration(
        color: zebra ? AppColors.surfaceBright.withOpacity(0.18) : Colors.transparent,
        border: Border(top: BorderSide(color: AppColors.glassBorder.withOpacity(0.5))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: List.generate(cells.length, (i) => Expanded(flex: flexes != null ? flexes[i] : 1, child: cells[i])),
      ),
    );
  }

  Widget _cellText(String text, {Color? color, bool bold = false, TextAlign align = TextAlign.left}) {
    return Text(text,
        textAlign: align,
        style: TextStyle(color: color ?? AppColors.textPrimary, fontSize: 12.5, fontWeight: bold ? FontWeight.bold : FontWeight.normal));
  }

  // ─── 1. RESUMO ───
  Widget _summaryTable(ReportData d) {
    final rows = <List<String>>[
      ['Maçãs Inspecionadas', '${d.totalApples}'],
      ['Frames Capturados', '${d.totalFrames}'],
      ['Lotes no Período', '${d.batchCount}'],
      ['Aprovação Global', '${d.globalApproval.toStringAsFixed(1)}%'],
      ['Confiança Média da IA', '${d.avgConf.toStringAsFixed(1)}%'],
      ['Taxa de Automação', '${d.automationRate.toStringAsFixed(1)}%'],
      ['Frutos Afetados', '${d.totalAnomalies}'],
      ['Fila de Revisão Manual', '${d.humanQueue}'],
      ['Doença Predominante', d.dominantAnomaly == 'Nenhuma' ? 'Nenhuma (sem casos)' : '${AppColors.displayName(d.dominantAnomaly)} (${d.dominantAnomalyCount} casos)'],
      ['Variação de Aprovação', '${d.deltaPp >= 0 ? "+" : ""}${d.deltaPp.toStringAsFixed(1)} pp'],
      ['Índice de Saúde Global', '${d.healthScore.toStringAsFixed(0)}% (${d.statusLabel})'],
    ];
    return _tableContainer([
      _headerRow(['Métrica', 'Valor'], flexes: [3, 2], aligns: [TextAlign.left, TextAlign.right]),
      for (int i = 0; i < rows.length; i++)
        _dataRow([
          _cellText(rows[i][0]),
          _cellText(rows[i][1], bold: true, align: TextAlign.right),
        ], flexes: const [3, 2], zebra: i.isOdd),
    ]);
  }

  // ─── 2. DISTRIBUIÇÃO ───
  Widget _distributionTable(ReportData d) {
    final total = d.totalApples > 0 ? d.totalApples : 1;
    final entries = d.distribution.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return _emptyPanel('Sem dados de distribuição disponíveis.');
    return _tableContainer([
      _headerRow(['Condição', 'Nº Maçãs', '% do Total'], flexes: const [3, 2, 2], aligns: const [TextAlign.left, TextAlign.right, TextAlign.right]),
      for (int i = 0; i < entries.length; i++)
        _dataRow([
          _cellText(AppColors.displayName(entries[i].key), color: AppColors.getColorForCondition(entries[i].key), bold: true),
          _cellText('${entries[i].value}', align: TextAlign.right),
          _cellText('${(entries[i].value / total * 100).toStringAsFixed(1)}%', align: TextAlign.right),
        ], flexes: const [3, 2, 2], zebra: i.isOdd),
      Container(
        color: AppColors.surfaceBright.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Expanded(flex: 3, child: _cellText('TOTAL', bold: true)),
          Expanded(flex: 2, child: _cellText('$total', bold: true, align: TextAlign.right)),
          Expanded(flex: 2, child: _cellText('100.0%', bold: true, align: TextAlign.right)),
        ]),
      ),
    ]);
  }

  // ─── 3. LOTES ───
  Widget _batchTable(ReportData d) {
    final rows = [...d.batchRisks]..sort((a, b) => b.urgency.compareTo(a.urgency));
    if (rows.isEmpty) return _emptyPanel('Sem lotes no período selecionado.');
    final top = rows.take(15).toList();
    const flexes = [2, 2, 3, 2, 2, 2];
    return Column(children: [
      _tableContainer([
        _headerRow(['Lote', 'Localização', 'Doença Predom.', 'Maçãs', 'Aprovação', 'Urgência'],
            flexes: flexes, aligns: const [TextAlign.left, TextAlign.left, TextAlign.left, TextAlign.right, TextAlign.right, TextAlign.right]),
        for (int i = 0; i < top.length; i++)
          _dataRow([
            _cellText(top[i].id, bold: true),
            _cellText(top[i].location),
            _cellText(top[i].dominant == 'Nenhuma' ? 'n/d' : AppColors.displayName(top[i].dominant), color: AppColors.getColorForCondition(top[i].dominant)),
            _cellText('${top[i].total}', align: TextAlign.right),
            _cellText('${top[i].approval.toStringAsFixed(0)}%', align: TextAlign.right),
            _cellText('${(top[i].urgency * 100).toStringAsFixed(0)}%', color: _urgencyColor(top[i].urgency), bold: true, align: TextAlign.right),
          ], flexes: flexes, zebra: i.isOdd),
      ]),
      if (rows.length > top.length) ...[
        const SizedBox(height: 6),
        Text('Mostrando os ${top.length} lotes de maior urgência de um total de ${rows.length}.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
      ],
    ]);
  }

  // ─── 4. CNN ───
  Widget _cnnTable(ReportData d) {
    final c = d.cnn;
    if (!c.hasData) return _emptyPanel('Sem classificações registadas pelo pipeline de IA no período.');
    final total = c.total > 0 ? c.total : 1;
    final totalHealthy = c.cnn2HealthyCount + c.cnn5HealthyCount;
    final th = totalHealthy > 0 ? totalHealthy : 1;
    final rows = <List<String>>[
      [
        'Triagem Primária (Gatekeeper binário)', 
        '${c.cnn2Count}', 
        '${(c.cnn2Count / total * 100).toStringAsFixed(0)}%', 
        '${(c.cnn2HealthyCount / th * 100).toStringAsFixed(0)}%', 
        '${c.cnn2AvgConf.toStringAsFixed(1)}%'
      ],
      [
        'Diagnóstico (Analisador multiclasse)', 
        '${c.cnn5Count}', 
        '${(c.cnn5Count / total * 100).toStringAsFixed(0)}%', 
        '${(c.cnn5HealthyCount / th * 100).toStringAsFixed(0)}%', 
        '${c.cnn5AvgConf.toStringAsFixed(1)}%'
      ],
    ];
    const flexes = [4, 2, 2, 2, 2];
    final det = d.cnnDetail;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tableContainer([
        _headerRow(['Modelo', 'Nº Classif.', '% do Fluxo', '% Saudáveis', 'Confiança Média'],
            flexes: flexes, aligns: const [TextAlign.left, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right]),
        for (int i = 0; i < rows.length; i++)
          _dataRow([
            _cellText(rows[i][0]),
            _cellText(rows[i][1], align: TextAlign.right),
            _cellText(rows[i][2], align: TextAlign.right),
            _cellText(rows[i][3], align: TextAlign.right),
            _cellText(rows[i][4], bold: true, align: TextAlign.right),
          ], flexes: flexes, zebra: i.isOdd),
      ]),
      const SizedBox(height: 6),
      Text('Fila de revisão humana (registos pendentes de triagem, pomar completo): ${c.uncertainCount} maçãs.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
      if (det != null && det.routedTotal > 0) ...[
        const SizedBox(height: 14),
        Text('Bandas de Decisão do CNN5 (regra operacional)',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _tableContainer([
          _headerRow(['Banda de confiança', 'Nº Maçãs', '%'],
              flexes: const [4, 2, 2], aligns: const [TextAlign.left, TextAlign.right, TextAlign.right]),
          _dataRow([
            _cellText('Aceite automático (>= ${det.acceptThresholdPct.toStringAsFixed(0)}%)', color: AppColors.healthy, bold: true),
            _cellText('${det.bandAccept}', align: TextAlign.right),
            _cellText('${(det.bandAccept / det.routedTotal * 100).toStringAsFixed(1)}%', align: TextAlign.right),
          ], flexes: const [4, 2, 2]),
          _dataRow([
            _cellText('Triagem manual (30% a ${det.acceptThresholdPct.toStringAsFixed(0)}%)', color: Colors.amber, bold: true),
            _cellText('${det.bandTriage}', align: TextAlign.right),
            _cellText('${(det.bandTriage / det.routedTotal * 100).toStringAsFixed(1)}%', align: TextAlign.right),
          ], flexes: const [4, 2, 2], zebra: true),
          _dataRow([
            _cellText('Auto-"Outros" (< 30%)', color: Colors.redAccent, bold: true),
            _cellText('${det.bandAutoOthers}', align: TextAlign.right),
            _cellText('${(det.bandAutoOthers / det.routedTotal * 100).toStringAsFixed(1)}%', align: TextAlign.right),
          ], flexes: const [4, 2, 2]),
        ]),
      ],
      if (det != null && det.gatekeeperTotal > 0) ...[
        const SizedBox(height: 14),
        Text('Divisão de Decisão CNN2/CNN5 (arquitetura gatekeeper)',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _tableContainer([
          _headerRow(['Resultado', 'Nº Maçãs', '%'],
              flexes: const [4, 2, 2], aligns: const [TextAlign.left, TextAlign.right, TextAlign.right]),
          _dataRow([
            _cellText('CNN2 aprovou como saudável (sem escalar)', color: AppColors.healthy, bold: true),
            _cellText('${det.cnn2Healthy}', align: TextAlign.right),
            _cellText('${(det.cnn2Healthy / det.gatekeeperTotal * 100).toStringAsFixed(1)}%', align: TextAlign.right),
          ], flexes: const [4, 2, 2]),
          _dataRow([
            _cellText('Escalado por precaução, CNN5 confirmou saudável', color: Colors.amber, bold: true),
            _cellText('${det.cnn5Healthy}', align: TextAlign.right),
            _cellText('${(det.cnn5Healthy / det.gatekeeperTotal * 100).toStringAsFixed(1)}%', align: TextAlign.right),
          ], flexes: const [4, 2, 2], zebra: true),
          _dataRow([
            _cellText('CNN5 diagnosticou doença', color: Colors.redAccent, bold: true),
            _cellText('${det.cnn5Disease}', align: TextAlign.right),
            _cellText('${(det.cnn5Disease / det.gatekeeperTotal * 100).toStringAsFixed(1)}%', align: TextAlign.right),
          ], flexes: const [4, 2, 2]),
        ]),
        const SizedBox(height: 6),
        Text(
          'Confiança média dos diagnósticos de doença do CNN5: ${det.avgDiseaseConfPct.toStringAsFixed(1)}%. '
          'O CNN2 nunca emite veredito de doença: sempre que suspeita, escala ao CNN5.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic),
        ),
      ],
    ]);
  }
}
