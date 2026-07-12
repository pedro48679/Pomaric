import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MODELO DE DADOS DO RELATÓRIO
// Estrutura plana (sem dependências de providers/Flutter) construída na UI
// (reports_dashboard.dart) e consumida tanto pela pré-visualização em ecrã
// como pela geração do PDF, garantindo que ambos mostram exatamente os
// mesmos números. Documento formal, orientado a tabelas — sem gráficos.
// ═══════════════════════════════════════════════════════════════════════════

class ReportData {
  final DateTime generatedAt;
  final String periodLabel; // ex: "Últimos 30 dias"
  final String generatedBy;
  final String scopeLabel; // ex: "Pomar completo · 5 lotes"

  // Agregados globais
  final int totalApples;
  final int totalFrames;
  final int totalHealthy;
  final int totalAnomalies;
  final int batchCount;
  final double globalApproval;
  final double avgConf;
  final double automationRate;
  final double healthScore;
  final double deltaPp; // tendência de aprovação (pontos percentuais)
  final int humanQueue;
  final String dominantAnomaly;
  final int dominantAnomalyCount;
  final Map<String, int> distribution;

  // Detalhe
  final List<BatchRiskRow> batchRisks;
  final CnnSummary cnn;
  final IotSummary? iot;
  final BatchFocus? focus;

  final String statusLabel;
  final List<ActionItem> recommendations;

  ReportData({
    required this.generatedAt,
    required this.periodLabel,
    required this.generatedBy,
    required this.scopeLabel,
    required this.totalApples,
    required this.totalFrames,
    required this.totalHealthy,
    required this.totalAnomalies,
    required this.batchCount,
    required this.globalApproval,
    required this.avgConf,
    required this.automationRate,
    required this.healthScore,
    required this.deltaPp,
    required this.humanQueue,
    required this.dominantAnomaly,
    required this.dominantAnomalyCount,
    required this.distribution,
    required this.batchRisks,
    required this.cnn,
    required this.iot,
    required this.focus,
    required this.statusLabel,
    required this.recommendations,
  });
}

class BatchRiskRow {
  final String id;
  final String location;
  final String dominant;
  final int total;
  final int healthy;
  final double approval;
  final double contamination;
  final double severity;
  final double urgency;

  BatchRiskRow({
    required this.id,
    required this.location,
    required this.dominant,
    required this.total,
    required this.healthy,
    required this.approval,
    required this.contamination,
    required this.severity,
    required this.urgency,
  });
}

class CnnSummary {
  final int cnn2Count;
  final int cnn5Count;
  final int otherCount;
  final double cnn2AvgConf;
  final double cnn5AvgConf;
  final int uncertainCount;
  CnnSummary({
    required this.cnn2Count,
    required this.cnn5Count,
    required this.otherCount,
    required this.cnn2AvgConf,
    required this.cnn5AvgConf,
    required this.uncertainCount,
  });

  int get total => cnn2Count + cnn5Count + otherCount;
  bool get hasData => total > 0;
}

class IotSummary {
  final bool online;
  final String mode;
  final double? cpuTemp;
  final double? cameraFps;
  final double? lastBlur;
  final int inferenceCount;
  final bool blurWarning;
  final String uptime;
  IotSummary({
    required this.online,
    required this.mode,
    required this.cpuTemp,
    required this.cameraFps,
    required this.lastBlur,
    required this.inferenceCount,
    required this.blurWarning,
    required this.uptime,
  });
}

class BatchFocus {
  final String id;
  final String location;
  final String dominant;
  final int total;
  final int healthy;
  final double approval;
  final double urgency;
  final double avgConf;
  final Map<String, int> distribution;
  final List<TopApple> worst;
  BatchFocus({
    required this.id,
    required this.location,
    required this.dominant,
    required this.total,
    required this.healthy,
    required this.approval,
    required this.urgency,
    required this.avgConf,
    required this.distribution,
    required this.worst,
  });
}

class TopApple {
  final String id;
  final String condition;
  final double confidence;
  TopApple({required this.id, required this.condition, required this.confidence});
}

class ActionItem {
  final String title;
  final String action;
  final String? citation;
  final String severity; // 'critico' | 'alerta' | 'info'
  ActionItem({required this.title, required this.action, this.citation, this.severity = 'info'});
}

// ═══════════════════════════════════════════════════════════════════════════
// GERAÇÃO DO PDF — documento formal, orientado a tabelas, sem gráficos.
// ═══════════════════════════════════════════════════════════════════════════

class PdfService {
  static const PdfColor _ink = PdfColor.fromInt(0xFF1A1A1A);
  static const PdfColor _slate = PdfColor.fromInt(0xFF5B6B66);
  static const PdfColor _line = PdfColor.fromInt(0xFFD0D5D2);
  static const PdfColor _headBg = PdfColor.fromInt(0xFFEFF3F1);
  static const PdfColor _emerald = PdfColor.fromInt(0xFF0E7C56);
  static const PdfColor _amber = PdfColor.fromInt(0xFFB45309);
  static const PdfColor _red = PdfColor.fromInt(0xFFB91C1C);
  static const PdfColor _violet = PdfColor.fromInt(0xFF6D28D9);
  static const PdfColor _pink = PdfColor.fromInt(0xFFBE185D);

  static PdfColor _conditionColor(String c) {
    switch (c.toLowerCase()) {
      case 'healthy':
        return _emerald;
      case 'rot':
        return _red;
      case 'blotch':
        return _violet;
      case 'scab':
        return _amber;
      case 'anthracnose':
        return _pink;
      default:
        return _slate;
    }
  }

  static String _displayName(String c) => c == 'Blotch' ? 'Sooty Blotch' : c;

  static PdfColor _statusColor(double score) =>
      score >= 85 ? _emerald : score >= 70 ? _emerald : score >= 50 ? _amber : _red;

  static PdfColor _urgencyColor(double urgency) =>
      urgency >= 0.7 ? _red : urgency >= 0.3 ? _amber : _emerald;

  static Future<void> generateAndPrintPdf(ReportData data) async {
    final pdf = await _createDocument(data);
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  static Future<Uint8List> generatePdfBytes(ReportData data) async {
    final pdf = await _createDocument(data);
    return pdf.save();
  }

  static Future<pw.Document> _createDocument(ReportData d) async {
    final pdf = pw.Document(
      title: 'Relatório de Estado do Pomar',
      author: 'Sistema de Inspeção de Qualidade · ${d.generatedBy}',
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 34),
        header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : _runningHeader(d),
        footer: (ctx) => _footer(ctx, d),
        build: (context) {
          final sections = <pw.Widget>[
            _titleBlock(d),
            pw.SizedBox(height: 4),
            _identificationTable(d),
            pw.SizedBox(height: 18),
            _section('1. Resumo Quantitativo'),
            _summaryTable(d),
            pw.SizedBox(height: 16),
            _section('2. Distribuição por Patologia'),
            _distributionTable(d),
            pw.SizedBox(height: 16),
            _section('3. Detalhe por Lote'),
            _batchTable(d),
            pw.SizedBox(height: 16),
            _section('4. Desempenho dos Modelos de Classificação'),
            _cnnTable(d),
          ];

          if (d.focus != null) {
            sections.addAll([
              pw.SizedBox(height: 16),
              _section('5. Lote em Foco: ${d.focus!.id}'),
              _focusTables(d.focus!),
            ]);
          }

          if (d.iot != null) {
            sections.addAll([
              pw.SizedBox(height: 16),
              _section('6. Equipamento de Captura'),
              _iotTable(d.iot!),
            ]);
          }

          sections.addAll([
            pw.SizedBox(height: 16),
            _section('7. Observações e Ações Recomendadas'),
            _recommendationsTable(d),
          ]);

          return sections;
        },
      ),
    );
    return pdf;
  }

  // ─── CABEÇALHO / IDENTIFICAÇÃO ───
  static pw.Widget _titleBlock(ReportData d) {
    final statusColor = _statusColor(d.healthScore);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('RELATÓRIO DE ESTADO DO POMAR',
                    style: pw.TextStyle(color: _ink, fontSize: 19, fontWeight: pw.FontWeight.bold, letterSpacing: 0.3)),
                pw.SizedBox(height: 3),
                pw.Text(d.scopeLabel, style: const pw.TextStyle(color: _slate, fontSize: 10)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('CLASSIFICAÇÃO', style: const pw.TextStyle(color: _slate, fontSize: 7, letterSpacing: 1)),
                pw.SizedBox(height: 2),
                pw.Text('${d.statusLabel} · ${d.healthScore.toStringAsFixed(0)}%',
                    style: pw.TextStyle(color: statusColor, fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: _ink, thickness: 1.2),
      ],
    );
  }

  static pw.Widget _identificationTable(ReportData d) {
    return pw.Table(
      border: null,
      columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1)},
      children: [
        pw.TableRow(children: [
          _idCell('PERÍODO', d.periodLabel),
          _idCell('GERADO EM', _fmtDateTime(d.generatedAt)),
          _idCell('RESPONSÁVEL', d.generatedBy),
        ]),
      ],
    );
  }

  static pw.Widget _idCell(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, right: 12),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: const pw.TextStyle(color: _slate, fontSize: 7, letterSpacing: 0.8)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: pw.TextStyle(color: _ink, fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ]),
    );
  }

  static pw.Widget _runningHeader(ReportData d) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Relatório de Estado do Pomar', style: pw.TextStyle(color: _slate, fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text(d.scopeLabel, style: const pw.TextStyle(color: _slate, fontSize: 9)),
      ]),
    );
  }

  static pw.Widget _footer(pw.Context ctx, ReportData d) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Gerado automaticamente · ${_fmtDateTime(d.generatedAt)}',
            style: const pw.TextStyle(color: _slate, fontSize: 8)),
        pw.Text('Página ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(color: _slate, fontSize: 8)),
      ]),
    );
  }

  // ─── SECÇÕES ───
  static pw.Widget _section(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line))),
      child: pw.Text(title.toUpperCase(),
          style: pw.TextStyle(color: _ink, fontSize: 11, fontWeight: pw.FontWeight.bold, letterSpacing: 0.6)),
    );
  }

  static pw.TableRow _headerRow(List<String> headers, {List<pw.Alignment>? aligns}) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: _headBg),
      children: headers.asMap().entries.map((e) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Align(
            alignment: aligns != null ? aligns[e.key] : pw.Alignment.centerLeft,
            child: pw.Text(e.value, style: pw.TextStyle(color: _ink, fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _cell(String text, {PdfColor? color, bool bold = false, pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Align(
        alignment: align,
        child: pw.Text(text, style: pw.TextStyle(color: color ?? _ink, fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ),
    );
  }

  static pw.TableBorder _tableBorder() => pw.TableBorder(
        horizontalInside: const pw.BorderSide(color: _line, width: 0.5),
        top: const pw.BorderSide(color: _line, width: 0.75),
        bottom: const pw.BorderSide(color: _line, width: 0.75),
      );

  // ─── 1. RESUMO QUANTITATIVO ───
  static pw.Widget _summaryTable(ReportData d) {
    final rows = <List<String>>[
      ['Maçãs Inspecionadas', '${d.totalApples}'],
      ['Frames Capturados', '${d.totalFrames}'],
      ['Lotes no Período', '${d.batchCount}'],
      ['Aprovação Global', '${d.globalApproval.toStringAsFixed(1)}%'],
      ['Confiança Média da IA', '${d.avgConf.toStringAsFixed(1)}%'],
      ['Taxa de Automação', '${d.automationRate.toStringAsFixed(1)}%'],
      ['Anomalias Detetadas', '${d.totalAnomalies}'],
      ['Fila de Revisão Manual', '${d.humanQueue}'],
      ['Doença Predominante', d.dominantAnomaly == 'Nenhuma' ? '— (sem casos)' : '${_displayName(d.dominantAnomaly)} (${d.dominantAnomalyCount} casos)'],
      ['Variação de Aprovação (vs. início do período)', '${d.deltaPp >= 0 ? "+" : ""}${d.deltaPp.toStringAsFixed(1)} pp'],
      ['Índice de Saúde Global', '${d.healthScore.toStringAsFixed(0)}% — ${d.statusLabel}'],
    ];
    return pw.Table(
      border: _tableBorder(),
      columnWidths: const {0: pw.FlexColumnWidth(2.4), 1: pw.FlexColumnWidth(1)},
      children: [
        _headerRow(['Métrica', 'Valor'], aligns: [pw.Alignment.centerLeft, pw.Alignment.centerRight]),
        for (final r in rows)
          pw.TableRow(children: [
            _cell(r[0]),
            _cell(r[1], bold: true, align: pw.Alignment.centerRight),
          ]),
      ],
    );
  }

  // ─── 2. DISTRIBUIÇÃO ───
  static pw.Widget _distributionTable(ReportData d) {
    final total = d.totalApples > 0 ? d.totalApples : 1;
    final entries = d.distribution.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return _muted('Sem dados de distribuição disponíveis.');
    return pw.Table(
      border: _tableBorder(),
      columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1)},
      children: [
        _headerRow(['Condição', 'Nº Maçãs', '% do Total'], aligns: [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight]),
        for (final e in entries)
          pw.TableRow(children: [
            _cell(_displayName(e.key), color: _conditionColor(e.key), bold: true),
            _cell('${e.value}', align: pw.Alignment.centerRight),
            _cell('${(e.value / total * 100).toStringAsFixed(1)}%', align: pw.Alignment.centerRight),
          ]),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headBg),
          children: [
            _cell('TOTAL', bold: true),
            _cell('${d.totalApples}', bold: true, align: pw.Alignment.centerRight),
            _cell('100.0%', bold: true, align: pw.Alignment.centerRight),
          ],
        ),
      ],
    );
  }

  // ─── 3. LOTES ───
  static pw.Widget _batchTable(ReportData d) {
    final rows = [...d.batchRisks]..sort((a, b) => b.urgency.compareTo(a.urgency));
    if (rows.isEmpty) return _muted('Sem lotes no período selecionado.');
    final top = rows.take(15).toList();
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Table(
        border: _tableBorder(),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.3),
          1: pw.FlexColumnWidth(1.3),
          2: pw.FlexColumnWidth(1.6),
          3: pw.FlexColumnWidth(0.9),
          4: pw.FlexColumnWidth(1),
          5: pw.FlexColumnWidth(1),
          6: pw.FlexColumnWidth(1),
        },
        children: [
          _headerRow(
            ['Lote', 'Localização', 'Doença Predominante', 'Maçãs', 'Aprovação', 'Contam.', 'Urgência'],
            aligns: [pw.Alignment.centerLeft, pw.Alignment.centerLeft, pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight],
          ),
          for (final b in top)
            pw.TableRow(children: [
              _cell(b.id, bold: true),
              _cell(b.location),
              _cell(b.dominant == 'Nenhuma' ? '—' : _displayName(b.dominant), color: _conditionColor(b.dominant)),
              _cell('${b.total}', align: pw.Alignment.centerRight),
              _cell('${b.approval.toStringAsFixed(0)}%', align: pw.Alignment.centerRight),
              _cell('${(b.contamination * 100).toStringAsFixed(0)}%', align: pw.Alignment.centerRight),
              _cell('${(b.urgency * 100).toStringAsFixed(0)}%', color: _urgencyColor(b.urgency), bold: true, align: pw.Alignment.centerRight),
            ]),
        ],
      ),
      if (rows.length > top.length) ...[
        pw.SizedBox(height: 4),
        _muted('Mostrando os ${top.length} lotes de maior urgência de um total de ${rows.length}.'),
      ],
    ]);
  }

  // ─── 4. MODELOS CNN ───
  static pw.Widget _cnnTable(ReportData d) {
    final c = d.cnn;
    if (!c.hasData) return _muted('Sem classificações registadas pelo pipeline de IA no período.');
    final total = c.total > 0 ? c.total : 1;
    final rows = <List<String>>[
      ['CNN2 (Gatekeeper — deteção de saudável)', '${c.cnn2Count}', '${(c.cnn2Count / total * 100).toStringAsFixed(0)}%', '${c.cnn2AvgConf.toStringAsFixed(1)}%'],
      ['CNN5 (Multiclasse — classificação de patologia)', '${c.cnn5Count}', '${(c.cnn5Count / total * 100).toStringAsFixed(0)}%', '${c.cnn5AvgConf.toStringAsFixed(1)}%'],
    ];
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Table(
        border: _tableBorder(),
        columnWidths: const {0: pw.FlexColumnWidth(2.4), 1: pw.FlexColumnWidth(0.8), 2: pw.FlexColumnWidth(0.8), 3: pw.FlexColumnWidth(1)},
        children: [
          _headerRow(['Modelo', 'Nº Classif.', '% do Fluxo', 'Confiança Média'], aligns: [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight]),
          for (final r in rows)
            pw.TableRow(children: [
              _cell(r[0]),
              _cell(r[1], align: pw.Alignment.centerRight),
              _cell(r[2], align: pw.Alignment.centerRight),
              _cell(r[3], bold: true, align: pw.Alignment.centerRight),
            ]),
        ],
      ),
      pw.SizedBox(height: 6),
      _muted('Fila de revisão humana (confiança < 80% ou amostragem de auditoria): ${c.uncertainCount} maçãs.'),
    ]);
  }

  // ─── 5. FOCO NO LOTE ───
  static pw.Widget _focusTables(BatchFocus f) {
    final total = f.total > 0 ? f.total : 1;
    final entries = f.distribution.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Table(
        border: null,
        columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1)},
        children: [
          pw.TableRow(children: [
            _idCell('LOCALIZAÇÃO', f.location),
            _idCell('APROVAÇÃO', '${f.approval.toStringAsFixed(1)}%'),
            _idCell('URGÊNCIA', '${(f.urgency * 100).toStringAsFixed(0)}%'),
            _idCell('CONFIANÇA MÉDIA', '${f.avgConf.toStringAsFixed(1)}%'),
          ]),
        ],
      ),
      pw.SizedBox(height: 10),
      if (entries.isNotEmpty)
        pw.Table(
          border: _tableBorder(),
          columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1)},
          children: [
            _headerRow(['Condição', 'Nº Maçãs', '% do Lote'], aligns: [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight]),
            for (final e in entries)
              pw.TableRow(children: [
                _cell(_displayName(e.key), color: _conditionColor(e.key), bold: true),
                _cell('${e.value}', align: pw.Alignment.centerRight),
                _cell('${(e.value / total * 100).toStringAsFixed(1)}%', align: pw.Alignment.centerRight),
              ]),
          ],
        ),
      if (f.worst.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text('Amostras de maior risco', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: _tableBorder(),
          columnWidths: const {0: pw.FlexColumnWidth(1.4), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1)},
          children: [
            _headerRow(['ID Maçã', 'Condição', 'Confiança'], aligns: [pw.Alignment.centerLeft, pw.Alignment.centerLeft, pw.Alignment.centerRight]),
            for (final a in f.worst)
              pw.TableRow(children: [
                _cell(a.id),
                _cell(_displayName(a.condition), color: _conditionColor(a.condition)),
                _cell('${(a.confidence * 100).toStringAsFixed(1)}%', bold: true, align: pw.Alignment.centerRight),
              ]),
          ],
        ),
      ],
    ]);
  }

  // ─── 6. IOT ───
  static pw.Widget _iotTable(IotSummary iot) {
    final statusColor = iot.online ? _emerald : _red;
    final rows = <List<String>>[
      ['Estado', iot.online ? iot.mode.toUpperCase() : 'OFFLINE'],
      ['Temperatura CPU', iot.cpuTemp != null ? '${iot.cpuTemp!.toStringAsFixed(0)}°C' : '—'],
      ['Câmara', iot.cameraFps != null ? '${iot.cameraFps!.toStringAsFixed(1)} fps' : '—'],
      ['Nitidez (Laplacian)', iot.lastBlur != null ? iot.lastBlur!.toStringAsFixed(0) : '—'],
      ['Total de Inferências', '${iot.inferenceCount}'],
      ['Uptime', iot.uptime],
    ];
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Table(
        border: _tableBorder(),
        columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1.4)},
        children: [
          for (final r in rows)
            pw.TableRow(children: [
              _cell(r[0]),
              _cell(r[1], color: r[0] == 'Estado' ? statusColor : _ink, bold: true, align: pw.Alignment.centerRight),
            ]),
        ],
      ),
      if (iot.blurWarning) ...[
        pw.SizedBox(height: 6),
        pw.Text('Aviso: nitidez baixa — lente possivelmente suja ou descalibrada.',
            style: pw.TextStyle(color: _amber, fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    ]);
  }

  // ─── 7. RECOMENDAÇÕES ───
  static pw.Widget _recommendationsTable(ReportData d) {
    if (d.recommendations.isEmpty) {
      return _muted('Sem observações críticas. Manter os protocolos operacionais atuais.');
    }
    return pw.Table(
      border: _tableBorder(),
      columnWidths: const {0: pw.FlexColumnWidth(0.9), 1: pw.FlexColumnWidth(1.6), 2: pw.FlexColumnWidth(3)},
      children: [
        _headerRow(['Prioridade', 'Observação', 'Ação Recomendada']),
        for (final r in d.recommendations)
          pw.TableRow(children: [
            _cell(
              r.severity == 'critico' ? 'CRÍTICO' : r.severity == 'alerta' ? 'ALERTA' : 'INFO',
              color: r.severity == 'critico' ? _red : r.severity == 'alerta' ? _amber : _emerald,
              bold: true,
            ),
            _cell(r.title, bold: true),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(r.action, style: const pw.TextStyle(fontSize: 8.5, color: _ink, lineSpacing: 1.5)),
                if (r.citation != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text('Fonte: ${r.citation!}', style: pw.TextStyle(fontSize: 7, color: _slate, fontStyle: pw.FontStyle.italic)),
                ],
              ]),
            ),
          ]),
      ],
    );
  }

  static pw.Widget _muted(String text) =>
      pw.Text(text, style: pw.TextStyle(fontSize: 9, color: _slate, fontStyle: pw.FontStyle.italic));

  static String _fmtDateTime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
