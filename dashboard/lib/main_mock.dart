import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart'; // Importa a app original
import 'providers/dashboard_provider.dart';
import 'services/supabase_service.dart';

/// Ponto de entrada alternativo para testar UI/UX com dados falsos.
/// Executa com: flutter run lib/main_mock.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicialização falsa do Supabase para evitar erros se algum widget tentar aceder à instância global
  await Supabase.initialize(
    url: 'https://mock.supabase.co',
    anonKey: 'mock',
  );

  // Ativamos o flag de mock
  SupabaseService.isMockMode = true;

  runApp(ProviderScope(
    overrides: [
      // Fazemos um override do provider que carrega os dados reais da BD
      loadDataFutureProvider.overrideWith((ref) async {
        // Simulamos um pequeno delay de rede
        await Future.delayed(const Duration(seconds: 1));
        
        final batches = SupabaseService.generateMockBatches();
        ref.read(availableBatchesProvider.notifier).setBatches(batches);
        if (batches.isNotEmpty) {
          ref.read(batchProvider.notifier).setBatch(batches.first);
        }
      }),
    ],
    child: const AppleQualityDashboard(),
  ));
}

