part of 'mlops_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// MLOPS · ACÇÕES
// Operações que mudam o estado do servidor: arranque e paragem do
// shadow runner, promoção a produção, publicação no Raspberry
// (export ONNX + scp) e arranque/cancelamento do treino.
// ═══════════════════════════════════════════════════════════

extension _MlopsActions on MlopsPageState {
  Future<void> _setShadowModel(String? modelName) async {
    if (SupabaseService.isMockMode) {
      setState(() {
        _shadowState = {
          'model': modelName,
          'apples_processed': modelName != null ? 247 : 0,
          'accuracy': modelName != null ? 84.2 : null,
          'f1': modelName != null ? 82.7 : null,
          'state': modelName != null ? 'running' : 'idle',
          'last_updated': DateTime.now().toIso8601String(),
        };
      });
      return;
    }
    try {
      await http.post(
        Uri.parse('${AppSettingsService.mlopsUrl}/shadow/set'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model': modelName}),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Inicia o shadow_runner.py via mlops_server (sem terminal)
  Future<void> _startShadow(String modelName) async {
    if (SupabaseService.isMockMode) {
      setState(() {
        _shadowState = {
          'model': modelName,
          'apples_processed': 0,
          'accuracy': null,
          'f1': null,
          'state': 'running',
          'last_updated': DateTime.now().toIso8601String(),
        };
      });
      // Simula progresso gradual em mock mode
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _shadowState = {
            ..._shadowState,
            'apples_processed': 247,
            'accuracy': 84.2,
            'f1': 82.7,
            'theoretical_f1': {
              'production': 95.4,
              'shadow': 96.8,
            },
            // Mesma forma do shadow_runner real, para o cartão
            // "Onde divergem?" funcionar na demo.
            'per_class_agreement': {
              'Healthy': {'total': 152, 'agree': 149},
              'Rot': {'total': 34, 'agree': 30},
              'Scab': {'total': 27, 'agree': 21},
              'Blotch': {'total': 21, 'agree': 15},
              'Anthracnose': {'total': 13, 'agree': 9},
            },
            'disagreements': [
              {'apple_id': 'APP-1042', 'production': 'Blotch', 'shadow': 'Scab', 'conf': 61.3},
              {'apple_id': 'APP-0987', 'production': 'Anthracnose', 'shadow': 'Rot', 'conf': 55.0},
              {'apple_id': 'APP-0871', 'production': 'Scab', 'shadow': 'Blotch', 'conf': 48.9},
              {'apple_id': 'APP-0764', 'production': 'Healthy', 'shadow': 'Blotch', 'conf': 42.6},
              {'apple_id': 'APP-0703', 'production': 'Rot', 'shadow': 'Anthracnose', 'conf': 66.1},
            ],
          };
        });
      });
      return;
    }
    try {
      await http.post(
        Uri.parse('${AppSettingsService.mlopsUrl}/shadow/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': modelName,
          'promote_after': _shadowPromoteAfter,
          'interval': 30,
        }),
      ).timeout(const Duration(seconds: 6));
      await _pollStatus();
    } catch (_) {}
  }

  Future<void> _simulateShadow(String modelName) async {
    if (SupabaseService.isMockMode) {
      _startShadow(modelName); // Fallback no mock mode
      return;
    }
    try {
      await http.post(
        Uri.parse('${AppSettingsService.mlopsUrl}/shadow/simulate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': modelName,
          'count': _shadowPromoteAfter,
        }),
      ).timeout(const Duration(seconds: 6));
      await _pollStatus();
    } catch (_) {}
  }

  /// Para o shadow_runner.py via mlops_server
  Future<void> _stopShadow() async {
    if (SupabaseService.isMockMode) {
      setState(() {
        _shadowState = {
          ..._shadowState,
          'state': 'idle',
        };
      });
      return;
    }
    try {
      await http
          .post(Uri.parse('${AppSettingsService.mlopsUrl}/shadow/stop'))
          .timeout(const Duration(seconds: 5));
      await _pollStatus();
    } catch (_) {}
  }

  /// Promove o modelo shadow a produção via mlops_server
  Future<void> _promoteShadow() async {
    if (SupabaseService.isMockMode) {
      setState(() {
        _shadowState = {
          ..._shadowState,
          'state': 'promoted',
        };
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('[MOCK] Modelo promovido a produção com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    try {
      final r = await http
          .post(Uri.parse('${AppSettingsService.mlopsUrl}/shadow/promote'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Modelo promovido a produção com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        await _pollStatus();
      }
    } catch (_) {}
  }

  /// Pede host/pasta do Raspberry, exporta o modelo em produção para ONNX
  /// quantizado e copia-o para lá (POST /models/publish). Não reinicia nada
  /// remotamente, o Pi só passa a usar o ficheiro no próximo arranque
  /// (resolve_latest_model() em raspberry_camera_format.py).
  Future<void> _publishToRaspberry() async {
    final hostController = TextEditingController(text: 'minipc@192.168.1.50');
    final dirController = TextEditingController(text: '/home/minipc/models');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Publicar no Raspberry', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Exporta o modelo em produção (só MobileNetV2, ResNet50 é recusado) '
              'para ONNX quantizado e copia-o para o Pi via scp. Precisas de reiniciar '
              'o script no Pi para ele passar a usar o modelo novo.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hostController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Host do Pi (user@ip)',
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dirController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Pasta remota',
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.healthy),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Publicar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (SupabaseService.isMockMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('[MOCK] Modelo publicado no Raspberry com sucesso!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      final r = await http
          .post(
            Uri.parse('${AppSettingsService.mlopsUrl}/models/publish'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'pi_host': hostController.text.trim(),
              'remote_dir': dirController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200 || body['error'] != null) {
        throw Exception(body['error'] ?? 'Falha ao iniciar publicação');
      }

      // A exportação + scp corre em background no servidor, faz polling do resultado.
      String state = 'exporting';
      String message = '';
      for (var i = 0; i < 30 && (state == 'exporting' || state == 'uploading'); i++) {
        await Future.delayed(const Duration(seconds: 2));
        final s = await http
            .get(Uri.parse('${AppSettingsService.mlopsUrl}/models/publish/status'))
            .timeout(const Duration(seconds: 5));
        final statusBody = jsonDecode(s.body) as Map<String, dynamic>;
        state = statusBody['state'] as String? ?? 'error';
        message = statusBody['message'] as String? ?? '';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state == 'done' ? message : 'Falha ao publicar: $message'),
          backgroundColor: state == 'done' ? Colors.green : Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao publicar: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _startTraining() async {
    if (_selectedClasses.isEmpty) return;

    if (SupabaseService.isMockMode) {
      // Treino animado localmente, simula epochs com métricas progressivas
      final clsList = _selectedClasses.toList();
      final totalEpochs = _epochs.clamp(3, 8); // max 8 épocas na demo para não demorar

      setState(() {
        _status = TrainingStatus(
          state: 'downloading',
          progress: 5,
          message: '[MOCK] A descarregar ${clsList.length * 120} imagens do Supabase...',
          epochs: totalEpochs,
          classes: clsList,
        );
      });
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      setState(() {
        _status = TrainingStatus(
          state: 'augmenting',
          progress: 12,
          message: '[MOCK] A equilibrar classes com augmentação...',
          epochs: totalEpochs,
          classes: clsList,
        );
      });
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      // Simula cada época com abrandamento (Plateau)
      double currentLr = _lr;
      int patience = 0;
      double trainAcc = 55.0;
      double valAcc = 50.0;
      double lossVal = 1.8;
      final mockHistory = <Map<String, dynamic>>[];

      for (int ep = 1; ep <= totalEpochs; ep++) {
        if (!mounted) return;
        
        double gain = (ep > totalEpochs / 2) ? 15.0 / totalEpochs : 30.0 / totalEpochs;
        if (patience >= 2) {
          currentLr *= 0.5;
          patience = 0;
        } else if (ep > 3 && gain < 1.0) {
          patience++;
        }
        
        trainAcc = (trainAcc + gain * 1.2).clamp(0.0, 99.5);
        valAcc = (valAcc + gain).clamp(0.0, 96.0);
        lossVal = (lossVal * 0.85).clamp(0.05, 2.0);
        
        final f1Val    = (valAcc - 2.0).clamp(0.0, 100.0);
        final precVal  = (valAcc + 1.0).clamp(0.0, 100.0);
        final recallVal= (valAcc - 3.0).clamp(0.0, 100.0);
        
        final perF1   = <String, double>{};
        final perPrec = <String, double>{};
        final perRec  = <String, double>{};
        for (int ci = 0; ci < clsList.length; ci++) {
          perF1[clsList[ci]]   = (f1Val - ci * 2.5).clamp(20.0, 99.0);
          perPrec[clsList[ci]] = (precVal - ci * 2.0).clamp(20.0, 99.0);
          perRec[clsList[ci]]  = (recallVal - ci * 2.5).clamp(20.0, 99.0);
        }
        // Mesma forma das entradas reais de train_cnn.py (acc em %, resto
        // em fração 0-1) para o gráfico live se comportar como em produção.
        mockHistory.add({
          'epoch': ep,
          'train_acc': trainAcc,
          'val_acc': valAcc,
          'loss': lossVal,
          'f1': f1Val / 100.0,
          'precision': precVal / 100.0,
          'recall': recallVal / 100.0,
        });
        setState(() {
          _status = TrainingStatus(
            state: 'training',
            progress: (12 + ep * 80 ~/ totalEpochs).clamp(12, 90),
            message: '[MOCK] Época $ep/$totalEpochs, LR: ${currentLr.toStringAsExponential(2)}, '
                'train=${trainAcc.toStringAsFixed(1)}%  '
                'val=${valAcc.toStringAsFixed(1)}%  '
                'loss=${lossVal.toStringAsFixed(4)}',
            epoch: ep,
            epochs: totalEpochs,
            trainAcc: trainAcc,
            valAcc: valAcc,
            loss: lossVal,
            f1: f1Val,
            precision: precVal,
            recall: recallVal,
            perClassF1: perF1,
            perClassPrecision: perPrec,
            perClassRecall: perRec,
            classes: clsList,
            history: List.of(mockHistory),
          );
        });
        await Future.delayed(const Duration(milliseconds: 800));
      }
      if (!mounted) return;

      // Salva modelo final
      setState(() {
        _status = TrainingStatus(
          state: 'saving',
          progress: 95,
          message: '[MOCK] A guardar modelo...',
          epochs: totalEpochs,
          classes: clsList,
        );
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final arch = _isBinary ? 'binary' : 'multi';
      final mockModelName =
          'cnn_${arch}_${_architecture}_${clsList.length}cls_acc${(87 + clsList.length).clamp(0, 99)}_f185_$ts.pth';

      setState(() {
        _status = TrainingStatus(
          state: 'done',
          progress: 100,
          message: '[MOCK] Treino concluído. Modelo guardado.',
          epoch: totalEpochs,
          epochs: totalEpochs,
          trainAcc: 89.5,
          valAcc: 87.4,
          loss: 0.1812,
          f1: 85.1,
          precision: 86.3,
          recall: 84.0,
          perClassF1: {for (int ci = 0; ci < clsList.length; ci++) clsList[ci]: (85.0 - ci * 2.0).clamp(70.0, 97.0)},
          perClassPrecision: {for (int ci = 0; ci < clsList.length; ci++) clsList[ci]: (86.0 - ci * 1.8).clamp(70.0, 97.0)},
          perClassRecall: {for (int ci = 0; ci < clsList.length; ci++) clsList[ci]: (84.0 - ci * 2.2).clamp(68.0, 97.0)},
          classes: clsList,
          modelPath: 'models/$mockModelName',
        );
      });
      // Adiciona o novo modelo í  lista
      setState(() {
        _models = [
          ModelInfo.fromJson({
            'name': mockModelName,
            'size_mb': _architecture == 'resnet50' ? 98.3 : 14.2,
            'val_accuracy': 87.4,
            'best_f1': 85.1,
            'classes': clsList,
            'architecture': _architecture,
            'created_at': DateTime.now().toIso8601String(),
            'total_images': clsList.length * 120,
            'epochs': totalEpochs,
            'history': List.generate(totalEpochs, (i) => {
              'epoch': i + 1,
              'train_acc': 55.0 + i * (35.0 / totalEpochs),
              'val_acc':   50.0 + i * (32.0 / totalEpochs),
            }),
          }),
          ..._models,
        ];
      });
      return;
    }

    final trainingClasses = _isBinary
        ? ['Healthy', ..._selectedDiseases]
        : _selectedClasses.toList();

    final config = {
      'classes': trainingClasses,
      'architecture': _architecture,
      'epochs': _epochs,
      'lr': _lr,
      'hard_threshold': _hardThreshold,
      'min_images': _minImages,
      'max_images': _maxImages,
      'batch_size': _batchSize,
      'is_binary': _isBinary,
    };
    try {
      await http.post(
        Uri.parse('${AppSettingsService.mlopsUrl}/train'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config),
      ).timeout(const Duration(seconds: 5));
      await _pollStatus();
    } catch (_) {}
  }

  Future<void> _cancelTraining() async {
    if (SupabaseService.isMockMode) {
      setState(() => _status = const TrainingStatus(
          state: 'cancelled',
          message: '[MOCK] Treino cancelado pelo utilizador.'));
      return;
    }
    try {
      await http
          .post(Uri.parse('${AppSettingsService.mlopsUrl}/cancel'))
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> _replayTraining(ModelInfo model) async {
    _isReplaying = true;
    try {
      setState(() {
        _tabIndex = 0;
      });

      setState(() {
        _status = TrainingStatus(
          state: 'training',
          progress: 12,
          message: '[REPLAY] A preparar histórico do modelo ${model.name}...',
          epochs: model.epochs,
          classes: model.classes,
        );
      });
      await Future.delayed(const Duration(seconds: 1));

      final mockHistory = <Map<String, dynamic>>[];

      for (int i = 0; i < model.history.length; i++) {
        if (!mounted) return;
        final epData = model.history[i] as Map<String, dynamic>;
        final ep = epData['epoch'] as int? ?? (i + 1);

        final perClassF1 = <String, double>{};
        final perClassPrecision = <String, double>{};
        final perClassRecall = <String, double>{};

        final rawF1 = epData['per_class_f1'] as List?;
        final rawPrec = epData['per_class_precision'] as List?;
        final rawRec = epData['per_class_recall'] as List?;

        for (int ci = 0; ci < model.classes.length; ci++) {
          final cls = model.classes[ci];
          if (rawF1 != null && ci < rawF1.length) perClassF1[cls] = (rawF1[ci] as num).toDouble() * 100.0;
          if (rawPrec != null && ci < rawPrec.length) perClassPrecision[cls] = (rawPrec[ci] as num).toDouble() * 100.0;
          if (rawRec != null && ci < rawRec.length) perClassRecall[cls] = (rawRec[ci] as num).toDouble() * 100.0;
        }

        final valAcc = (epData['val_acc'] as num?)?.toDouble() ?? 0;
        final trainAcc = (epData['train_acc'] as num?)?.toDouble() ?? 0;
        final loss = (epData['loss'] as num?)?.toDouble() ?? 0;
        final f1 = ((epData['f1'] as num?)?.toDouble() ?? 0) * 100.0;
        final precision = ((epData['precision'] as num?)?.toDouble() ?? 0) * 100.0;
        final recall = ((epData['recall'] as num?)?.toDouble() ?? 0) * 100.0;

        mockHistory.add({
          'epoch': ep,
          'train_acc': trainAcc,
          'val_acc': valAcc,
          'loss': loss,
          'f1': (epData['f1'] as num?)?.toDouble() ?? 0,
          'precision': (epData['precision'] as num?)?.toDouble() ?? 0,
          'recall': (epData['recall'] as num?)?.toDouble() ?? 0,
        });

        setState(() {
          _status = TrainingStatus(
            state: 'training',
            progress: (12 + (ep / model.epochs) * 80).clamp(12, 95).toInt(),
            message: '[REPLAY] Época $ep/${model.epochs} | '
                'train=${trainAcc.toStringAsFixed(1)}% '
                'val=${valAcc.toStringAsFixed(1)}%',
            epoch: ep,
            epochs: model.epochs,
            trainAcc: trainAcc,
            valAcc: valAcc,
            loss: loss,
            f1: f1,
            precision: precision,
            recall: recall,
            perClassF1: perClassF1,
            perClassPrecision: perClassPrecision,
            perClassRecall: perClassRecall,
            classes: model.classes,
            history: List.of(mockHistory),
          );
        });

        _replayDelayCompleter = Completer<void>();
        Future.delayed(const Duration(seconds: 5), () {
          if (_replayDelayCompleter != null && !_replayDelayCompleter!.isCompleted) {
            _replayDelayCompleter!.complete();
          }
        });
        await _replayDelayCompleter!.future;
        _replayDelayCompleter = null;
      }

      if (!mounted) return;
      setState(() {
        _status = TrainingStatus(
          state: 'done',
          progress: 100,
          message: 'Treino concluído. (Replay)',
          epoch: model.epochs,
          epochs: model.epochs,
          trainAcc: _status.trainAcc,
          valAcc: model.valAccuracy,
          loss: _status.loss,
          f1: model.bestF1,
          precision: _status.precision,
          recall: _status.recall,
          perClassF1: _status.perClassF1,
          perClassPrecision: _status.perClassPrecision,
          perClassRecall: _status.perClassRecall,
          classes: model.classes,
          history: _status.history,
          modelPath: 'models/${model.name}',
        );
      });
    } finally {
      _isReplaying = false;
    }
  }
}
