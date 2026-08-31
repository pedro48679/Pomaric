#!/usr/bin/env python3
"""Wrapper de produção do golden config com suporte a MÚLTIPLAS maçãs por frame.

AVISO DE ÂMBITO: o loop de vigilância clona fielmente golden.stream_vigilance_and_classify
(livestream MJPEG, modo repouso, lock-state do ROI neutral/locked_left/locked_right
com timeout, HeartbeatSender — todos reaproveitados sem alterações), com o
gancho multi-maçã a substituir a classificação single-apple. NÃO inclui
sensor-crop/de-skew (decisão já tomada nesta sessão de não usar sensor-crop —
atrapalha ver a maçã a rebolar). Por depender de correlacionar TODAS as
maçãs entre os N frames do burst, perde a sobreposição captura/processamento
que o golden tem no caminho normal (mesma troca que o golden já faz no seu
próprio modo de-skew, pela mesma razão: precisa do burst completo primeiro).

O `raspberry_camera_format.py` (golden) é doutrina intocável — este script
importa-o como módulo e reaproveita as suas peças (CameraStream, deteção HSV,
crop/máscara, RANSAC, envio para Supabase/ws_server). A única coisa nova é:

  1. `find_all_apple_regions(img, max_regions)`: duplicado deliberado da lógica
     de "ilhas" de `golden.find_apple_region` (mesmas máscaras HSV, mesmo
     RANSAC — reaproveitados via `golden._rgb_to_hsv_np`/`golden.fit_circle_ransac`),
     mas em vez de manter só a ilha mais circular, devolve até `max_regions`
     (top N por circularidade — nunca "tudo o que tem cor e forma de maçã"
     sem limite). Custo igual ao que já se paga hoje (~2-5ms, thumbnail
     ≤128px) — a análise é a mesma, só a etapa final de "escolher 1" mudou.
     Controlado por --multi-apple (default OFF = max_regions=1, idêntico ao
     golden) e --max-apples (default 4, só usado com --multi-apple).
  2. `crop_mask_and_tensor`: para cada maçã, cria um CROP PRÓPRIO a partir da
     imagem original (cópia + recorte, como o split_multi_apple_crops.py que
     serviu de referência — não é partição da imagem em grelha) usando a
     região já detetada na frame inteira, sem voltar a chamar a deteção do
     golden sobre o recorte isolado (ver o comentário na função — fazer isso
     podia escolher ruído do fundo em vez da maçã real, confirmado em teste).
  3. Correlação de maçãs entre os frames do burst (a mesma maçã física aparece
     em vários frames a ~150ms de intervalo — sem isto seria contada 2-3x).
  4. Uma maçã extra por frame custa ~100-200ms (o mesmo que uma maçã já custa
     hoje: crop+máscara+resize+inferência ONNX) — paralelizável com
     ThreadPoolExecutor, como o golden já faz para os frames do burst.

Flag --supabase (default OFF): controla o destino de TODOS os resultados.
  OFF: modo arquivo/dataset — grava SEMPRE todos os frames válidos de cada
       maçã, com o label REAL do CNN2 (nunca um placeholder tipo "incerto"),
       via SCP direto para uma pasta no PC, no formato Label_id_frameN.jpg
       (mesma convenção do dataset TempRaspberry/heavy, compatível com
       `raspberry_random_configo.py --from-dir`).
  ON:  modo produção — reaproveita o consenso do golden (blur, pior caso).
       Se o CNN2 é a decisão final (Healthy confiante): só o pior frame vai
       para o Supabase (golden._send_confident_healthy_to_supabase, intocada).
       Se a CNN5 (PC) decide: todos os frames vão por WebSocket, mas agora
       cada frame leva o label/confiança REAIS do CNN2 (o golden só mandava
       'unknown' a nível de topo e nada por frame) — ver o patch em
       ws_server.py que usa esse label por frame para nomear os ficheiros
       gravados, em vez do "unknown" que aparecia até agora.

Uso (idêntico às flags de câmara do golden; ver --help):
  python3 raspberry_multi_apple.py --stream \
    --model /home/minipc/models/model2.onnx \
    --ws-server ws://192.168.43.142:8765 \
    --shutter-us 3000 --lens-position 2.2 --burst 3 \
    --supabase --enable-supabase

  # Modo arquivo (default, sem --supabase): grava tudo no PC via SCP
  python3 raspberry_multi_apple.py --stream \
    --model /home/minipc/models/model2.onnx \
    --pc utilizador@192.168.1.50 --temp-folder "C:/Users/.../TempRaspberry/live" \
    --shutter-us 3000 --lens-position 2.2 --burst 3
"""
import argparse
import math
import time
import threading
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image

import raspberry_camera_format as golden  # golden config — NÃO modificar

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
MAX_TRACK_DIST_FRAC = 0.25   # fração da largura do frame — limite de correlação entre frames
CROP_MIN = 300               # lado mínimo do crop generoso (igual ao golden)

# O limiar de circularidade do golden (score<0.75) foi calibrado para escolher
# o MELHOR entre vários candidatos — nunca precisou de rejeitar sozinho um
# candidato fraco, porque só o vencedor era usado. Ao manter todos os que
# passam, blobs pequenos de fundo (sombra, borda de tabuleiro, canto escuro)
# também passam o mesmo limiar e apareciam como "maçãs" falsas (confirmado
# com o dataset real). Estes dois filtros de tamanho eliminam esse ruído sem
# descartar maçãs reais lado a lado (que têm tamanho comparável entre si):
MIN_AREA_FRAC = 0.02         # fração mínima da thumbnail (mesmo valor de split_multi_apple_crops.py)
MIN_SIZE_REL_TO_LARGEST = 0.30  # tamanho mínimo relativo ao maior candidato válido do frame


# ---------------------------------------------------------------------------
# Deteção multi-maçã: duplicado deliberado de golden.find_apple_region,
# devolvendo TODAS as ilhas válidas em vez de só a melhor.
# ---------------------------------------------------------------------------

def find_all_apple_regions(img: Image.Image, max_regions: int = 1) -> list:
    """Mesma análise HSV+RANSAC de golden.find_apple_region (reaproveita
    golden._rgb_to_hsv_np e golden.fit_circle_ransac tal e qual), mas mantém
    até `max_regions` ilhas que passam os critérios de circularidade/anti-sombra,
    não só a melhor. Devolve lista de tuplos (cx, cy, x_min, y_min, x_max, y_max,
    comp_mask) em coordenadas originais — mesmo formato de golden.find_apple_region,
    ordenados do mais circular para o menos (por isso max_regions=1, o default,
    reproduz exatamente o comportamento de golden.find_apple_region: só o melhor).
    """
    MAX_DIM = 128
    w_orig, h_orig = img.size
    scale = MAX_DIM / max(w_orig, h_orig)
    thumb_w = int(w_orig * scale)
    thumb_h = int(h_orig * scale)

    thumb = img.resize((thumb_w, thumb_h), Image.BILINEAR)
    arr = np.asarray(thumb, dtype=np.float32) / 255.0
    hsv = golden._rgb_to_hsv_np(arr)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]

    apple_color = ((h < 0.45) | (h > 0.85)) & (s > 0.30) & (v > 0.15)
    dark_mask = (v < 0.30) & (s > 0.10)
    skin_mask = (h < 0.12) & (s > 0.12) & (s < 0.65) & (v > 0.15) & (v < 0.95)

    m_y = thumb_h // 4
    m_x = thumb_w // 4
    center_zone = np.zeros((thumb_h, thumb_w), dtype=bool)
    center_zone[m_y: thumb_h - m_y, m_x: thumb_w - m_x] = True

    hand_pixels = skin_mask & ~center_zone
    valid_mask = (apple_color | dark_mask) & ~hand_pixels

    components = []
    visited = np.zeros((thumb_h, thumb_w), dtype=bool)
    ys_all, xs_all = np.where(valid_mask)
    pixel_set = set(zip(ys_all.tolist(), xs_all.tolist()))

    while pixel_set:
        y, x = pixel_set.pop()
        comp = []
        stack = [(y, x)]
        while stack:
            cy, cx = stack.pop()
            if visited[cy, cx]:
                continue
            visited[cy, cx] = True
            comp.append((cy, cx))
            for ny, nx in [(cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)]:
                if 0 <= ny < thumb_h and 0 <= nx < thumb_w and valid_mask[ny, nx] and not visited[ny, nx]:
                    stack.append((ny, nx))
                    pixel_set.discard((ny, nx))
        if len(comp) >= 20:
            comp_mask = np.zeros((thumb_h, thumb_w), dtype=bool)
            for cy, cx in comp:
                comp_mask[cy, cx] = True
            color_ratio = np.sum(comp_mask & apple_color) / len(comp)
            if color_ratio < 0.15:
                continue
            components.append((comp, comp_mask))

    thumb_area = float(thumb_w * thumb_h)
    candidates = []  # (score, comp_size, cx, cy, x_min, y_min, x_max, y_max, comp_mask)
    for comp, comp_mask in components:
        padded = np.pad(comp_mask, 1, mode='constant', constant_values=False)
        interior = (
            padded[1:-1, 1:-1] & padded[:-2, 1:-1] & padded[2:, 1:-1]
            & padded[1:-1, :-2] & padded[1:-1, 2:]
        )
        contour = comp_mask & ~interior
        cys, cxs = np.where(contour)
        if len(cxs) < 15:
            continue

        cx_fit, cy_fit, R_fit, inliers = golden.fit_circle_ransac(cxs, cys)
        if cx_fit is None:
            continue

        inlier_ratio = inliers / len(cxs)
        score = 1.0 - inlier_ratio

        centroid_x = np.mean(cxs)
        centroid_y = np.mean(cys)
        dist_to_centroid = np.sqrt((cx_fit - centroid_x) ** 2 + (cy_fit - centroid_y) ** 2)
        if dist_to_centroid > R_fit * 1.5:
            continue

        # Mesmo limiar de circularidade do golden: score < 0.75
        if score >= 0.75:
            continue

        if (len(comp) / thumb_area) < MIN_AREA_FRAC:
            continue

        candidates.append((
            score, len(comp), cx_fit, cy_fit,
            cx_fit - R_fit, cy_fit - R_fit, cx_fit + R_fit, cy_fit + R_fit,
            comp_mask,
        ))

    s_inv = 1.0 / scale

    if candidates:
        max_size = max(c[1] for c in candidates)
        candidates = [c for c in candidates if c[1] >= MIN_SIZE_REL_TO_LARGEST * max_size]
        candidates.sort(key=lambda c: c[0])  # mais circular primeiro
        candidates = candidates[:max_regions]  # top N por circularidade
        return [
            (cx * s_inv, cy * s_inv, x0 * s_inv, y0 * s_inv, x1 * s_inv, y1 * s_inv, mask)
            for _, _, cx, cy, x0, y0, x1, y1, mask in candidates
        ]

    # Fallback (igual ao golden): nenhum candidato circular — usa o maior blob
    # de cor, para nunca devolver "nada" quando há claramente algo na imagem.
    if components:
        largest_comp, largest_mask = max(components, key=lambda c: len(c[0]))
        cys, cxs = np.where(largest_mask)
        if len(cxs) > 0:
            x0, x1 = float(np.min(cxs)), float(np.max(cxs))
            y0, y1 = float(np.min(cys)), float(np.max(cys))
            cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
            return [(cx * s_inv, cy * s_inv, x0 * s_inv, y0 * s_inv, x1 * s_inv, y1 * s_inv, largest_mask)]

    return []


# ---------------------------------------------------------------------------
# Correlação entre frames do burst (identidade, não alinhamento sub-pixel —
# problema mais grosseiro que a fusão do laboratório: só "é a mesma maçã?")
# ---------------------------------------------------------------------------

def match_tracks(frame_regions: list, frame_width: int) -> list:
    """frame_regions[i] = lista de regiões detetadas no frame i.
    Devolve lista de tracks; cada track tem comprimento len(frame_regions),
    com a região correspondente (ou None se essa maçã não foi vista nesse frame).
    Referência = frame com mais regiões detetadas (maior chance de capturar
    todas as maçãs presentes)."""
    if not frame_regions or all(not r for r in frame_regions):
        return []

    ref_idx = max(range(len(frame_regions)), key=lambda i: len(frame_regions[i]))
    if not frame_regions[ref_idx]:
        return []

    tracks = [[None] * len(frame_regions) for _ in frame_regions[ref_idx]]
    for k, r in enumerate(frame_regions[ref_idx]):
        tracks[k][ref_idx] = r

    max_dist = MAX_TRACK_DIST_FRAC * frame_width
    for i, regions in enumerate(frame_regions):
        if i == ref_idx or not regions:
            continue
        used = set()
        for track in tracks:
            ref_r = track[ref_idx]
            best_j, best_d = None, max_dist
            for j, r in enumerate(regions):
                if j in used:
                    continue
                d = math.hypot(r[0] - ref_r[0], r[1] - ref_r[1])
                if d < best_d:
                    best_d, best_j = d, j
            if best_j is not None:
                track[i] = regions[best_j]
                used.add(best_j)

    return tracks


def _safe_crop_lado(region: tuple, other_regions: list, margin: float = 1.15) -> float:
    """Lado do crop generoso para uma maçã (mesma margem 1.15x do golden),
    limitado pela distância ao vizinho mais próximo do mesmo frame — nunca
    ultrapassa o ponto médio até outra maçã detetada (evita incluir a maçã
    vizinha no recorte)."""
    cx, cy, x_min, y_min, x_max, y_max, _ = region
    lado = max(x_max - x_min, y_max - y_min) * margin
    for other in other_regions:
        if other is region:
            continue
        d = math.hypot(cx - other[0], cy - other[1])
        if d > 0:
            lado = min(lado, d * 0.9)
    return lado


def crop_mask_and_tensor(img: Image.Image, region: tuple, lado: int, input_size: int):
    """Replica os passos 3-9 de golden.process_and_crop_transparent (máscara
    circular RANSAC, tight crop, resize único, normalização ImageNet) mas
    usando uma região JÁ CONHECIDA em vez de golden voltar a detetar do zero
    no recorte isolado.

    Isto é essencial, não cosmético: isolar uma maçã num crop apertado e
    voltar a chamar golden.process_and_crop_transparent (que re-deteta do
    zero) pode ocasionalmente escolher um blob de RUÍDO minúsculo (um ponto
    do padrão do tecido, poucos pixels) em vez da própria maçã — confirmado
    no dataset real: um blob de 23 pixels obteve score de circularidade
    melhor (0.150) que a maçã real de 4389 pixels (0.473), porque poucos
    pontos ajustam um círculo "perfeito" com mais facilidade. Reaproveitar a
    região já fiável (detetada na frame inteira, onde este problema não
    ocorre) evita a falha por construção.

    Devolve (pre_crop: Image RGB, cnn_rgba: Image RGBA 224x224, tensor).
    """
    cx, cy, x_min, y_min, x_max, y_max, _ = region
    w_img, h_img = img.size
    half = lado // 2
    left = max(0, min(w_img - lado, int(cx - half)))
    top = max(0, min(h_img - lado, int(cy - half)))
    pre_crop = img.crop((left, top, left + lado, top + lado))

    from PIL import ImageDraw, ImageFilter
    crop_rgba = pre_crop.convert('RGBA')
    radius = (x_max - x_min) / 2.0
    cx_crop = cx - left
    cy_crop = cy - top
    radius_padded = radius * 1.06

    mask_pil = Image.new('L', pre_crop.size, 0)
    draw = ImageDraw.Draw(mask_pil)
    draw.ellipse(
        [cx_crop - radius_padded, cy_crop - radius_padded,
         cx_crop + radius_padded, cy_crop + radius_padded],
        fill=255,
    )
    mask_pil = mask_pil.filter(ImageFilter.GaussianBlur(radius=2))
    crop_rgba.putalpha(mask_pil)

    alpha = np.array(crop_rgba)[:, :, 3]
    alpha_bin = np.where(alpha > 128, 255, 0).astype(np.uint8)
    crop_rgba.putalpha(Image.fromarray(alpha_bin))

    non_zero = np.argwhere(alpha_bin > 0)
    if non_zero.size > 0:
        y0a, x0a = non_zero.min(axis=0)
        y1a, x1a = non_zero.max(axis=0)
        cxa, cya = int((x0a + x1a) // 2), int((y0a + y1a) // 2)
        lado_t = int(max(y1a - y0a, x1a - x0a) * 1.08)
        half_t = lado_t // 2
        final_rgba = Image.new('RGBA', (lado_t, lado_t), (0, 0, 0, 0))
        src_l, src_t = cxa - half_t, cya - half_t
        w_c, h_c = crop_rgba.size
        ix0, iy0 = max(0, src_l), max(0, src_t)
        ix1, iy1 = min(w_c, src_l + lado_t), min(h_c, src_t + lado_t)
        if ix1 > ix0 and iy1 > iy0:
            final_rgba.paste(crop_rgba.crop((ix0, iy0, ix1, iy1)), (ix0 - src_l, iy0 - src_t))
    else:
        final_rgba = crop_rgba

    cnn_rgba = final_rgba.resize((input_size, input_size), Image.Resampling.LANCZOS)

    black_bg = Image.new('RGBA', cnn_rgba.size, (0, 0, 0, 255))
    cnn_rgb = Image.alpha_composite(black_bg, cnn_rgba).convert('RGB')
    arr = np.asarray(cnn_rgb, dtype=np.float32) / 255.0
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    arr = (arr - mean) / std
    tensor = np.transpose(arr, (2, 0, 1))[None, ...].astype(np.float32)

    return pre_crop, cnn_rgba, tensor


# ---------------------------------------------------------------------------
# Crop + classificação de uma região
# ---------------------------------------------------------------------------

def classify_region(img: Image.Image, region: tuple, other_regions: list, tmp_base: Path,
                    file_prefix: str, sess, input_name: str, labels: list, input_size: int) -> dict:
    """Recorta e classifica uma região JÁ CONHECIDA (ver crop_mask_and_tensor),
    grava os artefactos com a mesma convenção do golden (_crop.jpg + .png) e
    corre a inferência ONNX — devolve o mesmo dict de resultado por frame que
    o golden já usa."""
    t0 = time.perf_counter()
    w_img, h_img = img.size
    x_min, y_min, x_max, y_max = region[2], region[3], region[4], region[5]

    lado = int(_safe_crop_lado(region, other_regions))
    lado = max(lado, CROP_MIN)
    lado = min(lado, min(w_img, h_img))

    pre_crop, cnn_rgba, tensor = crop_mask_and_tensor(img, region, lado, input_size)

    png_path = tmp_base / f'{file_prefix}.png'
    crop_path = tmp_base / f'{file_prefix}_crop.jpg'
    cnn_rgba.save(png_path, 'PNG')
    pre_crop.save(crop_path, 'JPEG', quality=95)

    blur_score = golden.compute_blur_score(crop_path)
    out = sess.run(None, {input_name: tensor})[0]
    pred, conf = golden.postprocess_output(out)
    label = labels[pred] if pred < len(labels) else str(pred)

    return {
        'label': label, 'index': int(pred), 'confidence': float(conf),
        'blur_score': float(blur_score), 'png_path': png_path,
        'processing_ms': (time.perf_counter() - t0) * 1000,
    }


# ---------------------------------------------------------------------------
# Envio: flag --supabase
# ---------------------------------------------------------------------------

def _send_archive_scp(apple_id: str, track_results: list, args):
    """--supabase OFF: grava TODOS os frames válidos via SCP, nomeados
    Label_appleid_frameN.jpg — mesma convenção do dataset TempRaspberry/heavy,
    já compatível com raspberry_random_configo.py --from-dir."""
    import shutil

    sent = 0
    for i, r in enumerate(track_results):
        fname = f"{r['label']}_{apple_id}_frame{i + 1}.jpg"
        crop_path = r['png_path'].with_name(r['png_path'].stem + '_crop.jpg')
        src = crop_path if crop_path.exists() else r['png_path']
        renamed = src.with_name(fname)
        try:
            shutil.copy(str(src), str(renamed))
            golden.scp_send(renamed, args.pc, args.temp_folder)
            sent += 1
        except Exception as e:
            print(f'   [Arquivo] Erro a enviar {fname}: {e}')
        finally:
            renamed.unlink(missing_ok=True)
    print(f'   [Arquivo] {apple_id}: {sent}/{len(track_results)} frame(s) gravados em {args.pc}:{args.temp_folder}')


def _send_uncertain_ws(apple_id: str, track_results: list, worst: dict, args):
    """--supabase ON, CNN5 decide: envia todos os frames por WebSocket, com o
    label/confiança REAIS do CNN2 por frame (não 'unknown') — o campo de topo
    do payload mantém-se 'unknown'/0.0, é o sinal que o ws_server usa para
    saber que a CNN5 deve decidir (ver patch em ws_server.py para o uso do
    label por frame)."""
    import asyncio

    frames_payload = []
    for i, r in enumerate(track_results):
        img_resized_b64, crop_b64, _ = golden._frame_images_b64(r['png_path'])
        frames_payload.append({
            'frame': i + 1,
            'crop_image_b64': crop_b64,
            'image_resized_b64': img_resized_b64,
            'label': r['label'],
            'confidence': r['confidence'],
        })

    payload = {
        'is_burst': True,
        'apple_id': apple_id,
        'location': golden.get_active_location(getattr(args, 'location', None)),
        'label': 'unknown',
        'confidence': 0.0,
        'frames': frames_payload,
    }
    print(f'   [WS] Maçã {apple_id}: incerta ({worst["label"]} {worst["confidence"]:.1%} no pior frame) '
          f'— a enviar {len(track_results)} frames com label real do CNN2 por frame.')
    asyncio.run(golden.ws_send(args.ws_server, payload))


def send_track_results(apple_id: str, track_results: list, args):
    """Decide o destino de uma maçã (track) com base no consenso do golden
    (blur, pior caso, confiante-saudável) e na flag --supabase."""
    valid = [r for r in track_results if r['index'] >= 0]
    if not valid:
        print(f'   [Aviso] {apple_id}: sem classificações válidas, nada para enviar.')
        return

    best_blur = max(r['blur_score'] for r in valid)
    sharp = [r for r in valid if r['blur_score'] >= 0.5 * best_blur] or valid
    unhealthy = [r for r in sharp if r['label'] != 'Healthy']
    worst = max(unhealthy, key=lambda r: r['confidence']) if unhealthy else \
        min(sharp, key=lambda r: r['confidence'])
    is_confident_healthy = worst['label'] == 'Healthy' and worst['confidence'] > 0.80

    if not args.supabase:
        _send_archive_scp(apple_id, valid, args)
        return

    if is_confident_healthy and getattr(args, 'enable_supabase', False):
        frames_meta = [{
            'frame': i + 1, 'label': r['label'], 'confidence': r['confidence'],
            'is_worst_case': r is worst,
        } for i, r in enumerate(valid)]
        try:
            golden._send_confident_healthy_to_supabase(apple_id, worst, frames_meta, args)
            print(f'   [Supabase] Maçã {apple_id}: Healthy confiante em todos os frames — '
                  f'enviada direto (pior frame {worst["confidence"]:.1%}).')
            return
        except Exception as e:
            print(f'   [Supabase] Falha ({e}) — a usar caminho normal (WebSocket).')

    _send_uncertain_ws(apple_id, valid, worst, args)


# ---------------------------------------------------------------------------
# Processamento de um burst multi-maçã: deteta, correlaciona, classifica, envia
# ---------------------------------------------------------------------------

def process_burst_multi(frames: list, args, sess, input_name: str, tmp_base: Path) -> int:
    """Devolve o número de classificações válidas feitas (para o heartbeat)."""
    if not frames:
        return 0

    # --multi-apple off (default): max_regions=1 reproduz exatamente o golden
    # (só a maçã mais circular). --multi-apple on: até --max-apples (top N
    # por circularidade) — nunca processa "tudo o que tem cor e forma de
    # maçã" sem limite.
    max_regions = args.max_apples if getattr(args, 'multi_apple', False) else 1
    frame_regions = [find_all_apple_regions(f, max_regions=max_regions) for f in frames]
    n_apples = max((len(r) for r in frame_regions), default=0)

    if n_apples == 0:
        print('   [Aviso] Nenhuma maçã detetada em nenhum frame do burst.')
        return 0

    if n_apples == 1:
        print(f'   1 maçã detetada — caminho normal (idêntico ao golden).')
    else:
        print(f'   {n_apples} maçãs detetadas simultaneamente — a correlacionar entre frames...')

    tracks = match_tracks(frame_regions, frame_width=frames[0].size[0])
    total_classified = 0

    for k, track in enumerate(tracks):
        apple_id = golden.generate_apple_id()
        if len(tracks) > 1:
            apple_id = f'{apple_id}_{k + 1}'
        track_results = []
        for i, (frame, region) in enumerate(zip(frames, track)):
            if region is None:
                continue
            prefix = f'{apple_id}_frame{i + 1}'
            other_regions = [r for r in frame_regions[i] if r is not region]
            track_results.append(classify_region(
                frame, region, other_regions, tmp_base, prefix,
                sess, input_name, args.labels, args.input_size))

        for i, res in enumerate(track_results):
            print(f'      [Maçã {k + 1}] {res["label"]} ({res["confidence"]*100:.1f}%) '
                  f'| blur={res["blur_score"]:.0f} | {res["processing_ms"]:.0f}ms')

        total_classified += len([r for r in track_results if r.get('index', -1) >= 0])
        send_track_results(apple_id, track_results, args)

    return total_classified


# ---------------------------------------------------------------------------
# Loop de vigilância: clone fiel de golden.stream_vigilance_and_classify —
# gatilho por ROI, lock-state, modo repouso, livestream MJPEG (reaproveitados
# do golden sem alterações) — com o gancho multi-maçã a substituir a
# classificação single-apple. Sensor-crop/de-skew NÃO estão aqui (decisão já
# tomada nesta sessão de não usar sensor-crop — atrapalha ver a maçã a
# rebolar). Corrida de foco (best-blur scan) é aditiva, validada nesta sessão.
# ---------------------------------------------------------------------------

def run_stream(args, sess, input_name):
    import cv2

    tmp_base = Path('/tmp/onnx_capture_multi')
    tmp_base.mkdir(parents=True, exist_ok=True)

    colour_gains = None
    if args.colour_gains:
        try:
            r, b = args.colour_gains.split(',')
            colour_gains = (float(r), float(b))
        except Exception:
            print(f'   [Aviso] --colour-gains "{args.colour_gains}" inválido. AWB automático.')

    stream = golden.CameraStream(
        width=args.width, height=args.height,
        shutter_us=args.shutter_us,
        lens_position=args.lens_position,
        sharpness=args.sharpness,
        contrast=args.contrast,
        saturation=args.saturation,
        noise_reduction=args.noise_reduction,
        analogue_gain=args.analogue_gain,
        colour_gains=colour_gains,
    )
    stream.start()

    # --- Livestream MJPEG embutido (reaproveitado do golden, sem alterações) ---
    livestream_bus = golden._LivestreamFrameBus()
    livestream_server = None
    if not getattr(args, 'no_livestream', False):
        livestream_port = getattr(args, 'livestream_port', 8000)
        try:
            livestream_server = golden.LivestreamServer((golden.LIVESTREAM_HOST, livestream_port), livestream_bus)
            threading.Thread(target=livestream_server.serve_forever, daemon=True, name='LivestreamHTTP').start()
            print(f'   [Livestream] Servidor MJPEG embutido ativo em http://{golden.LIVESTREAM_HOST}:{livestream_port}/stream.mjpg')
        except OSError as e:
            print(f'   [Livestream] Falha ao abrir a porta {livestream_port} (já em uso?): {e}')

    _last_publish_ts = [0.0]

    def _read_and_publish():
        """Wrapper de stream.read() usado em TODOS os pontos de leitura do
        loop para que a livestream receba frames continuamente (igual ao
        golden)."""
        img, gray = stream.read()
        if img is not None and livestream_bus.has_clients:
            now_m = time.monotonic()
            if now_m - _last_publish_ts[0] >= golden.LIVESTREAM_MIN_PUBLISH_INTERVAL_S:
                _last_publish_ts[0] = now_m
                try:
                    livestream_bus.publish(golden._encode_livestream_frame(img))
                except Exception as e:
                    print(f'   [Livestream] Erro ao publicar frame: {e}')
        return img, gray

    heartbeat = None
    if args.ws_server:
        heartbeat = golden.HeartbeatSender(args.ws_server)
        heartbeat.start()

    motion_kernel = np.ones((5, 5), np.uint8)
    gray_prev = None
    cooldown_until = 0.0
    interval_s = args.burst_interval / 1000.0

    # Estado de ROI bloqueado e modo de repouso (igual ao golden)
    lock_state = 'neutral'  # 'neutral', 'locked_left', 'locked_right'
    in_repouso = False
    last_trigger_time = time.time()
    _total_inferences = 0

    print(f'\n[Multi-maçã] Vigilância ativa. burst={args.burst} | intervalo={args.burst_interval}ms '
          f'| shutter={args.shutter_us or "auto"}µs | --supabase={"ON" if args.supabase else "OFF (arquivo)"} '
          f'| --multi-apple={"ON (max " + str(args.max_apples) + ")" if args.multi_apple else "OFF"}')
    try:
        while True:
            img_rgb, gray_lores = _read_and_publish()
            if img_rgb is None or gray_lores is None:
                time.sleep(0.010)
                continue
            now = time.time()

            # --- Modo de Repouso (timeout de 1 minuto sem gatilhos), suspenso
            #     enquanto há espectadores ativos da livestream ---
            if not in_repouso and (now - last_trigger_time) > 60.0 and not livestream_bus.has_clients:
                in_repouso = True
                if heartbeat:
                    heartbeat.update(mode='sleep')
                print('\n[Vigilância] Inatividade detetada por 1 minuto. A entrar em modo de repouso...')
                stream.set_repouso(True)
                gray_prev = None
            elif in_repouso and livestream_bus.has_clients:
                print('\n[Livestream] Espectador ligado durante o repouso. A acordar a câmara...')
                in_repouso = False
                if heartbeat:
                    heartbeat.update(mode='idle')
                stream.set_repouso(False)
                time.sleep(0.2)
                gray_prev = None
                continue

            if now < cooldown_until:
                _read_and_publish()
                gray_prev = None
                continue

            # --- Timeout do bloqueio de ROI (30s sem ativação) ---
            if lock_state != 'neutral' and (now - last_trigger_time) > 30.0:
                print(f"\n[Vigilância] Inatividade do ROI superou 30s. Bloqueio '{lock_state}' reposto para neutro.")
                lock_state = 'neutral'

            gray_blur = cv2.GaussianBlur(gray_lores, (9, 9), 0)
            if gray_prev is None:
                gray_prev = gray_blur
                continue

            diff_signed = gray_blur.astype(np.float32) - gray_prev.astype(np.float32)
            row_mean = diff_signed.mean(axis=1, keepdims=True)
            diff_comp = np.abs(diff_signed - row_mean).astype(np.uint8)
            h_lr, w_lr = gray_blur.shape
            w_roi = int(w_lr * 0.15)
            mask_l = cv2.erode((diff_comp[:, :w_roi] > 25).astype(np.uint8), motion_kernel, iterations=2)
            mask_r = cv2.erode((diff_comp[:, w_lr - w_roi:] > 25).astype(np.uint8), motion_kernel, iterations=2)
            motion_left = int(mask_l.sum())
            motion_right = int(mask_r.sum())

            diff_center = diff_comp[:, w_roi:w_lr - w_roi]
            mask_center = cv2.erode((diff_center > 25).astype(np.uint8), motion_kernel, iterations=2)
            motion_center = int(mask_center.sum())

            area_side = float(w_roi * h_lr)
            area_center = float(max((w_lr - 2 * w_roi) * h_lr, 1))
            dens_left = motion_left / area_side
            dens_right = motion_right / area_side
            dens_center = motion_center / area_center
            left_localized = dens_left >= 2.0 * dens_center
            right_localized = dens_right >= 2.0 * dens_center

            # --- Gatilho filtrado pelo estado do ROI (lock-state, igual ao golden) ---
            triggered = False
            trigger_side = None
            if lock_state == 'neutral':
                if motion_left > args.motion_threshold and left_localized:
                    triggered, trigger_side, lock_state = True, 'ESQUERDO', 'locked_left'
                elif motion_right > args.motion_threshold and right_localized:
                    triggered, trigger_side, lock_state = True, 'DIREITO', 'locked_right'
            elif lock_state == 'locked_left':
                if motion_left > args.motion_threshold and left_localized:
                    triggered, trigger_side = True, 'ESQUERDO'
            elif lock_state == 'locked_right':
                if motion_right > args.motion_threshold and right_localized:
                    triggered, trigger_side = True, 'DIREITO'

            if triggered:
                if in_repouso:
                    print(f'\n[Gatilho Repouso] Movimento detetado no ROI {trigger_side}! A acordar a câmara...')
                    in_repouso = False
                    stream.set_repouso(False)
                    time.sleep(0.2)
                    gray_prev = None
                    last_trigger_time = time.time()
                    continue

                print(f'\n[Gatilho] Movimento detetado no ROI {trigger_side}! '
                      f'(L: {motion_left} px, R: {motion_right} px) - Estado: {lock_state}')
                if args.trigger_delay > 0:
                    t_d = time.perf_counter()
                    while (time.perf_counter() - t_d) * 1000.0 < args.trigger_delay:
                        _read_and_publish()

                # Corrida de foco: com lens_position fixo (sem AF), espera pelo
                # frame mais nítido dentro da janela em vez de um delay cego
                # (validado nesta sessão — sem isto a maçã chegava desfocada).
                best_img, best_blur = None, -1.0
                t_focus = time.perf_counter()
                while (time.perf_counter() - t_focus) * 1000.0 < args.focus_timeout_ms:
                    cand, _ = _read_and_publish()
                    if cand is None:
                        continue
                    gray_small = np.asarray(cand.convert('L').resize((256, 256), Image.BILINEAR), dtype=np.float32)
                    lap = (gray_small[:-2, 1:-1] + gray_small[2:, 1:-1] + gray_small[1:-1, :-2]
                           + gray_small[1:-1, 2:] - 4.0 * gray_small[1:-1, 1:-1])
                    b = float(np.var(lap))
                    if b > best_blur:
                        best_img, best_blur = cand, b
                    if b >= args.focus_min_blur:
                        break
                if best_img is not None:
                    elapsed_ms = (time.perf_counter() - t_focus) * 1000.0
                    print(f'   [Foco] Melhor frame do scan: blur={best_blur:.0f} ({elapsed_ms:.0f}ms de espera)')

                frames = [best_img] if best_img is not None else []
                for shot in range(1, args.burst):
                    t_i = time.perf_counter()
                    while (time.perf_counter() - t_i) < interval_s:
                        _read_and_publish()
                    shot_img, _ = _read_and_publish()
                    if shot_img is not None:
                        frames.append(shot_img)

                if frames:
                    _total_inferences += process_burst_multi(frames, args, sess, input_name, tmp_base)
                    if heartbeat:
                        heartbeat.update(mode='active', inference_count=_total_inferences)

                last_trigger_time = time.time()
                cooldown_until = time.time() + 1.0
                print('[Vigilância] Rajada enviada. A entrar em cooldown por 1.0s...')
                gray_prev = None
                continue

            gray_prev = gray_blur
            time.sleep(0.033)
    except KeyboardInterrupt:
        print('\n[Multi-maçã] Interrompido pelo utilizador.')
    finally:
        if heartbeat:
            heartbeat.stop()
        if livestream_server:
            livestream_server.shutdown()
            livestream_server.server_close()
        stream.stop()
        print('Câmara desligada com sucesso.')


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(
        description='Wrapper de produção do golden com suporte a múltiplas maçãs por frame.')
    p.add_argument('--model', default=None,
                   help='Modelo ONNX. Se omitido, o mais recente em --models-dir (como o golden).')
    p.add_argument('--models-dir', default='/home/minipc/models')
    p.add_argument('--labels', nargs='+', default=['Healthy', 'Unhealthy'])
    p.add_argument('--input_size', type=int, default=224)

    # --- Deteção multi-maçã (OFF por default = comportamento idêntico ao golden) ---
    p.add_argument('--multi-apple', action='store_true',
                   help='Ativa deteção de várias maçãs por frame (default: OFF, só a mais '
                        'circular, igual ao golden). Com esta flag, processa até --max-apples '
                        '(top N por circularidade), nunca todas as ilhas de cor sem limite.')
    p.add_argument('--max-apples', type=int, default=4,
                   help='Número máximo de maçãs a processar por frame com --multi-apple (default 4).')

    # --- Destino dos resultados ---
    p.add_argument('--supabase', action='store_true',
                   help='ON: modo produção (Supabase/ws_server/CNN5, como o golden). '
                        'OFF (default): modo arquivo — grava tudo em --temp-folder via SCP, '
                        'com o label real do CNN2 por frame (nunca "incerto").')
    p.add_argument('--enable-supabase', action='store_true',
                   help='Com --supabase: ativa o envio direto ao Supabase para maçãs '
                        'Healthy confiantes (mesmo comportamento do golden).')
    p.add_argument('--ws-server', default=None, help='WebSocket server URI (modo --supabase)')
    p.add_argument('--pc', default=None, help='user@host do PC via SSH (modo arquivo, --supabase off)')
    p.add_argument('--temp-folder', default=None,
                   help='Pasta remota no PC para o modo arquivo, ex: "C:/Users/.../TempRaspberry/live"')
    p.add_argument('--location', default=None)

    # --- Flags de câmara (iguais ao golden) ---
    p.add_argument('--burst', type=int, default=3)
    p.add_argument('--burst-interval', type=int, default=150)
    p.add_argument('--shutter-us', type=int, default=0)
    p.add_argument('--width', type=int, default=2304)
    p.add_argument('--height', type=int, default=1296)
    p.add_argument('--lens-position', type=float, default=2.9)
    p.add_argument('--sharpness', type=float, default=1.5)
    p.add_argument('--contrast', type=float, default=1.2)
    p.add_argument('--saturation', type=float, default=1.2)
    p.add_argument('--noise-reduction', choices=['off', 'fast', 'highquality'], default='fast')
    p.add_argument('--analogue-gain', type=float, default=0.0)
    p.add_argument('--colour-gains', type=str, default=None)
    p.add_argument('--motion-threshold', type=int, default=1800)
    p.add_argument('--trigger-delay', type=int, default=100)
    p.add_argument('--focus-timeout-ms', type=int, default=700,
                   help='Janela (ms) após o gatilho a ler frames à procura do mais nítido '
                        '(default 700) — necessário com --lens-position fixo (sem AF).')
    p.add_argument('--focus-min-blur', type=float, default=150.0)
    p.add_argument('--livestream-port', type=int, default=8000,
                   help='Porta HTTP do servidor MJPEG embutido /stream.mjpg (default 8000, '
                        'igual ao golden).')
    p.add_argument('--no-livestream', action='store_true',
                   help='Desativa o servidor de livestream MJPEG embutido (debug/perf).')
    args = p.parse_args()

    if not args.supabase and (not args.pc or not args.temp_folder):
        raise SystemExit('Modo arquivo (--supabase off): --pc e --temp-folder são obrigatórios.')
    if args.supabase and not args.ws_server:
        raise SystemExit('Modo produção (--supabase): --ws-server é obrigatório.')

    if args.model:
        model = Path(args.model)
        if not model.exists():
            raise FileNotFoundError(model)
    else:
        model = golden.resolve_latest_model(Path(args.models_dir))

    sess = ort.InferenceSession(str(model), providers=['CPUExecutionProvider'])
    input_name = sess.get_inputs()[0].name

    run_stream(args, sess, input_name)


if __name__ == '__main__':
    main()
