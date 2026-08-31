import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dashboard/models/models.dart';
import 'package:dashboard/providers/dashboard_provider.dart';
import 'package:dashboard/providers/auth_provider.dart';
import 'package:dashboard/utils/constants.dart';
import 'package:dashboard/services/supabase_service.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dashboard/services/local_cache_service.dart';

// Filas e editor movidos para part files: leem e escrevem o estado
// privado da triagem (_activePoints, _selectedPointIndex, ...) e
// chamam setState directamente.
part 'manual_queues.dart';
part 'manual_editor.dart';



class ManualSortingView extends ConsumerStatefulWidget {
  const ManualSortingView({Key? key}) : super(key: key);

  @override
  ConsumerState<ManualSortingView> createState() => _ManualSortingViewState();
}

class _ManualSortingViewState extends ConsumerState<ManualSortingView> {
  List<ManualAnnotation> _activePoints = []; 
  int _selectedPointIndex = 0;
  bool _initialPointModified = false; 
  
  int _selectedTab = 0; // 0 = Principal, 1 = Audit/Histórico
  Set<String> _expandedSections = {}; // Rastreia seções abertas no Gestor

  List<String> _customDiseases = [];

  @override
  void initState() {
    super.initState();
    // Para o Gestor, queremos que o separador padrão seja 'Audit' (index 1)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider);
      if (user?.role == UserRole.admin) {
        setState(() {
           _selectedTab = 1;
           _updateExpandedSections();
        });
      }
      SupabaseService.getCustomDiseases().then((list) {
        if (mounted) setState(() => _customDiseases = list);
      });
    });
  }

  /// Para mudar de lote a meio da triagem, reutiliza o ecrã de escolha de lote
  /// (SetupScreen), que já lista os lotes existentes e faz o setBatch correto.
  /// Desativar a sessão faz o main.dart mostrá-lo; ao escolher lá o lote, a
  /// sessão reativa e a dashboard volta já no lote novo.
  void _changeLote() {
    ref.read(sessionActiveProvider.notifier).setActive(false);
  }

  void _updateExpandedSections() {
    final uncertainApples = ref.read(uncertainApplesProvider);
    final history = ref.read(correctionHistoryProvider);
    final user = ref.read(authProvider);
    
    final visibleUncertain = uncertainApples.where((a) => !_hiddenAppleIds.contains(a.id)).toList();
    final operatorHistory = history.where((h) => h.correctedBy != user?.username).toList();
    final hNormal = operatorHistory.where((h) => ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'].contains(h.label)).toList();
    final hEspecial = operatorHistory.where((h) => !['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'].contains(h.label)).toList();

    List<String> priority = [];
    if (hEspecial.isNotEmpty) priority.add('especial');
    if (visibleUncertain.isNotEmpty) priority.add('triagem');
    if (hNormal.isNotEmpty) priority.add('audit');

    setState(() {
      _expandedSections = priority.take(2).toSet();
    });
  }

  void _toggleSection(String section) {
    setState(() {
      if (_expandedSections.contains(section)) {
        _expandedSections.remove(section);
      } else {
        if (_expandedSections.length >= 2) {
          // Remove a de menor prioridade aberta (audit > triagem > especial)
          if (_expandedSections.contains('audit')) {
            _expandedSections.remove('audit');
          } else if (_expandedSections.contains('triagem')) {
            _expandedSections.remove('triagem');
          } else {
            _expandedSections.clear();
          }
        }
        _expandedSections.add(section);
      }
    });
  }
  
  Apple? _selectedApple;
  CorrectionHistory? _selectedHistory;

  String? _selectedCorrectionLabel;
  final TextEditingController _customLabelController = TextEditingController();
  
  Set<String> _hiddenAppleIds = {}; // Local session state for hidden apples
  bool _showCnnHeatmap = false;
  bool _showOperatorFocus = true;

  // Unified movement and zoom logic to prevent gesture collision
  void _onScaleUpdate(ScaleUpdateDetails details, Size areaSize) {
    if (_activePoints.isEmpty) return;
    
    setState(() {
      final p = _activePoints[_selectedPointIndex];
      
      // Handle Zoom (Pinch)
      if (details.scale != 1.0) {
        _adjustRadius(details.scale > 1.0 ? 1.0 : -1.0);
      }
      
      // Handle Pan (Move)
      if (details.focalPointDelta != Offset.zero) {
        double newX = (p.x + details.focalPointDelta.dx).clamp(0.0, areaSize.width);
        double newY = (p.y + details.focalPointDelta.dy).clamp(0.0, areaSize.height);
        _activePoints[_selectedPointIndex] = ManualAnnotation(
          appleId: p.appleId,
          circleIndex: 0,
          disease: p.disease,
          x: newX,
          y: newY,
          radius: p.radius,
          
        );
        _initialPointModified = true;
      }
    });
  }

  void _adjustRadius(double delta) {
    if (_activePoints.isEmpty) return;
    setState(() {
      final p = _activePoints[_selectedPointIndex];
      final levels = [50.0, 85.0, 105.0, 120.0, 140.0];
      int currentIndex = 0;
      double minDiff = 1000;
      for (int i = 0; i < levels.length; i++) {
        double diff = (p.radius - levels[i]).abs();
        if (diff < minDiff) {
          minDiff = diff;
          currentIndex = i;
        }
      }
      int nextIndex = (currentIndex + (delta > 0 ? 1 : -1)).clamp(0, levels.length - 1);
      _activePoints[_selectedPointIndex] = ManualAnnotation(
        appleId: p.appleId,
        circleIndex: 0,
        disease: p.disease,
        x: p.x,
        y: p.y,
        radius: levels[nextIndex],
        
      );
      _initialPointModified = true;
    });
  }

  void _addPoint() {
    final appleId = _selectedApple?.id ?? _selectedHistory?.appleId ?? 'unknown';
    setState(() {
      _activePoints.add(ManualAnnotation(
        appleId: appleId,
        circleIndex: 0,
        disease: _selectedCorrectionLabel ?? 'Healthy',
        x: 225,
        y: 225,
        radius: 85.0,
      ));
      _selectedPointIndex = _activePoints.length - 1;
      _initialPointModified = true; 
    });
  }

  void _removePoint(int index) {
    setState(() {
      _activePoints.removeAt(index);
      if (_activePoints.isEmpty) {
        _selectedPointIndex = 0;
      } else if (_selectedPointIndex >= _activePoints.length) {
        _selectedPointIndex = _activePoints.length - 1;
      }
      _initialPointModified = true; // Remover também conta como modificação da sugestão inicial
    });
  }
  
  Future<void> _selectApple(Apple apple) async {
    // 1. Verificar se já existem anotações para esta maçã no Supabase
    final existing = await SupabaseService.getAnnotations(apple.id);
    
    setState(() {
      _selectedApple = apple;
      _selectedCorrectionLabel = apple.primaryCondition;
      
      if (existing.isNotEmpty) {
        // Se existem, carregamos e escalamos para o editor (450px)
        _activePoints = existing.map((p) => ManualAnnotation(
          appleId: p.appleId,
          circleIndex: p.circleIndex,
          disease: p.disease,
          x: p.x * 450.0,
          y: p.y * 450.0,
          radius: p.radius * 450.0,
          updatedBy: p.updatedBy,
          crop: p.crop,
        )).toList();
        _initialPointModified = true;
      } else {
        // Sem anotações prévias: começamos com 0 focos em vez de sugerir 1.
        // O operador/gestor tem de clicar em "Novo Foco" se quiser adicionar.
        _activePoints = [];
        _initialPointModified = false;
      }
      
      _selectedPointIndex = 0;
      _customLabelController.clear();
      _selectedHistory = null;
    });
  }

  Future<void> _selectHistory(CorrectionHistory history) async {
    // Se o histórico não tiver anotações em RAM (porque a app reiniciou), vamos buscar ao Supabase.
    List<ManualAnnotation> sourceAnnotations = history.annotations;
    if (sourceAnnotations.isEmpty) {
      sourceAnnotations = await SupabaseService.getAnnotations(history.appleId);
    }

    if (mounted) {
      setState(() {
        _selectedHistory = history;
        // Convertemos as coordenadas normalizadas (0.0-1.0) de volta para pixels do editor (450px)
        _activePoints = sourceAnnotations.map((p) => ManualAnnotation(
          appleId: p.appleId,
          circleIndex: p.circleIndex,
          disease: p.disease,
          x: p.x * 450.0,
          y: p.y * 450.0,
          radius: p.radius * 450.0,
          updatedBy: p.updatedBy,
          crop: p.crop,
        )).toList();
        _selectedPointIndex = 0;
        _selectedApple = null;
        _selectedCorrectionLabel = history.label;
        if (history.label != 'Healthy' && !['Rot', 'Scab', 'Blotch', 'Anthracnose'].contains(history.label)) {
          _selectedCorrectionLabel = 'Outro';
          _customLabelController.text = history.label;
        }
      });
    }
  }
  @override
  void dispose() {
    _customLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isAdmin = user?.role == UserRole.admin;
    
    final uncertainApples = ref.watch(uncertainApplesProvider);
    final history = ref.watch(correctionHistoryProvider);
    final currentBatch = ref.watch(batchProvider);

    final visibleUncertain = uncertainApples.where((a) => !_hiddenAppleIds.contains(a.id)).toList();

    // Gestor history (last 7 days by this user)
    final now = DateTime.now();
    final gestorHistory = history.where((h) => 
      h.correctedBy == user?.username && 
      now.difference(h.timestamp).inDays <= 7
    ).toList();

    // Operator history for audit
    final operatorHistory = history.where((h) => h.correctedBy != user?.username).toList();
    final hNormal = operatorHistory.where((h) => ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'].contains(h.label)).toList();
    final hEspecial = operatorHistory.where((h) => !['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'].contains(h.label)).toList();

    if (_selectedTab == 0 && _selectedApple == null && visibleUncertain.isNotEmpty && !isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(mounted) _selectApple(visibleUncertain.first);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.8),
            border: Border(bottom: BorderSide(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (isAdmin)
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 20),
                      onPressed: () => ref.read(currentPageProvider.notifier).state = 'Lote Dashboard',
                    ),
                  if (isAdmin) const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Triagem Humana: Auditoria de Anomalias',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5),
                      ),
                    ],
                  ),
                ],
              ),
              if (isAdmin)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.sync_problem, color: Colors.orangeAccent),
                      tooltip: 'Limpar Cache & Sincronizar Tudo',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.surface,
                            title: const Text('Limpar Cache?', style: TextStyle(color: Colors.white)),
                            content: const Text(
                              'Tem a certeza? Isto vai apagar todos os dados locais e transferir novamente da base de dados.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Limpar', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await LocalCacheService.clearCache();
                          ref.invalidate(loadDataFutureProvider);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Cache limpo! A descarregar todos os dados novamente do Supabase...'),
                          ));
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(AppColors.isDark ? Icons.light_mode : Icons.dark_mode, color: AppColors.textPrimary),
                      onPressed: () => ref.read(themeProvider.notifier).toggle(),
                      tooltip: 'Mudar Tema',
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.sync_problem, color: Colors.orangeAccent),
                      tooltip: 'Limpar Cache & Sincronizar Tudo',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.surface,
                            title: const Text('Limpar Cache?', style: TextStyle(color: Colors.white)),
                            content: const Text(
                              'Tem a certeza? Isto vai apagar todos os dados locais e transferir novamente da base de dados.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Limpar', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await LocalCacheService.clearCache();
                          ref.invalidate(loadDataFutureProvider);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Cache limpo! A descarregar todos os dados novamente do Supabase...'),
                          ));
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.location_on_outlined, size: 16),
                      label: Text(currentBatch != null ? 'Lote: ${currentBatch.location}' : 'Escolher lote'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      onPressed: _changeLote,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.grid_view, size: 16),
                      label: const Text('Grelha'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                        foregroundColor: AppColors.primary,
                        elevation: 0,
                      ),
                      onPressed: () => ref.read(currentPageProvider.notifier).setPage('Grelha Lote'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Sair'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.isDark ? Colors.white10 : Colors.black12,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                      ),
                      onPressed: () => ref.read(authProvider.notifier).logout(),
                    ),
                  ],
                ),
            ],
          ),
        ),
        
        Expanded(
          child: Row(
            children: [
              Container(
                width: 190,
                color: AppColors.isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
                child: Column(
                  children: [
                    if (isAdmin)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ToggleButtons(
                          isSelected: [_selectedTab == 0, _selectedTab == 1],
                          onPressed: (index) => setState(() => _selectedTab = index),
                          fillColor: AppColors.primary.withOpacity(0.1),
                          selectedColor: AppColors.primary,
                          color: AppColors.textSecondary,
                          constraints: const BoxConstraints(minWidth: 70, minHeight: 32),
                          borderRadius: BorderRadius.circular(8),
                          children: const [
                            Text('Histórico', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            Text('Triagem', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    else 
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text('FILA DE TRIAGEM', style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                      ),
                      
                    Expanded(
                      child: !isAdmin 
                        ? _buildUncertainQueue(visibleUncertain)
                        : _selectedTab == 0
                          ? _buildHistoryQueue(gestorHistory, 'Meus Últimos 7d')
                          : ListView(
                              padding: EdgeInsets.zero,
                              children: (() {
                                // Lógica de Reordenação: Abertas no topo, Fechadas no fundo
                                final sections = [
                                  if (visibleUncertain.isNotEmpty) 
                                    MapEntry('triagem', () => [
                                      _buildCascadeHeader('TRIAGEM IA / MANUAL', 'triagem', Colors.amber),
                                      if (_expandedSections.contains('triagem'))
                                        _buildUncertainQueue(visibleUncertain, shrinkWrap: true),
                                    ]),
                                  if (hNormal.isNotEmpty) 
                                    MapEntry('audit', () => [
                                      _buildCascadeHeader('FILA DE AUDITORIA', 'audit', Colors.blueAccent),
                                      if (_expandedSections.contains('audit'))
                                        _buildHistoryQueue(hNormal, 'Operadores', shrinkWrap: true),
                                    ]),
                                  if (hEspecial.isNotEmpty) 
                                    MapEntry('especial', () => [
                                      _buildCascadeHeader('OUTRAS PATOLOGIAS', 'especial', AppColors.primary),
                                      if (_expandedSections.contains('especial'))
                                        _buildHistoryQueue(hEspecial, 'Especial', shrinkWrap: true),
                                    ]),
                                ];

                                sections.sort((a, b) {
                                  final expandedList = _expandedSections.toList();
                                  bool aOpen = _expandedSections.contains(a.key);
                                  bool bOpen = _expandedSections.contains(b.key);
                                  
                                  if (aOpen && !bOpen) return -1;
                                  if (!aOpen && bOpen) return 1;
                                  if (aOpen && bOpen) {
                                    // Ambas abertas: manter ordem cronológica de abertura
                                    return expandedList.indexOf(a.key).compareTo(expandedList.indexOf(b.key));
                                  }
                                  return 0; // Ambas fechadas: manter ordem original
                                });

                                return [
                                  ...sections.expand((e) => e.value()),
                                  const SizedBox(height: 40),
                                ];
                              })(),
                            ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: Center(
                  child: _buildEditorArea(user, isEditingHistory: _selectedHistory != null),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }




}