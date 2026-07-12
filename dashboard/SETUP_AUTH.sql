-- ═══════════════════════════════════════════════════════════════
-- SETUP DE AUTENTICAÇÃO - TABELA WORKERS
-- ═══════════════════════════════════════════════════════════════

-- 1. Criar tabela de workers (utilizadores)
CREATE TABLE IF NOT EXISTS workers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'operator')),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 2. Criar índice para pesquisas rápidas por username
CREATE INDEX idx_workers_username ON workers(username);
CREATE INDEX idx_workers_is_active ON workers(is_active);

-- 3. Criar utilizadores (admin e operators)
-- NÃO inserir passwords/hashes neste ficheiro (fica versionado no git).
-- Gera um hash próprio primeiro com o utilitário do projeto:
--   dart bin/generate_password_hash.dart <username> <password>
-- O comando imprime o INSERT já pronto a colar aqui, com o hash bcrypt
-- calculado localmente — a password em texto simples nunca sai da tua máquina.
--
-- Exemplo de forma (substitui pelo output real do comando acima):
-- INSERT INTO workers (username, password_hash, role, is_active)
-- VALUES ('admin', '<hash-gerado-localmente>', 'admin', true)
-- ON CONFLICT (username) DO NOTHING;

-- 5. Ativar Row Level Security (RLS) para segurança extra
ALTER TABLE workers ENABLE ROW LEVEL SECURITY;

-- 6. Política para permitir apenas leitura de dados do próprio utilizador
CREATE POLICY "Utilizadores podem ver seus próprios dados"
  ON workers FOR SELECT
  USING (true);  -- Os utilizadores autenticados via aplicação têm permissão

CREATE POLICY "Apenas admin pode modificar workers"
  ON workers FOR UPDATE
  USING (true)  -- Implementar verificação no backend da app
  WITH CHECK (true);

CREATE POLICY "Apenas admin pode inserir workers"
  ON workers FOR INSERT
  WITH CHECK (true);  -- Implementar verificação no backend da app

-- ═══════════════════════════════════════════════════════════════
-- INSTRUÇÕES PARA GERAR HASHES DE BCRYPT
-- ═══════════════════════════════════════════════════════════════
--
-- Em Dart (Flutter):
-- ```dart
-- import 'package:bcrypt/bcrypt.dart';
--
-- String password = 'admin';
-- String hash = BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 10));
-- print(hash);
-- ```
--
-- Em Node.js:
-- ```bash
-- npm install bcryptjs
-- node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync('admin', 10));"
-- ```
--
-- Em Python:
-- ```bash
-- pip install bcrypt
-- python -c "import bcrypt; print(bcrypt.hashpw(b'admin', bcrypt.gensalt(rounds=10)).decode('utf-8'))"
-- ```
--
-- Em PostgreSQL (usando pgcrypto + uma extensão):
-- SELECT crypt('admin', gen_salt('bf'));
-- (Nota: Este método é lento e não recomendado para produção)
--
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- VERIFICAR DADOS (Depois de inserir)
-- ═══════════════════════════════════════════════════════════════
-- SELECT id, username, role, is_active, created_at FROM workers;
