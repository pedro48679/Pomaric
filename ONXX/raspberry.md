# raspberry_camera_format.py — Documentação Detalhada

## 1. Objetivo do ficheiro
- Capturar imagens no Raspberry Pi.
- Processar localmente para detetar e recortar maçãs.
- Classificar cada maçã com um modelo ONNX.
- Enviar resultado e imagens para um PC remoto por WebSocket ou SCP.
- Suportar modos:
  - `SINGLE`: captura uma foto única.
  - `BURST`: captura várias fotos em rajada com pipeline concorrente.
  - `STREAM`: vigilância contínua com deteção de movimento em ROI.

## 2. Motivações de design
- Otimizar para Raspberry Pi 5 e hardware limitado.
- Evitar dependências pesadas e flows de processamento lentos.
- Minimizar I/O e fazer o máximo em memória e CPU local.
- Aumentar robustez com fallback manual e análise de qualidade de imagem.
- Manter flexibilidade com flags para controlar foco, exposição, e modo de envio.

## 3. Flags e flexibilidade
### Principais flags explicadas
- `--model`: caminho para o modelo ONNX no Pi.
- `--ws-server`: URI do servidor WebSocket para envio direto.
- `--burst`: número de fotos em rajada; se `>1` ativa modo burst.
- `--burst-interval`: tempo entre fotos em burst, em ms.
- `--shutter-us`: tempo de exposição em microssegundos; baixo congela movimento.
- `--stream`: ativa o modo de vigilância contínua.
- `--motion-threshold`: sensibilidade do trigger de movimento.
- `--trigger-delay`: atrasa a captura após detetar movimento.
- `--lens-position`: foco manual em dioptrias. `0.0` = autofocus.
- `--sharpness`, `--contrast`, `--saturation`, `--noise-reduction`: ajuste fino da qualidade da captura.
- `--width`, `--height`: resolução de captura em alta qualidade.

### Porquê esta flexibilidade?
- `--burst` permite capturar múltiplos frames para melhorar a confiança e filtrar frames desfocados.
- `--stream` permite operação vigilante com baixo consumo até ser necessário capturar alta resolução.
- Ajustes de imagem permitem adaptar o Pi a diferentes condições de iluminação.
- `--ws-server` vs SCP dá suporte a duas infraestruturas diferentes de transporte.

## 4. Foco e distância: `lens_position`
### Como o script trata o foco
- `CameraStream.start()` tenta usar `Picamera2` se disponível.
- Se `lens_position > 0.0`:
  - ativa `AfModeEnum.Manual`.
  - define `LensPosition` para o valor fornecido.
- Se `lens_position == 0.0`:
  - usa autofocus contínuo em modo macro.

### Cálculo físico do foco manual
- O parâmetro `lens_position` é tratado como dioptrias.
- Fórmula: `distância (m) = 1 / dioptrias`.
- Exemplo:
  - `2.2` dioptrias → `1 / 2.2 ≈ 0.4545 m` → aproximadamente `45 cm`.
  - Para `40 cm`, o valor correto seria `1 / 0.40 = 2.5` dioptrias.
- Conclusão:
  - `2.2` não é exatamente 40cm; é mais próximo de `45 cm`.
  - O comentário do código diz `2.5 para 40cm`, o que está consistente com a fórmula.

## 5. Captura de imagem
### `capture_image()`
- Executa o comando do `rpicam-still`.
- Substitui `{output}` no comando se presente.
- Valida o código de retorno e a existência do ficheiro.
- Fornece mensagens de erro claras para problemas de escrita de ficheiro.

### Configuração padrão para `SINGLE`
- `rpicam-still -t <capture_time> --width 2304 --height 1296 --autofocus-mode continuous --autofocus-range macro --exposure sport -q 95 -n -o {output}`
- Razões:
  - `2304x1296` é alta resolução 16:9 para detalhe.
  - `macro` e `continuous` maximizam foco em curtas distâncias.
  - `sport` prioritiza obturador rápido e reduz motion blur.
  - JPEG 95% equilibra detalhe e tamanho de ficheiro.

## 6. Detecção de maçã e cálculo do raio
### `find_apple_region()`
- Converte a imagem para `RGB` e reduz para miniatura de até `128px` no lado maior.
- Usa HSV para segmentar pixels de maçã:
  - amarelo-verde: `0.08-0.26`
  - vermelho: `0-0.10` ou `0.88-1.0`
- Filtra por saturação `>0.38` e brilho `>0.22`.
- Bloqueia tom de pele fora da zona central para evitar a mão.

### Detalhes de robustez
- Cria componentes conectados para agrupar regiões de cor.
- Analisa contorno e circularidade para distinguir maçã de objetos não circulares.
- Usa `fit_circle_ransac()` para ajustar uma circunferência robusta.
- Fallback: se RANSAC falhar, usa o maior blob de cor.

### `fit_circle_ransac()`
- Seleciona 3 pontos aleatórios em cada iteração.
- Resolve a equação da circunferência diretamente para velocidade.
- Sanity checks:
  - ignora raios menores que 8 px ou maiores que 80 px no thumbnail.
- Conta inliers por distância ao círculo estimado.
- Refina com a solução de Kasa dos inliers.
- Resulta em centro e raio confiáveis.

### Porquê foco pela distância e raio?
- O foco manual e o recorte dependem diretamente da distância objetiva.
- A detecção de raio circular ajuda:
  - a construir máscara de fundo precisa;
  - centralizar o recorte na maçã;
  - estimar a dimensão da fruta no frame.
- A máscara circular reduz ruído de fundo e mantém apenas a área relevante.

## 7. Preprocessamento e maximização de desempenho
### `process_and_crop_transparent()`
- Carrega JPEG de alta resolução e converte para `RGB`.
- Usa `find_apple_region()` para recortar um quadrado generoso ao redor da maçã.
- Gera PNG transparente com máscara circular baseada na detecção de raio.
- Faz apenas um resize de alta qualidade para `224x224` no final.
- Normaliza para ImageNet e retorna tensor `np.float32` shape `[1,3,224,224]`.

### Otimizações importantes
- Somente um resize final de alta qualidade, evitando vários redimensionamentos.
- Máscara alfa binarizada para bordas nítidas.
- Uso de `PNG` transparente nos resultados enviados.
- Preparação do tensor em memória para ONNX sem dependências de frameworks grandes.

### `compute_blur_score()`
- Calcula desfoque com variância do Laplaciano numa thumbnail `256x256` grayscale.
- Complexidade baixa, rápido no Pi 5 (~0.5ms).
- Usa kernel 3x3 manual para evitar overhead de funções externas.
- Fornece métrica de qualidade para peso no consenso e para logs.

## 8. Inferência ONNX
### `infer()`
- Cria `InferenceSession` com `CPUExecutionProvider`.
- Alimenta o modelo com o tensor preparado.
- Usa `postprocess_output()` para converter logits em label/confiança.

### `postprocess_output()`
- Suporta saídas binárias `(1,)` ou multi-classe.
- Se saída unidimensional, aplica sigmoid.
- Se saída multiclasse, aplica softmax.
- Retorna rótulo, índice e confiança.

## 9. Modo `BURST`
### Objetivo e vantagens
- Capturar vários frames rápidos para robustez.
- Usar intervalos curtos (`150 ms` por defeito) para congelar movimento.
- Processar frames em paralelo usando `ThreadPoolExecutor`.

### Pipeline do burst
1. Preparar o comando `rpicam-still` em `timelapse`.
2. Iniciar processo externo e aguardar estabilidade de foco.
3. Disparar a rajada com stdin.
4. `wait_for_file()` aguarda cada JPEG.
5. Submete cada frame a uma thread para:
   - calcular blur;
   - processar crop e transparência;
   - correr ONNX.
6. Termina o processo da câmara após capturar todos os frames.
7. Agrega resultados e imprime logs.

### Maximização de desempenho
- A captura usa burst nativo do `rpicam-still` em vez de capturas sequenciais independentes.
- O processamento paralelo transforma `sum(proc_i)` em `max(proc_i)` de tempo de parede.
- O modelo é carregado apenas uma vez antes do burst.
- A sua lógica evita bloqueios I/O ao submeter frames assim que surgem no disco.

## 10. Modo `STREAM` de vigilância
### Objetivo
- Permanecer em modo de low-power e pegar movimento apenas nas laterais.
- Reduzir uso de CPU e disco enquanto não há alvo relevante.
- Reativar captura de alta qualidade apenas quando necessário.

### Arquitetura
- `CameraStream` mantém captura em background via `threading.Thread` e `VideoCapture`/`Picamera2`.
- `stream.read()` devolve `frame_rgb` para visualização e `gray_lores` para análise de movimento.
- `gray_lores` é uma versão reduzida `640x360`, suficiente para detecção rápida.

### Detecção de movimento
- Usa ROIs laterais de `15%` na esquerda e direita.
- Compara frame atual com frame anterior após compensação de brilho.
- Conta pixels com mudança absoluta maior que `25`.
- `motion_threshold` define o trigger.

### Lógica de estado
- `lock_state` controla se o gatilho aceita apenas um lado específico.
- `cooldown_until` evita re-trigger imediato.
- `in_repouso` reduz resolução para `640x360` após 1 min de inatividade.
- O stream volta ao modo ativo quando movimento é novamente detetado.

### Fluxo completo do stream
1. Ler novo frame.
2. Verificar modo repouso.
3. Suavizar com GaussianBlur.
4. Calcular compensação de brilho global.
5. Comparar ROI esquerda/direita com frame anterior.
6. Se trigger, capturar burst direto do stream.
7. Processar frames em paralelo.
8. Enviar resultados.
9. Ativar cooldown de 1 segundo.

## 11. Envio de resultados
### WebSocket
- `ws_send()` estabelece ligação a um servidor WebSocket.
- Envia JSON serializado.
- Espera uma resposta opcional.
- Usa `asyncio.run()` para simplificar a chamada síncrona.

### SCP
- `ensure_remote_dir()` tenta criar diretório remoto via SSH.
- `scp_send()` copia ficheiros para o PC remoto.
- O modo SCP envia:
  - PNG transparente;
  - crop JPEG;
  - original JPEG de alta resolução;
  - JSON de metadados.

### Formato payload
- `send_result()` e `send_burst_results_ws()` enviam:
  - `label`, `index`, `confidence`
  - `image_b64` de alta resolução ou miniatura
  - `crop_image_b64`
  - `image_resized_b64` de `224x224`
- No burst, envia também todos os frames e um resultado de consenso.

## 12. Consenso ponderado em burst
- `send_burst_results_ws()` agrega frames com peso baseado em:
  - `confidence`
  - `blur_score`
- Frames nítidos têm mais influência.
- O rótulo final é o com maior peso acumulado.
- Confiança final é média ponderada pelos scores de nitidez.

## 13. Otimizações de processamento
### Principais ganhos
- Redução de resolução seletiva:
  - `128px` para deteção de maçã.
  - `256px` para blur.
  - `640x360` para análise de movimento.
- Uso de `ThreadPoolExecutor` para paralelizar inferência e crop.
- Evitar múltiplos redimensionamentos grandes.
- Processamento em memória com `numpy` e `PIL`.
- Aprimorar a máscara com desfoque gaussiano seguido de binarização.
- `rpicam-still` em modo `timelapse` evita overhead de reinicializar a câmara.

## 14. Como o fluxo funciona do início ao fim
### Fluxo para `SINGLE`
1. Recebe flags e valida modelo.
2. Executa captura com `rpicam-still`.
3. Detecta maçã e recorta região relevante.
4. Cria PNG transparente e normaliza tensor.
5. Corre inferência ONNX.
6. Envia resultado por WebSocket ou SCP.

### Fluxo para `BURST`
1. Carrega modelo ONNX uma vez.
2. Inicia burst com `rpicam-still --timelapse`.
3. Espera ficheiros no disco.
4. Processa cada frame em paralelo.
5. Calcula blur e classificação por frame.
6. Envia payload consolidado.

### Fluxo para `STREAM`
1. Inicializa `CameraStream`.
2. Continua a ler frames em background.
3. Analisa movimento nas laterais.
4. Se trigger, captura burst do stream.
5. Processa e envia resultados.
6. Regressa a vigilância com cooldown.

## 15. Foco por distância e razão do foco pelo raio
- A distância afeta:
  - a escolha do modo de foco
  - a necessidade de recortar a área correta.
- A máscara circular usa o raio estimado da maçã para:
  - separar fruta do fundo;
  - reduzir falsos positivos;
  - gerar um crop centralizado e compacto.
- Esta abordagem é eficiente porque a maçã tem formato aproximadamente esférico/circular.

## 16. Notas importantes para relatório
- `focus-lens = 2.2`: corresponde a cerca de `45 cm`, não exatamente `40 cm`.
- `2.5` dioptrias é o valor indicado para `40 cm` pelo próprio comentário do script.
- A estratégia de processamento prioriza:
  - velocidade de captura,
  - nitidez do frame,
  - robustez de deteção,
  - envio eficiente de resultados.
- O design mistura detecção clássica por cor com inferência ONNX, evitando depender somente de redes neurais para localização.

## 17. Observações de fiabilidade
- A deteção por cor é rápida e adequada para maçãs, mas depende de iluminação.
- A máscara circular é tolerante a formas orgânicas e a corte parcial.
- O sistema tem fallback no maior blob quando RANSAC falha.
- A vigilância de movimento nas laterais reduz disparos falsos e foca em objectos que entram no enquadramento.

## 18. Recomendação de uso
- Usar `--stream` para aplicações de vigilância contínua.
- Usar `--burst 3 --burst-interval 150` quando a estabilidade de objecto for variável.
- Ajustar `--motion-threshold` para menos falsos positivos em cenários com vento ou vibração.
- Ajustar `--lens-position` para foco manual em distâncias fixas.
- Confirmar `--ws-server` ou SCP conforme a rede disponível.

## 19. Exemplo de comando
- Modo single com WebSocket:
  ```bash
  python3 raspberry_camera_format.py \
    --model /home/minipc/models/model2.onnx \
    --ws-server ws://192.168.43.142:8765
  ```
- Modo burst para 3 frames:
  ```bash
  python3 raspberry_camera_format.py \
    --model /home/minipc/models/model2.onnx \
    --ws-server ws://192.168.43.142:8765 \
    --burst 3 --burst-interval 150
  ```
- Modo stream com enfoque manual de `2.2` dioptrias:
  ```bash
  python3 raspberry_camera_format.py \
    --model /home/minipc/models/model2.onnx \
    --ws-server ws://192.168.43.142:8765 \
    --stream --lens-position 2.2
  ```

