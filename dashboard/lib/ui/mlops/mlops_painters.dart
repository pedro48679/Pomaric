import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../charts_v2/_chart_kit.dart' show axisStyle;

/// Pinta duas curvas de uma métrica de treino (por época) lado a lado.
/// [metricKey] pode ser 'val_acc', 'f1', 'precision', 'recall'.

class MetricCurvePainter extends CustomPainter {
  final List histA;
  final List histB;
  final String metricKey;
  final Color colorA;
  final Color colorB;

  /// false (omissão): eixo fixo 0-100 com auto-escala de frações, como nas
  /// curvas do Comparar. true: eixo min/max derivado dos dados brutos, sem
  /// multiplicar frações por 100; necessário para o Loss no gráfico live
  /// (valores tipo 0.02-2.5 não cabem numa régua percentual).
  final bool dynamicY;

  const MetricCurvePainter(this.histA, this.histB, this.metricKey,
      {required this.colorA, required this.colorB, this.dynamicY = false});

  // train_acc/val_acc já vêm em escala 0-100 do backend; f1/precision/recall
  // vêm em fração 0-1 (train_cnn.py só multiplica por 100 os dois primeiros)
  //, sem esta deteção, selecionar F1/Precisão/Recall desenhava ~0.85 contra
  // um eixo de 0-100, colando a curva a y=0. Mesmo critério já usado em
  // extractPerClass() acima, só que aqui não faltava aplicar.
  double _val(Map<String, dynamic> entry) {
    final raw = (entry[metricKey] as num?)?.toDouble() ?? 0.0;
    if (dynamicY) return raw;
    return raw <= 1.0 ? raw * 100.0 : raw;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (histA.isEmpty && histB.isEmpty) return;
    final allEpochs =
        [histA.length, histB.length].reduce((a, b) => a > b ? a : b);
    if (allEpochs == 0) return;

    double minY = 0.0;
    double maxY = 100.0;
    if (dynamicY) {
      final values = <double>[
        for (final e in histA) _val(e as Map<String, dynamic>),
        for (final e in histB) _val(e as Map<String, dynamic>),
      ];
      final lo = values.reduce((a, b) => a < b ? a : b);
      final hi = values.reduce((a, b) => a > b ? a : b);
      final pad = (hi - lo).abs() < 1e-9 ? (hi.abs() * 0.1 + 0.01) : (hi - lo) * 0.1;
      minY = lo - pad;
      maxY = hi + pad;
    }
    final denom = allEpochs - 1 == 0 ? 1.0 : (allEpochs - 1).toDouble();

    // Grid lines (5 divisões) e Text Labels
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
      
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    
    for (int g = 0; g <= 5; g++) {
      final yv = minY + (maxY - minY) * g / 5;
      final py = size.height - (yv - minY) / (maxY - minY) * size.height;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), gridPaint);
      
      final label = dynamicY ? yv.toStringAsFixed(2) : '${yv.toInt()}%';
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(2, py - 14));
    }

    void drawCurve(List hist, Color color) {
      if (hist.isEmpty) return;
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      for (int i = 0; i < hist.length; i++) {
        final v = _val(hist[i] as Map<String, dynamic>);
        final x = i / denom * size.width;
        final y = size.height - (v - minY) / (maxY - minY) * size.height;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, linePaint);

      // Dot no último ponto
      if (hist.isNotEmpty) {
        final v = _val(hist.last as Map<String, dynamic>);
        final x = (hist.length - 1) / denom * size.width;
        final y = size.height - (v - minY) / (maxY - minY) * size.height;
        canvas.drawCircle(
            Offset(x, y), 5, Paint()..color = color.withOpacity(0.9));
      }
    }

    drawCurve(histA, colorA);
    drawCurve(histB, colorB);
  }

  @override
  bool shouldRepaint(covariant MetricCurvePainter old) =>
      old.histA != histA ||
      old.histB != histB ||
      old.metricKey != metricKey ||
      old.dynamicY != dynamicY;
}

/// Pinta curvas ROC (FPR x TPR) ou Precision-Recall para duas comparações de modelos.
/// Cada classe é desenhada com uma variação de opacidade da cor base do modelo
/// (modelo A = cyan/primary, modelo B = roxo), ou apenas a classe selecionada.

class RocPrCurvePainter extends CustomPainter {
  final Map<String, dynamic> curvesA;
  final Map<String, dynamic> curvesB;
  final String? classFilter;
  final bool isRoc;
  final bool isDark;

  const RocPrCurvePainter({
    required this.curvesA,
    required this.curvesB,
    required this.classFilter,
    required this.isRoc,
    required this.isDark,
  });

  static const _colorA = Colors.cyanAccent;
  static const _colorB = Colors.purpleAccent;

  @override
  void paint(Canvas canvas, Size size) {
    final gridColor = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);
    final axisColor = isDark ? Colors.white.withOpacity(0.25) : Colors.black.withOpacity(0.25);

    // Grid 0-1 em ambos os eixos, 5 divisões
    final gridPaint = Paint()..color = gridColor..strokeWidth = 1;
    for (int i = 0; i <= 5; i++) {
      final f = i / 5;
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), gridPaint);
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), gridPaint);
    }

    // Eixos
    final axisPaint = Paint()..color = axisColor..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), axisPaint);
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), axisPaint);

    // Linha de referência diagonal (ROC: classificador aleatório)
    if (isRoc) {
      final diagPaint = Paint()
        ..color = axisColor
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      final dashPath = Path()..moveTo(0, size.height)..lineTo(size.width, 0);
      canvas.drawPath(dashPath, diagPaint);
    }

    void drawClassCurves(Map<String, dynamic> curves, Color base) {
      final entries = classFilter != null
          ? curves.entries.where((e) => e.key == classFilter)
          : curves.entries;
      int idx = 0;
      final total = entries.length.clamp(1, 999);
      for (final e in entries) {
        final data = e.value as Map<String, dynamic>;
        final xs = isRoc
            ? (data['fpr'] as List? ?? [])
            : (data['recall'] as List? ?? []);
        final ys = isRoc
            ? (data['tpr'] as List? ?? [])
            : (data['precision'] as List? ?? []);
        if (xs.isEmpty || ys.isEmpty) {
          idx++;
          continue;
        }
        final opacity = classFilter != null ? 1.0 : (0.4 + 0.6 * (idx + 1) / total);
        final paint = Paint()
          ..color = base.withOpacity(opacity)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final path = Path();
        for (int i = 0; i < xs.length; i++) {
          final x = (xs[i] as num).toDouble() * size.width;
          final y = size.height - (ys[i] as num).toDouble() * size.height;
          i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        canvas.drawPath(path, paint);
        idx++;
      }
    }

    drawClassCurves(curvesA, _colorA);
    drawClassCurves(curvesB, _colorB);
  }

  @override
  bool shouldRepaint(covariant RocPrCurvePainter old) =>
      old.curvesA != curvesA ||
      old.curvesB != curvesB ||
      old.classFilter != classFilter ||
      old.isRoc != isRoc;
}

/// Geometria partilhada entre o painter da matriz de erros A/B e o hit-test
/// do hover, mesmo padrão de `_gkColumnRects` usado no mosaico CNN2/CNN5 do
/// Controlo do Pomar (nunca desalinha, porque os dois usam exatamente a
/// mesma função).
Rect classErrorPlotRect(Size size) => Rect.fromLTRB(4, 6, size.width - 4, size.height - 16);

List<({double left, double right})> classErrorColumnRects(int n, Rect plot) {
  if (n == 0) return const [];
  const gap = 8.0;
  final usable = (plot.width - gap * (n - 1)).clamp(0.0, plot.width);
  final colWidth = usable / n;
  final rects = <({double left, double right})>[];
  double x = plot.left;
  for (int i = 0; i < n; i++) {
    rects.add((left: x, right: x + colWidth));
    x += colWidth + gap;
  }
  return rects;
}

/// Uma coluna por doença (classe verdadeira), bloco único dividido em 2
/// cores empilhadas (Modelo A fundo / Modelo B topo) com divisor sólido -
/// mesma linguagem visual do mosaico CNN2/CNN5 (branco em dark mode, preto
/// em light mode).
class ClassErrorMatrixPainter extends CustomPainter {
  final List<String> classes;
  final Map<String, List<Map<String, dynamic>>> byClassA;
  final Map<String, List<Map<String, dynamic>>> byClassB;
  final String? hovered;
  final Color colorA;
  final Color colorB;

  ClassErrorMatrixPainter({
    required this.classes,
    required this.byClassA,
    required this.byClassB,
    required this.hovered,
    required this.colorA,
    required this.colorB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plot = classErrorPlotRect(size);
    if (plot.width <= 0 || plot.height <= 0 || classes.isEmpty) return;

    int maxTotal = 1;
    for (final cls in classes) {
      final total = (byClassA[cls]?.length ?? 0) + (byClassB[cls]?.length ?? 0);
      if (total > maxTotal) maxTotal = total;
    }

    final rects = classErrorColumnRects(classes.length, plot);
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (int i = 0; i < classes.length; i++) {
      final cls = classes[i];
      final left = rects[i].left, right = rects[i].right;
      final countA = byClassA[cls]?.length ?? 0;
      final countB = byClassB[cls]?.length ?? 0;
      final isHovered = cls == hovered;
      final alpha = isHovered ? 1.0 : 0.85;

      final hA = (countA / maxTotal) * plot.height;
      final hB = (countB / maxTotal) * plot.height;

      if (hA > 0) {
        canvas.drawRect(
          Rect.fromLTRB(left, plot.bottom - hA, right, plot.bottom),
          Paint()..color = colorA.withValues(alpha: alpha),
        );
      }
      if (hB > 0) {
        canvas.drawRect(
          Rect.fromLTRB(left, plot.bottom - hA - hB, right, plot.bottom - hA),
          Paint()..color = colorB.withValues(alpha: alpha),
        );
      }
      if (hA > 0 && hB > 0) {
        canvas.drawLine(
          Offset(left, plot.bottom - hA),
          Offset(right, plot.bottom - hA),
          Paint()
            ..color = AppColors.isDark ? Colors.white : Colors.black
            ..strokeWidth = 1.6,
        );
      }
      if (isHovered) {
        canvas.drawRect(
          Rect.fromLTRB(left, plot.top, right, plot.bottom),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = AppColors.textPrimary,
        );
      }

      tp.text = TextSpan(text: cls, style: axisStyle(size: 8));
      tp.layout(maxWidth: (right - left) + 6);
      final labelX = (left + (right - left - tp.width) / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(labelX, plot.bottom + 3));
    }
  }

  @override
  bool shouldRepaint(covariant ClassErrorMatrixPainter old) =>
      old.classes != classes ||
      old.hovered != hovered ||
      old.byClassA != byClassA ||
      old.byClassB != byClassB;
}
