import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart'; // Importa a app original (main() de lá NÃO é executado)
import 'providers/auth_provider.dart';
import 'providers/dashboard_provider.dart';
import 'services/supabase_service.dart';

/// Ponto de entrada alternativo para testar UI/UX com dados 100% simulados.
///
///   flutter run -d chrome lib/main_mock.dart
///
/// O que muda em relação à versão real:
///   • Sem chamadas reais ao Supabase — todos os dados são gerados localmente
///   • Login saltado — entra direto como demo_admin (role: admin)
///   • Setup screen saltado — sessão já ativa
///   • Heartbeat da Raspberry simulado (CPU, RAM, temperatura, etc.)
///   • Endpoints MLOps (/classes, /models, /status, /train...) simulados
///   • Treino CNN animado localmente (sem GPU, sem dados reais)
///
/// Também serve de failsafe: se a BD falhar em produção, os métodos de
/// SupabaseService devolvem automaticamente dados mock.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialização fake do Supabase (evita crash se algum widget aceder à instância)
  // A URL/key são inválidas intencionalmente — nunca serão usadas em mock mode
  await Supabase.initialize(
    url: 'https://mock.supabase.co',
    anonKey: 'mock_key_never_used',
  );

  // Ativa mock globalmente — todas as chamadas à BD e HTTP devolvem dados simulados
  SupabaseService.isMockMode = true;

  runApp(ProviderScope(
    overrides: [
      // Utilizador não está pré-autenticado para podermos testar o LoginScreen
      // authProvider.overrideWith(_MockAuthNotifier.new),
      // sessão também não está ativa
      // sessionActiveProvider.overrideWith(_MockSessionNotifier.new),
      // Dados do dashboard carregados com mock batches (sem chamada à BD)
      loadDataFutureProvider.overrideWith((ref) async {
        await Future.delayed(const Duration(milliseconds: 600));
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

/// Admin pré-autenticado para sessão demo.
class _MockAuthNotifier extends AuthNotifier {
  @override
  AppUser? build() => AppUser(username: 'demo_admin', role: UserRole.admin);
}

/// Sessão sempre ativa (salta SetupScreen em mock mode).
class _MockSessionNotifier extends SessionActiveNotifier {
  @override
  bool build() => true;
}

