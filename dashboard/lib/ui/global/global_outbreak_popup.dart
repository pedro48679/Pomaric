part of '../global_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// CONTROLO DO POMAR · POPUP DE ALERTA DE SURTO
// Sobreposição, ao nível da tela, que avisa de um surto ativo.
// ═══════════════════════════════════════════════════════════

// ── Popup de Alerta de Surto ────────────────────────────────────────────────
// Cartão limpo e discreto (sem barra de título estilo "janela 2008"), com
// animação de entrada suave, minimização "genie-like" (encolhe para um canto,
// como minimizar uma janela no macOS) e saída animada antes de ser descartado.
class _OutbreakAlertPopup extends StatefulWidget {
  final List<Batch> riskBatches;
  final bool showSystemSurge;
  final VoidCallback onDismiss;

  const _OutbreakAlertPopup({
    required this.riskBatches,
    required this.showSystemSurge,
    required this.onDismiss,
  });

  @override
  State<_OutbreakAlertPopup> createState() => _OutbreakAlertPopupState();
}

class _OutbreakAlertPopupState extends State<_OutbreakAlertPopup> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _entrance;

  bool _minimized = false;
  bool _expanded = false;
  bool _dismissing = false;
  
  bool _showLogs = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _entrance = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    setState(() => _dismissing = true);
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    String mainPathology = 'Healthy';
    if (widget.riskBatches.isNotEmpty) {
      final counts = <String, int>{};
      for (final b in widget.riskBatches) {
        final dom = getDominantDiseaseENForBatch(b);
        counts[dom] = (counts[dom] ?? 0) + 1;
      }
      var maxVal = -1;
      counts.forEach((k, v) {
        if (v > maxVal) {
          maxVal = v;
          mainPathology = k;
        }
      });
    } else if (widget.showSystemSurge) {
      mainPathology = 'Rot';
    }

    final mainPathologyLabel = mainPathology == 'Rot'
        ? 'Rot'
        : mainPathology == 'Scab'
            ? 'Scab'
            : mainPathology == 'Blotch'
                ? 'Sooty Blotch'
                : mainPathology == 'Anthracnose'
                    ? 'Anthracnose'
                    : 'Estável';

    double avgUrgency = 0.0;
    if (widget.riskBatches.isNotEmpty) {
      avgUrgency = widget.riskBatches.map((b) => b.urgencyScore).reduce((a, b) => a + b) / widget.riskBatches.length;
    } else if (widget.showSystemSurge) {
      avgUrgency = 0.6;
    }

    String threatLevelText = 'BAIXO (EM ANÁLISE)';
    Color threatColor = AppColors.textSecondary; // Menos intrusivo para casos menos urgentes
    double progressValue = 0.33;
    if (avgUrgency > 0.45) {
      threatLevelText = 'CRÍTICO';
      threatColor = Colors.redAccent;
      progressValue = 1.0;
    } else if (avgUrgency > 0.20) {
      threatLevelText = 'MODERADO';
      threatColor = Colors.orangeAccent;
      progressValue = 0.66;
    }

    // Se a ameaça é baixa, o popup minimiza-se ao início para não interromper muito, 
    // a não ser que tenha sido aberto manualmente.
    // (Poderíamos inicializar _minimized = true no initState, mas faremos apenas estilo visual menos intrusivo)

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) => Opacity(
        opacity: _entrance.value,
        child: Transform.scale(
          scale: 0.92 + 0.08 * _entrance.value,
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          // Encolhe/expande a partir do canto inferior direito, com fade -
          // aproximação do efeito "genie" de minimizar uma janela no macOS.
          return ScaleTransition(
            scale: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
            alignment: Alignment.bottomRight,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: _minimized
            ? _buildMinimizedIcon(threatColor)
            : _buildExpandedCard(mainPathologyLabel, threatLevelText, threatColor, progressValue, mainPathology),
      ),
    );
  }

  Widget _buildMinimizedIcon(Color threatColor) {
    return GestureDetector(
      key: const ValueKey('minimized'),
      onTap: () => setState(() => _minimized = false),
      child: Tooltip(
        message: 'Reabrir alerta de surto',
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: threatColor.withValues(alpha: 0.45), width: 1.2),
            boxShadow: [
              BoxShadow(color: threatColor.withValues(alpha: 0.18), blurRadius: 10, spreadRadius: 1),
            ],
          ),
          child: Center(
            child: Icon(Icons.warning_amber_rounded, color: threatColor, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedCard(String pathologyLabel, String threatLevelText, Color threatColor, double progressValue, String mainPathology) {
    final allDiseases = ['Rot', 'Anthracnose', 'Bitter Rot', 'Scab', 'Brown Rot', 'Stinkbug', 'Frost', 'Blotch', 'Sunburn'];
    final presentDiseases = <String>{};
    if (mainPathology != 'Healthy') presentDiseases.add(mainPathology);
    for (final b in widget.riskBatches) {
      final dom = getDominantDiseaseENForBatch(b);
      if (dom != 'Healthy') presentDiseases.add(dom);
    }
    
    final sortedDiseases = [...allDiseases];
    sortedDiseases.sort((a, b) {
      final aPresent = presentDiseases.contains(a);
      final bPresent = presentDiseases.contains(b);
      if (aPresent && !bPresent) return -1;
      if (!aPresent && bPresent) return 1;
      return 0;
    });

    String alertTitle = threatLevelText == 'CRÍTICO' ? 'Alerta Crítico' : 'Aviso de Surto';
    return Container(
      key: const ValueKey('expanded'),
      width: 320,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: threatColor.withValues(alpha: 0.7), width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppColors.isDark ? 0.35 : 0.10),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: threatColor, size: 16),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      alertTitle,
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  _iconGhostButton(Icons.remove_rounded, 'Minimizar', () => setState(() => _minimized = true)),
                  const SizedBox(width: 2),
                  _iconGhostButton(Icons.close_rounded, 'Descartar', _dismissing ? null : _handleDismiss),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'RISCO BIOLÓGICO DETETADO',
                style: TextStyle(color: threatColor.withValues(alpha: 0.85), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.4),
              ),
              const SizedBox(height: 3),
              Text(
                pathologyLabel,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Nível de Ameaça', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                  Text(threatLevelText, style: TextStyle(color: threatColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 4,
                  backgroundColor: AppColors.surfaceBright,
                  valueColor: AlwaysStoppedAnimation(threatColor),
                ),
              ),
              if (widget.riskBatches.isNotEmpty) ...[
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Outros lotes afetados', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                        Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.textSecondary, size: 16),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: !_expanded
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (_) => true, // impede que o scroll feche o cabeçalho
                              child: SingleChildScrollView(
                                child: Column(
                                  children: widget.riskBatches.map((b) {
                                    final bDom = getDominantDiseaseENForBatch(b);
                                    final bDomLabel = AppColors.displayName(bDom);
                                    final condColor = AppColors.getColorForCondition(bDom);
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(b.id, style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                                              Text(bDomLabel.toUpperCase(), style: TextStyle(color: condColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(2),
                                            child: LinearProgressIndicator(
                                              value: b.urgencyScore,
                                              minHeight: 3,
                                              backgroundColor: AppColors.surfaceBright,
                                              valueColor: AlwaysStoppedAnimation(condColor),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
              
              // Botão de Guia Agronómico
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _showLogs = !_showLogs),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_showLogs ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'GUIA AGRONÓMICO DE TRATAMENTOS',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Seção de Guia Agronómico Deslizante
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: !_showLogs
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 250),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                          ),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (_) => true, // impede que o scroll esconda o cabeçalho global
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('RECOMENDAÇÕES PARA A TUA TRIAGEM', style: TextStyle(color: AppColors.textSecondary, fontSize: 8, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),
                                  ...sortedDiseases.map((d) => _buildGuideEntry(d, _getSuggestionForDisease(d))),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconGhostButton(IconData icon, String tooltip, VoidCallback? onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, color: AppColors.textSecondary, size: 15),
        ),
      ),
    );
  }

  String _getSuggestionForDisease(String disease) {
    switch (disease) {
      case 'Rot':
        return 'Isolar lote, higienizar caixas e manter armazenamento rigoroso a 0.5-1.5°C para travar esporos. (Comum: Pós-colheita / Armazenamento)';
      case 'Anthracnose':
        return 'Fungo agressivo em armazenamento quente. Reduzir temperatura e segregar imediatamente. (Comum: Final do Verão / Outono)';
      case 'Bitter Rot':
        return 'Podridão amarga com rápida propagação. Isolar lote e aplicar medidas sanitárias contíguas. (Comum: Verão quente e húmido)';
      case 'Scab':
        return 'Rever circulação de ar/humidade. Remover frutos afetados para evitar contaminação por contacto. (Comum: Primavera chuvosa)';
      case 'Brown Rot':
        return 'Podridão parda grave. Descartar frutos afetados e verificar higienização das escovas da linha. (Comum: Primavera / Verão)';
      case 'Stinkbug':
      case 'Stink Bug':
        return 'Danos causados por percevejo. Inspecionar o pomar de origem para pragas ativas; o fruto pode seguir para sumo. (Comum: Final do Verão)';
      case 'Frost':
        return 'Dano por geada visível na epiderme. Redirecionar para categorias inferiores ou processamento. (Comum: Primavera / Outono)';
      case 'Blotch':
      case 'Sooty Blotch':
        return 'Fungo estético/superficial. Verificar a eficácia das escovas e as condições de lavagem na linha. (Comum: Final do Verão / Outono)';
      case 'Sunburn':
        return 'Dano estético causado por sol/calor. Sem risco infeccioso, separar para mercado secundário ou sumo. (Comum: Verão)';
      default:
        return 'Desvio de qualidade detetado. Manter lote sob observação e rever cadência de processamento da linha.';
    }
  }

  Widget _buildGuideEntry(String disease, String suggestion) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(disease.toUpperCase(), style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(suggestion, style: TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.3)),
        ],
      ),
    );
  }
}
