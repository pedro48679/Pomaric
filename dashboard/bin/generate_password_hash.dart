#!/usr/bin/env dart
import 'dart:io';
import 'package:bcrypt/bcrypt.dart';

/// Utilitário para gerar hashes de bcrypt para novos utilizadores
///
/// Uso:
/// ```
/// dart bin/generate_password_hash.dart admin admin
/// dart bin/generate_password_hash.dart ana password123
/// ```

void main(List<String> args) {
  if (args.length < 2) {
    print('=== Gerador de Hash de Bcrypt ===\n');
    print('Uso: dart bin/generate_password_hash.dart <username> <password>\n');
    print('Exemplo:');
    print('  dart bin/generate_password_hash.dart admin admin');
    print('  dart bin/generate_password_hash.dart ana password123\n');
    print('O hash será gerado com 10 rounds (seguro para produção)');
    exit(1);
  }

  final username = args[0];
  final password = args[1];

  try {
    final hash = BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 10));

    print('\n=== Hash Gerado ===\n');
    print('Username: $username');
    print('Password: $password');
    print('Hash: $hash\n');

    print('=== SQL para Inserir no Supabase ===\n');
    print("""
INSERT INTO workers (username, password_hash, role, is_active)
VALUES (
  '$username',
  '$hash',
  'operator',  -- Mudar para 'admin' se necessário
  true
)
ON CONFLICT (username) DO NOTHING;
""");

    print('=== Instruções ===\n');
    print('1. Copiar o comando SQL acima');
    print('2. Ir para Supabase SQL Editor');
    print('3. Executar o comando');
    print('4. Agora o utilizador "$username" pode fazer login com a password "$password"');
  } catch (e) {
    print('Erro ao gerar hash: $e');
    exit(1);
  }
}
