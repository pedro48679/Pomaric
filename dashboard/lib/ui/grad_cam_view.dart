import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dashboard/models/models.dart';
import 'package:dashboard/providers/dashboard_provider.dart';
import 'package:dashboard/providers/auth_provider.dart';
import 'package:dashboard/utils/constants.dart';
import 'package:dashboard/services/supabase_service.dart';
import 'package:google_fonts/google_fonts.dart';

class GradCamOperatorView extends ConsumerStatefulWidget {
  const GradCamOperatorView({Key? key}) : super(key: key);

  @override
  ConsumerState<GradCamOperatorView> createState() => _GradCamOperatorViewState();
}

class _GradCamOperatorViewState extends ConsumerState<GradCamOperatorView> {
  List<ManualAnnotation> _activePoints = []; 
  int _selectedPointIndex = 0;
  bool _isSaved = false;
  bool _initialPointModified = false; 
  
  int _selectedTab = 0; // 0 = Principal, 1 = Audit/Histórico
  Set<String> _expandedSections = {}; // Rastreia seções abertas no Gestor
  
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
    });
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
        _isSaved = false;
      }
    });
  }

  void _adjustRadius(double delta) {
    if (_activePoints.isEmpty) return;
    setState(() {
      final p = _activePoints[_selectedPointIndex];
      final levels = [15.0, 50.0, 85.0, 120.0, 155.0];
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
      _isSaved = false;
    });
  }

  void _addPoint() {
    final appleId = _selectedApple?.id ?? _selectedHistory?.appleId ?? 'unknown';
    final frameId = _selectedApple?.worstFrame?.id ?? 0;
    setState(() {
      _activePoints.add(ManualAnnotation(
        appleId: appleId,
        circleIndex: 0,
        disease: _selectedCorrectionLabel ?? 'Healthy',
        x: 225,
        y: 225,
        radius: 60,
      ));
      _selectedPointIndex = _activePoints.length - 1;
      _initialPointModified = true; 
      _isSaved = false;
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
      _isSaved = false;
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
      _isSaved = false;
      _customLabelController.clear();
      _selectedHistory = null;
    });
  }

  void _selectHistory(CorrectionHistory history) {
    setState(() {
      _selectedHistory = history;
      // Convertemos as coordenadas normalizadas (0.0-1.0) de volta para pixels do editor (450px)
      _activePoints = history.annotations.map((p) => ManualAnnotation(
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
      _isSaved = true;
      _selectedApple = null;
      _selectedCorrectionLabel = history.label;
      if (history.label != 'Healthy' && !['Rot', 'Scab', 'Blotch', 'Anthracnose'].contains(history.label)) {
        _selectedCorrectionLabel = 'Outro';
        _customLabelController.text = history.label;
      }
    });
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
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (isAdmin)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: () => ref.read(currentPageProvider.notifier).state = 'Lote Dashboard',
                    ),
                  if (isAdmin) const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Centro de Diagnóstico Especializado',
                        style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
                      ),
                      Text(
                        'Auditoria & Refinamento de IA em Tempo Real',
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white38),
                      ),
                    ],
                  ),
                ],
              ),
              if (isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.primary.withValues(alpha: 0.05)]),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.psychology, color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'IA + Humano',
                        style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.grid_view, size: 16),
                      label: const Text('Grelha'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                        foregroundColor: AppColors.primary,
                        elevation: 0,
                      ),
                      onPressed: () => ref.read(currentPageProvider.notifier).setPage('Matriz (Grelha)'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Sair'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: Colors.white,
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
                width: 250,
                color: Colors.black26,
                child: Column(
                  children: [
                    if (isAdmin)
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: ToggleButtons(
                          isSelected: [_selectedTab == 0, _selectedTab == 1],
                          onPressed: (index) => setState(() => _selectedTab = index),
                          fillColor: AppColors.primary.withOpacity(0.1),
                          selectedColor: AppColors.primary,
                          color: Colors.white38,
                          constraints: const BoxConstraints(minWidth: 100, minHeight: 40),
                          borderRadius: BorderRadius.circular(12),
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Histórico', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Audit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      )
                    else 
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text('FILA DE TRIAGEM', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
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

  Widget _buildUncertainQueue(List<Apple> apples, {bool shrinkWrap = false}) {
    if (apples.isEmpty) {
      if (shrinkWrap) return const SizedBox.shrink();
      return const Center(child: Text('Nenhuma maçã pendente.', style: TextStyle(color: Colors.white10), textAlign: TextAlign.center));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      itemCount: apples.length,
      itemBuilder: (context, index) {
        final apple = apples[index];
        final isSelected = _selectedApple == apple;
        final prob = apple.effectiveConfidence;
        
        return GestureDetector(
          onTap: () => _selectApple(apple),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            height: 100,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withOpacity(0.05) : Colors.black12,
              border: Border.all(color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.05), width: isSelected ? 2 : 1),
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: NetworkImage(apple.worstFrameUrl),
                fit: BoxFit.fill,
                colorFilter: isSelected ? null : ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken),
              ),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      apple.primaryCondition,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${(prob * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryQueue(List<CorrectionHistory> history, String type, {bool shrinkWrap = false}) {
    if (history.isEmpty) {
      if (shrinkWrap) return const SizedBox.shrink();
      return Center(child: Text('Vazio ($type)', style: TextStyle(color: Colors.white10, fontSize: 11)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[history.length - 1 - index];
        final isSelected = _selectedHistory == item;
        
        return GestureDetector(
          onTap: () => _selectHistory(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            height: 80,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.black26,
              border: Border.all(color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.05), width: isSelected ? 2 : 1),
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: NetworkImage(item.frameUrl),
                fit: BoxFit.fill,
                colorFilter: isSelected ? null : ColorFilter.mode(Colors.black.withOpacity(0.6), BlendMode.darken),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                      ),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item.label,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              item.correctedBy,
                              style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (item.label == 'Outro') 
                          Text(item.label, style: const TextStyle(color: AppColors.primary, fontSize: 8)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditorArea(AppUser? user, {required bool isEditingHistory}) {
    final isAdmin = user?.role == UserRole.admin;
    final hasItem = isEditingHistory ? _selectedHistory != null : _selectedApple != null;
    if (!hasItem) {
      return Text(
        isAdmin ? 'Selecione uma triagem para Auditar.' : 'Selecione uma maçã na Fila de Triagem.', 
        style: GoogleFonts.inter(color: Colors.white24)
      );
    }

    final imageUrl = isEditingHistory ? _selectedHistory!.frameUrl : _selectedApple!.worstFrameUrl;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double editorSize = constraints.maxWidth < 450 ? constraints.maxWidth : 450;
            return Column(
              children: [
                Text(
                  isEditingHistory 
                    ? '${_selectedHistory!.appleId} (Triado por ${_selectedHistory!.correctedBy})' 
                    : _selectedApple!.id,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                
                Center(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: editorSize,
                          height: editorSize,
                          color: Colors.grey[900],
                          child: Listener(
                            onPointerSignal: (pointerSignal) {
                              if (pointerSignal is PointerScrollEvent) {
                                _adjustRadius(pointerSignal.scrollDelta.dy);
                              }
                            },
                            child: GestureDetector(
                              onScaleUpdate: (details) => _onScaleUpdate(details, Size(editorSize, editorSize)),
                              child: Stack(
                                children: [
                                  Positioned.fill(child: Image.network(imageUrl, fit: BoxFit.fill)),
                                  
                                  if (_showCnnHeatmap)
                                    Positioned.fill(
                                      child: Opacity(
                                        opacity: 0.6,
                                        child: Image.network(
                                          imageUrl.replaceFirst('.png', '_gradcam.png')
                                                  .replaceFirst('.jpg', '_gradcam.jpg')
                                                  .replaceFirst('.jpeg', '_gradcam.jpeg'),
                                          fit: BoxFit.fill,
                                          errorBuilder: (context, _, __) => const SizedBox(),
                                        ),
                                      ),
                                    ),

                                  if (_showOperatorFocus)
                                    ..._activePoints.asMap().entries.map((e) {
                                      final idx = e.key;
                                      final p = e.value;
                                      final isSelected = idx == _selectedPointIndex;
                                      
                                      return Positioned(
                                        left: p.x - p.radius,
                                        top: p.y - p.radius,
                                        child: GestureDetector(
                                          onTap: () {
                                          setState(() {
                                            _selectedPointIndex = idx;
                                            _selectedCorrectionLabel = p.disease;
                                            if (p.disease == 'Outro' || !['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'].contains(p.disease)) {
                                               _customLabelController.text = p.disease;
                                            }
                                          });
                                        },
                                          child: Container(
                                            width: p.radius * 2,
                                            height: p.radius * 2,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(color: isSelected ? Colors.white : Colors.white24, width: isSelected ? 2 : 1),
                                              gradient: RadialGradient(
                                                colors: [
                                                  Colors.redAccent.withOpacity(0.6),
                                                  Colors.redAccent.withOpacity(0.2),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                const Icon(Icons.pan_tool, color: Colors.white, size: 16),
                                                Positioned(
                                                  bottom: 4,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                                                    child: Text(p.disease, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                                  ),
                                                ),
                                                if (isSelected)
                                                  Positioned(
                                                    top: 0, right: 0,
                                                    child: IconButton(
                                                      icon: const Icon(Icons.cancel, color: Colors.white, size: 18),
                                                      onPressed: () => _removePoint(idx),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (true) // Tanto Operador como Gestor podem adicionar focos
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _addPoint,
                              icon: const Icon(Icons.add_circle_outline, size: 18),
                              label: const Text('Novo Foco'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.05),
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Text('Usa scroll para ajustar tamanho do foco', style: TextStyle(color: Colors.white24, fontSize: 10)),
                          ],
                        ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _toggleButton(
                            label: 'CNN Heatmap',
                            icon: Icons.layers,
                            isActive: _showCnnHeatmap,
                            onToggle: () => setState(() => _showCnnHeatmap = !_showCnnHeatmap),
                          ),
                          const SizedBox(width: 12),
                          if (isAdmin || isEditingHistory) ...[
                             _toggleButton(
                               label: 'Foco Operador',
                               icon: Icons.radar,
                               isActive: _showOperatorFocus,
                               onToggle: () => setState(() => _showOperatorFocus = !_showOperatorFocus),
                             ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
            
            const SizedBox(height: 32),
            
            const Text('Diagnóstico Selecionado:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose', 'Outro'].map((label) {
                final isSel = _selectedCorrectionLabel == label;
                return ChoiceChip(
                  label: Text(label),
                  selected: isSel,
                  onSelected: (val) {
                    setState(() {
                      _selectedCorrectionLabel = label;
                      if (_activePoints.isNotEmpty && _selectedPointIndex < _activePoints.length) {
                        final p = _activePoints[_selectedPointIndex];
                        _activePoints[_selectedPointIndex] = ManualAnnotation(
                          appleId: p.appleId,
                          circleIndex: 0,
                          disease: label,
                          x: p.x,
                          y: p.y,
                          radius: p.radius,
                          
                        );
                        _initialPointModified = true;
                      }
                    });
                  },
                  selectedColor: AppColors.healthy,
                  backgroundColor: AppColors.surface,
                  labelStyle: TextStyle(color: isSel ? Colors.white : Colors.white70),
                );
              }).toList(),
            ),
            if (_selectedCorrectionLabel == 'Outro') ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: TextField(
                  controller: _customLabelController,
                  enabled: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Descrição da anomalia...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 40),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAdmin ? AppColors.primary : AppColors.healthy,
                    foregroundColor: AppColors.surface, // Dark text for better contrast
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 10,
                    shadowColor: (isAdmin ? AppColors.primary : AppColors.healthy).withOpacity(0.5),
                  ),
                  icon: Icon(isAdmin ? Icons.fact_check : Icons.check_circle, size: 28),
                  label: Text(
                    isAdmin ? 'Validar Auditoria e Próximo' : 'Confirmar e Próximo', 
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                  ),
                  onPressed: () {
                    final finalLabel = _selectedCorrectionLabel == 'Outro' 
                        ? _customLabelController.text 
                        : _selectedCorrectionLabel;
                    
                    if (finalLabel == null || finalLabel.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, indique a doença/característica.')));
                      return;
                    }

                    // Atualiza o label do ponto selecionado se for customizado
                    if (_selectedCorrectionLabel == 'Outro' && _activePoints.isNotEmpty) {
                       final p = _activePoints[_selectedPointIndex];
                       _activePoints[_selectedPointIndex] = ManualAnnotation(
                          appleId: p.appleId,
                          circleIndex: p.circleIndex,
                          disease: finalLabel!,
                          x: p.x,
                          y: p.y,
                          radius: p.radius,
                          updatedBy: user?.username,
                       );
                    }

                    final currentBatch = ref.read(batchProvider);
                    final appleId = isEditingHistory ? _selectedHistory!.appleId : _selectedApple!.id;

                    // --- PERSISTÊNCIA REAL NO SUPABASE ---
                    final pointsToSave = (_activePoints.length == 1 && !_initialPointModified && !isEditingHistory)
                        ? <ManualAnnotation>[] 
                        : _activePoints.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final p = entry.value;
                            // Normalizamos as coordenadas para que o processador Python consiga 
                            // aplicar o crop independentemente da resolução da imagem original.
                            // Assumindo que o editor é sempre um quadrado (size x size).
                            const double editorSize = 450.0; 
                            return ManualAnnotation(
                              appleId: appleId,
                              circleIndex: idx,
                              disease: p.disease ?? finalLabel,
                              x: p.x / editorSize,
                              y: p.y / editorSize,
                              radius: p.radius / editorSize,
                              updatedBy: user?.username,
                            );
                          }).toList();

                    final primaryImageLabel = pointsToSave.isNotEmpty ? pointsToSave.first.disease : finalLabel;

                    // Tentamos recuperar os dados originais da IA para manter o histórico íntegro
                    final allApples = ref.read(availableBatchesProvider).expand((b) => b.apples).toList();
                    final originalApple = allApples.firstWhere((a) => a.id == appleId, orElse: () => _selectedApple!);
                    final originalClass = originalApple.primaryCondition;
                    final originalConfidence = (originalApple.effectiveConfidence * 100).toInt();

                    // --- PERSISTÊNCIA UNIFICADA NO SUPABASE ---
                    SupabaseService.completeReview(
                      appleId: appleId,
                      decision: primaryImageLabel,
                      username: user?.username ?? 'Desconhecido',
                      role: isAdmin ? 'manager' : 'operator',
                      circles: pointsToSave,
                      originalImageUrl: imageUrl,
                      originalClass: originalClass,
                      originalConfidence: originalConfidence,
                    );

                    // 3. Atualizar Estado Local
                    final newHistory = CorrectionHistory(
                      batchId: currentBatch?.id ?? 'unknown',
                      appleId: appleId,
                      frameUrl: imageUrl,
                      annotations: pointsToSave,
                      label: primaryImageLabel,
                      correctedBy: user?.username ?? 'Desconhecido',
                      timestamp: DateTime.now(),
                    );
                    
                    ref.read(correctionHistoryProvider.notifier).upsertCorrection(newHistory);
                    ref.read(batchProvider.notifier).updateAppleDiagnosis(appleId, primaryImageLabel);
                    
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Row(
                        children: [
                          Icon(isAdmin ? Icons.verified : Icons.cloud_done, color: Colors.white, size: 20),
                          const SizedBox(width: 12),
                          Text(isAdmin ? 'Auditoria Finalizada e Exportada para Treino!' : 'Diagnóstico sincronizado com a Central.'),
                        ],
                      ),
                      backgroundColor: isAdmin ? AppColors.primary : AppColors.healthy,
                      behavior: SnackBarBehavior.floating,
                    ));

                    setState(() {
                      if (!isEditingHistory) {
                        _hiddenAppleIds.add(appleId);
                        
                        final uncertainApples = ref.read(uncertainApplesProvider);
                        final visibleUncertain = uncertainApples.where((a) => !_hiddenAppleIds.contains(a.id)).toList();
                        
                        if (visibleUncertain.isNotEmpty) {
                          // Aguardar um frame e ir para a próxima
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _selectApple(visibleUncertain.first);
                          });
                        } else {
                          _selectedApple = null;
                        }
                      } else {
                        // Lógica de avanço para o Gestor (Auditoria)
                        final historyList = ref.read(correctionHistoryProvider);
                        final currentPending = historyList.where((h) => h.correctedBy != user?.username).toList();
                        
                        int currentIndex = currentPending.indexWhere((h) => h.appleId == appleId);
                        CorrectionHistory? nextHistory;
                        
                        if (currentIndex != -1 && currentIndex + 1 < currentPending.length) {
                          nextHistory = currentPending[currentIndex + 1];
                        } else if (currentPending.isNotEmpty && currentPending.first.appleId != appleId) {
                          nextHistory = currentPending.first;
                        }

                        if (nextHistory != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _selectHistory(nextHistory!);
                          });
                        } else {
                          _selectedHistory = null;
                          _isSaved = true;
                        }
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        );
      }
    ),
  ),
);
  }

  Widget _toggleButton({required String label, required IconData icon, required bool isActive, required VoidCallback onToggle}) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.1) : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? AppColors.primary : Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? AppColors.primary : Colors.white24, size: 16),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.white24, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
  Widget _buildCascadeHeader(String title, String sectionId, Color accentColor) {
    final isOpen = _expandedSections.contains(sectionId);
    return InkWell(
      onTap: () => _toggleSection(sectionId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isOpen ? accentColor.withOpacity(0.08) : Colors.black12,
          border: Border(
            left: BorderSide(color: isOpen ? accentColor : Colors.transparent, width: 4),
            bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title, 
                  style: GoogleFonts.inter(
                    color: isOpen ? Colors.white : Colors.white38, 
                    fontSize: 10, 
                    fontWeight: FontWeight.bold, 
                    letterSpacing: 1.5
                  )
                ),
                if (isOpen)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 24, height: 3,
                    decoration: BoxDecoration(
                      color: accentColor, 
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [BoxShadow(color: accentColor.withOpacity(0.5), blurRadius: 4)],
                    ),
                  ),
              ],
            ),
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, color: isOpen ? accentColor : Colors.white24, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
