import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MODELO DE DADOS DO RELATÓRIO
// Estrutura plana (sem dependências de providers/Flutter) construída na UI
// (reports_dashboard.dart) e consumida tanto pela pré-visualização em ecrã
// como pela geração do PDF, garantindo que ambos mostram exatamente os
// mesmos números. Documento formal, orientado a tabelas (sem gráficos).
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
  final CnnDecisionDetail? cnnDetail;
  final EconomicSummary? economic;
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
    required this.cnnDetail,
    required this.economic,
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
  final int cnn2HealthyCount;
  final int cnn5HealthyCount;
  CnnSummary({
    required this.cnn2Count,
    required this.cnn5Count,
    required this.otherCount,
    required this.cnn2AvgConf,
    required this.cnn5AvgConf,
    required this.uncertainCount,
    this.cnn2HealthyCount = 0,
    this.cnn5HealthyCount = 0,
  });

  int get total => cnn2Count + cnn5Count + otherCount;
  bool get hasData => total > 0;
}

/// Bandas de decisão do CNN5 + divisão gatekeeper CNN2/CNN5. Alimentado
/// pelo biChartsProvider (BiAdapters.uncertaintyZone + gatekeeperEfficiency),
/// os mesmos dados dos gráficos do Cap.3 da dashboard.
class CnnDecisionDetail {
  final int bandAccept; // confiança >= limiar de aceitação
  final int bandTriage; // 30% ao limiar: triagem manual
  final int bandAutoOthers; // <30%: auto-"Outros"
  final int routedTotal;
  final double acceptThresholdPct; // ex.: 80
  final int cnn2Healthy; // CNN2 aprovou saudável (nunca escalou)
  final int cnn5Healthy; // escalado por precaução, CNN5 confirmou saudável
  final int cnn5Disease; // CNN5 diagnosticou doença
  final double avgDiseaseConfPct;
  CnnDecisionDetail({
    required this.bandAccept,
    required this.bandTriage,
    required this.bandAutoOthers,
    required this.routedTotal,
    required this.acceptThresholdPct,
    required this.cnn2Healthy,
    required this.cnn5Healthy,
    required this.cnn5Disease,
    required this.avgDiseaseConfPct,
  });

  int get gatekeeperTotal => cnn2Healthy + cnn5Healthy + cnn5Disease;
  bool get hasData => routedTotal > 0 || gatekeeperTotal > 0;
}

/// Secção económica: 4 classes comerciais unificadas (Classe I / Classe II /
/// Indústria / Descarte) que somam sempre 100% do pomar. Preços por unidade
/// são estimativas para fins analíticos e de simulação (ver disclaimer na
/// secção), não valores de mercado reais.
class EconomicClassRow {
  final String label;
  final int count;
  final double pct; // 0-100, sobre o total do pomar
  final double precoUn; // €/unidade (0 para Descarte)
  final double valor; // €
  EconomicClassRow({
    required this.label,
    required this.count,
    required this.pct,
    required this.precoUn,
    required this.valor,
  });
}

class BatchCommercialRow {
  final String location;
  final int total;
  final double pctI;
  final double pctII;
  final double pctInd;
  final double pctDesc;
  BatchCommercialRow({
    required this.location,
    required this.total,
    required this.pctI,
    required this.pctII,
    required this.pctInd,
    required this.pctDesc,
  });
}

class EconomicSummary {
  final double valorTotal;
  final double capacityValue; // se 100% do pomar fosse Classe I
  final double metaValue; // 80% da capacidade
  final List<EconomicClassRow> classes; // I, II, Indústria, Descarte
  final List<BatchCommercialRow> perBatch;
  EconomicSummary({
    required this.valorTotal,
    required this.capacityValue,
    required this.metaValue,
    required this.classes,
    required this.perBatch,
  });

  bool get hasData => classes.any((c) => c.count > 0);
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
// GERAÇÃO DO PDF: documento formal, orientado a tabelas, sem gráficos.
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
  static const PdfColor _gold = PdfColor.fromInt(0xFFCA8A04);

  // Cores das 4 classes comerciais (secção económica), na ordem I/II/Ind/Desc.
  static const List<PdfColor> _classColors = [_emerald, _gold, _amber, _red];

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
          int sectionCounter = 1;
          final sections = <pw.Widget>[
            _titleBlock(d),
            pw.SizedBox(height: 4),
            _identificationTable(d),
            pw.SizedBox(height: 18),
            _section('${sectionCounter++}. Resumo Quantitativo'),
            _summaryTable(d),
            pw.SizedBox(height: 16),
            _section('${sectionCounter++}. Distribuição por Patologia'),
            _distributionTable(d),
            pw.SizedBox(height: 16),
            _section('${sectionCounter++}. Detalhe por Lote'),
            _batchTable(d),
            pw.SizedBox(height: 16),
            _section('${sectionCounter++}. Desempenho da Visão Computacional'),
            _cnnTable(d),
          ];

          if (d.economic != null && d.economic!.hasData) {
            sections.addAll([
              pw.SizedBox(height: 16),
              _section('${sectionCounter++}. Valor Económico da Colheita'),
              _economicSection(d.economic!),
            ]);
          }

          if (d.focus != null) {
            sections.addAll([
              pw.SizedBox(height: 16),
              _section('${sectionCounter++}. Lote em Foco: ${d.focus!.id}'),
              _focusTables(d.focus!),
            ]);
          }

          if (d.iot != null) {
            sections.addAll([
              pw.SizedBox(height: 16),
              _section('${sectionCounter++}. Equipamento de Captura'),
              _iotTable(d.iot!),
            ]);
          }

          sections.addAll([
            pw.SizedBox(height: 16),
            _section('${sectionCounter++}. Observações e Ações Recomendadas'),
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
      ['Frutos Afetados', '${d.totalAnomalies}'],
      ['Fila de Revisão Manual', '${d.humanQueue}'],
      ['Doença Predominante', d.dominantAnomaly == 'Nenhuma' ? 'Nenhuma (sem casos)' : '${_displayName(d.dominantAnomaly)} (${d.dominantAnomalyCount} casos)'],
      ['Variação de Aprovação (vs. início do período)', '${d.deltaPp >= 0 ? "+" : ""}${d.deltaPp.toStringAsFixed(1)} pp'],
      ['Índice de Saúde Global', '${d.healthScore.toStringAsFixed(0)}% (${d.statusLabel})'],
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
              _cell(b.dominant == 'Nenhuma' ? 'n/d' : _displayName(b.dominant), color: _conditionColor(b.dominant)),
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
    final det = d.cnnDetail;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Table(
        border: _tableBorder(),
        columnWidths: const {0: pw.FlexColumnWidth(2.4), 1: pw.FlexColumnWidth(0.8), 2: pw.FlexColumnWidth(0.8), 3: pw.FlexColumnWidth(0.8), 4: pw.FlexColumnWidth(1)},
        children: [
          _headerRow(['Modelo', 'Nº Classif.', '% do Fluxo', '% Saudáveis', 'Confiança Média'], aligns: [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight]),
          for (final r in rows)
            pw.TableRow(children: [
              _cell(r[0]),
              _cell(r[1], align: pw.Alignment.centerRight),
              _cell(r[2], align: pw.Alignment.centerRight),
              _cell(r[3], align: pw.Alignment.centerRight),
              _cell(r[4], bold: true, align: pw.Alignment.centerRight),
            ]),
        ],
      ),
      pw.SizedBox(height: 6),
      _muted('Fila de revisão humana (registos pendentes de triagem, pomar completo): ${c.uncertainCount} maçãs.'),
      if (det != null && det.routedTotal > 0) ...[
        pw.SizedBox(height: 12),
        pw.Text('Bandas de Decisão do CNN5 (regra operacional)',
            style: pw.TextStyle(color: _ink, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.Table(
          border: _tableBorder(),
          columnWidths: const {0: pw.FlexColumnWidth(2.4), 1: pw.FlexColumnWidth(0.8), 2: pw.FlexColumnWidth(0.8)},
          children: [
            _headerRow(['Banda de confiança', 'Nº Maçãs', '%'], aligns: [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight]),
            pw.TableRow(children: [
              _cell('Aceite automático (>= ${det.acceptThresholdPct.toStringAsFixed(0)}%)', color: _emerald, bold: true),
              _cell('${det.bandAccept}', align: pw.Alignment.centerRight),
              _cell('${(det.bandAccept / det.routedTotal * 100).toStringAsFixed(1)}%', align: pw.Alignment.centerRight),
            ]),
            pw.TableRow(children: [
              _cell('Triagem manual (30% a ${det.acceptThresholdPct.toStringAsFixed(0)}%)', color: _amber, bold: true),
              _cell('${det.bandTriage}', align: pw.Alignment.centerRight),
              _cell('${(det.bandTriage / det.routedTotal * 100).toStringAsFixed(1)}%', align: pw.Alignment.centerRight),
            ]),
            pw.TableRow(children: [
              _cell('Auto-"Outros" (< 30%)', color: _red, bold: true),
              _cell('${det.bandAutoOthers}', align: pw.Alignment.centerRight),
              _cell('${(det.bandAutoOthers / det.routedTotal * 100).toStringAsFixed(1)}%', align: pw.Alignment.centerRight),
            ]),
          ],
        ),
      ],
      if (det != null && det.gatekeeperTotal > 0) ...[
        pw.SizedBox(height: 12),
        pw.Text('Divisão de Decisão CNN2/CNN5 (arquitetura gatekeeper)',
            style: pw.TextStyle(color: _ink, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.Table(
          border: _tableBorder(),
          columnWidths: const {0: pw.FlexColumnWidth(2.4), 1: pw.FlexColumnWidth(0.8), 2: pw.FlexColumnWidth(0.8)},
          children: [
            _headerRow(['Resultado', 'Nº Maçãs', '%'], aligns: [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight]),
            pw.TableRow(children: [
              _cell('CNN2 aprovou como saudável (sem escalar)', color: _emerald, bold: true),
              _cell('${det.cnn2Healthy}', align: pw.Alignment.centerRight),
              _cell('${(det.cnn2Healthy / det.gatekeeperTotal * 100).toStringAsFixed(1)}%', align: pw.Alignment.centerRight),
            ]),
            pw.TableRow(children: [
              _cell('Escalado por precaução, CNN5 confirmou saudável', color: _gold, bold: true),
              _cell('${det.cnn5Healthy}', align: pw.Alignment.centerRight),
              _cell('${(det.cnn5Healthy / det.gatekeeperTotal * 100).toStringAsFixed(1)}%', align: pw.Alignment.centerRight),
            ]),
            pw.TableRow(children: [
              _cell('CNN5 diagnosticou doença', color: _red, bold: true),
              _cell('${det.cnn5Disease}', align: pw.Alignment.centerRight),
              _cell('${(det.cnn5Disease / det.gatekeeperTotal * 100).toStringAsFixed(1)}%', align: pw.Alignment.centerRight),
            ]),
          ],
        ),
        pw.SizedBox(height: 4),
        _muted('Confiança média dos diagnósticos de doença do CNN5: ${det.avgDiseaseConfPct.toStringAsFixed(1)}%. '
            'O CNN2 nunca emite veredito de doença: sempre que suspeita, escala ao CNN5.'),
      ],
    ]);
  }

  // ─── 5. VALOR ECONÓMICO ───
  /// Barra 100% empilhada com as 4 classes comerciais (flex proporcional às
  /// contagens). Única "primitiva gráfica" do documento; tudo o resto é tabela.
  static pw.Widget _stackedClassBar(List<int> counts, {double height = 9}) {
    final total = counts.fold<int>(0, (s, c) => s + c);
    if (total == 0) return pw.SizedBox(height: height);
    return pw.Row(children: [
      for (int i = 0; i < counts.length; i++)
        if (counts[i] > 0)
          pw.Expanded(
            flex: counts[i],
            child: pw.Container(height: height, color: _classColors[i]),
          ),
    ]);
  }

  static String _eur(double v) => '${v.toStringAsFixed(2)} EUR';

  static pw.Widget _economicSection(EconomicSummary e) {
    final metaHit = e.valorTotal >= e.metaValue;
    final counts = e.classes.map((c) => c.count).toList();
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      // KPIs
      pw.Table(
        border: null,
        columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1)},
        children: [
          pw.TableRow(children: [
            _idCell('VALOR ESTIMADO TOTAL', _eur(e.valorTotal)),
            _idCell('CAPACIDADE (100% CLASSE I)', _eur(e.capacityValue)),
            _idCell('META DE QUALIDADE (80%)',
                '${_eur(e.metaValue)} (${metaHit ? 'atingida' : 'abaixo'})'),
          ]),
        ],
      ),
      pw.SizedBox(height: 8),
      // Disclaimer obrigatório: estimativas, não preços de mercado.
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: pw.BoxDecoration(
          color: _headBg,
          border: pw.Border.all(color: _amber, width: 0.75),
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Text(
          'Nota: os valores por classe (0,60 EUR / 0,40 EUR / 0,20 EUR por unidade) são estimativas de referência '
          'para fins analíticos e de simulação, não preços de mercado reais. A classe Descarte agrega frutos sem '
          'valor comercial (Rot, Anthracnose e outros).',
          style: pw.TextStyle(color: _amber, fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 10),
      // Tabela das 4 classes
      pw.Table(
        border: _tableBorder(),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.2),
          1: pw.FlexColumnWidth(0.9),
          2: pw.FlexColumnWidth(0.8),
          3: pw.FlexColumnWidth(0.9),
          4: pw.FlexColumnWidth(1),
        },
        children: [
          _headerRow(
            ['Classe Comercial', 'Nº Maçãs', '% Pomar', 'Preço/un', 'Valor'],
            aligns: [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight, pw.Alignment.centerRight],
          ),
          for (int i = 0; i < e.classes.length; i++)
            pw.TableRow(children: [
              _cell(e.classes[i].label, color: _classColors[i], bold: true),
              _cell('${e.classes[i].count}', align: pw.Alignment.centerRight),
              _cell('${e.classes[i].pct.toStringAsFixed(1)}%', align: pw.Alignment.centerRight),
              _cell(e.classes[i].precoUn > 0 ? _eur(e.classes[i].precoUn) : 'sem valor', align: pw.Alignment.centerRight),
              _cell(_eur(e.classes[i].valor), bold: true, align: pw.Alignment.centerRight),
            ]),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _headBg),
            children: [
              _cell('TOTAL', bold: true),
              _cell('${counts.fold<int>(0, (s, c) => s + c)}', bold: true, align: pw.Alignment.centerRight),
              _cell('100.0%', bold: true, align: pw.Alignment.centerRight),
              _cell('', align: pw.Alignment.centerRight),
              _cell(_eur(e.valorTotal), bold: true, align: pw.Alignment.centerRight),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      _stackedClassBar(counts),
      pw.SizedBox(height: 4),
      _muted('Composição comercial do pomar: Classe I (verde), Classe II (dourado), Indústria (laranja), Descarte (vermelho).'),
      if (e.perBatch.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Text('Triagem de Qualidade Comercial por Lote',
            style: pw.TextStyle(color: _ink, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.Table(
          border: _tableBorder(),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.4),
            1: pw.FlexColumnWidth(0.8),
            2: pw.FlexColumnWidth(2.4),
            3: pw.FlexColumnWidth(0.9),
            4: pw.FlexColumnWidth(0.9),
          },
          children: [
            _headerRow(
              ['Lote', 'Maçãs', 'Composição', '% Classe I', '% Descarte'],
              aligns: [pw.Alignment.centerLeft, pw.Alignment.centerRight, pw.Alignment.center, pw.Alignment.centerRight, pw.Alignment.centerRight],
            ),
            for (final b in e.perBatch)
              pw.TableRow(children: [
                _cell(b.location, bold: true),
                _cell('${b.total}', align: pw.Alignment.centerRight),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: _stackedClassBar([
                    (b.pctI * 10).round(),
                    (b.pctII * 10).round(),
                    (b.pctInd * 10).round(),
                    (b.pctDesc * 10).round(),
                  ], height: 7),
                ),
                _cell('${b.pctI.toStringAsFixed(0)}%', color: _emerald, bold: true, align: pw.Alignment.centerRight),
                _cell('${b.pctDesc.toStringAsFixed(0)}%', color: b.pctDesc >= 20 ? _red : _ink, align: pw.Alignment.centerRight),
              ]),
          ],
        ),
      ],
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
        pw.SizedBox(height: 12),
        pw.Text('Amostras representativas do Lote', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.SizedBox(height: 5),
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
      ['Temperatura CPU', iot.cpuTemp != null ? '${iot.cpuTemp!.toStringAsFixed(0)}°C' : 'n/d'],
      ['Câmara', iot.cameraFps != null ? '${iot.cameraFps!.toStringAsFixed(1)} fps' : 'n/d'],
      ['Nitidez (Laplacian)', iot.lastBlur != null ? iot.lastBlur!.toStringAsFixed(0) : 'n/d'],
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
        pw.Text('Aviso: nitidez baixa, lente possivelmente suja ou descalibrada.',
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
