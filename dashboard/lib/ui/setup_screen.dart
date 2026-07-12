import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/dashboard_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/constants.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/tech_grid_background.dart';


class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final Set<Batch> _selectedBatches = {};
  final TextEditingController _blocoController = TextEditingController();
  final TextEditingController _filaController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();

  @override
  void dispose() {
    _blocoController.dispose();
    _filaController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(loadDataFutureProvider);
    final user = ref.watch(authProvider)!;
    final availableBatches = ref.watch(availableBatchesProvider);

    return TechGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Container(
            width: 600,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bom dia, ${user.username}!',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Em que localizações decorrerá a triagem de hoje?',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
              ),
              const SizedBox(height: 32),
              if (availableBatches.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Lotes Existentes:', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 280, // Aumentado para mostrar 4 lotes
                  child: Scrollbar(
                    controller: _listScrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 4,
                    radius: const Radius.circular(10),
                    child: ListView(
                      controller: _listScrollController,
                      padding: const EdgeInsets.only(right: 12),
                      children: availableBatches.map((batch) {
                        final isSelected = _selectedBatches.contains(batch);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedBatches.clear();
                                if (isSelected) {
                                  // Already cleared
                                } else {
                                  _selectedBatches.add(batch);
                                  _blocoController.clear();
                                  _filaController.clear();
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary.withOpacity(0.1) : (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05),
                                border: Border.all(color: isSelected ? AppColors.primary : (AppColors.isDark ? Colors.white10 : Colors.black12), width: 1.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.inventory_2, color: isSelected ? AppColors.primary : (AppColors.isDark ? Colors.white38 : Colors.black38), size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(batch.id, style: TextStyle(color: isSelected ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: FontWeight.bold)),
                                        Text('${batch.totalApples} maçãs inspecionadas', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                  if (isSelected) Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(child: Divider(color: AppColors.isDark ? Colors.white10 : Colors.black12)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('OU', style: TextStyle(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.1), fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: Divider(color: AppColors.isDark ? Colors.white10 : Colors.black12)),
                ]),
                const SizedBox(height: 24),
              ],
              const SizedBox(height: 32),
              Text('Identificação do Lote (RF02):', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _blocoController,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Bloco (ex: A, B, Norte)',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: Colors.black12,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _filaController,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Fila (ex: 4, 12, SUL)',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: Colors.black12,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_selectedBatches.isNotEmpty || (_blocoController.text.isNotEmpty && _filaController.text.isNotEmpty)) ? AppColors.healthy : Colors.grey[700],
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                ),
                onPressed: (_selectedBatches.isEmpty && (_blocoController.text.isEmpty || _filaController.text.isEmpty))
                    ? null
                    : () {
                        if (_selectedBatches.isNotEmpty) {
                          ref.read(batchProvider.notifier).setBatch(_selectedBatches.first);
                        } else {
                          // Create a custom batch based on input
                          final customBatch = Batch(
                            id: '${_blocoController.text}-${_filaController.text}',
                            name: 'Lote Manual',
                            date: DateTime.now(),
                            apples: [],
                          );
                          ref.read(batchProvider.notifier).setBatch(customBatch);
                        }
                        
                        ref.read(sessionActiveProvider.notifier).setActive(true);
                        
                        if (user.role == UserRole.admin) {
                          ref.read(currentPageProvider.notifier).setPage('Controlo do Pomar');
                        } else {
                          ref.read(currentPageProvider.notifier).setPage('Triagem Manual');
                        }
                      },
                child: Text('Iniciar Triagem Manual', style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}