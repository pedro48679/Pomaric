part of 'manual_sorting.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// TRIAGEM MANUAL · FILAS
// Fila de maçãs incertas à espera de decisão, histórico de correções e o cabeçalho em cascata que agrupa as secções.
// ═══════════════════════════════════════════════════════════

extension _ManualQueues on _ManualSortingViewState {
  Widget _buildUncertainQueue(List<Apple> apples, {bool shrinkWrap = false}) {
    if (apples.isEmpty) {
      if (shrinkWrap) return const SizedBox.shrink();
      return Center(child: Text('Nenhuma maçã pendente.', style: TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center));
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
              border: Border.all(color: isSelected ? AppColors.primary : (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05), width: isSelected ? 2 : 1),
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: NetworkImage(apple.worstFrameUrl),
                fit: BoxFit.fill,
                colorFilter: isSelected ? null : ColorFilter.mode(Colors.black.withOpacity(AppColors.isDark ? 0.4 : 0.15), BlendMode.darken),
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
                    Flexible(
                      child: Text(
                        apple.primaryCondition,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
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
      return Center(child: Text('Vazio ($type)', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)));
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
              color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.black.withOpacity(AppColors.isDark ? 0.26 : 0.06),
              border: Border.all(color: isSelected ? AppColors.primary : (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05), width: isSelected ? 2 : 1),
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: NetworkImage(item.frameUrl),
                fit: BoxFit.fill,
                colorFilter: isSelected ? null : ColorFilter.mode(Colors.black.withOpacity(AppColors.isDark ? 0.6 : 0.2), BlendMode.darken),
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
                            Flexible(
                              flex: 3,
                              child: Text(
                                item.label,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              flex: 5,
                              child: Text(
                                '${DateFormat('HH:mm:ss').format(item.timestamp)} · ${item.batchId}',
                                style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (item.label == 'Outro') 
                          Text(item.label, style: TextStyle(color: AppColors.isDark ? AppColors.primary : const Color(0xFF00FFC4), fontSize: 8)),
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
            bottom: BorderSide(color: (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.05)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title, 
                    style: GoogleFonts.inter(
                      color: isOpen ? AppColors.textPrimary : AppColors.textSecondary, 
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
            ),
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, color: isOpen ? accentColor : AppColors.textSecondary, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
