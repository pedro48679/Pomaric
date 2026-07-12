# Suporte de secretária: Raspberry Pi Camera Module 3

Stand ajustável para a câmara, em **3 peças impressas em 3D**. A câmara aparafusa à peça da frente, o ângulo ajusta-se com a mão e pode trancar-se com um parafuso. Todo o hardware necessário são parafusos M2 (um kit sortido de ~5€ na Amazon cobre tudo).

---

## O que está nesta pasta

- `camera_stand.scad`: o ficheiro-fonte do design (abre no OpenSCAD, incluindo a versão web). Só é preciso se quiseres alterar o design; para imprimir, ignora.
- `final/base.stl`: **Peça 1**: a base que assenta na mesa, com a caixa onde o braço encaixa.
- `final/arm.stl`: **Peça 2**: o braço vertical, com os dois pinos da dobradiça no topo.
- `final/head.stl`: **Peça 3**: a moldura onde a câmara aparafusa, com as duas abas que encaixam nos pinos.
- `final/assembly.stl`: o conjunto montado, **apenas para veres como fica no fim. NÃO imprimir este ficheiro**: sairiam as 3 peças coladas umas às outras.

---

## Instruções de impressão

Definições no slicer (o programa que prepara o STL para a impressora : Cura, PrusaSlicer, etc.):

- Altura de camada: **0.2mm** (o normal)
- **3 perímetros/paredes**, importante: a resistência destas peças vem das paredes, não do enchimento
- Enchimento (infill): **15–20%**, qualquer padrão
- **Não escalar as peças!** Os encaixes têm folgas de décimas de milímetro desenhadas ao certo, mudar o tamanho estraga tudo
- PETG: ~235°C no bico, ventoinha reduzida nas primeiras camadas

Cada STL **já vem virado na posição certa**, é abrir no slicer e fatiar, sem rodar nada:

- **base.stl**, imprime como está (pés para baixo). Sem suportes.
- **arm.stl**, imprime deitado, como está. É de propósito: assim as camadas de plástico correm ao longo do braço, que fica muito mais forte (em pé, partiria como uma bolacha). Único cuidado: os **2 pinos laterais precisam de suporte por baixo**, ativar "suportes a tocar na base" (touching buildplate). Depois de imprimir, cortar os suportes com um x-ato, sem torcer os pinos.
- **head.stl**, imprime como está (a face da lente fica virada para baixo). Sem suportes. Nota: o rebordo interior imprime "em ponte" sobre um vão pequeno, é normal e a impressora resolve sozinha; se ficar um bocadinho descaído, é na face escondida atrás da câmara, não interessa.

---

## Parafusos e cabo (comprar)

- 4× **M2 auto-roscante, 6mm**, prendem a câmara à moldura. (Não usar 8mm aqui: são compridos demais e furam o outro lado.)
- 1× **M2, 6 a 8mm**, o parafuso de bloqueio do ângulo, enrosca no boss da aba direita da cabeça.
- 1× M2, 6 a 8mm (opcional), para travar o braço na base em definitivo, entra por trás da caixa.
- "Auto-roscante" quer dizer que o parafuso abre a própria rosca no plástico, os furos já vêm impressos no tamanho certo para isso.

---

## Montagem (5 minutos)

1. Encaixa o braço na caixa da base, à pressão, até ao fundo. Se quiseres que nunca mais saia, mete o M2 opcional no furo por trás da caixa.
2. Encaixa a câmara no bolso da moldura, pela frente. O cabo sai por baixo, pelo rasgo aberto.
3. Aparafusa os 4 M2 por trás da moldura, nos furos pequenos. **Aperta até encostar e para**, se forçares, a rosca no plástico espana.
4. Alinha as duas abas da cabeça sobre os pinos do braço e carrega para baixo até ouvir o **clique**.
5. Enrosca o parafuso de bloqueio no boss da aba direita.
6. Passa o cabo entre os dois braços da cabeça, cai direitinho pelo buraco do meio da base.

---

## Ajustar o ângulo (entre −25° e +45°)

- **No dia a dia**: roda a cabeça com dois dedos. A fricção segura-a onde a deixares.
- **Para trancar**: aperta o parafuso de bloqueio, o bico encosta ao disco da dobradiça e o ângulo fica fixo, mesmo que a fricção tenha saído fraca da impressão.
- **Para trancar em definitivo** (quando já souberes o ângulo certo): desaperta o parafuso, mete uma broca de 1.6mm pelo furo da aba (serve de guia) e fura 3–4mm para dentro do disco. Volta a enroscar o parafuso, agora atravessa as duas peças e o ângulo fica trancado a aço, para sempre. 

---

## Se algo não encaixar bem

A regra: **apertado resolve-se a lixa; largo resolve-se com o parafuso**. As folgas foram desenhadas de propósito ligeiramente apertadas, porque tirar material é fácil.

- Abas não entram nos pinos → passar uma broca de 5mm à mão dentro dos furos das abas (furos horizontais encolhem sempre um pouco na impressão)
- Ângulo muito duro de rodar ao início → rodar 20–30 vezes; o plástico assenta e fica no ponto
- Braço não entra na caixa → lixa grossa nas faces do braço, 3-4 passagens
- Braço dança na caixa → o parafuso de trás resolve
- Câmara não entra no bolso → raspar a borda de entrada com x-ato
- Câmara descai sozinha → apertar o parafuso de bloqueio
- Partiu um pino ou uma aba → reimprime-se **só essa peça** (braço ~20 min, cabeça ~40 min)

---

## Modificações possiveis

Abrir `camera_stand.scad` no OpenSCAD (ou em openscad.org no browser). No topo do ficheiro, mudar `part` para `"base"`, `"arm"` ou `"head"` e exportar STL (F6 → F7). Os três valores mais úteis de afinar:

- `squeeze` (0.15), fricção da dobradiça: subir = mais dura
- `sock_clr` (0.15), folga do encaixe base↔braço: subir = mais largo
- `snap_w` (4.2), dureza do clique das abas: subir = mais fácil de encaixar

Os furos da câmara seguem o padrão real da Camera Module 3 (21.0 × 12.5mm, desviado 3.7mm do centro da placa, medido no modelo CAD oficial da Raspberry Pi), por isso não mexer nesses valores.
