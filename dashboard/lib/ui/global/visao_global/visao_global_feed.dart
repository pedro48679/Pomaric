part of '../../global_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// VISÃO GLOBAL · FEED
// Feed de produção em tempo real (tabela producao_atual).
// ═══════════════════════════════════════════════════════════

extension _VisaoGlobalFeed on _GlobalDashboardState {
  // ═══ FEED DE PRODUÇÃO EM TEMPO REAL (producao_atual) ═══
  Widget _productionFeed(WidgetRef ref) {
    final feedAsync = ref.watch(producaoAtualProvider);
    final records = feedAsync.value;

    return _card(
      'Últimas Classificações da Linha',
      'Veredicto final por maçã (producao_atual), atualização automática',
      250,
      tooltip: '• Cada cartão é o resultado final de uma maçã na linha: classe, confiança e origem da decisão.\n\n'
          '• Origem IA: decisão autónoma do pipeline. Origem HUMANO: validação/correção manual na triagem.\n\n'
          '• Atualiza por polling (10s em produção, 60s em modo demo).',
      records == null
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.conveyor_belt, color: AppColors.textSecondary.withOpacity(0.4), size: 32),
                      const SizedBox(height: 10),
                      Text(
                        'Sem registos de produção',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _productionTile(context, ref, records[i]),
                ),
    );
  }

  Widget _productionTile(BuildContext context, WidgetRef ref, ProducaoRecord r) {
    final color = AppColors.getColorForCondition(r.finalClass);
    final sourceColor = r.isHuman ? Colors.amberAccent : Colors.cyanAccent;
    return GestureDetector(
      onTap: () {
        // Find the full Apple object across all loaded batches
        final allBatches = ref.read(availableBatchesProvider);
        final allApples = allBatches.expand((b) => b.apples).toList();
        final apple = allApples.firstWhere(
          (a) => a.id == r.appleId, 
          orElse: () => Apple(
            id: r.appleId, 
            timestamp: r.timestamp, 
            frames: []
          ) // fallback (shouldn't happen ideally)
        );

        if (apple.frames.isNotEmpty) {
          // Find the batch it belongs to
          try {
            final batch = allBatches.firstWhere((b) => b.apples.any((a) => a.id == r.appleId));
            ref.read(batchProvider.notifier).setBatch(batch);
            ref.read(currentPageProvider.notifier).setPage('Grelha Lote');
            
            // Wait for navigation animation then open details
            Future.delayed(const Duration(milliseconds: 100), () {
              if (context.mounted) {
                AppleCard.showAppleDetails(context, apple);
              }
            });
          } catch (e) {
            // Batch not found, skip navigation
          }
        }
      },
      child: Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceBright.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: double.infinity,
                child: HybridImage(cloudUrl: r.frameThumbnail, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 11, color: AppColors.textSecondary.withOpacity(0.8)),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  (r.location != null && r.location!.trim().isNotEmpty) ? r.location!.trim() : r.appleId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  AppColors.displayName(r.finalClass),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${(r.finalConfidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sourceColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  r.isHuman ? 'HUMANO' : r.finalSource.toUpperCase(),
                  style: TextStyle(color: sourceColor, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
              Text(
                _relativeTime(r.timestamp),
                style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    return 'há ${diff.inDays}d';
  }
}
