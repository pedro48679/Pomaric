
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '_chart_kit.dart';

// ═══════════════════════════════════════════════════════════
// BI · CNN2 vs CNN5
// Mosaico de eficiência do gatekeeper: quem decide cada maçã.
// ═══════════════════════════════════════════════════════════
// ═══════════════ 5 · CNN2 vs CNN5: QUEM DECIDE? ═══════════════

class GatekeeperPoint {
  final String label; // ID do lote
  final int total;
  final int cnn2HealthyCount; // CNN2 decidiu Healthy diretamente (nunca escala)
  final int cnn5HealthyCount; // escalado por precaução, CNN5 confirmou Healthy
  final Map<String, int> cnn5DiseaseCounts; // doença -> contagem diagnosticada pelo CNN5
  final Map<String, double> cnn5DiseaseAvgConf; // doença -> confiança média (0..1) desse diagnóstico
  const GatekeeperPoint({
    required this.label,
    required this.total,
    required this.cnn2HealthyCount,
    required this.cnn5HealthyCount,
    this.cnn5DiseaseCounts = const {},
    this.cnn5DiseaseAvgConf = const {},
  });
}

class GatekeeperData {
  final List<GatekeeperPoint> points;
  final int totalApples;
  final int totalCnn2Healthy;
  final int totalCnn5Healthy;
  final int totalCnn5Disease;
  final int totalCnn5DiseaseHighConf;
  final double avgDiseaseConfidence; // média entre todos os diagnósticos de doença do CNN5
  const GatekeeperData({
    required this.points,
    required this.totalApples,
    required this.totalCnn2Healthy,
    required this.totalCnn5Healthy,
    required this.totalCnn5Disease,
    required this.totalCnn5DiseaseHighConf,
    required this.avgDiseaseConfidence,
  });
  bool get isEmpty => points.isEmpty;
}

/// Geometria partilhada entre o painter e o hit-test do hover: largura de
/// cada coluna proporcional ao volume do lote (mosaico/Marimekko), com um
/// espaço real entre colunas, um lote grande pesa mais no pipeline do que
/// um pequeno, e isso é visível diretamente na largura, não só num tooltip.
const double _gkLeftMargin = 34, _gkTopMargin = 6, _gkRightMargin = 4, _gkBottomMargin = 22, _gkGap = 7;

Rect _gkPlotRect(Size size) =>
    Rect.fromLTRB(_gkLeftMargin, _gkTopMargin, size.width - _gkRightMargin, size.height - _gkBottomMargin);

List<({double left, double right})> _gkColumnRects(List<GatekeeperPoint> points, Rect plot) {
  final n = points.length;
  if (n == 0) return const [];
  final grandTotal = points.fold<int>(0, (s, p) => s + p.total);
  final usable = (plot.width - _gkGap * (n - 1)).clamp(0.0, plot.width);
  final rects = <({double left, double right})>[];
  double x = plot.left;
  for (final p in points) {
    final w = grandTotal == 0 ? usable / n : (p.total / grandTotal) * usable;
    rects.add((left: x, right: x + w));
    x += w + _gkGap;
  }
  return rects;
}

class GatekeeperEfficiencyChart extends StatefulWidget {
  final GatekeeperData data;
  const GatekeeperEfficiencyChart({super.key, required this.data});

  @override
  State<GatekeeperEfficiencyChart> createState() => _GatekeeperEfficiencyChartState();
}

class _GatekeeperEfficiencyChartState extends State<GatekeeperEfficiencyChart> {
  // CNN2 e "CNN5 confirmou Healthy" ficam na mesma família de cor (verde da
  // app), são as duas formas de a maçã acabar saudável; a única diferença é
  // se precisou ou não de passar pelo classificador caro. As doenças usam a
  // paleta de patologia já estabelecida no resto da dashboard.
  static Color get _cnn2Color => AppColors.healthy;
  static Color get _cnn5HealthyColor => Color.lerp(AppColors.healthy, Colors.cyanAccent, 0.45)!;

  GatekeeperPoint? _hovered;
  Offset? _hoverPos;

  GatekeeperPoint? _pointAt(Offset local, Size size) {
    final points = widget.data.points;
    final plot = _gkPlotRect(size);
    if (local.dy < plot.top || local.dy > plot.bottom) return null;
    final rects = _gkColumnRects(points, plot);
    for (int i = 0; i < points.length; i++) {
      if (local.dx >= rects[i].left && local.dx <= rects[i].right) return points[i];
    }
    return null;
  }

  String _infoText(GatekeeperPoint p) {
    final diseaseTotal = p.cnn5DiseaseCounts.values.fold<int>(0, (s, v) => s + v);
    final parts = p.cnn5DiseaseCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final diseaseStr = parts.isEmpty
        ? 'sem diagnósticos de doença'
        : parts.take(3).map((e) {
            final conf = ((p.cnn5DiseaseAvgConf[e.key] ?? 0) * 100).round();
            return '${AppColors.displayName(e.key)} ${e.value} (conf. média $conf%)';
          }).join('\n');
    return '${p.label} · ${p.total} maçãs\n'
        'CNN2→Healthy: ${p.cnn2HealthyCount} · CNN5→Healthy: ${p.cnn5HealthyCount} · CNN5→Doença: $diseaseTotal\n'
        '$diseaseStr';
  }

  Widget _statDot(Color color, String label, int count, int total) {
    final pct = total > 0 ? count / total * 100 : 0.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label ', style: axisStyle(size: 10.5)),
        Text('${pct.toStringAsFixed(0)}%', style: TextStyle(color: AppColors.textPrimary, fontSize: 10.5, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) {
      return Center(
        child: Text('Sem lotes no período para comparar CNN2 vs CNN5.',
            textAlign: TextAlign.center, style: axisStyle(size: 11)),
      );
    }

    final diseasesPresent = <String>{};
    for (final p in data.points) {
      diseasesPresent.addAll(p.cnn5DiseaseCounts.keys);
    }
    final diseaseLegend = kClassOrder.where((d) => d != 'Healthy' && diseasesPresent.contains(d)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabeçalho leve (não caixas de KPI), 3 categorias com significado
        // real, em vez de um único par "50%/50%" que escondia que CNN2 nunca
        // dá o veredito final sobre doença, só sobre "está bem, não escalo".
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...() {
                    final totalHealthy = data.totalCnn2Healthy + data.totalCnn5Healthy;
                    return [
                      _statDot(_cnn2Color, 'CNN2 → Healthy', data.totalCnn2Healthy, totalHealthy),
                      _statDot(_cnn5HealthyColor, 'CNN5 → Healthy (confirmado)', data.totalCnn5Healthy, totalHealthy),
                    ];
                  }(),
                ],
              ),
            ),
            Text('${data.totalApples} maçãs · ${data.points.length} lotes', style: axisStyle(size: 10)),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              return MouseRegion(
                onHover: (e) => setState(() {
                  _hovered = _pointAt(e.localPosition, size);
                  _hoverPos = e.localPosition;
                }),
                onExit: (_) => setState(() {
                  _hovered = null;
                  _hoverPos = null;
                }),
                child: GestureDetector(
                  onTapDown: (e) => setState(() {
                    _hovered = _pointAt(e.localPosition, size);
                    _hoverPos = e.localPosition;
                  }),
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: size,
                        painter: _GatekeeperMosaicPainter(
                          data: data,
                          hovered: _hovered,
                          cnn2Color: _cnn2Color,
                          cnn5HealthyColor: _cnn5HealthyColor,
                        ),
                      ),
                      if (_hovered != null && _hoverPos != null)
                        hoverTooltipOverlay(pos: _hoverPos!, containerSize: size, text: _infoText(_hovered!)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        ChartLegend(
          alignment: WrapAlignment.center,
          items: [
            MapEntry('CNN2 · Healthy (direto)', _cnn2Color),
            MapEntry('CNN5 · Healthy (confirmado)', _cnn5HealthyColor),
            for (final d in diseaseLegend) MapEntry('CNN5 · ${AppColors.displayName(d)}', classColor(d)),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'Contorno verde = mosaico CNN2 · contorno âmbar = mosaico CNN5 · linha divisória = fronteira entre os dois',
          textAlign: TextAlign.center,
          style: axisStyle(size: 8.5),
        ),
      ],
    );
  }
}

/// Mosaico (Marimekko): largura de cada coluna ∝ volume do lote. Altura
/// dividida em 2 blocos PRIMÁRIOS, CNN2 (fundo, cor única, sem contorno: já
/// é "uma coisa só") e CNN5 (topo, com contorno, é onde vive a nuance:
/// Healthy-confirmado + cada doença, sub-partes SECUNDÁRIAS dentro do mesmo
/// grupo). A opacidade de cada doença é a confiança média do CNN5 nesse
/// diagnóstico naquele lote, um diagnóstico pouco confiante esbate-se em vez
/// de ganhar uma cor/padrão à parte, para o gráfico continuar "suave".
class _GatekeeperMosaicPainter extends CustomPainter {
  final GatekeeperData data;
  final GatekeeperPoint? hovered;
  final Color cnn2Color;
  final Color cnn5HealthyColor;
  _GatekeeperMosaicPainter({
    required this.data,
    required this.hovered,
    required this.cnn2Color,
    required this.cnn5HealthyColor,
  });

  // Contorno de cada mosaico: CNN2 num verde mais escuro que o preenchimento
  // (destaca-se contra ele em qualquer tema), CNN5 em âmbar, a mesma cor de
  // "identidade da escalada" já usada no cabeçalho/legenda.
  Color get _cnn2OutlineColor => Color.lerp(cnn2Color, Colors.black, 0.42)!;
  static const Color _cnn5OutlineColor = Colors.orangeAccent;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _gkPlotRect(size);
    if (plot.width <= 0 || plot.height <= 0 || data.points.isEmpty) return;

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final t in [0.0, 0.5, 1.0]) {
      tp.text = TextSpan(text: '${(t * 100).toInt()}%', style: axisStyle(size: 8));
      tp.layout();
      tp.paint(canvas, Offset(plot.left - tp.width - 6, plot.bottom - t * plot.height - tp.height / 2));
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom - 0.5 * plot.height),
      Offset(plot.right, plot.bottom - 0.5 * plot.height),
      Paint()..color = gridLineColor()..strokeWidth = 1,
    );

    final rects = _gkColumnRects(data.points, plot);
    for (int i = 0; i < data.points.length; i++) {
      final p = data.points[i];
      final left = rects[i].left, right = rects[i].right;
      final w = right - left;
      if (w <= 0 || p.total == 0) continue;
      final isHovered = identical(p, hovered);
      final dim = isHovered ? 1.0 : 0.9;

      // Bloco primário CNN2, simples, sem contorno.
      final cnn2H = (p.cnn2HealthyCount / p.total) * plot.height;
      final cnn5Bottom = plot.bottom - cnn2H;
      canvas.drawRect(
        Rect.fromLTRB(left, cnn5Bottom, right, plot.bottom),
        Paint()..color = cnn2Color.withValues(alpha: dim),
      );

      // Bloco primário CNN5, Healthy-confirmado primeiro (base, encostado ao
      // CNN2), depois cada doença empilhada, opacidade = confiança média.
      final cnn5HealthyH = (p.cnn5HealthyCount / p.total) * plot.height;
      if (cnn5HealthyH > 0) {
        canvas.drawRect(
          Rect.fromLTRB(left, cnn5Bottom - cnn5HealthyH, right, cnn5Bottom),
          Paint()..color = cnn5HealthyColor.withValues(alpha: dim),
        );
      }
      double segTop = cnn5Bottom - cnn5HealthyH;
      for (final cls in kClassOrder) {
        if (cls == 'Healthy') continue;
        final cnt = p.cnn5DiseaseCounts[cls] ?? 0;
        if (cnt == 0) continue;
        final segH = (cnt / p.total) * plot.height;
        final conf = (p.cnn5DiseaseAvgConf[cls] ?? 0.7).clamp(0.0, 1.0);
        final segAlpha = (0.38 + 0.62 * conf) * dim;
        canvas.drawRect(
          Rect.fromLTRB(left, segTop - segH, right, segTop),
          Paint()..color = classColor(cls).withValues(alpha: segAlpha.clamp(0.0, 1.0)),
        );
        segTop -= segH;
      }

      // Cada mosaico (CNN2, CNN5) é um bloco com o seu próprio contorno, numa
      // cor específica, CNN2 num verde mais escuro que o preenchimento (para
      // se destacar contra ele), CNN5 em âmbar (a "cor de identidade" da
      // escalada, já usada no cabeçalho). Isto substitui o contorno único que
      // só existia no CNN5.
      final hasCnn2Block = cnn5Bottom < plot.bottom - 0.5;
      final hasCnn5Block = cnn5Bottom > plot.top + 0.5;

      if (hasCnn2Block) {
        canvas.drawRect(
          Rect.fromLTRB(left, cnn5Bottom, right, plot.bottom),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isHovered ? 2.0 : 1.4
            ..color = _cnn2OutlineColor.withValues(alpha: dim),
        );
      }
      if (hasCnn5Block) {
        canvas.drawRect(
          Rect.fromLTRB(left, plot.top, right, cnn5Bottom),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isHovered ? 2.0 : 1.4
            ..color = _cnn5OutlineColor.withValues(alpha: dim),
        );
      }

      // Separador explícito entre os 2 mosaicos, branco em dark mode, preto
      // em light mode, sempre sólido (pedido literal, não uma cor esbatida).
      if (hasCnn2Block && hasCnn5Block) {
        canvas.drawLine(
          Offset(left, cnn5Bottom),
          Offset(right, cnn5Bottom),
          Paint()
            ..color = AppColors.isDark ? Colors.white : Colors.black
            ..strokeWidth = 2.0,
        );
      }

      if (isHovered) {
        canvas.drawRect(
          Rect.fromLTRB(left, plot.top, right, plot.bottom),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = AppColors.textPrimary,
        );
      }

      if (w > 26) {
        tp.text = TextSpan(text: p.label, style: axisStyle(size: 7.5));
        tp.layout(maxWidth: w);
        tp.paint(canvas, Offset(left + (w - tp.width) / 2, plot.bottom + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GatekeeperMosaicPainter old) => old.data != data || old.hovered != hovered;
}
