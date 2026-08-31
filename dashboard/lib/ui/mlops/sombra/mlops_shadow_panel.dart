part of '../mlops_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// MLOPS · SOMBRA, painel
// UI do shadow runner: escolha do modelo candidato, arranque e
// paragem, promoção a produção e estatísticas de concordância.
// ═══════════════════════════════════════════════════════════

extension _MlopsShadowPanel on MlopsPageState {
  // --------------------------------------------------------------------------
  // Painel Shadow CNN
  // --------------------------------------------------------------------------
  Widget _buildShadowPanel() {
    final shadowModel = _shadowState['model'] as String?;
    final shadowState = _shadowState['state'] as String? ?? 'idle';
    final applesProcessed = _shadowState['apples_processed'] as int? ?? 0;
    final shadowAcc = _shadowState['accuracy'];
    final shadowF1 = _shadowState['f1'];
    final isRunning = shadowState == 'running' || shadowState == 'ready_to_promote';
    final readyToPromote = shadowState == 'ready_to_promote';
    final concluded = shadowState == 'promoted' || shadowState == 'archived';
    final comparison = _shadowState['comparison'] as Map<String, dynamic>? ?? {};

    final modelNames = _models.map((m) => m.name).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isRunning
                ? AppColors.primary.withOpacity(0.3)
                : AppColors.glassBorder),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined,
                  color: isRunning ? AppColors.primary : AppColors.textSecondary,
                  size: 18),
              const SizedBox(width: 8),
              Text('Shadow CNN',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isRunning ? Colors.green : AppColors.textSecondary)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  shadowState == 'idle'
                      ? 'Parado'
                      : shadowState == 'running'
                          ? 'A correr'
                          : shadowState == 'ready_to_promote'
                              ? 'Pronto para promover!'
                              : shadowState == 'promoted'
                                  ? 'Promovido automaticamente'
                                  : shadowState == 'archived'
                                      ? 'Arquivado (não promovido)'
                                      : shadowState,
                  style: TextStyle(
                    color: shadowState == 'promoted'
                        ? Colors.green
                        : shadowState == 'archived'
                            ? Colors.orangeAccent
                            : readyToPromote
                                ? Colors.green
                                : isRunning
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isRunning ? const SizedBox(width: double.infinity) : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'O modelo Shadow é executado como processo independente (continua a correr mesmo que termines sessão ou mudes de página). '
                  'Classifica as mesmas maçãs que o modelo de produção, sem afetar decisões reais. '
                  'Ao atingir o número de maçãs configurado, compara automaticamente o seu F1 com o modelo em produção: '
                  'se for melhor, promove-se a si mesmo; senão, fica arquivado no histórico.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 12),
                _mlopsServerUrlField(),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // Seleção do modelo shadow
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Modelo Shadow',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: shadowModel,
                      dropdownColor: AppColors.surface,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 11),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: AppColors.glassBorder)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: AppColors.glassBorder)),
                      ),
                      hint: Text('Selecionar modelo...',
                          style: TextStyle(
                              color: AppColors.textSecondary.withOpacity(0.5),
                              fontSize: 11)),
                      items: modelNames
                          .map((n) =>
                              DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: isRunning ? null : (v) {
                        // Feedback local imediato...
                        setState(() => _shadowState = {
                          ..._shadowState,
                          'model': v,
                        });
                        // ...e persiste no servidor (POST /shadow/set), senão
                        // o próximo poll de _pollStatus() (a cada poucos
                        // segundos) repõe o modelo antigo por cima desta
                        // escolha, porque o servidor nunca chegou a saber
                        // dela, era exatamente o bug do peso a "saltar".
                        _setShadowModel(v);
                      },
                    ),
                    _weightStatsPreview(shadowModel),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: Icon(
                    isRunning ? Icons.stop : Icons.play_arrow,
                    size: 14,
                    color: isRunning ? Colors.white : AppColors.surface),
                label: Text(isRunning ? 'Parar' : 'Iniciar',
                    style: TextStyle(
                        color: isRunning ? Colors.white : AppColors.surface,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning ? Colors.red : AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: shadowModel == null
                    ? null
                    : () => isRunning ? _stopShadow() : _startShadow(shadowModel),
              ),
              if (!isRunning) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: Icon(Icons.history, size: 14, color: AppColors.primary),
                  label: Text('Simular c/ Histórico',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: shadowModel == null
                      ? null
                      : () => _simulateShadow(shadowModel),
                ),
              ],
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isRunning ? const SizedBox(width: double.infinity) : Column(
              children: [
                const SizedBox(height: 12),
                // Config promote_after
                Row(
                  children: [
                    Icon(Icons.flag, color: AppColors.textSecondary, size: 14),
                    const SizedBox(width: 6),
                    Text('Promover após',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        initialValue: _shadowPromoteAfter.toString(),
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'nº maçãs',
                          hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: AppColors.glassBorder)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: AppColors.glassBorder)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: AppColors.primary)),
                        ),
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n > 0) {
                            setState(() => _shadowPromoteAfter = n);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('maçãs',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Métricas Shadow
          if (applesProcessed > 0) ...[
            Text('Resultados Shadow vs Produção',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _kpi('Maçãs', applesProcessed.toString(),
                    Icons.apple, AppColors.primary),
                const SizedBox(width: 8),
                _kpi('Concordância (Acc)',
                    shadowAcc != null ? '$shadowAcc%' : 'n/d',
                    Icons.track_changes, Colors.green),
                const SizedBox(width: 8),
                _kpi('Concordância (F1)',
                    shadowF1 != null ? '$shadowF1%' : 'n/d',
                    Icons.psychology_alt, Colors.cyan),
              ],
            ),
            if (_shadowState.containsKey('theoretical_f1')) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fitness_center, size: 14, color: Colors.orangeAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Desempenho Teórico de Treino (Test Set)',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ),
                    Text(
                      'Produção: ${_shadowState['theoretical_f1']?['production'] ?? 'n/d'}%   |   Shadow: ${_shadowState['theoretical_f1']?['shadow'] ?? 'n/d'}%',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
            // Barra de progresso rumo í  promoção
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (applesProcessed / _shadowPromoteAfter).clamp(0.0, 1.0),
              backgroundColor: AppColors.glassBorder,
              valueColor: AlwaysStoppedAnimation<Color>(
                  readyToPromote ? Colors.green : AppColors.primary),
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 4),
            Text(
              readyToPromote
                  ? '✓ Limite atingido: modelo pronto para promoção!'
                  : '$applesProcessed / $_shadowPromoteAfter maçãs processadas',
              style: TextStyle(
                  color: readyToPromote ? Colors.green : AppColors.textSecondary,
                  fontSize: 10),
            ),
            _buildShadowDivergence(),
          ],

          const SizedBox(height: 16),

          // Botão promover manual (apenas fallback, normalmente é automático)
          if (readyToPromote)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upgrade, size: 16, color: Colors.white),
                label: const Text('Promover a Produção',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _promoteShadow,
              ),
            ),

          const SizedBox(height: 8),

          // Publica o modelo atualmente em produção no Raspberry (export ONNX + scp)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: _publishing
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.memory, size: 16),
              label: Text(_publishing ? 'A publicar...' : 'Publicar no Raspberry',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _publishing ? null : _publishToRaspberry,
            ),
          ),

          // Resultado da decisão automática mais recente
          if (concluded && comparison.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (shadowState == 'promoted' ? Colors.green : Colors.orangeAccent)
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: (shadowState == 'promoted' ? Colors.green : Colors.orangeAccent)
                        .withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    shadowState == 'promoted' ? Icons.check_circle : Icons.archive_outlined,
                    color: shadowState == 'promoted' ? Colors.green : Colors.orangeAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shadow F1 ${comparison['shadow_f1'] ?? 'n/d'}%  vs  Produção F1 ${comparison['production_f1'] ?? 'n/d'}%',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (comparison['reason'] as String?) ?? '',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Histórico de runs Shadow
          if (_shadowHistory.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Histórico Shadow',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...(_shadowHistory.take(8).map((h) {
              final isPromoted = h['result'] == 'promoted';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBright,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPromoted ? Icons.check_circle : Icons.archive_outlined,
                        size: 14,
                        color: isPromoted ? Colors.green : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (h['model'] as String?) ?? '',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${h['apples_processed'] ?? 0} maçãs · F1 ${h['f1'] ?? 'n/d'}% vs prod ${h['production_f1'] ?? 'n/d'}% · ${h['date'] ?? ''}',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        isPromoted ? 'PROMOVIDO' : 'ARQUIVADO',
                        style: TextStyle(
                            color: isPromoted ? Colors.green : AppColors.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            })),
          ],
        ],
      ),
      ),
    );
  }
}
