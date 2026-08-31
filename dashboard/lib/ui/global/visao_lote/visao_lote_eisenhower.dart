part of '../../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// VISÃO LOTE · MATRIZ DE EISENHOWER
// Matriz de prioridade urgência × impacto, com o campo de bolhas interativo por maçã.
// ═══════════════════════════════════════════════════════════


Widget eisenhowerMatrix(Batch batch, {List<CorrectionHistory> corrections = const []}) {
  return EisenhowerMatrixCard(batch: batch, corrections: corrections);
}

class EisenhowerMatrixCard extends StatefulWidget {
  final Batch batch;
  final List<CorrectionHistory> corrections;

  const EisenhowerMatrixCard({super.key, required this.batch, required this.corrections});

  @override
  State<EisenhowerMatrixCard> createState() => _EisenhowerMatrixCardState();
}

class _EisenhowerMatrixCardState extends State<EisenhowerMatrixCard> {
  bool _showGauge = false;

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;

    // Pesos base por doença (contágio = propensão a alastrar; econ = perda de valor).
    const meta = {
      'Rot': {'contagion': 0.95, 'econ': 0.90},
      'Anthracnose': {'contagion': 0.85, 'econ': 0.85},
      'Blotch': {'contagion': 0.55, 'econ': 0.40},
      'Scab': {'contagion': 0.35, 'econ': 0.60},
    };
    (double, double) weightsFor(String cls) {
      final m = meta[cls];
      if (m != null) return (m['contagion'] as double, m['econ'] as double);
      return (0.60, 0.60); // fallback para doenças "Outros" pós-manual
    }

    final dist = batch.healthDistribution;
    final total = batch.totalApples > 0 ? batch.totalApples : 1;

    // Agrupa maçãs pela ASSINATURA de multi-classe (conjunto de classes >5%).
    // Cada assinatura → 1 bolha; guarda confianças por classe (p/ média = fatia).
    final groups = <String, ({List<String> classes, Map<String, List<double>> confs, List<double> sevs})>{};
    for (final a in batch.apples) {
      if (a.primaryCondition == 'Healthy') continue;
      final sevVal = (a.worstFrame?.diseaseSum ?? a.effectiveConfidence).clamp(0.0, 1.0).toDouble();

      // Só as 5 classes da IA têm contágio/impacto económico definidos
      // (weightsFor), rótulos de correção manual fora desse conjunto
      // (Lixo, Frost, Stinkbug, ...) não têm severidade real associada,
      // por isso esta matriz usa sempre a classificação do worst frame da
      // CNN, nunca a etiqueta livre de uma correção humana.
      final probs = a.worstFrame?.probabilities ?? const <String, double>{};
      final confOf = <String, double>{};
      probs.forEach((k, v) {
        if (k != 'Healthy' && v > 0.05) confOf[k] = v;
      });
      if (confOf.isEmpty) continue;
      final classes = confOf.keys.toList()..sort();
      final key = classes.join(' + ');
      final g = groups.putIfAbsent(
          key, () => (classes: classes, confs: <String, List<double>>{}, sevs: <double>[]));
      confOf.forEach((k, v) => g.confs.putIfAbsent(k, () => <double>[]).add(v));
      g.sevs.add(sevVal);
    }

    final bubbles = groups.values.map((g) {
      final count = g.sevs.length;
      final avgSev = g.sevs.isEmpty ? 0.5 : g.sevs.reduce((a, b) => a + b) / g.sevs.length;
      // Fatia de cada classe = confiança média nessa classe; normalizada.
      final avgConf = <String, double>{};
      for (final c in g.classes) {
        final l = g.confs[c] ?? const <double>[];
        avgConf[c] = l.isEmpty ? 0.0 : l.reduce((a, b) => a + b) / l.length;
      }
      final sumConf = avgConf.values.fold(0.0, (a, b) => a + b);
      final slices = [
        for (final c in g.classes)
          _EisenSlice(c, sumConf > 0 ? avgConf[c]! / sumConf : 1.0 / g.classes.length, _eisenColorForClass(c)),
      ];
      // Posição pela mistura ponderada das fatias.
      double wCont = 0, wEcon = 0;
      for (final s in slices) {
        final w = weightsFor(s.cls);
        wCont += s.frac * w.$1;
        wEcon += s.frac * w.$2;
      }
      final x = (wEcon * (0.55 + 0.45 * avgSev) * 100).clamp(4.0, 98.0).toDouble();
      final y = (wCont * (0.30 + 0.70 * avgSev) * 100).clamp(4.0, 98.0).toDouble();
      final action = (y >= 50 && x >= 50)
          ? 'Fazer agora'
          : (y < 50 && x >= 50)
              ? 'Agendar'
              : (y >= 50 && x < 50)
                  ? 'Monitorizar'
                  : 'Ignorar';
      final radius = (6.0 + 3.5 * sqrt(count.toDouble())).clamp(6.0, 34.0).toDouble();
      return _EisenBubble(
        label: g.classes.map(_eisenDisplay).join(' + '),
        x: x, y: y, radius: radius, count: count, sev: avgSev, action: action, slices: slices,
      );
    }).toList()
      ..sort((a, b) => b.radius.compareTo(a.radius)); // maiores primeiro (pequenas por cima)

    int qNow = 0, qSched = 0, qMon = 0, qIgn = 0;
    for (final b in bubbles) {
      switch (b.action) {
        case 'Fazer agora': qNow += b.count; break;
        case 'Agendar': qSched += b.count; break;
        case 'Monitorizar': qMon += b.count; break;
        default: qIgn += b.count;
      }
    }

    Widget corner(String label, int count, Color c, {bool right = false}) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
            Text('$count maçãs', style: TextStyle(color: c.withValues(alpha: 0.85), fontSize: 9)),
          ],
        );

    // 3.D · Badge de pressão fitossanitária (absorve o gauge): o índice
    // composto passa a número de contexto subordinado à matriz acionável.
    final propagacao = (batch.contaminationScore * 100).clamp(0.0, 100.0);
    final danoComercial = (batch.severityScore * 100).clamp(0.0, 100.0);
    final taxaDoenca = ((1 - (dist['Healthy'] ?? 0) / total) * 100).clamp(0.0, 100.0);
    double shannon = 0;
    for (final d in ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose']) {
      final p = (dist[d] ?? 0) / total;
      if (p > 0) shannon -= p * log(p) / log(2);
    }
    final diversidade = ((shannon / (log(5) / log(2))) * 100).clamp(0.0, 100.0);
    final pressure =
        (propagacao * 0.30 + danoComercial * 0.25 + taxaDoenca * 0.30 + diversidade * 0.15) / 100.0;
    final pressureColor =
        pressure >= 0.65 ? Colors.redAccent : pressure >= 0.35 ? Colors.amber : AppColors.healthy;
    final pressureLevel = pressure >= 0.65 ? 'CRÍTICA' : pressure >= 0.35 ? 'MODERADA' : 'BAIXA';

    final pressureBadge = Builder(builder: (context) {
      return Tooltip(
        message: 'Clique para ver o Gauge detalhado.\n\n'
            'Pressão fitossanitária composta: ${(pressure * 100).toStringAsFixed(0)}/100\n\n'
            'Propagação (30%): ${propagacao.toStringAsFixed(0)}\n'
            'Dano Comercial (25%): ${danoComercial.toStringAsFixed(0)}\n'
            'Taxa de Doença (30%): ${taxaDoenca.toStringAsFixed(0)}\n'
            'Diversidade Shannon (15%): ${diversidade.toStringAsFixed(0)}\n\n'
            'A matriz diz QUAL doença tratar; este índice diz COM QUE agressividade.',
        padding: const EdgeInsets.all(12),
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _showGauge = true);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: pressureColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: pressureColor.withValues(alpha: 0.45)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: pressure.clamp(0.0, 1.0),
                    strokeWidth: 3,
                    backgroundColor: pressureColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(pressureColor),
                  ),
                ]),
              ),
              const SizedBox(width: 6),
              Text('Pressão ${(pressure * 100).toStringAsFixed(0)} · $pressureLevel',
                  style: TextStyle(color: pressureColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      );
    });

    final matrixContent = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: Row(children: [
              const Icon(Icons.widgets, color: Colors.indigoAccent, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text('Matriz de Ação Estratégica',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            pressureBadge,
            const SizedBox(width: 8),
            Tooltip(
              message: 'Eixo Y = Urgência (contágio × prevalência real no lote)\n'
                       'Eixo X = Impacto (peso económico × severidade média real)\n'
                       'Tamanho da bolha = nº de maçãs afetadas.\n\n'
                       'Fazer agora (↗) · Agendar (↘) · Monitorizar (↖) · Ignorar (↙)',
              padding: const EdgeInsets.all(12),
              textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11),
              decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
              ),
              child: Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
            ),
          ]),
        ]),
        Text('Posição data-driven pela prevalência e severidade reais deste lote',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 16),
        if (bubbles.isEmpty)
          Expanded(child: Center(child: Text('Sem patologias ativas neste lote', style: TextStyle(color: AppColors.textSecondary))))
        else
          Expanded(
            child: BrushZoomViewer(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: Container(color: Colors.lightBlueAccent.withValues(alpha: 0.12))),
                            Expanded(child: Container(color: Colors.redAccent.withValues(alpha: 0.14))),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: Container(color: Colors.green.withValues(alpha: 0.12))),
                            Expanded(child: Container(color: Colors.orangeAccent.withValues(alpha: 0.12))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: _EisenBubbleField(bubbles: bubbles, batch: batch),
                  ),
                  Positioned(
                    left: 0, right: 0, bottom: 2,
                    child: Center(
                      child: Text('Impacto (severidade económica)',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Positioned(
                    left: 2, top: 0, bottom: 0,
                    child: Center(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Text('Urgência',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  Positioned(top: 6, right: 8, child: corner('Fazer agora', qNow, Colors.redAccent, right: true)),
                  Positioned(bottom: 6, right: 8, child: corner('Agendar', qSched, Colors.orangeAccent, right: true)),
                  Positioned(top: 6, left: 8, child: corner('Monitorizar', qMon, Colors.lightBlueAccent)),
                  Positioned(bottom: 6, left: 8, child: corner('Ignorar', qIgn, Colors.green)),
                ],
              ),
            ),
          ),
      ]);

    return GlassCard(
      height: 380,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOutCirc,
        switchOutCurve: Curves.easeInCirc,
        transitionBuilder: (child, animation) {
          return ScaleTransition(
            scale: animation,
            alignment: Alignment.topRight, // Nasce do canto superior direito (botão)
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: _showGauge
            ? Container(
                key: const ValueKey('gauge'),
                padding: const EdgeInsets.all(20),
                child: Stack(
                  children: [
                    phytosanitaryPressureGauge(batch),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Voltar à Matriz',
                        onPressed: () => setState(() => _showGauge = false),
                        style: IconButton.styleFrom(backgroundColor: Colors.black26),
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                key: const ValueKey('matrix'),
                padding: const EdgeInsets.all(20),
                child: matrixContent,
              ),
      ),
    );
  }
}

// ── Eisenhower: bolhas multi-classe (uma bolha por assinatura) ────────────

class _EisenSlice {
  final String cls;
  final double frac;
  final Color color;
  const _EisenSlice(this.cls, this.frac, this.color);
}

class _EisenBubble {
  final String label;
  final double x, y, radius, sev;
  final int count;
  final String action;
  final List<_EisenSlice> slices;
  const _EisenBubble({
    required this.label,
    required this.x,
    required this.y,
    required this.radius,
    required this.count,
    required this.sev,
    required this.action,
    required this.slices,
  });
}

const _eisenKnownClasses = {'Rot', 'Scab', 'Blotch', 'Anthracnose', 'Healthy'};

Color _eisenColorForClass(String cls) {
  if (_eisenKnownClasses.contains(cls)) return AppColors.getColorForCondition(cls);
  // Cor estável por hash para doenças "Outros" pós-manual (Frost, Bitter rot…).
  final h = cls.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  return HSVColor.fromAHSV(1.0, (h % 360).toDouble(), 0.55, 0.88).toColor();
}

String _eisenDisplay(String cls) =>
    _eisenKnownClasses.contains(cls) ? AppColors.displayName(cls) : cls;

/// Campo de bolhas do Eisenhower: cada bolha = uma assinatura multi-classe,
/// desenhada como setores (fatia = confiança média por classe). Hover mostra o
/// detalhe. Mapeia x/y (0–100) para toda a área para alinhar com os quadrantes.
class _EisenBubbleField extends ConsumerStatefulWidget {
  final List<_EisenBubble> bubbles;
  final Batch batch;
  const _EisenBubbleField({required this.bubbles, required this.batch});

  @override
  ConsumerState<_EisenBubbleField> createState() => _EisenBubbleFieldState();
}

class _EisenBubbleFieldState extends ConsumerState<_EisenBubbleField> {
  int _hover = -1;
  Offset? _pos;

  Offset _center(_EisenBubble b, Size size) =>
      Offset(b.x / 100 * size.width, (1 - b.y / 100) * size.height);

  void _update(Offset p, Size size) {
    int found = -1;
    double best = double.infinity;
    for (int i = 0; i < widget.bubbles.length; i++) {
      final b = widget.bubbles[i];
      final d = (_center(b, size) - p).distance;
      if (d <= b.radius && d < best) {
        best = d;
        found = i;
      }
    }
    if (found != _hover || p != _pos) {
      setState(() {
        _hover = found;
        _pos = p;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final size = Size(cons.maxWidth, cons.maxHeight);
      return MouseRegion(
        onHover: (e) => _update(e.localPosition, size),
        onExit: (_) => setState(() {
          _hover = -1;
          _pos = null;
        }),
        child: GestureDetector(
          onTapUp: (_) {
            if (_hover >= 0 && _hover < widget.bubbles.length) {
              final b = widget.bubbles[_hover];
              
              // 1. Limpa os filtros
              ref.read(selectedConditionFilterProvider.notifier).resetFilter();
              
              // 1.5. Ativa multiclasse automaticamente se a bolha tiver várias classes
              if (b.slices.length > 1) {
                ref.read(multiClassFilterProvider.notifier).set(true);
              } else {
                ref.read(multiClassFilterProvider.notifier).set(false);
              }
              
              // 2. Ativa as doenças correspondentes a esta bolha
              for (final slice in b.slices) {
                if (slice.cls != 'Healthy') {
                  // Apenas adiciona ao filtro visual/ativo se a doença existir como primária neste lote
                  if ((widget.batch.healthDistribution[slice.cls] ?? 0) > 0) {
                    ref.read(selectedConditionFilterProvider.notifier).toggleFilter(slice.cls);
                  }
                }
              }
              
              // 3. Muda para a página de Grelha (Visão detalhada das maçãs)
              ref.read(currentPageProvider.notifier).setPage('Grelha Lote');
            }
          },
          child: Stack(children: [
            CustomPaint(size: Size.infinite, painter: _EisenPainter(widget.bubbles, _hover)),
            if (_hover >= 0 && _pos != null) _tooltip(widget.bubbles[_hover], _pos!, size),
          ]),
        ),
      );
    });
  }

  Widget _tooltip(_EisenBubble b, Offset p, Size size) {
    const w = 196.0;
    double left = p.dx + 14;
    if (left + w > size.width) left = size.width - w - 4;
    if (left < 0) left = 0;
    double top = p.dy + 14;
    if (top + 82 > size.height) top = p.dy - 82;
    if (top < 0) top = 0;
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: w,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.isDark ? Colors.white24 : Colors.black12),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.label, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 3),
            Text('${b.action} · ${b.count} maçã${b.count != 1 ? 's' : ''}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
            Text('Impacto ${b.x.toInt()} · Urgência ${b.y.toInt()} · Sev ${(b.sev * 100).toInt()}%',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
            const SizedBox(height: 4),
            for (final s in b.slices)
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: s.color)),
                  const SizedBox(width: 5),
                  Text('${_eisenDisplay(s.cls)} ${(s.frac * 100).round()}%',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _EisenPainter extends CustomPainter {
  final List<_EisenBubble> bubbles;
  final int highlight;
  _EisenPainter(this.bubbles, this.highlight);

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < bubbles.length; i++) {
      final b = bubbles[i];
      final c = Offset(b.x / 100 * size.width, (1 - b.y / 100) * size.height);
      final isHi = i == highlight;
      if (b.slices.length <= 1) {
        final col = b.slices.isEmpty ? Colors.grey : b.slices.first.color;
        canvas.drawCircle(c, b.radius, Paint()..color = col.withValues(alpha: 0.85));
      } else {
        double start = -pi / 2;
        for (final s in b.slices) {
          final sweep = s.frac * 2 * pi;
          canvas.drawArc(Rect.fromCircle(center: c, radius: b.radius), start, sweep, true,
              Paint()..color = s.color.withValues(alpha: 0.85));
          start += sweep;
        }
        // Separadores brancos entre fatias.
        double a = -pi / 2;
        for (final s in b.slices) {
          final dir = Offset(cos(a), sin(a));
          canvas.drawLine(c, c + dir * b.radius,
              Paint()
                ..color = Colors.white.withValues(alpha: 0.55)
                ..strokeWidth = 1);
          a += s.frac * 2 * pi;
        }
      }
      canvas.drawCircle(
        c,
        b.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHi ? 2.6 : 1.3
          ..color = Colors.white.withValues(alpha: isHi ? 0.95 : 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EisenPainter old) =>
      old.bubbles != bubbles || old.highlight != highlight;
}
