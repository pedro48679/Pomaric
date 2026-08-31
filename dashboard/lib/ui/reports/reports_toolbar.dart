part of 'reports_dashboard.dart';

// ═══════════════════════════════════════════════════════════
// RELATÓRIOS · BARRA E CABEÇALHO
// Barra de ferramentas, seletor de intervalo, pré-visualização do PDF e cabeçalho do documento.
// ═══════════════════════════════════════════════════════════

extension _ReportsToolbar on ReportsView {
  // ─────────────────────────────────────────────────────────────────────────
  // TOOLBAR
  // ─────────────────────────────────────────────────────────────────────────
  Widget _toolbar(BuildContext context, WidgetRef ref, ReportData data) {
    final range = ref.watch(dateRangeFilterProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 10),
          Text('Relatório de Estado do Pomar',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(children: [
              _rangeOption(ref, range, '7d', '7 DIAS'),
              _rangeOption(ref, range, '30d', '30 DIAS'),
            ]),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Imprimir'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(color: AppColors.glassBorder),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: () => PdfService.generateAndPrintPdf(data),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Exportar PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.isDark ? Colors.black : Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: () => _showPdfPreview(context, data),
          ),
        ],
      ),
    );
  }

  Widget _rangeOption(WidgetRef ref, String active, String val, String label) {
    final selected = active == val;
    return GestureDetector(
      onTap: () => ref.read(dateRangeFilterProvider.notifier).setRange(val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceBright : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              letterSpacing: 0.5,
            )),
      ),
    );
  }

  void _showPdfPreview(BuildContext context, ReportData data) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        backgroundColor: Colors.grey[900],
        child: SizedBox(
          width: 900,
          height: MediaQuery.of(ctx).size.height * 0.9,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  const Text('Pré-visualização do Relatório', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(ctx).pop()),
                ]),
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) => PdfService.generatePdfBytes(data),
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  pdfFileName: 'relatorio_pomar_${DateFormat('yyyyMMdd_HHmm').format(data.generatedAt)}.pdf',
                  useActions: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CABEÇALHO DO DOCUMENTO
  // ─────────────────────────────────────────────────────────────────────────
  Widget _documentHeader(ReportData d) {
    final color = _statusColor(d.healthScore);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RELATÓRIO DE ESTADO DO POMAR',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 21, fontWeight: FontWeight.bold, letterSpacing: -0.2)),
                    const SizedBox(height: 4),
                    Text(d.scopeLabel, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('CLASSIFICAÇÃO', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, letterSpacing: 1)),
                  const SizedBox(height: 2),
                  Text('${d.statusLabel} · ${d.healthScore.toStringAsFixed(0)}%',
                      style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.glassBorder, height: 1),
          const SizedBox(height: 14),
          Wrap(spacing: 32, runSpacing: 10, children: [
            _headMeta('PERÍODO', d.periodLabel),
            _headMeta('GERADO EM', DateFormat('dd/MM/yyyy · HH:mm').format(d.generatedAt)),
            _headMeta('RESPONSÁVEL', d.generatedBy),
          ]),
        ],
      ),
    );
  }

  Widget _headMeta(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 9, letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Color _statusColor(double score) =>
      score >= 85 ? AppColors.healthy : score >= 70 ? AppColors.healthy : score >= 50 ? AppColors.scab : AppColors.rot;

  Color _urgencyColor(double urgency) =>
      urgency >= 0.7 ? AppColors.rot : urgency >= 0.3 ? AppColors.scab : AppColors.healthy;
}
