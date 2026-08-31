part of 'reports_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// RELATÓRIOS · SECÇÕES
// Valor económico, focos por lote, IoT, recomendações, rodapé e estado vazio.
// ═══════════════════════════════════════════════════════════

extension _ReportsSections on ReportsView {
  // ─── 5. VALOR ECONÓMICO ───
  List<Color> get _classColors => [AppColors.healthy, Colors.amber, Colors.orangeAccent, Colors.redAccent];

  String _eur(double v) => '${v.toStringAsFixed(2)} €';

  Widget _stackedClassBar(List<int> counts, {double height = 10}) {
    final total = counts.fold<int>(0, (s, c) => s + c);
    if (total == 0) return SizedBox(height: height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Row(children: [
        for (int i = 0; i < counts.length; i++)
          if (counts[i] > 0)
            Expanded(flex: counts[i], child: Container(height: height, color: _classColors[i])),
      ]),
    );
  }

  Widget _economicSection(EconomicSummary e) {
    final metaHit = e.valorTotal >= e.metaValue;
    final counts = e.classes.map((c) => c.count).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.glassBorder)),
        child: Wrap(spacing: 28, runSpacing: 12, children: [
          _headMeta('VALOR ESTIMADO TOTAL', _eur(e.valorTotal)),
          _headMeta('CAPACIDADE (100% CLASSE I)', _eur(e.capacityValue)),
          _headMeta('META DE QUALIDADE (80%)', '${_eur(e.metaValue)} (${metaHit ? 'atingida' : 'abaixo'})'),
        ]),
      ),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.withOpacity(0.5)),
        ),
        child: Text(
          'Nota: os valores por classe (0,60 € / 0,40 € / 0,20 € por unidade) são estimativas de referência '
          'para fins analíticos e de simulação, não preços de mercado reais. A classe Descarte agrega frutos '
          'sem valor comercial (Rot, Anthracnose e outros).',
          style: TextStyle(color: Colors.amber.shade700, fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 14),
      _tableContainer([
        _headerRow(['Classe Comercial', 'Nº Maçãs', '% Pomar', 'Preço/un', 'Valor'],
            flexes: const [4, 2, 2, 2, 2],
            aligns: const [TextAlign.left, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right]),
        for (int i = 0; i < e.classes.length; i++)
          _dataRow([
            _cellText(e.classes[i].label, color: _classColors[i], bold: true),
            _cellText('${e.classes[i].count}', align: TextAlign.right),
            _cellText('${e.classes[i].pct.toStringAsFixed(1)}%', align: TextAlign.right),
            _cellText(e.classes[i].precoUn > 0 ? _eur(e.classes[i].precoUn) : 'sem valor', align: TextAlign.right),
            _cellText(_eur(e.classes[i].valor), bold: true, align: TextAlign.right),
          ], flexes: const [4, 2, 2, 2, 2], zebra: i.isOdd),
        Container(
          color: AppColors.surfaceBright.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(flex: 4, child: _cellText('TOTAL', bold: true)),
            Expanded(flex: 2, child: _cellText('${counts.fold<int>(0, (s, c) => s + c)}', bold: true, align: TextAlign.right)),
            Expanded(flex: 2, child: _cellText('100.0%', bold: true, align: TextAlign.right)),
            const Expanded(flex: 2, child: SizedBox()),
            Expanded(flex: 2, child: _cellText(_eur(e.valorTotal), bold: true, align: TextAlign.right)),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      _stackedClassBar(counts),
      const SizedBox(height: 6),
      Text('Composição comercial do pomar: Classe I (verde), Classe II (âmbar), Indústria (laranja), Descarte (vermelho).',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
      if (e.perBatch.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Triagem de Qualidade Comercial por Lote',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _tableContainer([
          _headerRow(['Lote', 'Maçãs', 'Composição', '% Classe I', '% Descarte'],
              flexes: const [2, 1, 4, 2, 2],
              aligns: const [TextAlign.left, TextAlign.right, TextAlign.center, TextAlign.right, TextAlign.right]),
          for (int i = 0; i < e.perBatch.length; i++)
            _dataRow([
              _cellText(e.perBatch[i].location, bold: true),
              _cellText('${e.perBatch[i].total}', align: TextAlign.right),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _stackedClassBar([
                  (e.perBatch[i].pctI * 10).round(),
                  (e.perBatch[i].pctII * 10).round(),
                  (e.perBatch[i].pctInd * 10).round(),
                  (e.perBatch[i].pctDesc * 10).round(),
                ], height: 8),
              ),
              _cellText('${e.perBatch[i].pctI.toStringAsFixed(0)}%', color: AppColors.healthy, bold: true, align: TextAlign.right),
              _cellText('${e.perBatch[i].pctDesc.toStringAsFixed(0)}%',
                  color: e.perBatch[i].pctDesc >= 20 ? Colors.redAccent : AppColors.textPrimary, align: TextAlign.right),
            ], flexes: const [2, 1, 4, 2, 2], zebra: i.isOdd),
        ]),
      ],
    ]);
  }

  // ─── 5. FOCO NO LOTE ───
  Widget _focusTables(BatchFocus f) {
    final total = f.total > 0 ? f.total : 1;
    final entries = f.distribution.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.glassBorder)),
          child: Wrap(spacing: 28, runSpacing: 12, children: [
            _headMeta('LOCALIZAÇÃO', f.location),
            _headMeta('APROVAÇÃO', '${f.approval.toStringAsFixed(1)}%'),
            _headMeta('URGÊNCIA', '${(f.urgency * 100).toStringAsFixed(0)}%'),
            _headMeta('CONFIANÇA MÉDIA', '${f.avgConf.toStringAsFixed(1)}%'),
          ]),
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 14),
          _tableContainer([
            _headerRow(['Condição', 'Nº Maçãs', '% do Lote'], flexes: const [3, 2, 2], aligns: const [TextAlign.left, TextAlign.right, TextAlign.right]),
            for (int i = 0; i < entries.length; i++)
              _dataRow([
                _cellText(AppColors.displayName(entries[i].key), color: AppColors.getColorForCondition(entries[i].key), bold: true),
                _cellText('${entries[i].value}', align: TextAlign.right),
                _cellText('${(entries[i].value / total * 100).toStringAsFixed(1)}%', align: TextAlign.right),
              ], flexes: const [3, 2, 2], zebra: i.isOdd),
          ]),
        ],
        if (f.worst.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Amostras representativas do Lote', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _tableContainer([
            _headerRow(['ID Maçã', 'Condição', 'Confiança'], flexes: const [3, 2, 2], aligns: const [TextAlign.left, TextAlign.left, TextAlign.right]),
            for (int i = 0; i < f.worst.length; i++)
              _dataRow([
                _cellText(f.worst[i].id),
                _cellText(AppColors.displayName(f.worst[i].condition), color: AppColors.getColorForCondition(f.worst[i].condition)),
                _cellText('${(f.worst[i].confidence * 100).toStringAsFixed(1)}%', bold: true, align: TextAlign.right),
              ], flexes: const [3, 2, 2], zebra: i.isOdd),
          ]),
        ],
      ],
    );
  }

  // ─── 6. IOT ───
  Widget _iotTable(IotSummary iot) {
    final color = iot.online ? AppColors.healthy : AppColors.rot;
    final rows = <List<String>>[
      ['Estado', iot.online ? iot.mode.toUpperCase() : 'OFFLINE'],
      ['Temperatura CPU', iot.cpuTemp != null ? '${iot.cpuTemp!.toStringAsFixed(0)}°C' : 'n/d'],
      ['Câmara', iot.cameraFps != null ? '${iot.cameraFps!.toStringAsFixed(1)} fps' : 'n/d'],
      ['Nitidez (Laplacian)', iot.lastBlur != null ? iot.lastBlur!.toStringAsFixed(0) : 'n/d'],
      ['Total de Inferências', '${iot.inferenceCount}'],
      ['Uptime', iot.uptime],
    ];
    return Column(children: [
      _tableContainer([
        for (int i = 0; i < rows.length; i++)
          _dataRow([
            _cellText(rows[i][0]),
            _cellText(rows[i][1], color: rows[i][0] == 'Estado' ? color : AppColors.textPrimary, bold: true, align: TextAlign.right),
          ], flexes: const [3, 2], zebra: i.isOdd),
      ]),
      if (iot.blurWarning) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.scab.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.scab.withOpacity(0.4))),
          child: Row(children: [
            Icon(Icons.warning_amber, color: AppColors.scab, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('Nitidez baixa, lente possivelmente suja ou descalibrada.', style: TextStyle(color: AppColors.scab, fontSize: 12, fontWeight: FontWeight.bold))),
          ]),
        ),
      ],
    ]);
  }

  // ─── 7. RECOMENDAÇÕES ───
  Widget _recommendationsTable(ReportData d) {
    if (d.recommendations.isEmpty) {
      return _tableContainer([
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.check_circle_outline, color: AppColors.healthy, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('Sem observações críticas. Manter os protocolos operacionais atuais.', style: TextStyle(color: AppColors.textPrimary, fontSize: 13))),
          ]),
        ),
      ]);
    }
    return _tableContainer([
      for (int i = 0; i < d.recommendations.length; i++) _recRow(d.recommendations[i], zebra: i.isOdd),
    ]);
  }

  Widget _recRow(ActionItem r, {bool zebra = false}) {
    final color = r.severity == 'critico' ? AppColors.rot : r.severity == 'alerta' ? AppColors.scab : AppColors.healthy;
    final tag = r.severity == 'critico' ? 'CRÍTICO' : r.severity == 'alerta' ? 'ALERTA' : 'INFO';
    return Container(
      decoration: BoxDecoration(
        color: zebra ? AppColors.surfaceBright.withOpacity(0.18) : Colors.transparent,
        border: Border(top: BorderSide(color: AppColors.glassBorder.withOpacity(0.5))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(tag, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
          ),
          SizedBox(
            width: 170,
            child: Text(r.title, style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.action, style: TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.4)),
                if (r.citation != null) ...[
                  const SizedBox(height: 3),
                  Text('Fonte: ${r.citation!}', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPanel(String text) {
    return _tableContainer([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
      ),
    ]);
  }

  Widget _reportFooter(ReportData d) {
    return Column(children: [
      Divider(color: AppColors.glassBorder),
      const SizedBox(height: 8),
      Text(
        'Documento gerado automaticamente pelo sistema de inspeção de qualidade em ${DateFormat('dd/MM/yyyy HH:mm').format(d.generatedAt)}. '
        'Os valores refletem o estado dos dados no momento da geração.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 11, height: 1.4),
      ),
    ]);
  }

  Widget _emptyState() {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, color: AppColors.textSecondary.withOpacity(0.4), size: 56),
            const SizedBox(height: 16),
            Text('Sem dados para gerar o relatório', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 6),
            Text('Aguarde a chegada de inspeções ou ajuste o período.', style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
