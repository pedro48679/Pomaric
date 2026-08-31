import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// ════════════════════════════════════════════════════════════════════════
/// KIT PARTILHADO DOS 16 GRÁFICOS (charts_v2)
///
/// Helpers de cor/texto/legenda reutilizados pelos widgets. NÃO faz
/// agregação de dados, cada widget recebe o payload já processado.
/// ════════════════════════════════════════════════════════════════════════

/// Ordem canónica das classes do CNN5 (taxonomia real da BD).
const List<String> kClassOrder = ['Healthy', 'Rot', 'Scab', 'Anthracnose', 'Blotch'];

/// Cor de uma classe patológica (delega na paleta oficial do projeto).
Color classColor(String c) => AppColors.getColorForCondition(c);

/// Cor de fallback para séries genéricas (não-patológicas) por índice.
const List<Color> kSeriesPalette = [
  Color(0xFF00FFC4), // mint
  Color(0xFFF59E0B), // amber
  Color(0xFF8B5CF6), // violet
  Color(0xFFFF4D6D), // red
  Color(0xFFEC4899), // pink
  Color(0xFF38BDF8), // sky
  Color(0xFF10B981), // emerald
];

/// Paleta para classes NOVAS (promovidas de "Outros": Bitter Rot, Frost, ...),
/// escolhida para não colidir com as 5 cores canónicas das classes treinadas.
const List<Color> kNoveltyPalette = [
  Color(0xFF38BDF8), // azul-céu
  Color(0xFFA3E635), // lima
  Color(0xFF818CF8), // índigo claro
  Color(0xFF2DD4BF), // teal
  Color(0xFFFB923C), // laranja
  Color(0xFFA78BFA), // lilás
  Color(0xFF94A3B8), // cinza-azulado
  Color(0xFFFACC15), // amarelo
];

/// Cor para QUALQUER classe: as 5 canónicas usam a paleta oficial; classes
/// desconhecidas recebem uma cor determinística (hash do nome → novelty
/// palette), estável entre sessões e distinta entre si.
Color classColorExt(String c) {
  if (kClassOrder.contains(c)) return classColor(c);
  final h = c.codeUnits.fold<int>(17, (s, u) => (s * 31 + u) & 0x7fffffff);
  return kNoveltyPalette[h % kNoveltyPalette.length];
}

/// Estilo de texto para eixos/labels dos gráficos.
TextStyle axisStyle({double size = 9, bool bold = false}) => TextStyle(
      color: AppColors.textSecondary,
      fontSize: size,
      fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
    );

/// Linha de grelha subtil coerente com o tema.
Color gridLineColor() => AppColors.textSecondary.withOpacity(0.15);
/// Legenda horizontal compacta (dot + label), reutilizável.
class ChartLegend extends StatelessWidget {
  final List<MapEntry<String, Color>> items;
  final double dotSize;
  final double fontSize;
  final WrapAlignment alignment;

  const ChartLegend({
    super.key,
    required this.items,
    this.dotSize = 9,
    this.fontSize = 10,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final e in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(color: e.value, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 5),
              Text(e.key, style: axisStyle(size: fontSize)),
            ],
          ),
      ],
    );
  }
}

/// Caixa de tooltip flutuante, mesmo estilo escuro/bordado usado em todo o
/// dashboard (fl_chart tem tooltip nativo; isto é para os gráficos
/// hand-rolled com CustomPainter, que não têm).
class FloatingTooltipBox extends StatelessWidget {
  final String? text;
  final Widget? child;
  final double maxWidth;
  const FloatingTooltipBox({super.key, this.text, this.child, this.maxWidth = 220})
      : assert(text != null || child != null, 'FloatingTooltipBox precisa de text ou child');

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: child ?? Text(text!, style: TextStyle(color: AppColors.textPrimary, fontSize: 10.5, height: 1.4)),
      );
}

/// Posiciona um [FloatingTooltipBox] junto do ponto `pos` (coordenadas locais
/// do `Stack` que envolve o CustomPaint), escolhendo o quadrante de ancoragem
/// pelo lado do cursor, assim nunca precisa de medir o tamanho real da
/// caixa para decidir se cabe, e não empurra/redimensiona o resto do layout
/// como um Container fixo abaixo do gráfico faria.
Widget hoverTooltipOverlay({
  required Offset pos,
  required Size containerSize,
  String? text,
  Widget? child,
  double maxWidth = 220,
}) {
  // Prefere sempre à direita, a não ser que esteja colado à borda direita
  final anchorRight = pos.dx < containerSize.width - 240;
  // Prefere sempre acima do rato (anchorBottom = false), a não ser que não haja espaço em cima
  final anchorBottom = pos.dy < 140;
  return Positioned(
    left: anchorRight ? pos.dx + 12 : null,
    right: anchorRight ? null : containerSize.width - pos.dx + 12,
    top: anchorBottom ? pos.dy + 12 : null,
    bottom: anchorBottom ? null : containerSize.height - pos.dy + 12,
    child: IgnorePointer(child: FloatingTooltipBox(text: text, child: child, maxWidth: maxWidth)),
  );
}
