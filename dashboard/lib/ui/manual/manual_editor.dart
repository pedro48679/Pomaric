part of 'manual_sorting.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// TRIAGEM MANUAL · EDITOR
// Área de edição da maçã selecionada: pontos de anotação, raio, mapa de calor da CNN e foco do operador.
// ═══════════════════════════════════════════════════════════

extension _ManualEditor on _ManualSortingViewState {
  Widget _buildEditorArea(AppUser? user, {required bool isEditingHistory}) {
    final isAdmin = user?.role == UserRole.admin;
    final hasItem = isEditingHistory ? _selectedHistory != null : _selectedApple != null;
    if (!hasItem) {
      return Text(
        isAdmin ? 'Selecione uma triagem para Auditar.' : 'Selecione uma maçã na Fila de Triagem.', 
        style: GoogleFonts.inter(color: AppColors.textSecondary)
      );
    }

    final imageUrl = isEditingHistory ? _selectedHistory!.frameUrl : _selectedApple!.worstFrameUrl;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
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
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                
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
                                              border: Border.all(color: isSelected ? Colors.white : Colors.white70, width: isSelected ? 2 : 1),
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
                                                Icon(Icons.pan_tool, color: Colors.white, size: 16),
                                                if (isSelected)
                                                  Positioned(
                                                    top: p.radius > 40 ? p.radius - 20 : 10,
                                                    child: Text('Scroll p/ ajustar', style: TextStyle(color: Colors.white70, fontSize: 8)),
                                                  ),
                                                Positioned(
                                                  bottom: 4,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(4)),
                                                    child: Text(p.disease, style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                                  ),
                                                ),
                                                if (isSelected)
                                                  Positioned(
                                                    top: 0, right: 0,
                                                    child: IconButton(
                                                      icon: Icon(Icons.cancel, color: Colors.white, size: 18),
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
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _addPoint,
                            icon: const Icon(Icons.add_circle_outline, size: 14),
                            label: const Text('Novo Foco', style: TextStyle(fontSize: 10)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.surface,
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _toggleButton(
                            label: 'CNN Heatmap',
                            icon: Icons.layers,
                            isActive: _showCnnHeatmap,
                            onToggle: () => setState(() => _showCnnHeatmap = !_showCnnHeatmap),
                          ),
                          if (isAdmin || isEditingHistory) ...[
                             const SizedBox(width: 8),
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
            
            const SizedBox(height: 16),
            
            Text('Diagnóstico Selecionado:', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ...['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'].map((label) {
                  final isSel = _selectedCorrectionLabel == label;
                  return ChoiceChip(
                    label: Text(label),
                    selected: isSel,
                    onSelected: (val) {
                      setState(() {
                        _selectedCorrectionLabel = label;
                        if (_activePoints.isNotEmpty && _selectedPointIndex < _activePoints.length) {
                          final p = _activePoints[_selectedPointIndex];
                          _activePoints[_selectedPointIndex] = p.copyWith(disease: label);
                          _initialPointModified = true;
                        }
                      });
                    },
                    selectedColor: AppColors.healthy,
                    backgroundColor: AppColors.surface,
                    labelStyle: TextStyle(color: isSel ? AppColors.textPrimary : AppColors.textSecondary),
                  );
                }).toList(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChoiceChip(
                      label: const Text('Outro'),
                      selected: _selectedCorrectionLabel == 'Outro',
                      onSelected: (val) {
                        setState(() {
                          _selectedCorrectionLabel = 'Outro';
                          if (_activePoints.isNotEmpty && _selectedPointIndex < _activePoints.length) {
                            final p = _activePoints[_selectedPointIndex];
                            _activePoints[_selectedPointIndex] = p.copyWith(disease: _customLabelController.text.isNotEmpty ? _customLabelController.text : 'Outro');
                            _initialPointModified = true;
                          }
                        });
                      },
                      selectedColor: AppColors.healthy,
                      backgroundColor: AppColors.surface,
                      labelStyle: TextStyle(color: _selectedCorrectionLabel == 'Outro' ? AppColors.textPrimary : AppColors.textSecondary),
                    ),
                    if (_customDiseases.isNotEmpty)
                      PopupMenuButton<String>(
                        icon: Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                        tooltip: 'Ver doenças personalizadas anteriores',
                        onSelected: (String result) {
                          setState(() {
                            _selectedCorrectionLabel = 'Outro';
                            _customLabelController.text = result;
                            if (_activePoints.isNotEmpty && _selectedPointIndex < _activePoints.length) {
                              final p = _activePoints[_selectedPointIndex];
                              _activePoints[_selectedPointIndex] = p.copyWith(disease: result);
                              _initialPointModified = true;
                            }
                          });
                        },
                        itemBuilder: (BuildContext context) {
                          return _customDiseases.map((String choice) {
                            return PopupMenuItem<String>(
                              value: choice,
                              child: Text(choice),
                            );
                          }).toList();
                        },
                      ),
                  ],
                ),
              ],
            ),
            if (_selectedCorrectionLabel == 'Outro') ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: TextField(
                  controller: _customLabelController,
                  enabled: true,
                  style: TextStyle(color: AppColors.textPrimary),
                  onChanged: (text) {
                    setState(() {
                      if (_activePoints.isNotEmpty && _selectedPointIndex < _activePoints.length) {
                        final p = _activePoints[_selectedPointIndex];
                        _activePoints[_selectedPointIndex] = p.copyWith(disease: text.isNotEmpty ? text : 'Outro');
                      }
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Descrição da anomalia...',
                    hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                    filled: true,
                    fillColor: AppColors.surface,
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
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 10,
                    shadowColor: (isAdmin ? AppColors.primary : AppColors.healthy).withOpacity(0.5),
                  ),
                  icon: Icon(isAdmin ? Icons.fact_check : Icons.check_circle, size: 24),
                  label: const Text(
                    'Confirmar', 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                  ),
                  onPressed: () async {
                    final finalLabel = _selectedCorrectionLabel == 'Outro'
                        ? _customLabelController.text
                        : _selectedCorrectionLabel;
                    
                    if (finalLabel == null || finalLabel.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, indique a doença/característica.')));
                      return;
                    }

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

                    final pointsToSave = (_activePoints.length == 1 && !_initialPointModified && !isEditingHistory)
                        ? <ManualAnnotation>[] 
                        : _activePoints.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final p = entry.value;
                            const double editorSize = 450.0;
                            // Se a disease do ponto for 'Outro', forçamos o texto da caixa de texto (se existir) 
                            String resolvedDisease = p.disease;
                            if (resolvedDisease == 'Outro' && _customLabelController.text.isNotEmpty) {
                              resolvedDisease = _customLabelController.text;
                            }
                            // Usar um ID único aleatório (abaixo do limite de 2B do int4 do Postgres)
                            // para evitar problemas de cache agressiva na CDN do Supabase.
                            final uniqueCircleIndex = (DateTime.now().millisecondsSinceEpoch % 1000000000).toInt() + idx;
                            
                            return ManualAnnotation(
                              appleId: appleId,
                              circleIndex: uniqueCircleIndex,
                              disease: resolvedDisease,
                              x: p.x / editorSize,
                              y: p.y / editorSize,
                              radius: p.radius / editorSize,
                              updatedBy: user?.username,
                            );
                          }).toList();

                    final primaryImageLabel = pointsToSave.isNotEmpty ? pointsToSave.first.disease : finalLabel;

                    final allApples = ref.read(availableBatchesProvider).expand((b) => b.apples).toList();
                    // Em auditoria de histórico _selectedApple é null; se a maçã
                    // também já não estiver nos lotes carregados (cache de 30d),
                    // o antigo `orElse: () => _selectedApple!` crashava aqui.
                    final originalApple =
                        allApples.where((a) => a.id == appleId).firstOrNull ?? _selectedApple;
                    final String originalClass;
                    final int originalConfidence;
                    if (originalApple != null) {
                      originalClass = originalApple.primaryCondition;
                      originalConfidence = (originalApple.effectiveConfidence * 100).toInt();
                    } else {
                      // Preservar os valores originais já registados no
                      // manual_review em vez de os reescrever com placeholders.
                      final row = ref
                          .read(manualReviewsProvider)
                          .value
                          ?.where((r) => r['apple_id'] == appleId)
                          .firstOrNull;
                      originalClass = row?['original_class'] as String? ?? 'Unknown';
                      originalConfidence = (row?['original_confidence'] as num?)?.toInt() ?? 0;
                    }

                    // Aguardar o resultado real: antes era fire-and-forget e
                    // a UI mostrava "sincronizado" mesmo quando a gravação
                    // na BD tinha falhado em silêncio.
                    final saved = await SupabaseService.completeReview(
                      appleId: appleId,
                      decision: primaryImageLabel,
                      username: user?.username ?? 'Desconhecido',
                      role: isAdmin ? 'manager' : 'operator',
                      circles: pointsToSave,
                      originalImageUrl: imageUrl,
                      originalClass: originalClass,
                      originalConfidence: originalConfidence,
                    );
                    if (!mounted) return;
                    if (!saved) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text(
                            'Falha ao guardar a triagem na BD, nada foi alterado. Verifica a ligação e tenta outra vez.'),
                        backgroundColor: Colors.red.shade700,
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }

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
                          Icon(isAdmin ? Icons.verified : Icons.cloud_done, color: AppColors.textPrimary, size: 20),
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
          color: isActive ? AppColors.primary.withOpacity(0.1) : (AppColors.isDark ? Colors.white : Colors.black).withOpacity(0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? AppColors.primary : (AppColors.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? AppColors.primary : AppColors.textSecondary, size: 16),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isActive ? AppColors.textPrimary : AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
