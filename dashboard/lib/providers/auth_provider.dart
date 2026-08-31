import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';
import 'dashboard_provider.dart';

enum UserRole { admin, operator }

class AppUser {
  final String username;
  final UserRole role;

  AppUser({required this.username, required this.role});
}

class AuthNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null; // null means not logged in

  Future<bool> login(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      return false;
    }

    final worker = await SupabaseService.login(username, password);

    if (worker == null) {
      return false;
    }

    final role = worker.role.toLowerCase() == 'admin'
        ? UserRole.admin
        : UserRole.operator;

    state = AppUser(username: worker.username, role: role);
    return true;
  }

  void logout() {
    state = null;
    // Limpar o estado da sessão anterior: sem isto, o timer de polling de
    // 5s do BatchNotifier continuava a correr no ecrã de login (invalidate
    // dispara o onDispose do notifier, que cancela o timer), e o próximo
    // utilizador herdava batches/histórico/pendentes de quem saiu.
    ref.invalidate(batchProvider);
    ref.invalidate(availableBatchesProvider);
    ref.invalidate(loadDataFutureProvider);
    ref.invalidate(correctionHistoryProvider);
    ref.invalidate(dbPendingReviewProvider);
    ref.invalidate(forcedTriageProvider);
    ref.read(sessionActiveProvider.notifier).setActive(false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);
