import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';

class PdfService {
  static Future<void> generateAndPrintPdf(Batch batch) async {
    final pdf = await _createDocument(batch);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  static Future<Uint8List> generatePdfBytes(Batch batch) async {
    final pdf = await _createDocument(batch);
    return pdf.save();
  }

  static Future<pw.Document> _createDocument(Batch batch) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            _buildHeader(batch),
            pw.SizedBox(height: 20),
            _buildMetrics(batch),
            pw.SizedBox(height: 20),
            _buildDistribution(batch),
            pw.SizedBox(height: 20),
            _buildSignatureGallery(batch),
          ];
        },
      ),
    );
    return pdf;
  }

  static pw.Widget _buildHeader(Batch batch) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Passaporte de Qualidade', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.Text('PROTÓTIPO IOT', style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey700, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Relatório do Lote: ${batch.id}', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                pw.Text('Localização: ${batch.location}', style: const pw.TextStyle(fontSize: 12, color: PdfColors.blueAccent)),
              ],
            ),
            pw.Text('Data: ${batch.date.year}-${batch.date.month}-${batch.date.day}', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
          ],
        ),
        pw.Divider(thickness: 2, color: PdfColors.blueAccent),
      ],
    );
  }

  static pw.Widget _buildMetrics(Batch batch) {
    final distribution = batch.healthDistribution;
    final int healthyCount = distribution['Healthy'] ?? 0;
    final double healthIndex = batch.totalApples > 0 ? (healthyCount / batch.totalApples) * 100 : 0;

    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _metricBox('Total Maçãs', '${batch.totalApples}'),
            _metricBox('Aprovadas', '$healthyCount'),
            _metricBox('Índice Saúde', '${healthIndex.toStringAsFixed(1)}%'),
            _metricBox('Tendência', '${batch.growthRate > 0 ? "+" : ""}${batch.growthRate.toStringAsFixed(1)}%'),
          ],
        ),
        pw.SizedBox(height: 16),
        _buildRiskSection(batch),
      ],
    );
  }

  static pw.Widget _buildRiskSection(Batch batch) {
    final color = batch.urgencyScore > 0.7 ? PdfColors.red : batch.urgencyScore > 0.3 ? PdfColors.orange : PdfColors.green;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: color, width: 2),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('ANÁLISE PREDITIVA DE RISCO (IA)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
              pw.SizedBox(height: 4),
              pw.Text(
                batch.urgencyScore > 0.7 
                  ? 'CRÍTICO: Risco elevado de alastramento detetado nesta zona.' 
                  : batch.urgencyScore > 0.3 
                    ? 'ALERTA: Tendência de crescimento de patologias detetada.' 
                    : 'ESTÁVEL: Níveis de saúde dentro dos parâmetros normais.',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          ),
          pw.Column(
            children: [
              pw.Text('SCORE', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text('${(batch.urgencyScore * 100).toStringAsFixed(0)}%', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _metricBox(String label, String value) {
    return pw.Container(
      width: 120,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _buildDistribution(Batch batch) {
    final distribution = batch.healthDistribution;
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Distribuição de Patologias:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          headers: ['Condição', 'Quantidade', 'Percentagem'],
          data: distribution.entries
              .where((entry) => entry.value > 0)
              .map((entry) => [
                    entry.key,
                    entry.value.toString(),
                    '${((entry.value / batch.totalApples) * 100).toStringAsFixed(1)}%',
                  ])
              .toList(),
        ),
      ],
    );
  }

  static pw.Widget _buildSignatureGallery(Batch batch) {
    // Pegar algumas melhores e piores. Nota: devido a problemas no loading assincrono de networks no PDF, 
    // mockamos apenas os nomes aqui ou deixamos um aviso no MockData de que a imagem ficaria aqui.
    // O PDF exige NetworkImage com package printing puxando na memória antes. Para simplicidade, text placeholders.
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Galeria de Amostras (Signature Gallery)', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text('*Em ambiente de produção, as miniaturas dos piores defeitos e melhores sãos aparecem aqui.*', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey600)),
      ],
    );
  }
}
