part of 'mlops_dashboard.dart';

// setState é protected: o analisador assinala-o quando chamado de uma
// extension. Aqui é seguro por construção, a extension está no mesmo
// library que o State (part file), não em código externo.
// ignore_for_file: invalid_use_of_protected_member

// ═══════════════════════════════════════════════════════════
// MLOPS · CARREGAMENTO DE DADOS
// Pedidos ao mlops_server.py que alimentam os três separadores:
// classes, modelos, estado do treino e resultado da comparação.
// Fica separado da UI porque não pertence a nenhum separador.
// ═══════════════════════════════════════════════════════════

extension _MlopsDataLoaders on MlopsPageState {
  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    await Future.wait([_loadClasses(), _loadModels(), _pollStatus(), _loadShadowHistory()]);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadShadowHistory() async {
    if (SupabaseService.isMockMode) return;
    try {
      final r = await http
          .get(Uri.parse('${AppSettingsService.mlopsUrl}/shadow/history'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _shadowHistory = (data['history'] as List? ?? [])
              .map((e) => e as Map<String, dynamic>)
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadClasses() async {
    if (SupabaseService.isMockMode) {
      const mockClasses = [
        ClassInfo('Healthy',     1842, gold: 34, hardCases: 12),
        ClassInfo('Rot',          234, gold: 21, hardCases: 45),
        ClassInfo('Scab',         187, gold: 17, hardCases: 38),
        ClassInfo('Blotch',       156, gold: 9,  hardCases: 29),
        ClassInfo('Anthracnose',  203, gold: 14, hardCases: 51),
      ];
      if (!mounted) return;
      setState(() {
        _classes = mockClasses;
        _serverOnline = true;
        if (_selectedClasses.isEmpty) {
          _selectedClasses = mockClasses.map((c) => c.name).toSet();
        }
        if (_selectedDiseases.isEmpty) {
          _selectedDiseases = mockClasses
              .where((c) => c.name.toLowerCase() != 'healthy')
              .map((c) => c.name)
              .toSet();
        }
      });
      return;
    }
    try {
      final r = await http
          .get(Uri.parse('${AppSettingsService.mlopsUrl}/classes'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (data['classes'] as List? ?? [])
            .map((c) => ClassInfo(
                  c['name'] as String,
                  (c['count'] as num?)?.toInt() ?? 0,
                  gold: (c['gold'] as num?)?.toInt() ?? 0,
                  hardCases: (c['hard_cases'] as num?)?.toInt() ?? 0,
                ))
            .toList();
        if (!mounted) return;
        setState(() {
          _classes = list;
          _serverOnline = true;
          if (_selectedClasses.isEmpty) {
            _selectedClasses = list.map((c) => c.name).toSet();
          }
          if (_selectedDiseases.isEmpty) {
            _selectedDiseases = list
                .where((c) => c.name.toLowerCase() != 'healthy')
                .map((c) => c.name)
                .toSet();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _serverOnline = false);
    }
  }

  Future<void> _loadModels() async {
    if (SupabaseService.isMockMode) {
      if (!mounted) return;
      setState(() {
        _models = [
          ModelInfo.fromJson({
            'name': 'cnn_multi_mobilenet_5cls_acc87_f185_20260628.pth',
            'size_mb': 14.2,
            'val_accuracy': 87.4,
            'best_f1': 85.1,
            'classes': ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'],
            'architecture': 'mobilenet_v2',
            'created_at': '2026-06-28T14:32:00',
            'total_images': 2622,
            'epochs': 15,
            'history': List.generate(15, (i) => {
              'epoch': i + 1,
              'train_acc': 65.0 + i * 1.8,
              'val_acc': 62.0 + i * 1.7,
              'f1': 60.0 + i * 1.9,
            }),
          }),
          ModelInfo.fromJson({
            'name': 'cnn_binary_resnet50_2cls_acc92_f191_20260601.pth',
            'size_mb': 98.6,
            'val_accuracy': 91.8,
            'best_f1': 91.2,
            'classes': ['Healthy', 'Disease'],
            'architecture': 'resnet50',
            'created_at': '2026-06-01T09:15:00',
            'total_images': 4120,
            'epochs': 20,
            'history': List.generate(20, (i) => {
              'epoch': i + 1,
              'train_acc': 70.0 + i * 1.2,
              'val_acc': 68.0 + i * 1.2,
              'f1': 67.0 + i * 1.3,
            }),
          }),
        ];
      });
      return;
    }
    try {
      final r = await http
          .get(Uri.parse('${AppSettingsService.mlopsUrl}/models'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _models = (data['models'] as List? ?? [])
              .map((m) => ModelInfo.fromJson(m as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _pollStatus() async {
    if (_polling) return;
    _polling = true;
    try {
      await _pollStatusInner();
    } finally {
      _polling = false;
    }
  }

  Future<void> _pollStatusInner() async {
    if (_isReplaying) return; // Se estivermos no modo replay, não atualizar estado real do servidor!

    if (SupabaseService.isMockMode) {
      // Em mock mode o estado é gerido localmente por _startTraining (não há servidor)
      if (!mounted) return;
      setState(() {
        _serverOnline = true;
        // Apenas inicializa shadow state se ainda não existir
        if (_shadowState.isEmpty) {
          _shadowState = {
            'model': null,
            'apples_processed': 0,
            'accuracy': null,
            'f1': null,
            'state': 'idle',
          };
        }
      });
      return;
    }
    try {
      final r = await http
          .get(Uri.parse('${AppSettingsService.mlopsUrl}/status'))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) {
        final newStatus = TrainingStatus.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
        final wasDone = _status.state == 'done';
        if (!mounted) return;
        setState(() {
          _status = newStatus;
          _serverOnline = true;
        });
        if (!wasDone && newStatus.state == 'done') {
          _loadModels();
        }
        if (_status.isActive && _logScroll.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_logScroll.hasClients) {
              _logScroll.animateTo(
                _logScroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    } catch (_) {}
    // Shadow state (independente do treino)
    try {
      final r = await http
          .get(Uri.parse('${AppSettingsService.mlopsUrl}/shadow/status'))
          .timeout(const Duration(seconds: 2));
      if (r.statusCode == 200) {
        final wasConcluded = _shadowState['state'] == 'promoted' ||
            _shadowState['state'] == 'archived';
        final newShadowState = jsonDecode(r.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() => _shadowState = newShadowState);
        final nowConcluded = newShadowState['state'] == 'promoted' ||
            newShadowState['state'] == 'archived';
        if (!wasConcluded && nowConcluded) {
          _loadShadowHistory();
          _loadModels();
        }
      }
    } catch (_) {}
  }

  Future<void> _loadCompare() async {
    if (_compareA == null || _compareB == null) return;
    if (mounted) setState(() => _loadingCompare = true);
    if (SupabaseService.isMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() {
        _compareResult = {
          'model_a': {
            'name': _compareA,
            'val_accuracy': 87.4,
            'best_f1': 85.1,
            'precision': 86.3,
            'recall': 84.0,
            'classes': ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose'],
            'architecture': 'mobilenet_v2',
            'total_images': 2622,
            'epochs': 15,
            'history': List.generate(15, (i) => {
              'epoch': i+1,
              'val_acc':   42.0 + i * 3.4,
              'f1':        38.0 + i * 3.6,
              'precision': 40.0 + i * 3.5,
              'recall':    36.0 + i * 3.7,
            }),
            'per_class_f1':        {'Healthy': 92.1, 'Rot': 81.3, 'Scab': 78.5, 'Blotch': 83.2, 'Anthracnose': 80.4},
            'per_class_precision': {'Healthy': 93.0, 'Rot': 82.1, 'Scab': 79.2, 'Blotch': 84.0, 'Anthracnose': 81.3},
            'per_class_recall':    {'Healthy': 91.0, 'Rot': 80.4, 'Scab': 77.8, 'Blotch': 82.4, 'Anthracnose': 79.5},
          },
          'model_b': {
            'name': _compareB,
            'val_accuracy': 91.8,
            'best_f1': 91.2,
            'precision': 92.1,
            'recall': 90.4,
            'classes': ['Healthy', 'Disease'],
            'architecture': 'resnet50',
            'total_images': 4120,
            'epochs': 20,
            'history': List.generate(20, (i) => {
              'epoch': i+1,
              'val_acc':   50.0 + i * 2.4,
              'f1':        48.0 + i * 2.5,
              'precision': 51.0 + i * 2.3,
              'recall':    47.0 + i * 2.5,
            }),
            'per_class_f1':        {'Healthy': 94.3, 'Disease': 88.1},
            'per_class_precision': {'Healthy': 95.1, 'Disease': 89.2},
            'per_class_recall':    {'Healthy': 93.5, 'Disease': 87.0},
          },
        };
        _loadingCompare = false;
      });
      return;
    }
    try {
      final r = await http
          .get(Uri.parse(
              '${AppSettingsService.mlopsUrl}/compare?a=${Uri.encodeComponent(_compareA!)}&b=${Uri.encodeComponent(_compareB!)}'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        if (mounted) {
          setState(() => _compareResult =
              jsonDecode(r.body) as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingCompare = false);
  }
}
