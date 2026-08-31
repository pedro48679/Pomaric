import 'package:flutter/material.dart';
import '../../../utils/constants.dart';
import '../mlops_models.dart';

class MlopsConfigPanel extends StatelessWidget {
  final BuildContext parentContext;
  final List<ClassInfo> classes;
  final Set<String> selectedClasses;
  final Set<String> selectedDiseases;
  final bool isBinary;
  final int epochs;
  final double hardThreshold;
  final int minImages;
  final int maxImages;
  final int batchSize;
  final double lr;
  final TrainingStatus status;
  final bool serverOnline;
  final String architecture;

  final ValueChanged<Set<String>> onSelectedClassesChanged;
  final ValueChanged<Set<String>> onSelectedDiseasesChanged;
  final VoidCallback onSelectCnn2;
  final VoidCallback onSelectCnn5;
  final ValueChanged<String> onArchitectureChanged;
  final ValueChanged<int> onEpochsChanged;
  final ValueChanged<double> onHardThresholdChanged;
  final ValueChanged<int> onMinImagesChanged;
  final ValueChanged<int> onMaxImagesChanged;
  final ValueChanged<int> onBatchSizeChanged;
  
  final VoidCallback onStartTraining;
  final VoidCallback onCancelTraining;

  const MlopsConfigPanel({
    super.key,
    required this.parentContext,
    required this.classes,
    required this.selectedClasses,
    required this.selectedDiseases,
    required this.isBinary,
    required this.epochs,
    required this.hardThreshold,
    required this.minImages,
    required this.maxImages,
    required this.batchSize,
    required this.lr,
    required this.status,
    required this.serverOnline,
    required this.architecture,
    required this.onSelectedClassesChanged,
    required this.onSelectedDiseasesChanged,
    required this.onSelectCnn2,
    required this.onSelectCnn5,
    required this.onArchitectureChanged,
    required this.onEpochsChanged,
    required this.onHardThresholdChanged,
    required this.onMinImagesChanged,
    required this.onMaxImagesChanged,
    required this.onBatchSizeChanged,
    required this.onStartTraining,
    required this.onCancelTraining,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Título
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: [
                  Icon(Icons.tune, color: AppColors.primary, size: 16),
                  const SizedBox(width: 6),
                  Text('Configuração de Treino',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Divider(color: AppColors.glassBorder, height: 1),

            // Toggle CNN2 / CNN5
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Expanded(child: _cnnModeBtn(
                    label: 'CNN2', sub: 'Binário',
                    active: isBinary,
                    activeColor: AppColors.primary,
                    onTap: status.isActive ? null : onSelectCnn2,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _cnnModeBtn(
                    label: 'CNN5', sub: 'Multiclasse',
                    active: !isBinary,
                    activeColor: const Color(0xFF8B5CF6),
                    onTap: status.isActive ? null : onSelectCnn5,
                  )),
                ],
              ),
            ),

            Divider(color: AppColors.glassBorder, height: 1),

            // Classes a treinar
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text('Classes a treinar',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ),
            if (classes.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Text('Sem dados. Inicia o servidor.',
                    style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.6),
                        fontSize: 11)),
              )
            else if (isBinary)
              _buildBinaryClassList()
            else
              ...classes.map((cls) => _classCheckbox(cls)),

            Divider(color: AppColors.glassBorder, height: 1),

            // Arquitetura
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Arquitetura',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: architecture,
                    dropdownColor: AppColors.surface,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.glassBorder)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.glassBorder)),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'mobilenet_v2',
                          child: Text('MobileNetV2 (rápido)')),
                      DropdownMenuItem(
                          value: 'resnet50', child: Text('ResNet50 (preciso)')),
                    ],
                    onChanged: status.isActive
                        ? null
                        : (v) => onArchitectureChanged(v!),
                  ),
                ],
              ),
            ),

            Divider(color: AppColors.glassBorder, height: 1),

            // Sliders
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Builder(
                builder: (context) {
                  final totalImgs = classes.fold(0, (s, c) => s + c.count);
                  double sMin = 10;
                  double sMax = totalImgs > 0 ? (totalImgs * 0.3).clamp(100.0, 5000.0) : 100.0;
                  if (minImages > sMax) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      onMinImagesChanged(sMax.round());
                    });
                  } else if (minImages < sMin) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      onMinImagesChanged(sMin.round());
                    });
                  }
                  int sDivs = (sMax - sMin) > 0 ? ((sMax - sMin) ~/ 10) : 90;
                  if (sDivs < 1) sDivs = 1;
                  if (sDivs > 200) sDivs = 200;

                  return Column(
                    children: [
                      _cfgSlider('Épocas', epochs.toDouble(), 5, 50, 45, context,
                          valueLabel: epochs.toString(),
                          onChanged: (v) => onEpochsChanged(v.round())),
                      const SizedBox(height: 8),
                      _cfgSlider(
                          'Hard Case threshold',
                          hardThreshold,
                          0.5,
                          0.95,
                          45, context,
                          valueLabel: hardThreshold.toStringAsFixed(2),
                          onChanged: (v) => onHardThresholdChanged(v)),
                      const SizedBox(height: 8),
                      _cfgSlider('Min. imagens/classe', minImages.toDouble().clamp(sMin, sMax), sMin,
                          sMax, sDivs, context,
                          valueLabel: minImages.toString(),
                          onChanged: (v) => onMinImagesChanged(v.round())),
                      const SizedBox(height: 8),
                      _cfgSlider('Max. imagens/classe', maxImages.toDouble(), 100,
                          5000, 49, context,
                          valueLabel: maxImages.toString(),
                          onChanged: (v) => onMaxImagesChanged(v.round())),
                      const SizedBox(height: 8),
                      _cfgSlider(
                          'Batch size', batchSize.toDouble(), 8, 64, 56, context,
                          valueLabel: batchSize.toString(),
                          onChanged: (v) => onBatchSizeChanged(v.round())),
                    ],
                  );
                },
              ),
            ),

            // Botão Treinar
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: status.isActive
                  ? SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.stop_circle_outlined,
                            color: Colors.red, size: 16),
                        label: const Text('CANCELAR',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: onCancelTraining,
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.model_training,
                            color: AppColors.surface, size: 16),
                        label: Text(
                          'TREINAR NOVO MODELO',
                          style: TextStyle(
                              color: AppColors.surface,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          disabledBackgroundColor:
                              AppColors.textSecondary.withOpacity(0.2),
                        ),
                        onPressed: (selectedClasses.isEmpty || !serverOnline)
                            ? null
                            : onStartTraining,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _classCheckbox(ClassInfo cls) {
    final isSelected = selectedClasses.contains(cls.name);
    final enough = cls.count >= minImages;
    return InkWell(
      onTap: status.isActive
          ? null
          : () {
              final Set<String> newSelection = Set.from(selectedClasses);
              if (isSelected) {
                newSelection.remove(cls.name);
              } else {
                newSelection.add(cls.name);
              }
              onSelectedClassesChanged(newSelection);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: isSelected,
                onChanged: status.isActive
                    ? null
                    : (v) {
                        final Set<String> newSelection = Set.from(selectedClasses);
                        if (v!) {
                          newSelection.add(cls.name);
                        } else {
                          newSelection.remove(cls.name);
                        }
                        onSelectedClassesChanged(newSelection);
                      },
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(cls.name,
                  style: TextStyle(
                      color: enough
                          ? AppColors.textPrimary
                          : AppColors.textSecondary.withOpacity(0.5),
                      fontSize: 12)),
            ),
            Text('${cls.count}',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            if (cls.gold > 0) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Imagens triadas manualmente (ouro): entram no treino com peso reforçado',
                child: Text('+${cls.gold}',
                    style: const TextStyle(
                        color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
            if (cls.hardCases > 0) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Casos difíceis não triados: excluídos do treino, usados na avaliação de generalização',
                child: Text('${cls.hardCases} aval.',
                    style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.6), fontSize: 9)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Botão de seleção de modo CNN (CNN2 / CNN5)
  Widget _cnnModeBtn({
    required String label,
    required String sub,
    required bool active,
    required Color activeColor,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? activeColor.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? activeColor : AppColors.glassBorder,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: active ? activeColor : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: (active ? activeColor : AppColors.textSecondary)
                          .withOpacity(0.7),
                      fontSize: 9)),
            ],
          ),
        ),
      );

  /// Lista de classes em modo CNN2, Healthy (locked) + Unhealthy com sub-itens
  Widget _buildBinaryClassList() {
    final healthyCls =
        classes.where((c) => c.name.toLowerCase() == 'healthy').firstOrNull;
    final diseaseCls =
        classes.where((c) => c.name.toLowerCase() != 'healthy').toList();
    final selectedDiseaseCls = diseaseCls.where((c) => selectedDiseases.contains(c.name)).toList();
    final totalCount = selectedDiseaseCls.fold(0, (s, c) => s + c.count);
    final totalGold = selectedDiseaseCls.fold(0, (s, c) => s + c.gold);
    final totalHardEval = selectedDiseaseCls.fold(0, (s, c) => s + c.hardCases);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Healthy (locked on)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 18, height: 18,
              child: Checkbox(
                value: true, onChanged: null,
                activeColor: AppColors.healthy,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('Healthy', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))),
            Text('${healthyCls?.count ?? 'n/d'}',
                style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
        // Unhealthy group (locked on)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 18, height: 18,
              child: Checkbox(
                value: true, onChanged: null,
                activeColor: AppColors.rot,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('Unhealthy',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
            Text('$totalCount',
                style: TextStyle(color: AppColors.rot, fontSize: 11, fontWeight: FontWeight.w600)),
            if (totalGold > 0) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Imagens triadas manualmente (ouro): entram no treino com peso reforçado',
                child: Text('+$totalGold',
                    style: const TextStyle(
                        color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
            if (totalHardEval > 0) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Casos difíceis não triados: excluídos do treino, usados na avaliação de generalização',
                child: Text('$totalHardEval aval.',
                    style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.6), fontSize: 9)),
              ),
            ],
          ]),
        ),
        // Sub-items indentados, checkboxes interativos para escolher doenças em "Unhealthy"
        ...diseaseCls.map((cls) {
          final checked = selectedDiseases.contains(cls.name);
          return Padding(
            padding: const EdgeInsets.only(left: 40, right: 14, top: 1, bottom: 1),
            child: Row(children: [
              SizedBox(
                width: 9, height: 9,
                child: Checkbox(
                  value: checked,
                  onChanged: status.isActive ? null : (v) {
                    final Set<String> newSelection = Set.from(selectedDiseases);
                    if (v == true) {
                      newSelection.add(cls.name);
                    } else {
                      newSelection.remove(cls.name);
                    }
                    onSelectedDiseasesChanged(newSelection);
                  },
                  activeColor: AppColors.getColorForCondition(cls.name),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(child: Text(cls.name,
                  style: TextStyle(
                    color: checked ? AppColors.textSecondary : AppColors.textSecondary.withOpacity(0.4),
                    fontSize: 11,
                  ))),
              Text('${cls.count}',
                  style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(checked ? 0.7 : 0.3),
                    fontSize: 10,
                  )),
              if (cls.gold > 0) ...[
                const SizedBox(width: 3),
                Tooltip(
                  message: 'Imagens triadas manualmente (ouro): treino com peso reforçado',
                  child: Text('+${cls.gold}',
                      style: TextStyle(
                        color: checked ? Colors.amber : Colors.amber.withOpacity(0.3),
                        fontSize: 9,
                      )),
                ),
              ],
              if (cls.hardCases > 0) ...[
                const SizedBox(width: 3),
                Tooltip(
                  message: 'Não triados: só avaliação, nunca treino',
                  child: Text('${cls.hardCases} aval.',
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(checked ? 0.5 : 0.25),
                        fontSize: 8,
                      )),
                ),
              ],
            ]),
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _cfgSlider(String title, double value, double min, double max,
      int divisions, BuildContext context,
      {required String valueLabel,
      required ValueChanged<double> onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
            Text(valueLabel,
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.textSecondary.withOpacity(0.2),
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withOpacity(0.12),
            disabledThumbColor: AppColors.textSecondary.withOpacity(0.3),
            disabledActiveTrackColor: AppColors.textSecondary.withOpacity(0.3),
          ),
          child: SizedBox(
            height: 24,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: status.isActive ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
