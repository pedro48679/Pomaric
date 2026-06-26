# Questão dos Gráficos da Dashboard

Este documento documenta a lógica das visualizações utilizadas na Dashboard Global e na Dashboard de Lote. Cada gráfico deve responder a uma questão clara de negócio ou operação; gráficos que não respondem a uma questão são desnecessários.

## Dashboard Global

### Visão geral da estrutura desejada
1. KPIs no topo
2. Visão global da produção
3. Análise de lotes específicos, metas e evolução temporal
4. Qualidade dos CNNs
5. Tabela de lotes ativos com links para dashboards de lote

### Gráficos existentes

#### 1. Evolução de Anomalias (`disease area chart`)
- Questão: Como as doenças evoluem ao longo do tempo em todos os lotes?
- Resposta: mostra a incidência percentual de cada patologia por dia.
- Qualidade: Alta. Entrega informação nova e relevante, essencial para detectar surtos e tendências.
- Melhoria: adicionar uma linha de média móvel ou um alerta de crescimento de anomalia para sinalizar mudanças abruptas.

#### 2. Saúde Global (`gauge`)
- Questão: Qual é o estado consolidado da produção considerando aprovação, confiança e urgência?
- Resposta: apresenta uma pontuação composta de aprovação, confiança e urgência.
- Qualidade: Média-Alta. Boa síntese, mas pode regurgitar elementos já presentes em KPIs individuais.
- Melhoria: expor claramente como cada componente contribui para a nota, e reduzir a sobreposição com KPIs separados.

#### 3. Distribuição de Anomalias (`pareto`)
- Questão: Quais doenças têm maior impacto nas anomalias totais?
- Resposta: identifica as patologias mais frequentes / impactantes.
- Qualidade: Alta. É um gráfico objetivo que prioriza ação.
- Melhoria: incluir taxa de crescimento da doença para destacar ameaças emergentes.

#### 4. Heatmap de lotes (`heatmap`)
- Questão: Quais lotes apresentam padrão de risco por patologia?
- Resposta: mostra a intensidade de doença por lote e tipo.
- Qualidade: Média. Boa visão de risco, mas precisa de contexto para que não pareça apenas estética.
- Melhoria: adicionar filtros de severidade ou um destaque automático para lotes críticos.

#### 5. Gráfico divergente de lotes (`diverging bar`)
- Questão: Quais lotes se destacam em relação ao desempenho médio?
- Resposta: compara lotes em métricas de qualidade e urgência.
- Qualidade: Média-Alta. Complementa a visão de lotes específicos.
- Melhoria: tornar explícito qual métrica está sendo divergida e adicionar benchmark de meta.

#### 6. Confiança média CNN (`cnn evolution` / `trend line`)
- Questão: Como evolui a confiança média das CNNs ao longo do tempo?
- Resposta: traz a comparação de CNN5 e CNN2 em média de confiança por dia.
- Qualidade: Alta. É um gráfico de qualidade para avaliar estabilidade do modelo.
- Melhoria: separar CNN5 e CNN2 em painéis distintos para reduzir ruído e facilitar interpretação.

#### 7. Matriz de confusão global (`confusion matrix`)
- Questão: Onde o modelo se confunde entre as classes?
- Resposta: exibe acertos e erros por classe.
- Qualidade: Alta. Entrega insight direto sobre performance do modelo.
- Melhoria: realçar classes com alta confusão e recomendar retreino ou revisão de classes.

#### 8. Distribuição de confiança global (`global confidence distribution`)
- Questão: Qual é a distribuição da confiança das previsões em todos os lotes?
- Resposta: mostra o spread de confiança do modelo em produção.
- Qualidade: Média. Complementa CNN evolution, mas pode ser redundante se o painel de confiança já estiver claro.
- Melhoria: vincular ao desempenho real (correções humanas) em vez de apenas à confiança.

#### 9. Tabela de lotes ativos e detalhes (`table`)
- Questão: Quais lotes estão ativos e quais são seus principais indicadores?
- Resposta: apresenta lotes, aprovação, risco e tendência com acesso ao detalhe.
- Qualidade: Alta. É necessária para navegação operacional.
- Melhoria: incluir coluna de link direto ou ação clara para acessar o dashboard do lote.

### Avaliação geral da Dashboard Global
- Estrutura: boa, com uma hierarquia clara de KPIs → produção → lotes → CNN → tabela.
- Qualidade: forte, já entrega visão executiva e operacional.
- Oportunidade: reduzir redundância entre KPI composto e métricas individuais, e fortalecer a narrativa de meta/melhor vs pior lote.

## Dashboard de Lote

### Visão geral da estrutura desejada
1. KPIs do lote no topo
2. Saúde do lote, patologia e conformidade
3. Fluxo de triagem, confiança e calibração
4. Comparação com outros lotes
5. Métricas de produção e análise de CNN

### Gráficos existentes

#### 1. Distribuição de Patologias (`donut`)
- Questão: Qual é a proporção de saúde vs patologias no lote?
- Resposta: mostra fatias por condição.
- Qualidade: Alta. É direto e relevante.
- Melhoria: tornar a legenda mais informativa com valores absolutos e severidade esperada.

#### 2. Saúde do Lote (`gauge card`)
- Questão: Qual é o score composto do lote?
- Resposta: junta aprovação, confiança e urgência.
- Qualidade: Média. Bom resumo, mas repete informações dos KPIs do topo.
- Melhoria: usar um score mais simples ou segmentar a avaliação para cada dimensão.

#### 3. Taxa de Conformidade Cumulativa (`cumulative compliance`)
- Questão: Como a conformidade evolui durante o processamento do lote?
- Resposta: mostra a evolução da proporção de maçãs saudáveis cumulativamente.
- Qualidade: Média-Alta. Útil se o lote tiver variação temporal interna.
- Melhoria: mostrar claramente pontos de transição ou quando o lote cruza limiares importantes.

#### 4. Radar de Perfil do Lote (`radar profile`)
- Questão: Qual é o perfil de confiança por patologia?
- Resposta: calcula probabilidades médias por classe.
- Qualidade: Baixa-Média. Muito semelhante à distribuição de patologias do donut e não adiciona novidade suficiente.
- Melhoria: substituir por um gráfico que compare doenças em severidade ou tempo, ou focar em risco comercial / loteiro.

#### 5. Funil de Triagem (`triagem funnel`)
- Questão: Como o lote progride desde inspeção até revisão e correção?
- Resposta: mostra o fluxo operacional do pipeline.
- Qualidade: Alta. Tem sentido e agrega valor operacional.
- Melhoria: especificar melhor os limiares de incerteza e quantificar tempo médio em cada etapa.

#### 6. Box Plot de Confiança (`confidence box plot`)
- Questão: Como a confiança varia por doença?
- Resposta: mostra mínimo, média e máximo por condição.
- Qualidade: Média-Alta. Entrega informação nova sobre variabilidade.
- Melhoria: indicar se a distribuição está dentro de faixas aceitáveis e quando a classe perde robustez.

#### 7. Velocidade de Vazão (`throughput chart`)
- Questão: Qual é a taxa de maçãs processadas por minuto ao longo do lote?
- Resposta: apresenta throughput e meta nominal.
- Qualidade: Média. Tem potencial, mas depende da qualidade dos timestamps.
- Melhoria: se a vazão for real, mostrar gaps e modos de processamento lento; caso contrário, marcar como estimativa.

#### 8. Segmentação de Severidade (`severity distribution bar`)
- Questão: Como o lote se distribui entre graus de severidade?
- Resposta: mostra percentuais de saúde, leve, moderado e grave.
- Qualidade: Média-Alta. Útil para avaliar aproveitamento comercial.
- Melhoria: esclarecer critérios de segmentação e evitar confusão entre severidade e tipo de doença.

#### 9. Calibração de IA (`calibration chart`)
- Questão: Em quais faixas de confiança ocorrem as correções humanas?
- Resposta: identifica onde a IA acha que está certa, mas o humano corrige.
- Qualidade: Alta. Insight relevante sobre erro confiante.
- Melhoria: relacionar diretamente com custo de revisão ou volume de retrabalho.

#### 10. Matriz de Probabilidade CNN (`probMatrix`)
- Questão: Como o modelo distribui probabilidades entre classes previstas?
- Resposta: mostra a confiança média em cada classe para cada classe prevista.
- Qualidade: Alta. Excelente para entender confusão específica do lote.
- Melhoria: limitar a visualização a classes com volume relevante e realçar falsos positivos críticos.

#### 11. Comparação de Lotes (`BatchComparisonShowcase`)
- Questão: Como este lote se comporta em relação a outros lotes ou à média histórica?
- Resposta: compara métricas-chave com a média ou lote específico.
- Qualidade: Alta. Fornece contexto operacional.
- Melhoria: incluir uma recomendação de ação (ex: 'mais urgente que a média', 'menor confiança que o esperado').

### Avaliação geral da Dashboard de Lote
- Ponto forte: seção de saúde e fluxo de triagem está bem estruturada.
- Ponto fraco: há redundância entre `donut` e `radar profile`; o radar poderia ser substituído por um gráfico mais distinto.
- Ponto forte: comparação entre lotes e calibração IA têm alto valor.
- Melhoria geral: priorizar clareza e reduzir gráficos que regurgitam a mesma informação; foco em insights acionáveis e operacionais.

## Recomendação de reformulação
- Dashboard Global: manter KPIs no topo e reforçar a visão de produção com metas e alertas.
- Dashboard Global: usar a área de anomalias para sinalizar surtos e não apenas mostrar curvas.
- Dashboard Global: destacar os lotes corretos para investigação no heatmap / diverging bar.
- Dashboard de Lote: substituir o radar de perfil por um gráfico de severidade por doença ou um gráfico de tendência de problemas.
- Dashboard de Lote: reforçar o throughput com contexto de meta e a calibração com custo de retrabalho.
- Dashboard de Lote: assegurar que cada visualização entregue um insight novo e não apenas um reescrito do que já existe.

## Conexão com a Base de Dados
Com base na estrutura de `DB_structure.md`, a dashboard deve aproveitar melhor estas tabelas:
- `apples`: chave primária para cada fruta e carimbo temporal para análise de fluxo e produção.
- `frames`: `diseaseSum` e `probabilities` fornecem a per-apple confiança por classe; são a base da calibração e do perfil de severidade.
- `cnn_predictions`: model_name, label e confidence permitem separar CNN2 vs CNN5 e reconstruir a confiança do modelo em cada maçã.
- `manual_review` / `manual_annotation`: armazenam correções humanas e classes finais, essenciais para medir calibração e erro confiante.
- `producao_atual`: pode ser usada para alimentar métricas operacionais de inspeção em tempo real.

### Melhoria para o gráfico de Severidade por lote
Problema atual:
- o gráfico está visualmente incorreto e tende a gravar 100% continuamente, porque está usando valores de probabilidade ou `diseaseSum` como se fossem percentuais.

Planos de correção:
1. Usar a métrica `severityScore` do `Batch` ou agrupar por severidade real em classes: `Healthy`, `Leve`, `Moderado`, `Grave`.
2. Calcular percentuais pelo número de maçãs em cada categoria, não pela soma de probabilidades. Dessa forma o eixo terá significado real e não será sempre 100%.
3. Exibir um gráfico de barras empilhadas ou uma barra segmentada, com legendas explícitas de valor absoluto + percentual.
4. Se quiser manter a relação com doenças, usar um gráfico de barras horizontais que mostre a taxa de cada doença por severidade/impacto.

### Mudança para o gráfico de Confiança da IA
Problema atual:
- não agrega informação nova; muitas vezes é apenas uma distribuição de confiança sem correlação com erro ou ação.

Plano de substituição:
1. Trocar para um gráfico de calibração real: buckets de confiança (por exemplo, `<60%, 60-70%, 70-80%, 80-90%, >90%`) versus taxa de correção humana.
2. Usar `manual_review` / `correctionHistory` para separar ``IA correta`` de ``IA errada`` em cada bucket.
3. Mostrar claramente quando a IA está `confiante e errada` — esse é o insight crítico que a matriz já complementa.
4. Colocar esse gráfico ao lado da matriz de probabilidade para formar um par: a matriz detalha “onde o modelo confunde doenças” e a calibração mostra “quando a confiança era alta apesar do erro”.

### Proposta concreta de visualização do novo gráfico de calibração
- Eixo X: faixas de confiança da IA (porcentagem)
- Eixo Y: número ou proporção de correções manuais
- Dois conjuntos de barras: correções em casos que o modelo era confiante x correções em casos de baixa confiança
- Linha de meta: taxa esperada de erro para cada faixa, evidenciando falhas de calibração

### Melhorias gerais baseadas na DB
- Usar `cnn_predictions.model_name` para separar CNN2 e CNN5 de forma consistente nos relatórios.
- Usar `manual_annotation.primary_apple_disease` e `manual_review.corrected_class` para calcular a exatidão real pós-revisão.
- Criar um gráfico de `Erro Confiante` diretamente: maçãs com confiança >= 80% e correção humana realizada.
- Em vez de exibir apenas percentuais de confiança, mostrar `precisão por bucket de confiança` (calibration curve).

## Princípio de Design
- Todo gráfico deve começar com uma pergunta clara.
- A visualização deve responder a essa pergunta com informação nova.
- Evitar gráficos que regurgitam dados já exibidos em outro painel.
- Perguntar a pergunta básica: "O que preciso decidir com esta visualização?" antes de manter o gráfico.
