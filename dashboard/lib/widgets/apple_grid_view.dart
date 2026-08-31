import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import 'apple_card.dart';
import '../utils/constants.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';

class AppleGridView extends ConsumerStatefulWidget {
  final List<Apple> apples;

  const AppleGridView({Key? key, required this.apples}) : super(key: key);

  @override
  ConsumerState<AppleGridView> createState() => _AppleGridViewState();
}

class _AppleGridViewState extends ConsumerState<AppleGridView> {
  final ScrollController _scrollController = ScrollController();
  int _visibleCount = 24; // Aprox. 6 linhas iniciais (4 por linha)
  bool _isLoadingMore = false;
  late List<Apple> _validApples;
  double _gridExtent = 220.0;
  int _multiClassCount = 0;

  @override
  void initState() {
    super.initState();
    _updateValidApples();
    _scrollController.addListener(_onScroll);
  }

  void _updateValidApples() {
    _multiClassCount = 0;
    _validApples = widget.apples.where((a) {
      if (a.frames.isEmpty) return false;
      
      int activePathologies = 0;
      final probs = a.worstFrame?.probabilities ?? {};
      for (var p in probs.values) {
        if (p > 0.05) activePathologies++;
      }
      
      final isMultiClass = activePathologies >= 2;
      if (isMultiClass) _multiClassCount++;
      
      return true;
    }).toList();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _visibleCount < _validApples.length) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);

    // Simula um buffer de carregamento para suavizar a performance
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        _visibleCount += 24; // Carrega mais 6 linhas
        _isLoadingMore = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Compara por CONTEÚDO (ids em sequência), não por identidade de lista:
  /// filteredApplesProvider devolve uma List nova a cada poll de 5s, por isso
  /// `oldWidget.apples != widget.apples` era sempre true e a grelha resetava
  /// a paginação/scroll a cada 5 segundos, mesmo sem nenhuma maçã nova.
  bool _sameApples(List<Apple> a, List<Apple> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(AppleGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameApples(oldWidget.apples, widget.apples)) {
      _updateValidApples();
      _visibleCount = 24;
    } else if (!identical(oldWidget.apples, widget.apples)) {
      // Mesmo conjunto de maçãs mas objetos possivelmente atualizados
      // (ex.: correção manual aplicada), refresca os dados exibidos
      // sem resetar a paginação/posição de scroll.
      _updateValidApples();
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlyMultiClass = ref.watch(multiClassFilterProvider);
    final displayItems = _validApples.take(_visibleCount).toList();

    return Column(
      children: [
        // ── ZOOM CONTROLS ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black12,
            border: Border(bottom: BorderSide(color: AppColors.isDark ? Colors.white10 : Colors.black12)),
          ),
          child: Row(
            children: [
              Text('Ajustar Vista:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              Icon(Icons.grid_on, color: AppColors.textSecondary, size: 18),
              Expanded(
                child: Slider(
                  value: _gridExtent,
                  min: 120.0,
                  max: 450.0,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.isDark ? Colors.white10 : Colors.black12,
                  onChanged: (val) => setState(() => _gridExtent = val),
                ),
              ),
              Icon(Icons.crop_square, color: AppColors.textSecondary, size: 24),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  '${(_gridExtent / 220 * 100).toInt()}%',
                  style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 24),
              Container(width: 1, height: 24, color: AppColors.isDark ? Colors.white24 : Colors.black26),
              const SizedBox(width: 24),
              InkWell(
                onTap: () {
                  ref.read(multiClassFilterProvider.notifier).toggle();
                  _scrollController.jumpTo(0);
                },
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: onlyMultiClass,
                        onChanged: (val) {
                          ref.read(multiClassFilterProvider.notifier).toggle();
                          _scrollController.jumpTo(0);
                        },
                        activeColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Apenas Multi-classe ($_multiClassCount)', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ── GRID ──
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _gridExtent,
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              return AnimatedScale(
                scale: 1.0,
                duration: const Duration(milliseconds: 300),
                child: AppleCard(apple: displayItems[index]),
              );
            },
          ),
        ),
        if (_isLoadingMore)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'A carregar mais...',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}