import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import 'apple_card.dart';
import '../utils/constants.dart';

class AppleGridView extends StatefulWidget {
  final List<Apple> apples;

  const AppleGridView({Key? key, required this.apples}) : super(key: key);

  @override
  State<AppleGridView> createState() => _AppleGridViewState();
}

class _AppleGridViewState extends State<AppleGridView> {
  final ScrollController _scrollController = ScrollController();
  int _visibleCount = 24; // Aprox. 6 linhas iniciais (4 por linha)
  bool _isLoadingMore = false;
  late List<Apple> _validApples;
  double _gridExtent = 220.0;

  @override
  void initState() {
    super.initState();
    _updateValidApples();
    _scrollController.addListener(_onScroll);
  }

  void _updateValidApples() {
    // Cada maçã grava sempre pelo menos 1 frame (o worst_case, via CNN2
    // confiante ou CNN5) — basta ter imagem para aparecer na grelha.
    _validApples = widget.apples.where((a) => a.frames.isNotEmpty).toList();
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

  @override
  void didUpdateWidget(AppleGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se a lista de maçãs enviada pelo pai mudar, recalcula os válidos e reseta o contador
    if (oldWidget.apples.length != widget.apples.length ||
        oldWidget.apples != widget.apples) {
      _updateValidApples();
      _visibleCount = 24;
    }
  }

  @override
  Widget build(BuildContext context) {
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