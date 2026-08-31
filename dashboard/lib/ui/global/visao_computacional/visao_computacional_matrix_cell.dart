part of '../../global_dashboard.dart';

// ── Perfil do Lote vs. Pomar (Dumbbell) ─────────────────────────────────────
// Substitui o donut de composição (já mostrado agregado no Cap. 1) por uma
// comparação: a taxa de cada classe neste lote vs. a média dos restantes
// lotes do pomar. Revela lotes atípicos que uma simples fatia de tarte não
// consegue mostrar, a mesma % de "Rot" pode ser normal ou um surto,
// dependendo da baseline do pomar.

// ── Ridgeline (Joyplot): densidade de confiança por patologia ──────────────

  // ── B3/B4: Matriz 2×2 Confiança × Classificação ─────────────────────────
  //
  // x = confiança da CNN: 0 = <75% · 1 = ≥75%
  // y = classificação: 0 = incorreta (operador corrigiu) · 1 = correta
  //
  // (1,0): alta confiança + incorreto → mais grave (CNN confiante mas errou)
  // (0,0): baixa confiança + incorreto → esperado (CNN incerta e errou)
  // (1,1): alta confiança + correto → ideal
  // (0,1): baixa confiança + correto → conservador/seguro

Widget matrixCell(String coord, int count, String pctLabel, String label, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(coord, style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 1),
              Text('$count', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold, height: 1.1)),
              Text(pctLabel, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 10)),
              const SizedBox(height: 1),
              Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 8.5), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }

  // ── C1: Composição Temporal de Doenças ──────────────────────────────────
  // Divide a sessão em 8 janelas de tempo equitativas e mostra a proporção
  // de cada doença em cada janela, revela se há surtos ou zonas contaminadas.

// ── Cronograma Analítico de Qualidade ───────────────────────────────────────
// Composição de patologias empilhada por janela temporal, confiança da CNN
// sobreposta e surtos marcados. A legenda é clicável: tocar numa patologia
// remove-a da pilha (útil para isolar as restantes quando "Healthy" domina
// visualmente o gráfico).

  // ── C2: Taxa de Doença por Janela Temporal (Surtos) ──────────────────────
  // Detecta janelas de tempo com taxa de doença anormalmente elevada (surtos):
  // pontos a vermelho se a taxa exceder a média + 1.5 desvios-padrão.

  // ── D1: Pressão Fitossanitária (Radar Composto) ──────────────────────────
  // Combina 4 dimensões num radar: Propagação, Dano Comercial, Taxa de Doença,
  // e Diversidade de Doenças. A área do polígono representa a pressão total.

  // ── Comparação entre Lotes ────────────────────────────────────────────────

  // ── Timeline Mestre: Heatmap + Surtos + Sparkline de Entropia ─────────────
  // Fusão de 3 widgets em 1: heatmap de qualidade, deteção de surtos (⚠)
  // e o monitor cardíaco de entropia da IA como linha sobreposta.

