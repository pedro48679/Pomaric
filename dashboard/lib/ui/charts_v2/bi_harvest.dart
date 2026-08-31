import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '_chart_kit.dart';

// ═══════════════════════════════════════════════════════════
// BI · VALOR DA COLHEITA
// Copo de valor económico: Classe I, Classe II e Indústria.
// ═══════════════════════════════════════════════════════════
// ═══════════════ 4 · VALOR ECONÓMICO DA COLHEITA: CATEGORIA A vs B ═══════════════

class HarvestValueData {
  final int countA; // Classe I (Verde)
  final int countB; // Classe II (Amarelo)
  final int countC; // Indústria (Laranja)
  final int countTotal; // todas as maçãs do período (inclui Refugo)
  final double pctA; // countA / countTotal, % REAL do pomar
  final double pctB; // countB / countTotal, % REAL do pomar
  final double pctC; // countC / countTotal, % REAL do pomar
  final double valorA;
  final double valorB;
  final double valorC;
  final double capacityValue; // valor hipotético se TODO o pomar fosse Categoria A
  final double metaValue; // meta de qualidade = capacityValue × metaPct (80% por defeito)

  const HarvestValueData({
    required this.countA,
    required this.countB,
    required this.countC,
    required this.countTotal,
    required this.pctA,
    required this.pctB,
    required this.pctC,
    required this.valorA,
    required this.valorB,
    required this.valorC,
    required this.capacityValue,
    required this.metaValue,
  });

  double get valorTotal => valorA + valorB + valorC;
}

class HarvestValueChart extends StatelessWidget {
  final HarvestValueData data;
  const HarvestValueChart({super.key, required this.data});

  static Color _colorA = AppColors.healthy; 
  static Color _colorB = Colors.amber; 
  static Color _colorC = Colors.orangeAccent;

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: axisStyle(size: 9.5))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (data.countTotal <= 0) {
      return Center(
        child: Text('Sem maçãs no período para calcular o valor da colheita.',
            textAlign: TextAlign.center, style: axisStyle(size: 11)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('€ ${data.valorTotal.toStringAsFixed(2)}',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) => CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _LiquidCupPainter(
                pctA: data.pctA,
                pctB: data.pctB,
                pctC: data.pctC,
                capacityValue: data.capacityValue,
                colorA: _colorA,
                colorB: _colorB,
                colorC: _colorC,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _legendDot(_colorA, 'Classe I · ${(data.pctA * 100).toStringAsFixed(0)}% · €${data.valorA.toStringAsFixed(0)}'),
        const SizedBox(height: 4),
        _legendDot(_colorB, 'Classe II · ${(data.pctB * 100).toStringAsFixed(0)}% · €${data.valorB.toStringAsFixed(0)}'),
        const SizedBox(height: 4),
        _legendDot(_colorC, 'Indústria · ${(data.pctC * 100).toStringAsFixed(0)}% · €${data.valorC.toStringAsFixed(0)}'),
      ],
    );
  }
}

/// Copo 2D fino: eixo Y = % real do pomar (0 no fundo, 100% no topo, rotulado
/// em € via `capacityValue` = valor hipotético se TODO o pomar fosse Categoria
/// A). As bandas (A por baixo, B por cima) usam a percentagem REAL de cada
/// categoria na população total, não o valor económico, por isso o
/// preenchimento total (A+B) reflete exatamente a fração do pomar coberta por
/// estas duas categorias; o espaço vazio acima é Rot+Anthracnose+Outros.
/// Linha tracejada horizontal marca a meta de qualidade (80%). Desenho
/// deliberadamente estreito (copo, não funil), largura do copo é uma fração
/// da área disponível, centrada.
class _LiquidCupPainter extends CustomPainter {
  final double pctA; // 0..1
  final double pctB; // 0..1
  final double pctC; // 0..1
  final double capacityValue; // só para o rótulo do eixo (€ equivalente a 100%)
  final Color colorA;
  final Color colorB;
  final Color colorC;
  static const double metaPct = 0.80;

  _LiquidCupPainter({
    required this.pctA,
    required this.pctB,
    required this.pctC,
    required this.capacityValue,
    required this.colorA,
    required this.colorB,
    required this.colorC,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelMargin = 40.0, topMargin = 10.0, rightMargin = 4.0, bottomMargin = 18.0;
    final availLeft = labelMargin;
    final availRight = size.width - rightMargin;
    final top = topMargin;
    final bottom = size.height - bottomMargin;
    if (availRight <= availLeft || bottom <= top) return;

    // Copo fino e centrado, deliberadamente mais estreito que a área
    // disponível, para ler como "copo" e não como o antigo funil largo.
    final availWidth = availRight - availLeft;
    final cupWidth = math.max(28.0, availWidth * 0.55);
    final cupLeft = availLeft + (availWidth - cupWidth) / 2;
    final cupRight = cupLeft + cupWidth;
    final taper = cupWidth * 0.08; // ligeiro afunilamento (mais largo no topo, como um copo)

    final cupPath = Path()
      ..moveTo(cupLeft, top)
      ..lineTo(cupRight, top)
      ..lineTo(cupRight - taper, bottom)
      ..lineTo(cupLeft + taper, bottom)
      ..close();
    canvas.drawPath(cupPath, Paint()..color = AppColors.textSecondary.withOpacity(0.04));
    canvas.drawPath(
      cupPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppColors.textSecondary.withOpacity(0.35),
    );

    // Eixo Y: 0€ no fundo, capacidade (100%) no topo, ancorado à esquerda do copo.
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void axisLabel(String text, double y, {bool bold = false}) {
      tp.text = TextSpan(text: text, style: axisStyle(size: 8, bold: bold));
      tp.layout();
      tp.paint(canvas, Offset((cupLeft - tp.width - 5).clamp(0.0, double.infinity), y - tp.height / 2));
    }

    axisLabel('0€', bottom);
    axisLabel('€${capacityValue.toStringAsFixed(0)}', top, bold: true);

    // Preenchimento: banda A (fundo) + banda B (meio) + banda C (topo)
    canvas.save();
    canvas.clipPath(cupPath);
    final height = bottom - top;
    final hA = pctA.clamp(0.0, 1.0) * height;
    final hB = pctB.clamp(0.0, (1.0 - pctA).clamp(0.0, 1.0)) * height;
    final hC = pctC.clamp(0.0, (1.0 - pctA - pctB).clamp(0.0, 1.0)) * height;
    
    if (hA > 0) {
      canvas.drawRect(Rect.fromLTRB(cupLeft, bottom - hA, cupRight, bottom), Paint()..color = colorA);
    }
    if (hB > 0) {
      canvas.drawRect(Rect.fromLTRB(cupLeft, bottom - hA - hB, cupRight, bottom - hA), Paint()..color = colorB);
    }
    if (hC > 0) {
      canvas.drawRect(Rect.fromLTRB(cupLeft, bottom - hA - hB - hC, cupRight, bottom - hA - hB), Paint()..color = colorC);
    }
    canvas.restore();

    // Linha de meta (80%).
    final metaY = bottom - metaPct * height;
    final dashPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1.3;
    double x = cupLeft - 4;
    while (x < cupRight + 4) {
      canvas.drawLine(Offset(x, metaY), Offset(math.min(x + 5, cupRight + 4), metaY), dashPaint);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidCupPainter old) =>
      old.pctA != pctA || old.pctB != pctB || old.pctC != pctC || old.capacityValue != capacityValue;
}
