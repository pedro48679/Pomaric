# Dashboard Redesign Plan — v2.0
> Análise crítica completa + Plano de implementação por fases  
> Produzido por: Senior UX/UI & Analytics Engineering Review  
> Data: Junho 2026

---

## 1. ANÁLISE CRÍTICA DA SOLUÇÃO ATUAL

### 1.1 Pontos fortes identificados

| Área | Avaliação |
|---|---|
| Paleta de cores | Coesa, dark-mode forest-green com semântica clara de doença |
| Hierarquia geral | KPIs → Produção → CNN → Tabela é o fluxo correto |
| GlassCard | Componente bem construído, reutilizável |
| Tooltips | Fórmula de urgência explicada inline — excelente para executivos |
| Calibração IA | Reliability Diagram já implementado — alta qualidade analítica |
| Funil de triagem | Insight operacional real e bem comunicado |

### 1.2 Problemas críticos encontrados

#### A. Excesso cognitivo na fila de KPIs (Global Dashboard)
- **7 KPIs numa única linha** com `Row + Expanded` → em ecrãs inferiores a 1440px os cards ficam esmagados.
- "Total Inspec." e "Lotes" são métricas de contexto, não de decisão → não merecem o mesmo destaque que "Aprovação" ou "Lote Urgente".
- O ícone de `Icons.scale` para total de inspeções é semanticamente fraco.

#### B. Redundância entre Gauge e KPIs individuais
- O Gauge de "Saúde Global" agrega aprovação + confiança + urgência — exactamente os mesmos valores que já aparecem como KPIs separados.
- **O utilizador lê o mesmo número duas vezes** com apresentações diferentes → confusão, não clareza.
- Custo: ocupa flex:2 (40% da largura) da linha mais importante da dashboard.

#### C. Pareto implementado como Donut, não como Pareto
- O widget `_pareto()` usa `PieChart`, não um gráfico de Pareto real (barras ordenadas + linha cumulativa).
- Um gráfico de Pareto real responderia à questão "qual doença representa 80% do problema?" de forma muito mais directa.
- Oportunidade de impacto alto com alteração de código relativamente simples.

#### D. Radar Profile (Batch Dashboard) — redundância confirmada
- `_radarProfile()` calcula probabilidades médias por classe para todas as maçãs.
- O Donut já mostra a distribuição de patologias do mesmo lote.
- O radar não acrescenta informação nova — apenas reformata os mesmos dados em forma de polígono.
- **Decisão: eliminar o radar profile.** Substituir por um gráfico que mostre severidade por doença ao longo do tempo dentro do lote.

#### E. Severity Distribution Bar — bug documentado no Questao.md
- O `_severityDistributionBar()` tende a registar 100% continuamente por usar `diseaseSum` como percentual.
- A lógica correcta: agrupar maçãs em 4 categorias (Healthy, Leve, Moderado, Grave) e calcular percentual de maçãs em cada categoria.
- **Este bug deve ser corrigido na fase 1.**

#### F. Gauge Card duplicado (existe em Global E em Batch)
- O `_gaugeCard()` no Batch Dashboard repete exactamente a mesma lógica do `_gauge()` no Global Dashboard.
- No contexto do lote, um score composto não acrescenta valor — o operador já tem os KPIs individuais.
- **Decisão: eliminar o gauge do Batch Dashboard.** Substituir por um "Batch Health Summary Card" textual com 3 métricas inline.

#### G. Secções com cores de accent inconsistentes
- Global Dashboard usa: `Colors.greenAccent`, `Colors.orangeAccent`, `Colors.cyanAccent`.
- Batch Dashboard usa: `Colors.blueAccent`, `Colors.tealAccent`, `Colors.cyanAccent`, `Colors.orangeAccent`.
- Não existe um sistema de cores para secções — cada `_sectionHeader` tem cor arbitrária.
- **Problema: o utilizador não consegue mapear mentalmente "azul = produção, verde = saúde, etc."**

#### H. Confusion Matrix no Global Dashboard
- A matriz de confusão global agrega todos os lotes — cria valores médios sem contexto de lote.
- É mais útil na Batch Dashboard, onde o operador pode agir sobre as classes confusas daquele lote específico.
- No Global Dashboard, o insight mais valioso seria: "quantas maçãs foram reclassificadas pelo humano em todos os lotes, por doença?" — um gráfico diferente.

#### I. `_InteractiveRiscoChart` — título genérico, propósito pouco claro
- O nome "Risco" é vago; precisa de uma questão de negócio explícita.
- Pela lógica do código, compara urgência por lote — deveria chamar-se "Mapa de Urgência por Lote".

#### J. Throughput Chart — dependente de qualidade de timestamps
- O `_throughputChart` calcula maçãs/minuto por timestamp.
- Se os timestamps não forem precisos ao minuto (upload batch, não stream real-time), o gráfico mostra picos artificiais.
- Deve ter um aviso visual de "estimativa baseada em timestamps" ou ser escondido quando o desvio padrão for demasiado alto.

---

## 2. OPORTUNIDADES NÃO EXPLORADAS

### 2.1 Métricas ausentes com alto valor executivo

| Métrica | Fonte DB | Impacto |
|---|---|---|
| **Taxa de Erro Confiante** (confiança ≥80% + corrigido pelo humano) | `manual_review` + `cnn_predictions` | Mede calibração real — insight crítico de qualidade do modelo |
| **Tempo médio de processamento por lote** | `apples.timestamp` (min→max por lote) | Métrica operacional de throughput real |
| **Volume de maçãs em `producao_atual`** | `producao_atual` | Pipeline em tempo real vs. histórico — diferenciador de produto |
| **Taxa de correção por operador** | `manual_review.updated_by` | Qualidade da equipa de triagem humana |
| **Evolução de aprovação lote a lote** (sparkline por lote) | `Batch.healthDistribution` | Tendência de qualidade por linha de produção |

### 2.2 Perguntas de negócio não respondidas

1. **"Qual é a tendência de qualidade nos últimos 7 dias vs. 30 dias?"** — só existe vista de 30 dias.
2. **"Quais operadores fazem mais correções?"** — dados existem em `updated_by`, não são usados.
3. **"O modelo está a melhorar ou a degradar ao longo do tempo?"** — o trend line mostra confiança, não precisão.
4. **"Qual é a perda comercial estimada deste lote?"** — pode ser calculada com severityScore × volume.

---

## 3. NOVA ARQUITECTURA DA DASHBOARD

### 3.1 Sistema de Design

#### Paleta de Cores (actualizada, mantendo DNA da solução actual)

```
Background:     #050E0C   (Forest Black — mantém)
Surface:        #0D1B16   (Deep Sage — ligeiramente mais claro)
Surface Bright: #162822   (Para hover states)
Surface Elevated: #1C3530 (Para cards destacados / alert)

Borders:        rgba(16,185,129,0.12) normal
                rgba(16,185,129,0.25) hover/focus

── Cor Primária (acção/destaque) ──
Primary:        #00FFC4   (Neon Mint-Cyan — mantém)
Primary Dim:    rgba(0,255,196,0.08)  (background de badges)

── Semântica ──
Success/Healthy: #10B981  (Emerald — mantém)
Warning:         #F59E0B  (Amber)
Danger:          #EF4444  (Red — mais saturado que o actual #FF4D6D)
Critical Pulse:  #FF4D6D  (para alertas activos em pulso)

── Doenças (mantém) ──
Rot:            #FF4D6D
Blotch:         #8B5CF6
Scab:           #F59E0B
Anthracnose:    #EC4899
Healthy:        #10B981

── Texto ──
textPrimary:    #E2F1EC
textSecondary:  #8CA59D
textTertiary:   #4A6B63  (para labels de eixos — mais subtil)

── Secções (sistema novo) ──
section.production: #10B981  (verde — saúde/produção)
section.anomaly:    #F59E0B  (âmbar — anomalias/risco)
section.ai:         #06B6D4  (cyan — IA/modelos)
section.ops:        #8B5CF6  (violeta — operações humanas)
```

#### Tipografia

```
Família:      Inter (Google Fonts — já usado)
Fallback:     -apple-system, BlinkMacSystemFont, system-ui

Page Title:   Inter 28px / Bold / letterSpacing: -0.8px
Section Head: Inter 13px / SemiBold 600 / UPPERCASE / letterSpacing: 1.2px / textSecondary
Card Title:   Inter 13px / SemiBold 600 / textPrimary
KPI Value:    Inter 26px / Bold / letterSpacing: -1px / textPrimary
KPI Label:    Inter 10px / Medium 500 / textSecondary / UPPERCASE
KPI Sub:      Inter 10px / Regular / textTertiary
Body:         Inter 13px / Regular / textSecondary
Caption:      Inter 11px / Regular / textTertiary
Axis Labels:  Inter 10px / Regular / rgba(255,255,255,0.3)
Code/Formula: Fira Code 11px (já usado para fórmulas)
```

#### Espaçamento e Grid

```
Page padding:       32px (desktop) / 20px (laptop <1280px)
Section gap:        40px
Card gap:           16px
Card inner padding: 20px (padrão) / 16px (KPI cards)
Border radius:      12px (cards normais) / 8px (badges/tags) / 6px (micro)
Divider:            1px / rgba(255,255,255,0.06)
```

---

### 3.2 Nova Estrutura — GLOBAL DASHBOARD

```
┌─────────────────────────────────────────────────────────────────┐
│  HEADER: "Produção Global"  [LIVE badge]  [Filtro 7d/30d/custom]│
├─────────────────────────────────────────────────────────────────┤
│  FAIXA DE ALERTA (conditional — só aparece se surgeAlert ≠ Estável) │
├─────────────────────────────────────────────────────────────────┤
│  KPI ROW — 5 cards (2 contexto + 3 decisão)                     │
│  [Total Insp] [Lotes] | [Aprovação ▲▼] [Urgente ⚠] [Fila Humana]│
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: PRODUÇÃO & TENDÊNCIAS (verde)                          │
│  [Area Chart Doenças — flex:3] [Sparkline Row por lote — flex:2]│
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: DISTRIBUIÇÃO DE RISCO (âmbar)                          │
│  [Pareto REAL — flex:1] [Heatmap Lote×Patologia — flex:2]       │
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: COMPARAÇÃO DE LOTES (âmbar)                            │
│  [Diverging Bar — flex:1] [Mapa de Urgência — flex:1]           │
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: QUALIDADE DA IA (cyan)                                  │
│  [CNN Trend Line — flex:1] [Erro Confiante — flex:1] [Autonomia KPI + Calibração Gap] │
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: LOTES ACTIVOS (violeta)                                 │
│  [Tabela com sparklines inline + link → Batch Dashboard]        │
└─────────────────────────────────────────────────────────────────┘
```

**Alterações vs. actual:**
- ❌ Gauge removido (redundante com KPIs)
- ❌ Confusion Matrix global removida (mais útil por lote)
- ❌ GlobalConfidenceDistribution removida (substituída por Erro Confiante)
- ❌ GlobalSeverityAreaChart removido (fundido com Area Chart de doenças com toggle)
- ✅ Faixa de alerta activa (condicional, não ocupa espaço quando normal)
- ✅ Sparkline Row — tendência de aprovação dos últimos 7 lotes por linha de produção
- ✅ Pareto REAL com linha cumulativa
- ✅ Erro Confiante — novo gráfico de alto valor
- ✅ Filtro temporal 7d/30d no header

---

### 3.3 Nova Estrutura — BATCH DASHBOARD

```
┌─────────────────────────────────────────────────────────────────┐
│  HEADER: "Lote [ID]" · [local] · [data] · [N maçãs]            │
│  [Badge: ACTIVO/CONCLUÍDO] [Badge: urgência ALTA/MÉDIA/BAIXA]   │
├─────────────────────────────────────────────────────────────────┤
│  KPI ROW — 5 cards                                              │
│  [Total] [Aprovação] [Doença Dom.] [Urgência ▲▼ vs anterior] [Em Revisão] │
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: SAÚDE DO LOTE (verde)                                  │
│  [Donut Patologias — flex:2] [Severity Segmented Bar — flex:2] [Cumulative Compliance — flex:3] │
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: PIPELINE DE TRIAGEM (âmbar)                            │
│  [Funil — flex:2] [Box Plot de Confiança por Doença — flex:3] [Calibração Reliability Diagram — flex:3] │
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: ANÁLISE CNN (cyan)                                      │
│  [Matriz de Probabilidade — flex:2] [CNN Trend (30d) — flex:3]  │
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: COMPARAÇÃO COM OUTROS LOTES (violeta)                  │
│  [BatchComparisonShowcase full width]                           │
├─────────────────────────────────────────────────────────────────┤
│  SECÇÃO: TRIAGEM HUMANA (violeta)                               │
│  [Overconfidence Corrections — flex:2] [Review Queue — flex:3] [Correction History — flex:2] │
└─────────────────────────────────────────────────────────────────┘
```

**Alterações vs. actual:**
- ❌ Gauge Card removido (substituído por 3 métricas inline no header)
- ❌ Radar Profile removido (redundante com Donut)
- ✅ Box Plot de Confiança movido para secção de Pipeline (junto com Calibração)
- ✅ Throughput Chart substituído por Box Plot de Confiança (throughput só aparece se timestamps forem confiáveis — lógica condicional)
- ✅ Ordem re-organizada: Saúde → Pipeline → CNN → Comparação → Humano

---

## 4. KPIs FINAIS

### Global Dashboard — 5 KPIs

| # | KPI | Valor | Sub-info | Cor semântica | Prioridade |
|---|---|---|---|---|---|
| 1 | **Aprovação Global** | 87.3% | ▲ 2.1pp vs 7d | verde/âmbar | ⭐⭐⭐ Principal |
| 2 | **Lote Urgente** | LOT-042 | C:45% G:67% | vermelho/âmbar | ⭐⭐⭐ Acção |
| 3 | **Fila Humana** | 234 | aguardam revisão | âmbar | ⭐⭐ Operacional |
| 4 | **Total Inspecionado** | 12,847 | 6 lotes activos | azul | ⭐ Contexto |
| 5 | **Autonomia IA** | 94.2% | decisão automática | cyan | ⭐⭐ Qualidade |

**KPIs removidos do actual:**
- "Frames" — é detalhe técnico, não métrica executiva.
- "Tendência (24h)" como KPI separado — fundido com badge condicional no header.
- "Lotes (últimos 30 dias)" — movido para subtexto do KPI Total.

### Batch Dashboard — 5 KPIs

| # | KPI | Valor | Sub-info | Cor semântica | Prioridade |
|---|---|---|---|---|---|
| 1 | **Taxa de Aprovação** | 82.1% | [progress bar inline] | verde/âmbar | ⭐⭐⭐ |
| 2 | **Doença Dominante** | Scab | 47 casos | cor da doença | ⭐⭐⭐ |
| 3 | **Urgência do Lote** | 38% | ▼ 12pp vs lote anterior | vermelho/âmbar | ⭐⭐⭐ |
| 4 | **Em Revisão Humana** | 23 | aguardam validação | âmbar | ⭐⭐ |
| 5 | **Total Inspecionado** | 1,243 | processadas com CNN | azul | ⭐ |

---

## 5. GRÁFICOS FINAIS — JUSTIFICAÇÃO

### Global Dashboard

#### G1 — Area Chart: Evolução de Anomalias ✅ MANTER (com melhorias)
- **Questão**: Como evoluem as doenças ao longo do tempo?
- **Melhoria**: Adicionar toggle "7d / 30d" e linha pontilhada de média móvel (3 pontos).
- **Justificação de manter**: Excelente gráfico para detectar surtos. Posição correcta.

#### G2 — Sparkline Row: Aprovação por Lote ✅ NOVO
- **Questão**: Qual é a tendência de aprovação de cada lote individual?
- **Tipo**: Row de mini-sparklines (LineChart de 6-8 pontos) por lote, ao lado do Area Chart.
- **Justificação**: Permite ao executivo comparar a trajectória de múltiplos lotes em simultâneo sem abrir cada Batch Dashboard.
- **Substitui**: Gauge (que não responde a esta questão).

#### G3 — Pareto REAL: Distribuição de Anomalias ✅ REDESENHAR
- **Questão**: Quais doenças representam 80% do problema?
- **Tipo actual**: PieChart (errado para esta pergunta).
- **Novo tipo**: BarChart descendente (horizontal) + linha cumulativa sobreposta.
- **Justificação**: O Pareto responde "onde concentrar o esforço de controlo" de forma muito mais directa que um pie chart. A linha cumulativa mostra o princípio 80/20 visualmente.

#### G4 — Heatmap Lote×Patologia ✅ MANTER (com melhorias)
- **Questão**: Quais lotes apresentam concentração de risco por patologia?
- **Melhoria**: Adicionar coluna de "Urgência Total" à direita com badge vermelho/âmbar/verde.
- **Justificação**: O heatmap é eficaz para detecção rápida de padrões em múltiplas dimensões.

#### G5 — Diverging Bar: Desvio vs. Média ✅ MANTER
- **Questão**: Quais lotes se desviam significativamente da média de aprovação?
- **Melhoria**: Tornar explícito qual a métrica (aprovação %) e adicionar linha de meta a 80%.

#### G6 — Mapa de Urgência por Lote ✅ RENOMEAR + MELHORAR
- **Questão**: Qual é o perfil risco/urgência de cada lote activo?
- **Melhoria**: Nome claro; adicionar quadrante "Alto Risco / Baixa Confiança" destacado.

#### G7 — CNN Trend Line ✅ MANTER
- **Questão**: Como evolui a confiança das CNNs ao longo do tempo?
- **Melhoria**: Separar CNN5 e CNN2 mais claramente com legendas maiores.

#### G8 — Erro Confiante ✅ NOVO (substitui Confusion Matrix global)
- **Questão**: Quando é que a IA está confiante e errada?
- **Tipo**: Grouped Bar Chart — por faixa de confiança (5 buckets), barra total vs. barra corrigida pelo humano.
- **Fonte DB**: `manual_review.original_confidence` + `manual_review.corrected_class ≠ original_class`.
- **Justificação**: A Confusion Matrix global perde contexto por agregar lotes heterogéneos. O Erro Confiante é o insight mais valioso sobre qualidade do modelo.

#### G9 — Tabela de Lotes Activos ✅ MANTER + ENRIQUECER
- **Questão**: Quais lotes estão activos e quais são os indicadores principais?
- **Melhorias**: Sparkline de aprovação inline (últimas 5 inspecções), badge de tendência, link directo para Batch Dashboard como texto âncora estilizado.

---

### Batch Dashboard

#### B1 — Donut: Distribuição de Patologias ✅ MANTER
- **Melhoria**: Adicionar valores absolutos à legenda (e.g. "Scab · 47 maçãs · 32%").

#### B2 — Severity Segmented Bar ✅ REDESENHAR (corrigir bug)
- **Questão**: Qual é a distribuição de severidade comercial do lote?
- **Tipo**: Stacked horizontal bar única (100%) com 4 segmentos: Healthy, Leve, Moderado, Grave.
- **Lógica correcta**: `Healthy = primaryCondition=='Healthy'`, `Leve = Scab/Blotch`, `Moderado = Blotch avançado`, `Grave = Rot/Anthracnose`.
- **Mostrar**: N maçãs + % por segmento, com tooltip.

#### B3 — Taxa de Conformidade Cumulativa ✅ MANTER
- **Melhoria**: Marcar claramente quando a linha cruza o limiar de 80% (annotation visual).

#### B4 — Funil de Triagem ✅ MANTER
- **Melhoria**: Adicionar percentagem de cada etapa em relação ao total.

#### B5 — Box Plot de Confiança por Doença ✅ MANTER
- **Questão**: Como varia a confiança do modelo por tipo de doença?
- **Melhoria**: Adicionar linha de threshold de 80% e realçar classes com alta variância.

#### B6 — Calibration Reliability Diagram ✅ MANTER (já de alta qualidade)
- **Questão**: A IA está bem calibrada?
- **Melhoria**: Adicionar área sombreada entre a linha de referência e a curva observada para visualizar o gap.

#### B7 — Overconfidence Corrections Chart ✅ MANTER (já implementado em proposed_visuals.diff)
- **Questão**: Em que faixas de confiança ocorrem mais erros confiantes?

#### B8 — Matriz de Probabilidade CNN ✅ MANTER
- **Questão**: Como o modelo distribui probabilidades entre classes?
- **Melhoria**: Realçar células com valor alto fora da diagonal (falsos positivos críticos).

#### B9 — CNN Trend Line ✅ MANTER
- **Questão**: Como evolui a confiança CNN neste lote vs. histórico global?

#### B10 — BatchComparisonShowcase ✅ MANTER
- **Questão**: Como este lote se compara com os outros?

#### B11 — Review Queue + Correction History ✅ MANTER

**Eliminados:**
- ❌ Gauge Card (substituído por badge no header)
- ❌ Radar Profile (redundante com Donut)
- ❌ Throughput Chart (substituído por Box Plot — throughput só quando timestamps confiáveis)

---

## 6. COMPONENTES — MELHORIAS PROPOSTAS

### 6.1 KPI Card (Global)
```
Actual:  Ícone circular + label + valor + sub
Novo:    
  - Remover ícone circular para KPIs de dados (manter apenas em KPIs de acção)
  - Aumentar valor para 22px (vs 18px actual)  
  - Badge de tendência mais proeminente: pill colorido com ▲/▼ + valor
  - Linha de separação fina (1px) entre label e valor
  - Hover state: border glow com cor semântica
```

### 6.2 KPI Card (Batch)
```
Actual:  Container com border-left colorida + ícone grande + título + valor
Novo:    
  - Manter border-left (diferenciação visual eficaz)
  - Adicionar progress bar inline no card de Aprovação
  - Reduzir ícone: 20px (vs 26px actual) — menos peso visual
  - Cor do valor = cor semântica (vs sempre branco actual)
```

### 6.3 Section Headers
```
Actual:  Icon + Title + Divider (cores inconsistentes por secção)
Novo:    
  - Sistema de cores por secção (ver paleta acima)
  - Label em UPPERCASE 11px / letterSpacing 1.5px (vs 18px bold actual)
  - Divider mais subtil: 1px / rgba(255,255,255,0.06)
  - Remover ícone das secções — o label UPPERCASE já diferencia
  - Resultado: muito menos peso visual nas transições de secção
```

### 6.4 GlassCard
```
Actual:  BackdropFilter blur:20 + border glassBorder
Melhoria:  
  - Reduzir blur para 12 (mais subtil, menos pesado em GPU)
  - Adicionar hover state: border-color brighten + subtle shadow
  - Adicionar variant "elevated": background levemente mais claro para cards críticos
  - Remover blur do GlassCard em contextos sem imagem de fundo (desnecessário)
```

### 6.5 Tabela de Lotes (Global)
```
Actual:  DataTable básico
Novo:    
  - Header fixo com sort por coluna (aprovação, urgência, data)
  - Sparkline de aprovação inline (mini LineChart 60×24px)
  - Badge de estado: ACTIVO (verde pulsado) / CONCLUÍDO (cinza)
  - Hover row: subtle background highlight
  - Link para Batch Dashboard: text âncora estilizado + ícone arrow
  - Paginação: Previous/Next com contador "Lotes 1-10 de 47"
```

### 6.6 Tooltips
```
Actual:  Texto simples, padding 12px
Novo:    
  - Adicionar título em bold + separador + conteúdo
  - Max-width: 280px
  - Shadow: rgba(0,0,0,0.4) blur:8
  - Delay de 300ms (evitar tooltips acidentais)
```

### 6.7 Empty States
```
Proposta:
  - Ícone grande (48px) com opacidade 0.2
  - Título: "Sem dados disponíveis"
  - Subtítulo: contexto específico ("Este lote ainda não tem maçãs inspecionadas")
  - CTA quando aplicável
```

### 6.8 Loading States
```
Actual:  CircularProgressIndicator centrado
Novo:    
  - Skeleton screen: GlassCard com shimmer animation
  - Cores: surface → surfaceBright → surface (loop)
  - Altura do skeleton = altura esperada do conteúdo final
```

---

## 7. EXPERIÊNCIA DO UTILIZADOR

### 7.1 Fluxo de navegação actual
```
Login → Dashboard Screen → [Global | Batch (via sidebar/tabs)]
```

### 7.2 Melhorias de UX propostas

#### A. Filtro temporal persistente
- Adicionar `FilterBar` no topo da Global Dashboard: [7 dias] [30 dias] [Custom].
- Estado partilhado via Riverpod — todos os gráficos respondem ao mesmo filtro.
- Ficheiro: `providers/dashboard_provider.dart` — adicionar `dateRangeProvider`.

#### B. Navegação rápida de lote
- Na tabela da Global, cada linha tem um link directo para a Batch Dashboard.
- No Batch Dashboard, adicionar "← Voltar à Global" e arrows "Lote anterior / próximo" no header.
- Elimina a necessidade de o utilizador navegar manualmente pela sidebar.

#### C. Alerta visual condicional
- Quando `surgeAlert ≠ 'Estável'`, mostrar uma `AlertBanner` entre o header e os KPIs.
- Cor: vermelho com ícone `Icons.warning_amber`.
- Desaparece quando resolvido — não permanente.

#### D. Responsividade
- Layout actual: `Row + Expanded` fixo — quebra em ecrãs < 1200px.
- Proposta: usar `LayoutBuilder` para adaptar:
  - ≥ 1440px: 3 colunas (actual)
  - 1200-1440px: 2 colunas
  - < 1200px: 1 coluna (scroll vertical)

---

## 8. PLANO DE IMPLEMENTAÇÃO POR FASES

### FASE 1 — CRÍTICO (1–2 semanas)
> Corrigir bugs, eliminar redundâncias, melhorar consistência.

| # | Tarefa | Ficheiro(s) | Impacto |
|---|---|---|---|
| 1.1 | Corrigir bug Severity Distribution Bar (usar contagem real de maçãs por categoria, não diseaseSum) | `batch_dashboard.dart` → `_severityDistributionBar()` | 🔴 Bug crítico |
| 1.2 | Eliminar Gauge Card do Batch Dashboard; substituir por 3 métricas inline no header | `batch_dashboard.dart` | 🔴 Redundância |
| 1.3 | Eliminar Radar Profile; espaço redirecciona para Box Plot (já existente) | `batch_dashboard.dart` | 🟠 Limpeza |
| 1.4 | Substituir Pie Chart de Pareto por BarChart horizontal descendente + linha cumulativa | `global_dashboard.dart` → `_pareto()` | 🟠 Qualidade analítica |
| 1.5 | Implementar sistema de cores de secção consistente (verde/âmbar/cyan/violeta) | `global_dashboard.dart` + `batch_dashboard.dart` → `_sec()` / `_sectionHeader()` | 🟠 Consistência |
| 1.6 | Aplicar proposed_visuals.diff (já aprovado): `_overconfidenceCorrectionsChart` renomeado e melhorado | `batch_dashboard.dart` | 🟠 Qualidade |
| 1.7 | Reduzir KPIs do Global de 7 para 5; remover "Total Frames" | `global_dashboard.dart` → `_kpiRow()` | 🟡 Clareza |
| 1.8 | Corrigir inconsistência de `_bConfCNN5()` que usa `cnn2Confidence` em vez de confiança CNN5 | `global_dashboard.dart` → `_bConfCNN5()` | 🔴 Bug lógico |

---

### FASE 2 — ALTA PRIORIDADE (2–3 semanas)
> Novos gráficos de alto valor, melhorias visuais significativas.

| # | Tarefa | Ficheiro(s) | Impacto |
|---|---|---|---|
| 2.1 | Substituir Confusion Matrix global pelo gráfico "Erro Confiante" | `global_dashboard.dart` → novo `_overconfidenceGlobal()` | 🔴 Novo insight |
| 2.2 | Adicionar filtro temporal (7d/30d) no header da Global Dashboard | `global_dashboard.dart` + `providers/dashboard_provider.dart` | 🟠 UX |
| 2.3 | Adicionar AlertBanner condicional (surge alert) | `global_dashboard.dart` → novo widget `_alertBanner()` | 🟠 Operacional |
| 2.4 | Enriquecer tabela de lotes: sparkline inline + badge estado + sort | `global_dashboard.dart` → `_table()` | 🟠 Navegação |
| 2.5 | Melhorar GlassCard: reduzir blur, hover state, variant elevated | `widgets/glass_card.dart` | 🟡 Visual |
| 2.6 | Adicionar média móvel (3 pontos) ao Area Chart de doenças | `global_dashboard.dart` → `_diseaseAreaChart()` | 🟡 Analítico |
| 2.7 | Melhorar loading states: skeleton screens com shimmer | Novo widget `widgets/skeleton_card.dart` | 🟡 Polish |
| 2.8 | Adicionar navegação rápida entre lotes no Batch Dashboard header | `batch_dashboard.dart` | 🟡 UX |

---

### FASE 3 — MÉDIA PRIORIDADE (3–4 semanas)
> Refinamentos, novas métricas, responsividade.

| # | Tarefa | Ficheiro(s) | Impacto |
|---|---|---|---|
| 3.1 | Implementar LayoutBuilder para responsividade 1col/2col/3col | `global_dashboard.dart` + `batch_dashboard.dart` | 🟠 Acessibilidade |
| 3.2 | Adicionar Sparkline Row por lote no Global Dashboard | `global_dashboard.dart` → novo `_sparklineRow()` | 🟡 Visual |
| 3.3 | Área sombreada no Calibration Reliability Diagram (gap visual) | `batch_dashboard.dart` → `_calibrationReliabilityDiagram()` | 🟡 Analítico |
| 3.4 | Indicador de throughput condicional (só aparece se desvio padrão de timestamps < threshold) | `batch_dashboard.dart` → `_throughputChart()` | 🟡 Qualidade |
| 3.5 | Realce automático de células fora da diagonal na Prob Matrix | `batch_dashboard.dart` → `_probMatrix()` | 🟡 Analítico |
| 3.6 | Tooltip melhorado com título + separador + body (novo componente) | Novo widget `widgets/rich_tooltip.dart` | 🟡 Polish |
| 3.7 | Empty states com ilustração + mensagem contextual | Todos os gráficos | 🟡 Polish |
| 3.8 | KPI Card com progress bar inline (Aprovação) | `batch_dashboard.dart` → `_section1Kpis()` | 🟡 Visual |

---

### FASE 4 — BAIXA PRIORIDADE / ROADMAP (futuro)
> Features que requerem novas queries à DB ou nova lógica de negócio.

| # | Tarefa | Notas |
|---|---|---|
| 4.1 | Taxa de correção por operador (gráfico novo) | Requer query a `manual_review.updated_by` |
| 4.2 | Perda comercial estimada por lote | Requer definição de preço/maçã × severityScore |
| 4.3 | Tendência de precisão do modelo ao longo do tempo (vs. apenas confiança) | Requer ground-truth consolidado em `manual_annotation` |
| 4.4 | Dashboard de `producao_atual` em tempo real | Requer Supabase Realtime subscription |
| 4.5 | Export PDF melhorado com tema premium | `services/pdf_service.dart` |
| 4.6 | Modo claro (light mode) | Novo tema em `utils/constants.dart` |

---

## 9. RESUMO EXECUTIVO

### O que está bem
A dashboard actual tem uma base sólida: modelo de dados bem estruturado, hierarquia KPIs → produção → CNN → tabela correcta, paleta de cores coesa com semântica clara, e gráficos avançados como o Reliability Diagram já implementados.

### Problemas prioritários a resolver
1. **Bug na Severity Bar** — mostra sempre ~100% (correcção simples, impacto alto).
2. **Gauge duplicado** — mesmo score em KPI e em gráfico dedicado — eliminar.
3. **Pareto implementado como Pie** — não responde à questão de negócio adequadamente.
4. **Bug em `_bConfCNN5()`** — usa `cnn2Confidence` em vez de confiança CNN5.
5. **7 KPIs na mesma linha** — excessivo; reduzir para 5 priorizados.

### Maior oportunidade de impacto
Substituir a Confusion Matrix global pelo gráfico de **Erro Confiante** (maçãs com confiança ≥80% e correcção humana) — transforma um gráfico técnico num insight directamente accionável para o gestor de qualidade.

### Filosofia de redesign
> **Cada visualização deve existir para tomar uma decisão, não para mostrar dados.**

A versão 2.0 desta dashboard não é mais colorida nem tem mais gráficos — é mais precisa, mais rápida de ler e mais fácil de agir sobre ela.
