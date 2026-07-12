import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../utils/constants.dart';

/// Diálogo de escolha/alteração do lote ativo (location gravada em novas
/// maçãs pelo Raspberry).
///
/// [mandatory] = true (login do operador): obrigatório, sem "Cancelar" nem
/// fecho pelo fundo — o operador tem sempre de escolher um lote antes de
/// entrar no Triagem. O fallback para o location mais recente em 'apples'
/// não é ideal porque pode misturar.
///
/// Parâmetros:
/// [mandatory] = true (login de operador): impede fechar sem escolher.
/// [mandatory] = false (reaberto a partir do Triagem): cancelável, para o
/// operador corrigir um nome errado ou mudar de lote a meio da triagem.
///
/// Devolve o location escolhido se confirmado, ou null se cancelado (só
/// possível quando mandatory=false). Nunca lança — se a tabela 'active_lote'
/// não existir (é opcional), a escrita falha em silêncio.
Future<String?> showLotePickerDialog(
  BuildContext context, {
  required String username,
  bool mandatory = false,
}) async {
  final current = await SupabaseService.getActiveLote();
  final controller = TextEditingController(text: current ?? '');

  if (!context.mounted) return null;

  return showDialog<String>(
    context: context,
    barrierDismissible: !mandatory,
    builder: (dialogContext) => PopScope(
      canPop: !mandatory,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Lote atual', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mandatory
                  ? 'Indica o lote onde vais fazer a triagem. As maçãs capturadas '
                    'pelo Raspberry vão ficar associadas a este lote até o mudares.'
                  : 'As maçãs capturadas pelo Raspberry vão ficar associadas a este lote, '
                    'até seres tu a mudá-lo outra vez.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.background,
                hintText: 'Ex: Linha 1',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          if (!mandatory)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.healthy),
            onPressed: () async {
              final location = controller.text.trim();
              if (location.isEmpty) return;
              try {
                await SupabaseService.setActiveLote(location, setBy: username);
              } catch (_) {
                // Tabela 'active_lote' pode não existir (uso opcional).
              }
              if (dialogContext.mounted) Navigator.of(dialogContext).pop(location);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ),
  );
}
