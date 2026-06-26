import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UserRole { admin, operator }

class AppUser {
  final String username;
  final UserRole role;

  AppUser({required this.username, required this.role});
}

class AuthNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null; // null means not logged in

  void login(String username, String password) {
    // Mock login logic
    if (username == 'admin') {
      state = AppUser(username: username, role: UserRole.admin);
    } else {
      state = AppUser(username: username, role: UserRole.operator);
    }
  }

  void logout() {
    state = null;
  }
}

final authProvider = NotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);
