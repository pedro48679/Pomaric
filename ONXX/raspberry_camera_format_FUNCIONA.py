#!/usr/bin/env python3
"""Capture image on Raspberry Pi, classify with ONNX model, send image and JSON to PC.

Modos de Operação:
  1. SINGLE (padrão): Tira 1 foto, remove o fundo, classifica e envia.
  2. BURST (--burst N): Tira N fotos em rajada rápida (rpicam-still --timelapse),
     usando 2 threads em pipeline para sobrepor captura e processamento:
       - Thread 1 (Produtor): Captura fotos e monitoriza o disco.
       - Thread 2 (Consumidor): Remove fundo (rembg u2netp) e classifica (ONNX)
                                cada imagem assim que fica disponível.
     No Raspberry Pi 5, 3 fotos são processadas em ~450ms após a primeira captura.

Usage example on the Pi:
  # Modo single (1 foto)
  python3 raspberry_camera_format.py \
    --model /home/minipc/models/model2.onnx \
    --ws-server ws://192.168.43.142:8765

  # Modo burst (3 fotos a 150ms de intervalo)
  python3 raspberry_camera_format.py \
    --model /home/minipc/models/model2.onnx \
    --ws-server ws://192.168.43.142:8765 \
    --burst 3 --burst-interval 150

Notes:
- The PC must run an SSH server (Windows OpenSSH) and accept the provided user.
- The script will attempt to `ssh user@host mkdir -p <dir>` before scp; a password prompt may appear.
"""
import argparse
import io
import json
import math
import os
import shlex
import socket
import subprocess
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image

# ---------------------------------------------------------------------------
# Supabase — usado apenas quando a CNN2 está confiante de que a maçã é
# 'Healthy' em todos os frames: nesse caso a maçã vai direto para a BD,
# sem passar pelo ws_server/PC. Mesmas credenciais e bucket já usados no
# resto do projeto (ver mlops_server.py / shadow_runner.py / automatic_triage_processor.py).
# ---------------------------------------------------------------------------
# URL e chave vêm do ambiente (systemd Environment=/EnvironmentFile=), para
# manter a chave fora do código e garantir que o Pi e o PC/dashboard apontam ao
# MESMO projeto Supabase. O default do URL é o projeto usado pela dashboard;
# sem SUPABASE_KEY, o caminho direto-a-Supabase falha em silêncio e a maçã cai
# no caminho normal (WebSocket para o PC).
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", "")
SUPABASE_BUCKET = "Apple"

# Subpasta dentro do bucket 'Apple' para onde vão as imagens. Neste momento é
# a pasta de teste "2026" (separada da coleção real). Quando o pipeline estiver
# validado, troca esta linha para a pasta correta e reinicia o script.
# TEM de coincidir com STORAGE_FOLDER em cnn5_watcher.py.
STORAGE_FOLDER = "2026"

# ---------------------------------------------------------------------------
# Livestream MJPEG embutido — serve /stream.mjpg diretamente a partir do
# CameraStream já ativo em modo --stream, sem abrir uma 2ª instância de
# Picamera2 (a câmara só suporta um consumidor de cada vez). Ver
# _LivestreamFrameBus / LivestreamServer mais abaixo.
# ---------------------------------------------------------------------------
LIVESTREAM_HOST = '0.0.0.0'
LIVESTREAM_JPEG_WIDTH = 1280
LIVESTREAM_JPEG_HEIGHT = 720
LIVESTREAM_JPEG_QUALITY = 80
LIVESTREAM_MAX_CLIENT_SECONDS = 300.0    # corta ligação esquecida aberta (é "temporário")
LIVESTREAM_FRAME_WAIT_TIMEOUT = 1.0      # s — intervalo de keepalive no handler HTTP
LIVESTREAM_MIN_PUBLISH_INTERVAL_S = 0.08  # ~12 fps — limita custo de encode, não afeta a captura


def _supabase_headers(content_type: str | None = None) -> dict:
    headers = {
        'apikey': SUPABASE_KEY,
        'Authorization': f'Bearer {SUPABASE_KEY}',
    }
    if content_type:
        headers['Content-Type'] = content_type
    return headers


def supabase_insert(table: str, rows: list) -> None:
    """INSERT direto via REST (evita depender do pacote supabase-py no Pi)."""
    import requests

    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers={**_supabase_headers('application/json'), 'Prefer': 'return=minimal'},
        json=rows,
        timeout=15,
    )
    resp.raise_for_status()


def supabase_insert_returning(table: str, rows: list) -> list:
    """Como supabase_insert(), mas devolve as linhas inseridas (para ler ids gerados)."""
    import requests

    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers={**_supabase_headers('application/json'), 'Prefer': 'return=representation'},
        json=rows,
        timeout=15,
    )
    resp.raise_for_status()
    return resp.json()


_active_location_cache: dict = {'value': None, 'fetched_at': 0.0}
_ACTIVE_LOCATION_TTL = 30.0  # segundos — evita 1 pedido REST por rajada


def get_active_location(override: str | None = None) -> str:
    """Lote (location) a gravar nas tabelas: usa --location se explicitamente
    passado, senão consulta 'active_lote' (escolhido pelo operador na
    dashboard após login), com cache de 30s para poupar pedidos ao Pi.
    Cai para o location mais recente em 'apples', e por fim para 'Linha 1'.
    """
    import time
    import requests

    if override:
        return override

    now = time.time()
    if _active_location_cache['value'] and now - _active_location_cache['fetched_at'] < _ACTIVE_LOCATION_TTL:
        return _active_location_cache['value']

    location = None
    try:
        resp = requests.get(
            f"{SUPABASE_URL}/rest/v1/active_lote?id=eq.1&select=location",
            headers=_supabase_headers(), timeout=5,
        )
        resp.raise_for_status()
        rows = resp.json()
        if rows:
            location = rows[0].get('location')
    except Exception:
        pass

    if not location:
        try:
            resp = requests.get(
                f"{SUPABASE_URL}/rest/v1/apples?order=timestamp.desc&limit=1&select=location",
                headers=_supabase_headers(), timeout=5,
            )
            resp.raise_for_status()
            rows = resp.json()
            if rows:
                location = rows[0].get('location')
        except Exception:
            pass

    location = location or 'Linha 1'
    _active_location_cache['value'] = location
    _active_location_cache['fetched_at'] = now
    return location


def supabase_upload_image(local_path: Path, storage_path: str, content_type: str = 'image/jpeg') -> str:
    """Faz upload de uma imagem ao Storage e devolve o URL público."""
    import requests

    resp = requests.post(
        f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{storage_path}",
        headers={**_supabase_headers(content_type), 'x-upsert': 'true'},
        data=local_path.read_bytes(),
        timeout=30,
    )
    resp.raise_for_status()
    return f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}/{storage_path}"


def generate_apple_id() -> str:
    """ID único e lexicograficamente ordenável, gerado no Pi (usado nos dois caminhos:
    direto-a-Supabase e via ws_server, para manter o esquema de apple_id consistente)."""
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%f')


class HeartbeatSender:
    """Envia telemetria do sistema ao ws_server a cada 5 segundos numa thread daemon.

    Métricas enviadas: temperatura CPU, % CPU, RAM, disco, modo (active/idle/sleep),
    uptime, contagem de inferências e FPS da câmara.
    Mantém uma ligação WebSocket persistente e reconecta automaticamente.
    """

    def __init__(self, ws_uri: str, device_id: str = 'raspberry5', interval: float = 5.0):
        self._ws_uri = ws_uri
        self._device_id = device_id
        self._interval = interval
        self._lock = threading.Lock()
        self._state: dict = {'mode': 'idle', 'inference_count': 0, 'camera_fps': 0.0}
        self._running = False
        self._thread: threading.Thread | None = None

    def update(self, **kwargs):
        """Atualiza campos de estado enviados no próximo heartbeat."""
        with self._lock:
            self._state.update(kwargs)

    def start(self):
        self._running = True
        self._thread = threading.Thread(target=self._run_loop, daemon=True, name='HeartbeatSender')
        self._thread.start()
        print(f'   [Heartbeat] A enviar telemetria para {self._ws_uri} cada {self._interval:.0f}s')

    def stop(self):
        self._running = False

    def _collect(self) -> dict:
        cpu_temp = None
        try:
            with open('/sys/class/thermal/thermal_zone0/temp') as f:
                cpu_temp = round(int(f.read().strip()) / 1000.0, 1)
        except Exception:
            pass

        cpu_pct = ram_used = ram_total = disk_used = disk_total = uptime = None
        try:
            import psutil
            mem = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            cpu_pct = round(psutil.cpu_percent(interval=0.1), 1)
            uptime = int(time.time() - psutil.boot_time())
            ram_used = round(mem.used / 1024 / 1024, 1)
            ram_total = round(mem.total / 1024 / 1024, 1)
            disk_used = round(disk.used / 1024 / 1024 / 1024, 2)
            disk_total = round(disk.total / 1024 / 1024 / 1024, 2)
        except ImportError:
            pass

        with self._lock:
            state = dict(self._state)

        return {
            'type': 'heartbeat',
            'device_id': self._device_id,
            'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'cpu_temp': cpu_temp,
            'cpu_percent': cpu_pct,
            'ram_used_mb': ram_used,
            'ram_total_mb': ram_total,
            'disk_used_gb': disk_used,
            'disk_total_gb': disk_total,
            'uptime_seconds': uptime,
            **state,
        }

    def _handle_restart(self, new_flags: dict):
        """Reconstrói os argumentos do processo com as novas flags e faz os.execv()."""
        import os
        import sys
        print('[Heartbeat] Comando de reinício recebido — a aplicar nova configuração...')

        # Parsear argv atual em flag -> lista de valores (suporta flags multi-valor
        # como --labels Healthy Unhealthy; None = flag booleana)
        current: dict = {}
        positional: list = []
        i = 1  # skip nome do script
        argv = sys.argv
        while i < len(argv):
            if argv[i].startswith('-'):
                values: list[str] = []
                j = i + 1
                while j < len(argv) and not argv[j].startswith('-'):
                    values.append(argv[j])
                    j += 1
                current[argv[i]] = values if values else None
                i = j
            else:
                positional.append(argv[i])
                i += 1

        # Aplicar novas flags (sobrepõe as existentes)
        for flag, value in new_flags.items():
            current[str(flag)] = [str(value)]

        # Reconstruir argv
        new_argv: list[str] = [argv[0]] + positional
        for flag, values in current.items():
            new_argv.append(flag)
            if values is not None:
                new_argv.extend(values)

        self.stop()
        time.sleep(0.3)  # pausa breve para o socket fechar
        print(f'[Heartbeat] Reiniciando: {sys.executable} {" ".join(new_argv)}')
        os.execv(sys.executable, [sys.executable] + new_argv)

    def _run_loop(self):
        import asyncio as _asyncio
        import websockets as _ws

        async def _loop():
            while self._running:
                try:
                    async with _ws.connect(self._ws_uri, ping_interval=None) as ws:
                        while self._running:
                            payload = self._collect()
                            await ws.send(json.dumps(payload))
                            # Aguarda resposta (ack ou comando de reinício)
                            try:
                                raw = await _asyncio.wait_for(ws.recv(), timeout=3.0)
                                resp = json.loads(raw)
                                if resp.get('type') == 'restart_cmd':
                                    self._handle_restart(resp.get('flags', {}))
                                    return  # os.execv() substitui o processo
                            except (_asyncio.TimeoutError, Exception):
                                pass
                            # Espera restante do intervalo em micro-passos
                            for _ in range(int(self._interval * 10)):
                                if not self._running:
                                    break
                                await _asyncio.sleep(0.1)
                except Exception as e:
                    if self._running:
                        print(f'   [Heartbeat] Ligação perdida: {e}. A reconectar em 5s...')
                        await _asyncio.sleep(5)

        _asyncio.run(_loop())


def run_cmd(cmd):
    # run command and capture output for diagnostics
    cp = subprocess.run(cmd, capture_output=True, text=True)
    return cp


def capture_image(output_path: Path, rpicam_cmd: list):
    cmd = list(rpicam_cmd)
    # replace placeholder {output} if present
    replaced = False
    for i, p in enumerate(cmd):
        if '{output}' in p:
            cmd[i] = p.replace('{output}', str(output_path))
            replaced = True
    if not replaced:
        cmd += ['-o', str(output_path)]
    cp = run_cmd(cmd)
    if cp.returncode != 0:
        raise RuntimeError(f"Capture command failed (rc={cp.returncode})\nSTDOUT:\n{cp.stdout}\nSTDERR:\n{cp.stderr}")
    # ensure file was created
    if not output_path.exists():
        raise RuntimeError(
            f"Capture command completed but output file was not found: {output_path}\n"
            f"Command stdout:\n{cp.stdout}\nCommand stderr:\n{cp.stderr}\n"
            "Check rpicam-still flags and that the camera wrote the file to the given path. "
            "You can try running the capture command manually to debug or add the '{output}' placeholder in --rpicam-cmd."
        )


def _rgb_to_hsv_np(rgb: np.ndarray) -> np.ndarray:
    """Convert HxWx3 float [0,1] RGB array to HxWx3 HSV array."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    maxc = np.max(rgb, axis=-1)
    minc = np.min(rgb, axis=-1)
    v = maxc
    with np.errstate(divide='ignore', invalid='ignore'):  # 0/0 em pixels pretos é mascarado pelo np.where
        s = np.where(maxc != 0, (maxc - minc) / maxc, 0.0)
    delta = maxc - minc
    h = np.zeros_like(maxc)
    mask_r = (maxc == r) & (delta != 0)
    mask_g = (maxc == g) & (delta != 0)
    mask_b = (maxc == b) & (delta != 0)
    h[mask_r] = ((g[mask_r] - b[mask_r]) / delta[mask_r]) % 6
    h[mask_g] = (b[mask_g] - r[mask_g]) / delta[mask_g] + 2
    h[mask_b] = (r[mask_b] - g[mask_b]) / delta[mask_b] + 4
    h = (h / 6.0) % 1.0
    return np.stack([h, s, v], axis=-1)


def fit_circle_ransac(xs, ys, max_iters=35, threshold=4.0):
    """Fit a circle to 2D points using RANSAC to be robust to cut-offs and noise."""
    import random
    N = len(xs)
    if N < 3:
        return None, None, None, 0
        
    points = np.column_stack((xs, ys))
    best_cx, best_cy, best_R = None, None, None
    max_inliers = -1
    
    # Use python's random which is much faster for single sample generation
    random.seed(42)
    
    # Pre-convert points to list of tuples for fast sampling
    pts_list = [tuple(p) for p in points]
    
    for _ in range(max_iters):
        # Pick 3 random points
        p1, p2, p3 = random.sample(pts_list, 3)
        
        # Inline circle equation solve for speed
        x1, y1 = p1
        x2, y2 = p2
        x3, y3 = p3
        
        d = 2 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2))
        if abs(d) < 1e-5:
            continue
            
        cx = ((x1**2 + y1**2) * (y2 - y3) + (x2**2 + y2**2) * (y3 - y1) + (x3**2 + y3**2) * (y1 - y2)) / d
        cy = ((x1**2 + y1**2) * (x3 - x2) + (x2**2 + y2**2) * (x1 - x3) + (x3**2 + y3**2) * (x2 - x1)) / d
        R = np.sqrt((x1 - cx)**2 + (y1 - cy)**2)
        
        if R < 5 or R > 140:  # Sanity checks on radius relative to thumbnail
            continue
            
        # Fast vectorized distance check using squared distances to avoid np.sqrt inside loop
        r_min_sq = (R - threshold) ** 2
        r_max_sq = (R + threshold) ** 2
        dist_sq = (xs - cx)**2 + (ys - cy)**2
        
        inliers = np.sum((dist_sq >= r_min_sq) & (dist_sq <= r_max_sq))
        if inliers > max_inliers:
            max_inliers = inliers
            best_cx, best_cy, best_R = cx, cy, R
            
    # Refine the fit using Kasa method on inliers only
    if best_cx is not None:
        dist_sq = (xs - best_cx)**2 + (ys - best_cy)**2
        r_min_sq = (best_R - threshold) ** 2
        r_max_sq = (best_R + threshold) ** 2
        inlier_mask = (dist_sq >= r_min_sq) & (dist_sq <= r_max_sq)
        inlier_xs = xs[inlier_mask]
        inlier_ys = ys[inlier_mask]
        
        if len(inlier_xs) >= 3:
            A = np.column_stack((inlier_xs, inlier_ys, np.ones_like(inlier_xs)))
            B = inlier_xs**2 + inlier_ys**2
            try:
                res, _, _, _ = np.linalg.lstsq(A, B, rcond=None)
                a, b, c = res
                cx_ref = a / 2.0
                cy_ref = b / 2.0
                R_ref_val = c + cx_ref**2 + cy_ref**2
                if R_ref_val > 0:
                    best_cx, best_cy, best_R = cx_ref, cy_ref, np.sqrt(R_ref_val)
                    # Recompute inliers after refinement
                    r_min_sq = (best_R - threshold) ** 2
                    r_max_sq = (best_R + threshold) ** 2
                    dist_sq = (xs - best_cx)**2 + (ys - best_cy)**2
                    max_inliers = np.sum((dist_sq >= r_min_sq) & (dist_sq <= r_max_sq))
            except:
                pass
                
    return best_cx, best_cy, best_R, max_inliers


class _LivestreamFrameBus:
    """Estado partilhado entre a thread principal do loop de vigilância
    (produtora, única a falar com a Picamera2) e as threads HTTP do
    LivestreamServer (consumidoras). Nenhum método aqui toca na câmara."""

    def __init__(self):
        self._cond = threading.Condition()
        self._frame: bytes | None = None
        self._frame_id: int = 0
        self._client_count: int = 0

    def publish(self, jpeg_bytes: bytes) -> None:
        with self._cond:
            self._frame = jpeg_bytes
            self._frame_id += 1
            self._cond.notify_all()

    def wait_for_frame(self, last_id: int, timeout: float) -> tuple[bytes | None, int]:
        with self._cond:
            self._cond.wait_for(lambda: self._frame_id != last_id, timeout=timeout)
            return self._frame, self._frame_id

    def client_connected(self) -> int:
        with self._cond:
            self._client_count += 1
            return self._client_count

    def client_disconnected(self) -> int:
        with self._cond:
            self._client_count = max(0, self._client_count - 1)
            return self._client_count

    @property
    def has_clients(self) -> bool:
        with self._cond:
            return self._client_count > 0


def _encode_livestream_frame(img_rgb: Image.Image) -> bytes:
    """Reaproveita o PIL.Image que stream.read() já devolveu — sem reencode
    via cv2 como o antigo mjpeg_server.py fazia. Redimensiona para o alvo de
    bandwidth do livestream (1280x720), independente da resolução nativa
    da CameraStream (2304x1296 em modo ativo, 640x360 em repouso)."""
    w, h = img_rgb.size
    if w > LIVESTREAM_JPEG_WIDTH or h > LIVESTREAM_JPEG_HEIGHT:
        img_rgb = img_rgb.resize((LIVESTREAM_JPEG_WIDTH, LIVESTREAM_JPEG_HEIGHT), Image.BILINEAR)
    buf = io.BytesIO()
    img_rgb.save(buf, format='JPEG', quality=LIVESTREAM_JPEG_QUALITY)
    return buf.getvalue()


class _LivestreamHandler(BaseHTTPRequestHandler):
    """Serve GET /stream.mjpg como multipart/x-mixed-replace, lendo sempre
    do _LivestreamFrameBus (nunca chama picam.capture_array() diretamente —
    evita acesso concorrente à câmara a partir desta thread)."""

    def do_GET(self):
        if self.path != '/stream.mjpg':
            self.send_response(404)
            self.end_headers()
            return

        bus: _LivestreamFrameBus = self.server.frame_bus
        self.send_response(200)
        self.send_header('Cache-Control', 'no-cache, private')
        self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=FRAME')
        self.end_headers()

        bus.client_connected()
        last_id = 0
        deadline = time.monotonic() + LIVESTREAM_MAX_CLIENT_SECONDS
        try:
            while time.monotonic() < deadline:
                if self._peer_closed():
                    break  # cliente fechou a ligação (FIN) — não esperar por um write falhado
                frame, last_id = bus.wait_for_frame(last_id, LIVESTREAM_FRAME_WAIT_TIMEOUT)
                if frame is None:
                    continue  # câmara ainda a acordar — continua à espera
                self.wfile.write(b'--FRAME\r\n')
                self.send_header('Content-Type', 'image/jpeg')
                self.send_header('Content-Length', str(len(frame)))
                self.end_headers()
                self.wfile.write(frame)
                self.wfile.write(b'\r\n')
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass  # cliente desligou
        finally:
            bus.client_disconnected()

    def _peer_closed(self) -> bool:
        """Deteta um fecho gracioso do lado do cliente (FIN) através de um
        peek não-bloqueante no socket. Necessário porque escrever num socket
        cujo par já fechou nem sempre falha de imediato (em particular em
        loopback no Windows) — sem isto, has_clients podia ficar True durante
        minutos depois do cliente ter desligado, mantendo a câmara acordada."""
        try:
            self.connection.settimeout(0.0)
            return self.connection.recv(1, socket.MSG_PEEK) == b''
        except BlockingIOError:
            return False  # sem dados pendentes — cliente continua ligado (normal, é só GET)
        except OSError:
            return True
        finally:
            self.connection.settimeout(None)

    def log_message(self, format, *args):
        pass  # silencia logs de acesso HTTP


class LivestreamServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple, frame_bus: _LivestreamFrameBus):
        super().__init__(address, _LivestreamHandler)
        self.frame_bus = frame_bus


class CameraStream:
    def __init__(self, width=2304, height=1296, fps=30, shutter_us=0, lens_position=0.0, sharpness=1.5, contrast=1.2, saturation=1.2, noise_reduction='fast', colour_gains=None, analogue_gain=0.0):
        self.width = width
        self.height = height
        self.fps = fps
        self.shutter_us = shutter_us
        self.lens_position = lens_position
        self.sharpness = sharpness
        self.contrast = contrast
        self.saturation = saturation
        self.noise_reduction = noise_reduction
        self.colour_gains = colour_gains             # None = AWB automático; (r, b) fixa os ganhos de cor
        self.analogue_gain = analogue_gain           # 0.0 = ganho automático; >0 fixa o ISO (ex: 1.0 = ISO base, menos ruído)
        self.use_picamera = False
        self.picam = None
        self.cap = None
        self.running = False
        self.latest_frame = None
        self.lock = threading.Lock()

        try:
            # Tentar importar e iniciar com Picamera2
            from picamera2 import Picamera2
            self.picam = Picamera2()
            self.use_picamera = True
            print("   [Câmara] Picamera2 detetada com sucesso.")
            
            # Criar as configurações aqui mesmo para permitir alternar dinamicamente
            self.config_high = self.picam.create_video_configuration(
                main={"size": (self.width, self.height), "format": "RGB888"}
            )
            self.config_low = self.picam.create_video_configuration(
                main={"size": (640, 360), "format": "RGB888"}
            )
        except ImportError:
            print("   [Câmara] Picamera2 não disponível. A usar OpenCV backend...")
        except Exception as e:
            print(f"   [Câmara] Picamera2 não disponível ou erro de config: {e}. A usar OpenCV backend...")
            self.use_picamera = False

    def start(self):
        if self.use_picamera:
            try:
                import libcamera
                self.picam.configure(self.config_high)
                self.picam.start()
                
                # Configurar controlos de focagem, exposição e qualidade de imagem
                controls = {}
                
                # Configurar Foco: Manual com LensPosition ou Autofocus Contínuo (Macro)
                if self.lens_position > 0.0:
                    controls["AfMode"] = libcamera.controls.AfModeEnum.Manual
                    controls["LensPosition"] = self.lens_position
                    print(f"   [Câmara] Foco manual fixado em {self.lens_position} dioptrias (~{1.0/self.lens_position:.2f}m).")
                else:
                    controls["AfMode"] = libcamera.controls.AfModeEnum.Continuous
                    controls["AfRange"] = libcamera.controls.AfRangeEnum.Macro
                    print("   [Câmara] Autofocus contínuo (modo Macro) ativado por omissão.")
                
                # Configurar Exposição
                controls["AeExposureMode"] = libcamera.controls.AeExposureModeEnum.Short
                if self.shutter_us > 0:
                    # Exposição manual: desativa o AE por completo (AeEnable=False).
                    # Sem isto, o AGC continua a ajustar o GANHO sozinho por trás,
                    # mesmo com ExposureTime fixo — o mesmo shutter podia dar
                    # imagens bem diferentes de execução para execução, porque
                    # 'exposição total' = tempo × ganho, e só o tempo estava fixo.
                    controls["ExposureTime"] = self.shutter_us
                    controls["AeEnable"] = False
                    print(f"   [Câmara] Obturador fixado em {self.shutter_us}µs (AE desativado — exposição totalmente manual).")
                else:
                    print("   [Câmara] Modo de exposição desportiva (Short/Sport) ativado por omissão.")

                # Ganho analógico (ISO): >0 fixa-o (menos ruído com boa luz); 0 = automático
                # (só relevante com AE ligado, ou seja, --shutter-us 0)
                if self.analogue_gain > 0.0:
                    controls["AnalogueGain"] = float(self.analogue_gain)
                    print(f"   [Câmara] Ganho analógico fixado em {self.analogue_gain} (ISO manual).")

                # Configurar controlos de qualidade de imagem
                controls["Sharpness"] = self.sharpness
                controls["Contrast"] = self.contrast
                controls["Saturation"] = self.saturation
                print(f"   [Câmara] Afinamento de Imagem -> Sharpness: {self.sharpness}, Contrast: {self.contrast}, Saturation: {self.saturation}")

                # Fixar balanço de brancos (evita que o AWB automático mude matizes HSV/cor entre frames)
                if self.colour_gains is not None:
                    controls["AwbEnable"] = False
                    controls["ColourGains"] = (float(self.colour_gains[0]), float(self.colour_gains[1]))
                    print(f"   [Câmara] AWB desativado. ColourGains fixados em R={self.colour_gains[0]}, B={self.colour_gains[1]}.")

                # Configurar Redução de Ruído
                if self.noise_reduction:
                    nr_val = self.noise_reduction.lower()
                    nr_enum = None
                    if hasattr(libcamera.controls, 'draft') and hasattr(libcamera.controls.draft, 'NoiseReductionModeEnum'):
                        nr_enum = libcamera.controls.draft.NoiseReductionModeEnum
                    elif hasattr(libcamera.controls, 'NoiseReductionModeEnum'):
                        nr_enum = libcamera.controls.NoiseReductionModeEnum
                    
                    if nr_enum is not None:
                        if nr_val == 'off':
                            controls["NoiseReductionMode"] = nr_enum.Off
                        elif nr_val == 'highquality':
                            controls["NoiseReductionMode"] = nr_enum.HighQuality
                        else:
                            controls["NoiseReductionMode"] = nr_enum.Fast
                        print(f"   [Câmara] Redução de Ruído -> Modo: {self.noise_reduction}")
                    else:
                        print("   [Câmara] Aviso: Enum de NoiseReductionMode não encontrado em libcamera.controls.")
                
                try:
                    self.picam.set_controls(controls)
                except Exception as e:
                    print(f"   [Câmara] Aviso: Não foi possível configurar alguns controlos: {e}")
                    
                print("   [Câmara] Stream iniciado com Picamera2.")
                return
            except Exception as e:
                print(f"   [Câmara] Erro ao iniciar Picamera2: {e}. A reverter para OpenCV...")
                self.use_picamera = False

        # Iniciar com OpenCV
        import cv2
        for dev_idx in [0, 1, 2]:
            self.cap = cv2.VideoCapture(dev_idx)
            if self.cap.isOpened():
                print(f"   [Câmara] OpenCV abriu dispositivo {dev_idx}.")
                break
        if not self.cap or not self.cap.isOpened():
            raise RuntimeError("Não foi possível abrir nenhuma câmara via OpenCV ou Picamera2!")

        # Tentar definir resolução
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
        self.cap.set(cv2.CAP_PROP_FPS, self.fps)
        try:
            self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        except:
            pass
        
        # Ativar Autofocus nativo na câmara (se suportado pelo driver V4L2)
        try:
            self.cap.set(cv2.CAP_PROP_AUTOFOCUS, 1)
        except:
            pass

        self.running = True
        self.thread = threading.Thread(target=self._update_opencv, daemon=True)
        self.thread.start()

    def _update_opencv(self):
        import cv2
        while self.running:
            ret, frame = self.cap.read()
            if ret and frame is not None:
                with self.lock:
                    self.latest_frame = frame
            else:
                time.sleep(0.005)

    def set_repouso(self, enabled: bool):
        if not self.use_picamera:
            return
        try:
            if enabled:
                print("   [Câmara] A alternar para modo de repouso (Resolução reduzida: 640x360)...")
                self.picam.switch_mode(self.config_low)
            else:
                print(f"   [Câmara] A restaurar modo ativo (Resolução nativa: {self.width}x{self.height})...")
                self.picam.switch_mode(self.config_high)
                
                # Reconfigurar controlos
                import libcamera
                controls = {}
                if self.lens_position > 0.0:
                    controls["AfMode"] = libcamera.controls.AfModeEnum.Manual
                    controls["LensPosition"] = self.lens_position
                else:
                    controls["AfMode"] = libcamera.controls.AfModeEnum.Continuous
                    controls["AfRange"] = libcamera.controls.AfRangeEnum.Macro
                
                controls["AeExposureMode"] = libcamera.controls.AeExposureModeEnum.Short
                if self.shutter_us > 0:
                    controls["ExposureTime"] = self.shutter_us
                    controls["AeEnable"] = False  # exposição manual determinística (ver start())
                if self.analogue_gain > 0.0:
                    controls["AnalogueGain"] = float(self.analogue_gain)

                controls["Sharpness"] = self.sharpness
                controls["Contrast"] = self.contrast
                controls["Saturation"] = self.saturation

                if self.colour_gains is not None:
                    controls["AwbEnable"] = False
                    controls["ColourGains"] = (float(self.colour_gains[0]), float(self.colour_gains[1]))

                if self.noise_reduction:
                    nr_val = self.noise_reduction.lower()
                    nr_enum = None
                    if hasattr(libcamera.controls, 'draft') and hasattr(libcamera.controls.draft, 'NoiseReductionModeEnum'):
                        nr_enum = libcamera.controls.draft.NoiseReductionModeEnum
                    elif hasattr(libcamera.controls, 'NoiseReductionModeEnum'):
                        nr_enum = libcamera.controls.NoiseReductionModeEnum
                    
                    if nr_enum is not None:
                        if nr_val == 'off':
                            controls["NoiseReductionMode"] = nr_enum.Off
                        elif nr_val == 'highquality':
                            controls["NoiseReductionMode"] = nr_enum.HighQuality
                        else:
                            controls["NoiseReductionMode"] = nr_enum.Fast
                
                self.picam.set_controls(controls)
        except Exception as e:
            print(f"   [Câmara] Erro ao alternar modo de repouso: {e}")

    def read(self):
        """Retorna (Image.Image em RGB, gray_lores numpy array)."""
        import cv2
        if self.use_picamera:
            try:
                frame_main = self.picam.capture_array()
                if frame_main is None:
                    return None, None
                # Se a câmara já estiver a correr a 640x360 (modo low-power), evitamos o resize
                if frame_main.shape[1] == 640 and frame_main.shape[0] == 360:
                    frame_lores = frame_main
                else:
                    frame_lores = cv2.resize(frame_main, (640, 360), interpolation=cv2.INTER_LINEAR)
                gray_lores = cv2.cvtColor(frame_lores, cv2.COLOR_BGR2GRAY)
                # Converter de BGR para RGB para compatibilidade com PIL e classificação ONNX
                frame_rgb = cv2.cvtColor(frame_main, cv2.COLOR_BGR2RGB)
                return Image.fromarray(frame_rgb), gray_lores
            except Exception as e:
                print(f"   [Câmara] Erro ao ler da Picamera2: {e}")
                return None, None
        else:
            with self.lock:
                frame_bgr = self.latest_frame
            if frame_bgr is None:
                return None, None
            # OpenCV captura em BGR, converter para RGB para PIL e classificação
            frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            # Redimensionar para lores (640x360) para análise de movimento
            frame_lores = cv2.resize(frame_bgr, (640, 360), interpolation=cv2.INTER_LINEAR)
            gray_lores = cv2.cvtColor(frame_lores, cv2.COLOR_BGR2GRAY)
            return Image.fromarray(frame_rgb), gray_lores

    def lock_auto_exposure(self):
        """Lê a exposição/ganho/AWB a que o auto convergiu e trava-os
        (AeEnable=False, AwbEnable=False). Deve ser chamado DEPOIS do warm-up,
        só faz sentido quando a exposição está em automático (shutter_us==0).
        Dá exposição/cor estáveis frame-a-frame, em vez de flutuarem por maçã."""
        if not self.use_picamera:
            print("   [Câmara] Lock de exposição indisponível no backend OpenCV.")
            return
        try:
            md = self.picam.capture_metadata()
            exp = md.get('ExposureTime')
            gain = md.get('AnalogueGain')
            cgains = md.get('ColourGains')
            controls = {'AeEnable': False, 'AwbEnable': False}
            if exp:
                controls['ExposureTime'] = int(exp)
            if gain:
                controls['AnalogueGain'] = float(gain)
            if cgains:
                controls['ColourGains'] = (float(cgains[0]), float(cgains[1]))
            self.picam.set_controls(controls)
            print(f"   [Câmara] Exposição travada: {exp}µs | ganho {gain:.2f} | "
                  f"AWB {tuple(round(c, 2) for c in cgains) if cgains else 'auto'}.")
        except Exception as e:
            print(f"   [Câmara] Não foi possível travar a exposição: {e}")

    def stop(self):
        self.running = False
        if self.use_picamera:
            try:
                self.picam.stop()
            except:
                pass
        else:
            if self.cap:
                self.cap.release()


def find_apple_region(img: Image.Image):
    """Deteta o centro e bounding box da maçã usando segmentação HSV por cor e filtros de circularidade geométrica.

    Strategy:
     - Pixels com cor de maçã (amarelo/verde/vermelho) são candidatos válidos.
     - Pixels com tom de pele FORA da zona central são bloqueados (mão).
     - Identifica "ilhas" (componentes conectadas) e analisa a sua circularidade geométrica.
     - Filtra e escolhe a ilha mais circular para ser a maçã, ignorando a mão.

    Returns:
        tuple (cx, cy, x_min, y_min, x_max, y_max, best_comp_mask) em coordenadas originais,
        ou None se não for encontrada.
    Usa thumbnail proporcional com limite máximo de 128px para velocidade (~2ms no Pi 5).
    """
    MAX_DIM = 128
    w_orig, h_orig = img.size
    scale = MAX_DIM / max(w_orig, h_orig)
    thumb_w = int(w_orig * scale)
    thumb_h = int(h_orig * scale)

    thumb = img.resize((thumb_w, thumb_h), Image.BILINEAR)
    arr = np.asarray(thumb, dtype=np.float32) / 255.0
    hsv = _rgb_to_hsv_np(arr)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]

    # --- Apple hue range [0,1] ---
    # Yellow-green (0.08-0.26), red (0-0.10 or 0.88-1.0)
    hue_apple = ((h < 0.10) | (h > 0.88) | ((h > 0.08) & (h < 0.28)))
    # Incluir zonas com reflexo especular de iluminação (v > 0.65 e s > 0.08)
    bright_glare = (v > 0.65) & (s > 0.08) & hue_apple
    apple_mask = (hue_apple & (s > 0.22) & (v > 0.15)) | bright_glare

    # Preenchimento morfológico simples de buracos interiores na máscara da maçã
    if np.any(apple_mask):
        import cv2
        mask_u8 = (apple_mask.astype(np.uint8)) * 255
        kernel = np.ones((5, 5), np.uint8)
        mask_u8 = cv2.morphologyEx(mask_u8, cv2.MORPH_CLOSE, kernel)
        apple_mask = mask_u8 > 0

    # --- Skin tone range in HSV [0,1] ---
    skin_mask = (h < 0.12) & (s > 0.12) & (s < 0.65) & (v > 0.15) & (v < 0.95)

    # --- Central safe zone: inner 50% do thumbnail ---
    m_y = thumb_h // 4
    m_x = thumb_w // 4
    center_zone = np.zeros((thumb_h, thumb_w), dtype=bool)
    center_zone[m_y: thumb_h - m_y, m_x: thumb_w - m_x] = True

    hand_pixels = skin_mask & ~center_zone
    valid_mask = apple_mask & ~hand_pixels

    # --- Lógica de Ilhas (Componentes Conectadas em Numpy/Stack) ---
    components = []
    visited = np.zeros((thumb_h, thumb_w), dtype=bool)
    ys_all, xs_all = np.where(valid_mask)
    pixel_set = set(zip(ys_all, xs_all))

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
            # 4-vizinhos
            for ny, nx in [(cy-1, cx), (cy+1, cx), (cy, cx-1), (cy, cx+1)]:
                if 0 <= ny < thumb_h and 0 <= nx < thumb_w and valid_mask[ny, nx] and not visited[ny, nx]:
                    stack.append((ny, nx))
                    pixel_set.discard((ny, nx))
        if len(comp) >= 20:  # Ignorar ruídos insignificantes
            comp_mask = np.zeros((thumb_h, thumb_w), dtype=bool)
            for cy, cx in comp:
                comp_mask[cy, cx] = True
            components.append((comp, comp_mask))

    best_candidate = None
    best_comp_mask = None
    min_score = 999.0

    import cv2
    for comp, comp_mask in components:
        # Extrair contornos da ilha de forma rápida em Numpy
        padded = np.pad(comp_mask, 1, mode='constant', constant_values=False)
        interior = (
            padded[1:-1, 1:-1] &
            padded[:-2, 1:-1] &
            padded[2:, 1:-1] &
            padded[1:-1, :-2] &
            padded[1:-1, 2:]
        )
        contour = comp_mask & ~interior
        cys, cxs = np.where(contour)
        
        if len(cxs) < 10:
            continue
            
        # 1. Tentar RANSAC clássico para estimar o círculo
        cx_fit, cy_fit, R_fit, inliers = fit_circle_ransac(cxs, cys)
        
        # 2. Se o RANSAC falhar ou for incerto, usar cv2.minEnclosingCircle determinístico
        if cx_fit is None or R_fit is None or R_fit < 5:
            pts = np.column_stack((cxs, cys)).astype(np.float32)
            (cx_fit, cy_fit), R_fit = cv2.minEnclosingCircle(pts)
            score = 0.1  # Excelente pontuação determinística
        else:
            inlier_ratio = inliers / len(cxs)
            score = 1.0 - inlier_ratio

        # Garante que o raio é razoável
        if R_fit < 5 or R_fit > 140:
            continue

        if score < min_score:
            min_score = score
            x_min_c = cx_fit - R_fit
            y_min_c = cy_fit - R_fit
            x_max_c = cx_fit + R_fit
            y_max_c = cy_fit + R_fit
            best_candidate = (cx_fit, cy_fit, x_min_c, y_min_c, x_max_c, y_max_c)
            best_comp_mask = comp_mask

    if best_candidate is None:
        # FALLBACK: Usar o maior blob de cor detetado via cv2.minEnclosingCircle
        if components:
            largest_comp, largest_comp_mask = max(components, key=lambda c: len(c[0]))
            cys, cxs = np.where(largest_comp_mask)
            if len(cxs) >= 5:
                pts = np.column_stack((cxs, cys)).astype(np.float32)
                (cx_l, cy_l), R_l = cv2.minEnclosingCircle(pts)
                x_min_l = cx_l - R_l
                y_min_l = cy_l - R_l
                x_max_l = cx_l + R_l
                y_max_l = cy_l + R_l
                
                s = 1.0 / scale
                print(f"   [Deteção Híbrida] A usar minEnclosingCircle no maior blob de cor ({len(largest_comp)} px).")
                return (cx_l * s, cy_l * s, x_min_l * s, y_min_l * s, x_max_l * s, y_max_l * s, largest_comp_mask)
        return None

    # Escalar de volta para coordenadas originais
    cx, cy, x_min, y_min, x_max, y_max = best_candidate
    s = 1.0 / scale
    return (cx * s, cy * s, x_min * s, y_min * s, x_max * s, y_max * s, best_comp_mask)



# Manter retrocompatibilidade: find_apple_center delega para find_apple_region
def find_apple_center(img: Image.Image):
    region = find_apple_region(img)
    if region is None:
        return None
    cx, cy = region[0], region[1]
    return (cx, cy)


def frame_has_apple(img: Image.Image, min_area_frac: float = 0.0) -> bool:
    """True se find_apple_region encontra uma maçã no frame. Com min_area_frac>0,
    exige também que a bounding box ocupe pelo menos essa fração da área do frame,
    rejeitando blobs minúsculos de ruído de fundo em falsos gatilhos. Usado para
    NÃO enviar frames sem maçã (fundo vazio) para a BD/PC."""
    region = find_apple_region(img)
    if region is None:
        return False
    if min_area_frac > 0.0:
        _, _, x_min, y_min, x_max, y_max, _ = region
        area = max(0.0, x_max - x_min) * max(0.0, y_max - y_min)
        if area < min_area_frac * (img.size[0] * img.size[1]):
            return False
    return True


def blur_score_image(img: Image.Image) -> float:
    """Variância do Laplaciano numa thumbnail 256x256 grayscale, em memória
    (mesma matemática de compute_blur_score, sem passar pelo disco). Usado na
    corrida de foco para escolher o frame mais nítido logo após o gatilho."""
    small = np.asarray(img.convert('L').resize((256, 256), Image.BILINEAR), dtype=np.float32)
    lap = (small[:-2, 1:-1] + small[2:, 1:-1] + small[1:-1, :-2] + small[1:-1, 2:]
           - 4.0 * small[1:-1, 1:-1])
    return float(np.var(lap))


def calibrate_focus(args):
    """Modo de calibração de foco para montagens fixas.

    Coloca uma maçã PARADA no ponto exato onde as maçãs passam e corre o script
    com --calibrate-focus. O autofocus contínuo (macro) converge sobre a maçã e,
    no fim, imprime a LensPosition mediana — o valor a pôr em --lens-position
    daí em diante (foco fixo, sem 'caça' de foco em cada maçã)."""
    import statistics

    print("\n" + "=" * 60)
    print(" MODO CALIBRAÇÃO DE FOCO")
    print(" Coloca uma maçã PARADA no ponto exato de passagem das maçãs.")
    print(" A medir a posição de foco durante ~15s...")
    print("=" * 60 + "\n")

    stream = CameraStream(
        width=getattr(args, 'width', 2304) or 2304,
        height=getattr(args, 'height', 1296) or 1296,
        shutter_us=0,        # exposição automática: imagem clara facilita o AF
        lens_position=0.0,   # 0.0 = autofocus contínuo (macro)
        sharpness=getattr(args, 'sharpness', 1.5),
        contrast=getattr(args, 'contrast', 1.2),
        saturation=getattr(args, 'saturation', 1.2),
        noise_reduction=getattr(args, 'noise_reduction', 'fast'),
    )
    stream.start()

    if not stream.use_picamera:
        print("[Calibração] ERRO: este modo requer Picamera2 — o backend OpenCV "
              "não expõe a metadata LensPosition.")
        stream.stop()
        return

    readings = []
    t_end = time.time() + 15.0
    try:
        while time.time() < t_end:
            try:
                md = stream.picam.capture_metadata()
            except Exception as e:
                print(f"[Calibração] Erro a ler metadata: {e}")
                time.sleep(0.25)
                continue
            lens = md.get('LensPosition')
            af_state = md.get('AfState')  # 0=Idle 1=Scanning 2=Focused 3=Failed
            if lens is not None:
                if af_state == 2:
                    readings.append(float(lens))
                    print(f"   FOCADO: LensPosition={lens:.2f} ({len(readings)} amostras)")
                else:
                    print(f"   a focar... LensPosition={lens:.2f} (AfState={af_state})")
            time.sleep(0.25)
    finally:
        stream.stop()

    print("\n" + "=" * 60)
    if readings:
        med = statistics.median(readings)
        dist_str = f" (~{1.0 / med:.2f} m)" if med > 0.01 else ""
        print(f" RESULTADO: LensPosition mediana = {med:.2f}{dist_str}")
        print(f" Usa a partir de agora:  --lens-position {med:.2f}")
    else:
        print(" [Calibração] O autofocus nunca convergiu (AfState=Focused).")
        print(" Verifica a iluminação e se a maçã está entre ~8cm e 1m da lente.")
    print("=" * 60)


def _crop_box_by_distance(img: Image.Image, distance_cm: float) -> tuple:
    """Return (left, top, right, bottom) crop box centered on the apple.
    Does NOT resize — caller does a single high-quality resize to the target size.
    """
    w, h = img.size
    factor = 15.0 / distance_cm
    factor = max(0.15, min(1.0, factor))
    crop_size = int(w * factor)
    center = find_apple_center(img)
    cx, cy = center if center is not None else (w / 2.0, h / 2.0)
    half = crop_size // 2
    left   = max(0, min(w - crop_size, int(cx - half)))
    top    = max(0, min(h - crop_size, int(cy - half)))
    right  = left + crop_size
    bottom = top  + crop_size
    return (left, top, right, bottom)


def compute_blur_score(raw_img_path: Path) -> float:
    """Deteta desfoque por variância do Laplaciano (~0.5ms no Pi 5).

    Score alto = imagem nítida. Score baixo = motion blur ou foco incorreto.
    Calculado numa thumbnail 256×256 em grayscale para máxima velocidade.
    Valores típicos: >200 nítido, 50-200 ligeiramente desfocado, <50 muito desfocado.
    """
    img = Image.open(raw_img_path).convert("L")  # grayscale
    img_small = img.resize((256, 256), Image.BILINEAR)
    arr = np.asarray(img_small, dtype=np.float32)
    # Kernel Laplaciano 3x3 por subtracão de vizinhos
    lap = (
        arr[:-2, 1:-1] + arr[2:, 1:-1]
        + arr[1:-1, :-2] + arr[1:-1, 2:]
        - 4.0 * arr[1:-1, 1:-1]
    )
    return float(np.var(lap))


def process_and_crop_transparent(raw_img_path: Path, output_png_path: Path, input_size=224):
    """
    Pipeline otimizado de processamento de imagem sem rembg:

    1. Carrega a imagem JPEG de alta resolução (2048×2048).
    2. Deteta a maçã por COR e filtra componente circular (~2ms).
    3. Faz um crop generoso centrado nela.
    4. Projeta a máscara de circularidade no crop e aplica no canal Alpha (instantâneo, <1ms).
    5. Binariza a máscara alfa (>128 → 255, senão 0) para bordas nítidas.
    6. Tight crop pelo canal alfa com margem de 8%.
    7. Resize para 224×224 + fundo preto → tensor normalizado para a CNN.

    Retorna o tensor np.float32 [1, 3, 224, 224] pronto para ONNX.
    """
    # 1. Carregar a imagem JPEG capturada pela câmara
    img = Image.open(raw_img_path).convert("RGB")
    w_img, h_img = img.size
    print(f"   Imagem carregada: {w_img}×{h_img}")

    # ── 2. Deteção rápida da maçã por cor (~2ms) ──
    region = find_apple_region(img)

    if region is None:
        print(f"   [Filtro Anti-Tapete] Nenhuma maçã detetada em {raw_img_path.name}. Imagem sem maçã descartada.")
        return None

    best_comp_mask = None
    cx, cy, x_min, y_min, x_max, y_max, best_comp_mask = region
    apple_w = x_max - x_min
    apple_h = y_max - y_min
    # Crop super focado: 1.15× o tamanho da maçã (remove ~95% do fundo)
    lado = int(max(apple_w, apple_h) * 1.15)
    lado = max(lado, 200)  # Mínimo 200px para manter resolução do crop
    lado = min(lado, min(w_img, h_img))  # Garante que não excede a imagem e evita margens pretas
    print(f"   Maçã detetada por cor: centro=({cx:.0f},{cy:.0f}), "
          f"bbox={apple_w:.0f}×{apple_h:.0f}, crop={lado}×{lado}")

    half = lado // 2
    left   = max(0, min(w_img - lado, int(cx - half)))
    top    = max(0, min(h_img - lado, int(cy - half)))
    right  = left + lado
    bottom = top  + lado
    pre_crop = img.crop((left, top, right, bottom))
    print(f"   Crop generoso: {pre_crop.size[0]}×{pre_crop.size[1]}")

    # ── 3. Mascarar o fundo usando a máscara circular suave (circunferência perfeita) ──
    crop_rgba = pre_crop.convert("RGBA")

    if region is not None:
        # O raio é derivado diretamente do ajuste RANSAC
        radius = (x_max - x_min) / 2.0
        
        # Coordenadas do centro relativas ao pre_crop (usando o centro geométrico direto do RANSAC)
        cx_crop = cx - left
        cy_crop = cy - top
        
        # Margem de segurança de 6% para incluir toda a casca da maçã de forma limpa
        radius_padded = radius * 1.06

        from PIL import ImageDraw, ImageFilter
        mask_pil = Image.new("L", pre_crop.size, 0)
        draw = ImageDraw.Draw(mask_pil)
        # Desenhar uma circunferência perfeita (rx == ry == radius_padded)
        draw.ellipse(
            [
                cx_crop - radius_padded,
                cy_crop - radius_padded,
                cx_crop + radius_padded,
                cy_crop + radius_padded
            ],
            fill=255
        )
        # Suavizar as bordas (anti-aliasing) com um leve desfoque gaussiano
        resized_mask_pil = mask_pil.filter(ImageFilter.GaussianBlur(radius=2))
    else:
        # Fallback: crop central sólido
        resized_mask_pil = Image.new("L", pre_crop.size, 255)

    crop_rgba.putalpha(resized_mask_pil)

    # ── 4. Binarizar a máscara alfa (bordas nítidas, sem gradiente/halo) ──
    alpha = np.array(crop_rgba)[:, :, 3]
    alpha_bin = np.where(alpha > 128, 255, 0).astype(np.uint8)
    crop_rgba.putalpha(Image.fromarray(alpha_bin))

    # ── 5. Tight crop pelo canal alfa com margem de 8% ──
    non_zero = np.argwhere(alpha_bin > 0)

    if non_zero.size > 0:
        y_min_a, x_min_a = non_zero.min(axis=0)
        y_max_a, x_max_a = non_zero.max(axis=0)

        cx_a = int((x_min_a + x_max_a) // 2)
        cy_a = int((y_min_a + y_max_a) // 2)

        lado_tight = int(max(y_max_a - y_min_a, x_max_a - x_min_a) * 1.08)
        half_t = lado_tight // 2

        # Criar canvas quadrado transparente para centralização perfeita da maçã
        final_rgba = Image.new("RGBA", (lado_tight, lado_tight), (0, 0, 0, 0))
        
        src_left   = cx_a - half_t
        src_top    = cy_a - half_t
        src_right  = src_left + lado_tight
        src_bottom = src_top + lado_tight

        w_c, h_c = crop_rgba.size
        ix_min = max(0, src_left)
        iy_min = max(0, src_top)
        ix_max = min(w_c, src_right)
        iy_max = min(h_c, src_bottom)

        if ix_max > ix_min and iy_max > iy_min:
            visible_part = crop_rgba.crop((ix_min, iy_min, ix_max, iy_max))
            dest_x = ix_min - src_left
            dest_y = iy_min - src_top
            final_rgba.paste(visible_part, (dest_x, dest_y))

        print(f"   Tight crop centrado: {final_rgba.size[0]}×{final_rgba.size[1]}")
    else:
        final_rgba = crop_rgba
        print("   [AVISO] Sem pixels no alfa, a usar crop sem ajuste")

    # ── 6a. Crop MASCARADO (maçã em fundo preto via RANSAC) em resolução nativa.
    # É ESTE que viaja para a BD e para o PC — nunca o crop cru com tapete. ──
    crop_jpg_path = output_png_path.with_name(output_png_path.stem + "_crop.jpg")
    black_full = Image.new("RGBA", final_rgba.size, (0, 0, 0, 255))
    Image.alpha_composite(black_full, final_rgba).convert("RGB").save(crop_jpg_path, "JPEG", quality=90)

    # ── 6. Resize para 224×224 (um único resize) ──
    cnn_rgba = final_rgba.resize((input_size, input_size), Image.Resampling.LANCZOS)

    # ── 7. Guardar PNG {input_size}×{input_size} transparente para envio ──
    cnn_rgba.save(output_png_path, "PNG")
    print(f"   -> PNG {input_size}×{input_size} guardado em: {output_png_path}")

    # ── 8. Fundo preto para a CNN ──
    black_bg = Image.new("RGBA", cnn_rgba.size, (0, 0, 0, 255))
    cnn_rgb = Image.alpha_composite(black_bg, cnn_rgba).convert("RGB")

    # ── 9. Normalização ImageNet ──
    arr = np.asarray(cnn_rgb, dtype=np.float32) / 255.0
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    arr = (arr - mean) / std
    arr = np.transpose(arr, (2, 0, 1))[None, ...].astype(np.float32)
    return arr



def postprocess_output(out):
    out = np.asarray(out)
    if out.ndim == 1 and out.shape[0] == 1:
        prob = 1.0 / (1.0 + np.exp(-out[0]))
        pred = int(prob >= 0.5)
        conf = float(prob)
    else:
        if out.ndim == 2:
            logits = out[0]
        else:
            logits = out.flatten()
        ex = np.exp(logits - np.max(logits))
        probs = ex / ex.sum()
        pred = int(np.argmax(probs))
        conf = float(probs[pred])
    return pred, conf


def infer(model_path: Path, raw_image_path: Path, output_png_path: Path, input_size: int):
    sess = ort.InferenceSession(str(model_path), providers=['CPUExecutionProvider'])
    input_name = sess.get_inputs()[0].name
    inp = process_and_crop_transparent(raw_image_path, output_png_path, input_size)
    out = sess.run(None, {input_name: inp})[0]
    pred, conf = postprocess_output(out)
    return pred, conf


# ---------------------------------------------------------------------------
# Modo Burst: ThreadPoolExecutor (N frames em paralelo)
# ---------------------------------------------------------------------------

def burst_capture_and_classify(
    model_path: Path, tmp_base: Path, input_size: int, labels: list,
    capture_time: int, num_shots: int = 3, interval_ms: int = 150,
    shutter_us: int = 0
):
    """
    Captura N fotos em rajada e processa-as em paralelo com ThreadPoolExecutor.

    Fase 1 (capture): Dispara todos os N shots a interval_ms de intervalo.
                      Total: ~(N-1)*interval_ms + disk_write_time ≈ 370ms para N=3.
    Fase 2 (process): Processa todos os frames simultaneamente em N threads.
                      Wall time ≈ max(proc_frame_i) em vez de sum(proc_frame_i).

    Resistência a movimento:
      - shutter_us: obturador rápido congela objetos em movimento.
      - blur_score (Laplaciano) por frame: peso no consenso final.

    Returns:
        list of dicts ordenados por índice de captura.
    """
    import signal

    shutter_str = f"{shutter_us}µs" if shutter_us else "automático"
    print(f"\n{'='*60}")
    print(f" MODO BURST: {num_shots} fotos | intervalo={interval_ms}ms | shutter={shutter_str}")
    print(f"{'='*60}")

    # 1. Pré-carregar modelos (cold start ~1s, só na 1ª vez)
    print("A pré-carregar modelos...")
    sess = ort.InferenceSession(str(model_path), providers=['CPUExecutionProvider'])
    input_name = sess.get_inputs()[0].name
    print("Modelos carregados!")

    # 2. Limpar ficheiros de burst anteriores
    for f in tmp_base.glob('burst_*'):
        f.unlink()

    t_global_start = time.perf_counter()

    # 3. Preparar comando timelapse nativo (evita as perdas do modo --signal)
    burst_pattern = str(tmp_base / 'burst_%04d.jpg')
    burst_cmd = [
        'rpicam-still',
        '-t', '0',                                # Fica ativo indefinidamente até ao sinal
        '--keypress',                             # Aguarda por um input no stdin para disparar
        '--timelapse', str(interval_ms),
        '--framestart', '0',
        '--width', '2304', '--height', '1296',   # Resolução 16:9 de alta qualidade
        '--autofocus-mode', 'auto',               # 'auto' é melhor que 'continuous' para objetos parados
        '--autofocus-range', 'macro',             # Foco curto otimizado (30-40cm)
        '--exposure', 'sport',                    # Obturador rápido para congelar movimento com luz automática
        '-q', '95', '-n',                         # Qualidade JPEG 95% para máximo detalhe
        '-o', burst_pattern
    ]
    if shutter_us and shutter_us > 0:
        burst_cmd.extend(['--shutter', str(shutter_us)])

    print(f"\nA iniciar câmara, sensor a aquecer e a focar ({capture_time/1000:.1f}s)...\n")
    print(f"Comando de captura: {' '.join(burst_cmd)}")
    
    # Inicia a câmara primeiro para que ela possa focar com o sensor ativo
    capture_proc = subprocess.Popen(
        burst_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE
    )
    
    # Aguardar que o autofocus estabilize com a câmara ligada
    time.sleep(capture_time / 1000.0)
    
    print(f"Foco estabilizado. A enviar sinal de disparo para a rajada...")
    t_burst_start = time.perf_counter()
    
    # Enviar sinal "Enter" via stdin para disparar
    try:
        capture_proc.stdin.write(b'\n')
        capture_proc.stdin.flush()
    except Exception as e:
        print(f"Erro ao disparar câmara via stdin: {e}")

    def wait_for_file(fpath, timeout_s=4.0):
        """Aguarda que o ficheiro exista e tenha tamanho razoável."""
        t0 = time.perf_counter()
        while (time.perf_counter() - t0) < timeout_s:
            try:
                if fpath.exists() and fpath.stat().st_size > 1000:
                    return True
            except OSError:
                pass
            time.sleep(0.010)
        return False

    # =====================================================================
    # FASE 2: Pipeline de Processamento Assíncrono Concorrente
    # =====================================================================
    results = [None] * num_shots
    futures = {}

    def process_one_frame(idx, raw_path, png_path):
        """Processa um frame: blur + circular_mask + ONNX. Corre numa thread própria."""
        t0 = time.perf_counter()
        try:
            blur_score = compute_blur_score(raw_path)
            inp = process_and_crop_transparent(raw_path, png_path, input_size)
            out = sess.run(None, {input_name: inp})[0]
            pred, conf = postprocess_output(out)
            label = labels[pred] if pred < len(labels) else str(pred)
            elapsed_ms = (time.perf_counter() - t0) * 1000
            return idx, {
                'label': label, 'index': int(pred),
                'confidence': float(conf), 'blur_score': float(blur_score),
                'png_path': png_path, 'processing_ms': elapsed_ms
            }
        except Exception as e:
            print(f"   [Frame {idx+1}] ERRO: {e}")
            return idx, {
                'label': 'Error', 'index': -1,
                'confidence': 0.0, 'blur_score': 0.0,
                'png_path': png_path, 'processing_ms': 0
            }

    print(f"\nA iniciar pipeline concorrente de captura e processamento...")
    with ThreadPoolExecutor(max_workers=num_shots) as pool:
        for i in range(num_shots):
            fpath = tmp_base / f'burst_{i:04d}.jpg'
            # Damos tempo para cada ficheiro aparecer. O primeiro demora mais pelo arranque, os seguintes são rápidos
            if wait_for_file(fpath, timeout_s=4.0):
                png_p = tmp_base / f'burst_{i:04d}.png'
                t_disk = (time.perf_counter() - t_burst_start) * 1000
                print(f"   [Shot {i+1}/{num_shots}] No disco @ T+{t_disk:.0f}ms -> A processar concorrentemente...")
                # Submeter para processamento assíncrono de imediato
                futures[pool.submit(process_one_frame, i, fpath, png_p)] = i
            else:
                print(f"   [Shot {i+1}/{num_shots}] AVISO: ficheiro não apareceu!")

        # Matar a câmara imediatamente após recolher os frames desejados
        capture_proc.terminate()
        try:
            capture_proc.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            capture_proc.kill()

        # Aguardar conclusão dos frames submetidos
        for fut in as_completed(futures):
            idx, result = fut.result()
            results[idx] = result

    # Imprimir os logs de forma estritamente sequencial (Frame 1 a N)
    for i, res in enumerate(results):
        if res is not None and res['index'] >= 0:
            blur_score = res['blur_score']
            sharpness = "nítido" if blur_score > 200 else ("ok" if blur_score > 50 else "desfocado!")
            print(f"   [Frame {i+1}] {res['label']} ({res['confidence']*100:.1f}%) | blur={blur_score:.0f} ({sharpness}) | {res['processing_ms']:.0f}ms")

    t_total = (time.perf_counter() - t_global_start) * 1000
    num_ok = sum(1 for r in results if r is not None and r['index'] >= 0)
    print(f"\n{'='*60}")
    print(f" BURST COMPLETO: {num_ok}/{num_shots} fotos em {t_total:.0f}ms")
    print(f"{'='*60}\n")

    return [r for r in results if r is not None]


# ===========================================================================
# MULTI-MAÇÃ (beta, --multi-apple) — portado de raspberry_multi_apple.py,
# reaproveitando as funções DESTE ficheiro (find_apple_region usa _rgb_to_hsv_np
# e fit_circle_ransac; classify_region usa compute_blur_score/postprocess_output;
# o envio reaproveita send_burst_results_ws/send_result). OFF por omissão: nada
# disto corre e o caminho single-maçã fica exatamente igual.
# ===========================================================================
_MULTI_MAX_TRACK_DIST_FRAC = 0.25   # limite de correlação entre frames (fração da largura)
_MULTI_CROP_MIN = 300               # lado mínimo do crop generoso (igual ao single)
_MULTI_MIN_AREA_FRAC = 0.02         # área mínima da ilha (fração da thumbnail)
_MULTI_MIN_SIZE_REL = 0.30          # tamanho mínimo relativo ao maior candidato do frame


def find_all_apple_regions(img: Image.Image, max_regions: int = 1) -> list:
    """Como find_apple_region, mas devolve até `max_regions` ilhas válidas
    (top-N por circularidade) em vez de só a melhor. max_regions=1 reproduz o
    comportamento single. Cada item: (cx, cy, x_min, y_min, x_max, y_max, mask)."""
    MAX_DIM = 128
    w_orig, h_orig = img.size
    scale = MAX_DIM / max(w_orig, h_orig)
    thumb_w = int(w_orig * scale)
    thumb_h = int(h_orig * scale)

    thumb = img.resize((thumb_w, thumb_h), Image.BILINEAR)
    arr = np.asarray(thumb, dtype=np.float32) / 255.0
    hsv = _rgb_to_hsv_np(arr)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]

    apple_color = ((h < 0.45) | (h > 0.85)) & (s > 0.30) & (v > 0.15)
    dark_mask = (v < 0.30) & (s > 0.10)

    # Multi-maçã: NÃO assume uma maçã centrada. Ao contrário do single
    # (find_apple_region), não aplica o filtro "mão/pele fora do centro" que
    # apagava maçãs nas bordas — aqui queremos maçãs em qualquer posição. Mãos
    # e ruído são rejeitados a jusante pela circularidade (RANSAC score<0.75) +
    # área mínima + color_ratio, que uma mão (não circular) não passa.
    valid_mask = apple_color | dark_mask

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
    candidates = []
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

        cx_fit, cy_fit, R_fit, inliers = fit_circle_ransac(cxs, cys)
        if cx_fit is None:
            continue

        inlier_ratio = inliers / len(cxs)
        score = 1.0 - inlier_ratio

        centroid_x = np.mean(cxs)
        centroid_y = np.mean(cys)
        dist_to_centroid = np.sqrt((cx_fit - centroid_x) ** 2 + (cy_fit - centroid_y) ** 2)
        if dist_to_centroid > R_fit * 1.5:
            continue
        if score >= 0.75:
            continue
        if (len(comp) / thumb_area) < _MULTI_MIN_AREA_FRAC:
            continue

        candidates.append((
            score, len(comp), cx_fit, cy_fit,
            cx_fit - R_fit, cy_fit - R_fit, cx_fit + R_fit, cy_fit + R_fit,
            comp_mask,
        ))

    s_inv = 1.0 / scale

    if candidates:
        max_size = max(c[1] for c in candidates)
        candidates = [c for c in candidates if c[1] >= _MULTI_MIN_SIZE_REL * max_size]
        candidates.sort(key=lambda c: c[0])
        candidates = candidates[:max_regions]
        return [
            (cx * s_inv, cy * s_inv, x0 * s_inv, y0 * s_inv, x1 * s_inv, y1 * s_inv, mask)
            for _, _, cx, cy, x0, y0, x1, y1, mask in candidates
        ]

    # Fallback: nenhum candidato circular — maior blob de cor (nunca "nada")
    if components:
        largest_comp, largest_mask = max(components, key=lambda c: len(c[0]))
        cys, cxs = np.where(largest_mask)
        if len(cxs) > 0:
            x0, x1 = float(np.min(cxs)), float(np.max(cxs))
            y0, y1 = float(np.min(cys)), float(np.max(cys))
            cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
            return [(cx * s_inv, cy * s_inv, x0 * s_inv, y0 * s_inv, x1 * s_inv, y1 * s_inv, largest_mask)]

    return []


def match_tracks(frame_regions: list, frame_width: int) -> list:
    """Correlaciona a MESMA maçã física entre os frames do burst (senão seria
    contada 2-3x). Cada track tem len(frame_regions) posições (região ou None)."""
    if not frame_regions or all(not r for r in frame_regions):
        return []
    ref_idx = max(range(len(frame_regions)), key=lambda i: len(frame_regions[i]))
    if not frame_regions[ref_idx]:
        return []
    tracks = [[None] * len(frame_regions) for _ in frame_regions[ref_idx]]
    for k, r in enumerate(frame_regions[ref_idx]):
        tracks[k][ref_idx] = r
    max_dist = _MULTI_MAX_TRACK_DIST_FRAC * frame_width
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


def _multi_safe_crop_lado(region: tuple, other_regions: list, margin: float = 1.15) -> float:
    """Lado do crop de uma maçã, limitado a nunca ultrapassar o ponto médio até
    o vizinho mais próximo do mesmo frame (não inclui a maçã ao lado)."""
    cx, cy = region[0], region[1]
    lado = max(region[4] - region[2], region[5] - region[3]) * margin
    for other in other_regions:
        if other is region:
            continue
        d = math.hypot(cx - other[0], cy - other[1])
        if d > 0:
            lado = min(lado, d * 0.9)
    return lado


def _multi_crop_mask_and_tensor(img: Image.Image, region: tuple, lado: int, input_size: int):
    """Replica os passos de crop/máscara/normalização usando uma região JÁ
    CONHECIDA (não re-deteta no recorte isolado, onde escolheria ruído). Devolve
    (pre_crop RGB, cnn_rgba RGBA 224, tensor [1,3,224,224])."""
    from PIL import ImageDraw, ImageFilter
    cx, cy, x_min, y_min, x_max, y_max, _ = region
    w_img, h_img = img.size
    half = lado // 2
    left = max(0, min(w_img - lado, int(cx - half)))
    top = max(0, min(h_img - lado, int(cy - half)))
    pre_crop = img.crop((left, top, left + lado, top + lado))

    crop_rgba = pre_crop.convert('RGBA')
    radius = (x_max - x_min) / 2.0
    radius_padded = radius * 1.06
    cx_crop, cy_crop = cx - left, cy - top
    mask_pil = Image.new('L', pre_crop.size, 0)
    draw = ImageDraw.Draw(mask_pil)
    draw.ellipse([cx_crop - radius_padded, cy_crop - radius_padded,
                  cx_crop + radius_padded, cy_crop + radius_padded], fill=255)
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

    # Crop MASCARADO em resolução nativa (maçã em fundo preto via RANSAC), para
    # gravar/enviar — livra-se do tapete de fundo, ao contrário do pre_crop cru.
    black_full = Image.new('RGBA', final_rgba.size, (0, 0, 0, 255))
    masked_crop = Image.alpha_composite(black_full, final_rgba).convert('RGB')

    arr = np.asarray(cnn_rgb, dtype=np.float32) / 255.0
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    arr = (arr - mean) / std
    tensor = np.transpose(arr, (2, 0, 1))[None, ...].astype(np.float32)
    return masked_crop, cnn_rgba, tensor


def classify_region(img, region, other_regions, tmp_base, file_prefix, sess, input_name, labels, input_size):
    """Recorta e classifica uma região conhecida; grava {prefix}.png + {prefix}_crop.jpg
    (mesma convenção do single, para send_burst_results_ws os reaproveitar) e
    devolve o mesmo dict de resultado por frame."""
    t0 = time.perf_counter()
    w_img, h_img = img.size
    lado = int(_multi_safe_crop_lado(region, other_regions))
    lado = max(lado, _MULTI_CROP_MIN)
    lado = min(lado, min(w_img, h_img))

    masked_crop, cnn_rgba, tensor = _multi_crop_mask_and_tensor(img, region, lado, input_size)
    png_path = tmp_base / f'{file_prefix}.png'
    crop_path = tmp_base / f'{file_prefix}_crop.jpg'
    cnn_rgba.save(png_path, 'PNG')
    masked_crop.save(crop_path, 'JPEG', quality=95)  # maçã em fundo preto (sem tapete)

    blur_score = compute_blur_score(crop_path)
    out = sess.run(None, {input_name: tensor})[0]
    pred, conf = postprocess_output(out)
    label = labels[pred] if pred < len(labels) else str(pred)
    return {
        'label': label, 'index': int(pred), 'confidence': float(conf),
        'blur_score': float(blur_score), 'png_path': png_path,
        'processing_ms': (time.perf_counter() - t0) * 1000,
    }


def process_burst_multi(frames, args, sess, input_name, tmp_base, input_size, labels) -> int:
    """[BETA] Deteta várias maçãs por frame, correlaciona-as e envia CADA uma
    como o seu próprio apple_id (imagem separada). Devolve nº de classificações
    válidas. Reaproveita o consenso/envio do single via send_burst_results_ws."""
    if not frames:
        return 0
    max_regions = getattr(args, 'max_apples', 4)
    frame_regions = [find_all_apple_regions(f, max_regions=max_regions) for f in frames]
    n_apples = max((len(r) for r in frame_regions), default=0)
    if n_apples == 0:
        print("   [Multi] Descartado: nenhuma maçã detetada em nenhum frame.")
        return 0
    print(f"   [Multi] {n_apples} maçã(s) detetada(s) — a correlacionar entre frames...")

    tracks = match_tracks(frame_regions, frame_width=frames[0].size[0])
    total = 0
    for k, track in enumerate(tracks):
        apple_id = generate_apple_id()
        if len(tracks) > 1:
            apple_id = f"{apple_id}_{k + 1}"
        track_results = []
        for i, (frame, region) in enumerate(zip(frames, track)):
            if region is None:
                continue
            prefix = f"{apple_id}_frame{i + 1}"
            others = [r for r in frame_regions[i] if r is not region]
            track_results.append(classify_region(
                frame, region, others, tmp_base, prefix, sess, input_name, labels, input_size))
        valid = [r for r in track_results if r.get('index', -1) >= 0]
        # Mínimo de frames por maçã (a CNN5 precisa de >= min_frames p/ patologias);
        # nunca exige mais do que os frames capturados.
        required = min(getattr(args, 'min_frames', 2), len(frames))
        if len(valid) < required:
            print(f"      [Maçã {k + 1}] descartada: {len(valid)} frame(s) (< {required} exigidos).")
            continue
        for r in valid:
            print(f"      [Maçã {k + 1}] {r['label']} ({r['confidence'] * 100:.1f}%) | blur={r['blur_score']:.0f}")
        total += len(valid)
        if args.ws_server:
            send_burst_results_ws(valid, args, apple_id=apple_id)
        else:
            for i, r in enumerate(valid):
                send_result(r, args, tmp_base / f"multi_{apple_id}_{i}.json")
    return total


def stream_vigilance_and_classify(model_path: Path, input_size: int, labels: list, args):
    """
    Mantém o stream da câmara ativo. Monitoriza movimento nos 15% das colunas esquerda/direita (ROIs).
    Quando deteta movimento, faz capturas de alta qualidade, processa e classifica com ONNX.
    """
    import cv2
    import time
    
    # Garantir que a pasta temporária de crops existe
    tmp_base = Path('/tmp/onnx_capture')
    tmp_base.mkdir(parents=True, exist_ok=True)

    width = args.width if hasattr(args, 'width') and args.width else 2304
    height = args.height if hasattr(args, 'height') and args.height else 1296
    
    print(f"\n{'='*60}")
    print(f" MODO STREAM CONTÍNUO: {width}x{height} | burst={args.burst} | interval={args.burst_interval}ms")
    print(f"{'='*60}")

    # 1. Carregar modelo ONNX (cold start único)
    print("A carregar modelo ONNX...")
    sess = ort.InferenceSession(str(model_path), providers=['CPUExecutionProvider'])
    input_name = sess.get_inputs()[0].name
    print("Modelo carregado com sucesso!")

    # 2. Inicializar o stream da câmara
    shutter_us = args.shutter_us if hasattr(args, 'shutter_us') else 0
    lens_position = args.lens_position if hasattr(args, 'lens_position') else 0.0
    sharpness = args.sharpness if hasattr(args, 'sharpness') else 1.5
    contrast = args.contrast if hasattr(args, 'contrast') else 1.2
    saturation = args.saturation if hasattr(args, 'saturation') else 1.2
    noise_reduction = args.noise_reduction if hasattr(args, 'noise_reduction') else 'fast'

    # Parsear colour_gains: vem como string "r,b" da CLI, ex: "1.6,1.5"
    colour_gains_raw = getattr(args, 'colour_gains', None)
    colour_gains = None
    if colour_gains_raw:
        try:
            parts = colour_gains_raw.split(',')
            colour_gains = (float(parts[0].strip()), float(parts[1].strip()))
        except Exception:
            print(f"   [Aviso] --colour-gains '{colour_gains_raw}' inválido. Formato esperado: 'r,b' ex: '1.6,1.5'. AWB automático será usado.")

    stream = CameraStream(
        width=width, height=height,
        shutter_us=shutter_us,
        lens_position=lens_position,
        sharpness=sharpness,
        contrast=contrast,
        saturation=saturation,
        noise_reduction=noise_reduction,
        colour_gains=colour_gains,
        analogue_gain=getattr(args, 'analogue_gain', 0.0),
    )
    stream.start()

    # --- Warm-up: descarta frames enquanto AF/AE/AWB convergem (evita gatilho
    # falso inicial e capturas durante a 'caça' de foco/exposição). ---
    warmup_ms = getattr(args, 'warmup_ms', 3000)
    if warmup_ms > 0:
        print(f"\n[Warm-up] A aquecer a câmara {warmup_ms/1000.0:.1f}s (AF/AE/AWB a convergir)...")
        t_warm = time.perf_counter()
        while (time.perf_counter() - t_warm) * 1000.0 < warmup_ms:
            stream.read()
            time.sleep(0.01)

    # --- Lock de exposição: depois de estabilizar, trava a exposição/ganho/AWB
    # a que o auto convergiu (só quando a exposição está em automático). ---
    if getattr(args, 'lock_exposure', True) and shutter_us == 0:
        stream.lock_auto_exposure()

    # Iniciar servidor de livestream MJPEG embutido
    livestream_bus = _LivestreamFrameBus()
    livestream_server = None
    if not getattr(args, 'no_livestream', False):
        livestream_port = getattr(args, 'livestream_port', 8000)
        try:
            livestream_server = LivestreamServer((LIVESTREAM_HOST, livestream_port), livestream_bus)
            threading.Thread(target=livestream_server.serve_forever, daemon=True, name='LivestreamHTTP').start()
            print(f"   [Livestream] Servidor MJPEG embutido ativo em http://{LIVESTREAM_HOST}:{livestream_port}/stream.mjpg")
        except OSError as e:
            print(f"   [Livestream] Falha ao abrir a porta {livestream_port} (já em uso?): {e}")

    _last_publish_ts = [0.0]

    def _read_and_publish():
        """Wrapper de stream.read() usado em TODOS os pontos de leitura do loop
        (incluindo os de drenagem/descarte) para que a livestream receba frames
        continuamente, sem depender de um único ponto de leitura 'canónico'."""
        img, gray = stream.read()
        if img is not None and livestream_bus.has_clients:
            now_m = time.monotonic()
            if now_m - _last_publish_ts[0] >= LIVESTREAM_MIN_PUBLISH_INTERVAL_S:
                _last_publish_ts[0] = now_m
                try:
                    livestream_bus.publish(_encode_livestream_frame(img))
                except Exception as e:
                    print(f"   [Livestream] Erro ao publicar frame: {e}")
        return img, gray

    # Iniciar HeartbeatSender se ligação WebSocket configurada
    heartbeat = None
    if args.ws_server:
        heartbeat = HeartbeatSender(args.ws_server)
        # Reportar a config efetiva no heartbeat para o dashboard fazer seed dos sliders
        heartbeat.update(config={
            'lens_position': args.lens_position,
            'shutter_us': args.shutter_us,
            'burst': args.burst,
            'burst_interval': args.burst_interval,
            'motion_threshold': args.motion_threshold,
            'trigger_delay': args.trigger_delay,
            'sharpness': args.sharpness,
            'contrast': args.contrast,
            'saturation': args.saturation,
            'noise_reduction': args.noise_reduction,  # string: off|fast|highquality
        })
        heartbeat.start()

    gray_prev = None
    cooldown_until = 0.0

    # Variáveis de estado para ROI bloqueado, Modo de Repouso e timeouts
    lock_state = 'neutral'  # 'neutral', 'locked_left', 'locked_right'
    in_repouso = False
    last_trigger_time = time.time()
    _total_inferences = 0

    # Limpar ficheiros de captura anteriores
    for f in tmp_base.glob('stream_*'):
        try:
            f.unlink()
        except:
            pass

    print("\nModo Vigilância Ativo. A monitorizar movimento nas laterais (cantos esquerdo/direito)...")
    
    t_last_telemetry = time.time()
    t_last_none_warning = 0.0
    frame_count = 0
    t_read_sum = 0.0

    try:
        while True:
            t0_read = time.perf_counter()
            img_rgb, gray_lores = _read_and_publish()
            t_read_sum += (time.perf_counter() - t0_read) * 1000
            frame_count += 1

            if img_rgb is None or gray_lores is None:
                now = time.time()
                if now - t_last_none_warning > 5.0:
                    print("   [AVISO] A câmara não está a produzir frames! "
                          "Se estiver no Raspberry Pi 5 com a Camera Module 3, o OpenCV backend NÃO funciona. "
                          "Tem de utilizar o Picamera2. Certifique-se de que recriou o seu venv com "
                          "'--system-site-packages' para expor o Picamera2 do sistema.")
                    t_last_none_warning = now
                time.sleep(0.010)
                continue

            now = time.time()
            
            # --- Modo de Repouso (Timeout de 1 minuto sem gatilhos), suspenso
            #     enquanto há espectadores ativos da livestream ---
            if not in_repouso and (now - last_trigger_time) > 60.0 and not livestream_bus.has_clients:
                in_repouso = True
                if heartbeat:
                    heartbeat.update(mode='sleep')
                print("\n[Vigilância] Inatividade detetada por 1 minuto. A entrar em modo de repouso (Qualidade: 640x360)...")
                stream.set_repouso(True)
                gray_prev = None  # Resetar referências de diferença de frames
            elif in_repouso and livestream_bus.has_clients:
                print("\n[Livestream] Espectador ligado durante o repouso. A acordar a câmara...")
                in_repouso = False
                if heartbeat:
                    heartbeat.update(mode='idle')
                stream.set_repouso(False)
                time.sleep(0.2)
                gray_prev = None
                continue

            # --- Limpeza de Fila de Buffers durante Cooldown ---
            if now < cooldown_until:
                # Continuamos a ler e descartar frames da câmara para manter os buffers atualizados (sem lag)
                _read_and_publish()
                gray_prev = None  # Forçar re-inicialização do frame de referência após cooldown
                continue

            # --- Timeout do Bloqueio de ROI de Entrada (30 segundos sem ativação) ---
            if lock_state != 'neutral' and (now - last_trigger_time) > 30.0:
                print(f"\n[Vigilância] Inatividade do ROI de entrada superou 30s. Bloqueio '{lock_state}' reposto para neutro.")
                lock_state = 'neutral'

            # Aplicar filtro GaussianBlur nos frames de análise para remover grão digital e ruído
            gray_lores_blurred = cv2.GaussianBlur(gray_lores, (9, 9), 0)

            if gray_prev is None:
                gray_prev = gray_lores_blurred
                continue

            # --- Compensação Global de Brilho (Cancela flutuações de Auto-Exposição/Ganho) ---
            mean_prev = np.mean(gray_prev)
            mean_curr = np.mean(gray_lores_blurred)
            diff_mean = mean_curr - mean_prev
            
            # Ajustar pixels do frame de referência adicionando a variação média de brilho
            gray_prev_compensated = np.clip(gray_prev.astype(np.float32) + diff_mean, 0, 255).astype(np.uint8)

            # Definir ROIs laterais (15% cada lado)
            h_lr, w_lr = gray_lores_blurred.shape
            w_roi = int(w_lr * 0.15)

            roi_left = gray_lores_blurred[:, :w_roi]
            roi_right = gray_lores_blurred[:, w_lr - w_roi:]

            roi_left_prev = gray_prev_compensated[:, :w_roi]
            roi_right_prev = gray_prev_compensated[:, w_lr - w_roi:]

            # Calcular diferença absoluta após compensação de luz
            diff_left = cv2.absdiff(roi_left, roi_left_prev)
            diff_right = cv2.absdiff(roi_right, roi_right_prev)

            # Contar pixéis em movimento
            motion_left = np.sum(diff_left > 25)
            motion_right = np.sum(diff_right > 25)

            # Telemetria do centro (opcional)
            roi_center = gray_lores_blurred[:, w_roi : w_lr - w_roi]
            roi_center_prev = gray_prev_compensated[:, w_roi : w_lr - w_roi]
            diff_center = cv2.absdiff(roi_center, roi_center_prev)
            motion_center = np.sum(diff_center > 25)

            sensitivity = args.motion_threshold if hasattr(args, 'motion_threshold') else 500

            # Imprimir telemetria de 1 em 1 segundo (não exibe no modo repouso para economizar consola)
            if not in_repouso and (now - t_last_telemetry >= 1.0):
                avg_read_ms = t_read_sum / frame_count if frame_count > 0 else 0.0
                fps = frame_count / (now - t_last_telemetry)
                print(f"[Vigilância] FPS: {fps:.1f} | Latência de Captura: {avg_read_ms:.1f}ms | "
                      f"Movimento -> L: {motion_left}, Centro: {motion_center}, R: {motion_right} | Limiar: {sensitivity} | Estado: {lock_state}")
                if heartbeat:
                    heartbeat.update(
                        mode='active' if triggered else 'idle',
                        camera_fps=round(fps, 1),
                        inference_count=_total_inferences,
                    )
                t_last_telemetry = now
                frame_count = 0
                t_read_sum = 0.0

            # --- Lógica de Gatilho Filtrada pelo Estado do ROI ---
            triggered = False
            trigger_side = None

            if lock_state == 'neutral':
                if motion_left > sensitivity:
                    triggered = True
                    trigger_side = "ESQUERDO"
                    lock_state = 'locked_left'
                elif motion_right > sensitivity:
                    triggered = True
                    trigger_side = "DIREITO"
                    lock_state = 'locked_right'
            elif lock_state == 'locked_left':
                if motion_left > sensitivity:
                    triggered = True
                    trigger_side = "ESQUERDO"
            elif lock_state == 'locked_right':
                if motion_right > sensitivity:
                    triggered = True
                    trigger_side = "DIREITO"

            if triggered:
                # Se estiver em repouso, acorda a câmara e re-analisa na alta resolução
                if in_repouso:
                    print(f"\n[Gatilho Repouso] Movimento detetado no ROI {trigger_side}! A acordar a câmara...")
                    in_repouso = False
                    stream.set_repouso(False)
                    time.sleep(0.2)  # Dar tempo para a câmara re-estabelecer o modo alta resolução e exposição
                    gray_prev = None
                    last_trigger_time = time.time()
                    continue

                print(f"\n[Gatilho] Movimento detetado no ROI {trigger_side}! (L: {motion_left} px, R: {motion_right} px) - Estado: {lock_state}")
                
                # --- Capturar rajada (burst) de frames diretamente da stream ---
                t_burst_start = time.perf_counter()
                burst_frames = []
                num_shots = args.burst
                interval_s = args.burst_interval / 1000.0

                # 1. Atraso inicial para permitir que a maçã entre no enquadramento (limpando o buffer da câmara)
                trigger_delay_ms = args.trigger_delay if hasattr(args, 'trigger_delay') else 50
                if trigger_delay_ms > 0:
                    t_delay_start = time.perf_counter()
                    while (time.perf_counter() - t_delay_start) * 1000.0 < trigger_delay_ms:
                        _read_and_publish()  # descarta frame de buffer para evitar lag (mas ainda alimenta a livestream)

                # 1b. Corrida de foco: em vez de capturar às cegas, lê frames
                # durante uma janela curta e guarda o MAIS NÍTIDO (sai cedo ao
                # atingir o limiar). Apanha a maçã já em foco, não no instante
                # em que se mexeu. O melhor frame torna-se o frame 1 do burst.
                focus_timeout_ms = getattr(args, 'focus_timeout_ms', 500)
                focus_min_blur = getattr(args, 'focus_min_blur', 150.0)
                best_img, best_blur = None, -1.0
                if focus_timeout_ms > 0:
                    t_focus = time.perf_counter()
                    while (time.perf_counter() - t_focus) * 1000.0 < focus_timeout_ms:
                        cand, _ = _read_and_publish()
                        if cand is None:
                            continue
                        b = blur_score_image(cand)
                        if b > best_blur:
                            best_img, best_blur = cand, b
                        if b >= focus_min_blur:
                            break
                    if best_img is not None:
                        print(f"   [Foco] Melhor frame do scan: blur={best_blur:.0f} "
                              f"({(time.perf_counter()-t_focus)*1000.0:.0f}ms de espera)")

                # 2. Captura da rajada. O frame nítido do scan é o frame 1; os
                # restantes capturam-se com o intervalo normal entre si.
                burst_frames = [best_img] if best_img is not None else []
                shots_needed = num_shots - len(burst_frames)
                for _shot_idx in range(shots_needed):
                    if burst_frames:  # espera o intervalo antes de cada shot extra
                        t_int_start = time.perf_counter()
                        while (time.perf_counter() - t_int_start) < interval_s:
                            _read_and_publish()
                    img_shot, _ = _read_and_publish()
                    if img_shot is not None:
                        burst_frames.append(img_shot)

                t_capture = (time.perf_counter() - t_burst_start) * 1000
                print(f"   Rajada capturada: {len(burst_frames)} frames obtidos em {t_capture:.0f}ms")

                # --- MULTI-MAÇÃ (beta, --multi-apple): deteta várias maçãs e
                #     envia cada uma como o seu próprio apple_id. OFF (default)
                #     salta este ramo e o caminho single-maçã fica intacto. ---
                if getattr(args, 'multi_apple', False):
                    _total_inferences += process_burst_multi(
                        burst_frames, args, sess, input_name, tmp_base, input_size, labels)
                    last_trigger_time = time.time()
                    if heartbeat:
                        heartbeat.update(mode='active', inference_count=_total_inferences)
                    cooldown_until = time.time() + 1.0
                    print("[Vigilância] Rajada (multi-maçã) processada. Cooldown 1.0s...")
                    gray_prev = gray_lores_blurred
                    time.sleep(0.033)
                    continue

                # --- Processar frames concorrentemente ---
                results = [None] * len(burst_frames)
                futures = {}

                def process_single_frame(idx, PIL_img):
                    t0 = time.perf_counter()
                    raw_path = tmp_base / f'stream_frame_{idx}.jpg'
                    png_path = tmp_base / f'stream_frame_{idx}.png'
                    # Rejeita frames sem maçã (falso gatilho / fundo vazio): não
                    # gasta inferência nem os envia para a BD/PC.
                    if getattr(args, 'require_apple', True) and not frame_has_apple(
                            PIL_img, getattr(args, 'min_apple_area', 0.0)):
                        return idx, {
                            'label': 'NoApple', 'index': -1, 'confidence': 0.0,
                            'blur_score': 0.0, 'png_path': None,
                            'processing_ms': (time.perf_counter() - t0) * 1000,
                            'no_apple': True,
                        }
                    try:
                        PIL_img.save(raw_path, "JPEG", quality=95)
                        blur_score = compute_blur_score(raw_path)
                        inp = process_and_crop_transparent(raw_path, png_path, input_size)
                        out = sess.run(None, {input_name: inp})[0]
                        pred, conf = postprocess_output(out)
                        label = labels[pred] if pred < len(labels) else str(pred)
                        elapsed_ms = (time.perf_counter() - t0) * 1000
                        return idx, {
                            'label': label, 'index': int(pred),
                            'confidence': float(conf), 'blur_score': float(blur_score),
                            'png_path': png_path, 'processing_ms': elapsed_ms
                        }
                    except Exception as e:
                        print(f"   [Frame {idx+1}] ERRO: {e}")
                        return idx, {
                            'label': 'Error', 'index': -1,
                            'confidence': 0.0, 'blur_score': 0.0,
                            'png_path': png_path, 'processing_ms': 0
                        }

                with ThreadPoolExecutor(max_workers=len(burst_frames)) as pool:
                    for idx, PIL_img in enumerate(burst_frames):
                        futures[pool.submit(process_single_frame, idx, PIL_img)] = idx

                    for fut in as_completed(futures):
                        idx, result = fut.result()
                        results[idx] = result

                # Imprimir logs sequenciais
                for idx_res, res in enumerate(results):
                    if res is not None and res['index'] >= 0:
                        b_score = res['blur_score']
                        sharpness = "nítido" if b_score > 200 else ("ok" if b_score > 50 else "desfocado!")
                        print(f"   [Frame {idx_res+1}] {res['label']} ({res['confidence']*100:.1f}%) | blur={b_score:.0f} ({sharpness}) | {res['processing_ms']:.0f}ms")

                # Contabilizar inferências e monitorizar blur para o heartbeat.
                # Frames sem maçã (no_apple) são excluídos: não contam nem são enviados.
                valid_results = [r for r in results if r is not None and not r.get('no_apple')]
                _total_inferences += len([r for r in valid_results if r.get('index', -1) >= 0])

                valid_blur = [r['blur_score'] for r in valid_results if r.get('blur_score', 0) > 0]
                avg_blur = sum(valid_blur) / len(valid_blur) if valid_blur else None

                # Enviar via WebSocket (ou SCP) — exige um mínimo de frames com
                # maçã. A CNN5 precisa de pelo menos --min-frames (default 2) para
                # as patologias; o mínimo nunca excede os frames capturados (ex.
                # --burst 1 aceita 1). Menos que isso: descarta a maçã inteira.
                required = min(getattr(args, 'min_frames', 2), len(burst_frames))
                if len(valid_results) >= required:
                    if args.ws_server:
                        send_burst_results_ws(valid_results, args)
                    else:
                        for i, result in enumerate(valid_results):
                            send_result(result, args, tmp_base / f'stream_result_{i}.json')
                else:
                    print(f"   [Vigilância] Descartado: {len(valid_results)} frame(s) com maçã "
                          f"(< {required} exigidos para a CNN5). Nada enviado.")

                # Reiniciar timer de inatividade
                last_trigger_time = time.time()
                if heartbeat:
                    heartbeat.update(
                        mode='active',
                        inference_count=_total_inferences,
                        last_blur=round(avg_blur, 1) if avg_blur is not None else None,
                        # Limiar 80: abaixo disto a lente pode estar suja ou mal calibrada
                        blur_warning=avg_blur is not None and avg_blur < 80,
                    )

                # Entrar em cooldown para evitar re-gatilho contínuo da mesma maçã
                cooldown_until = time.time() + 1.0
                print(f"[Vigilância] Rajada enviada. A entrar em cooldown por 1.0s...")

            gray_prev = gray_lores_blurred
            time.sleep(0.033)  # Limitar loop de vigilância a ~30 FPS

    except KeyboardInterrupt:
        print("\nStream contínuo interrompido pelo utilizador.")
    finally:
        if heartbeat:
            heartbeat.stop()
        if livestream_server:
            livestream_server.shutdown()
            livestream_server.server_close()
        stream.stop()
        print("Câmara desligada com sucesso.")



def ensure_remote_dir(userhost: str, remote_dir: str):
    # try to create remote dir (works if SSH server on PC)
    cmd = ['ssh', userhost, f"mkdir -p '{remote_dir}'"]
    cp = run_cmd(cmd)
    if cp.returncode != 0:
         raise RuntimeError(f"Failed to ensure remote dir {remote_dir} on {userhost}\nSTDOUT:\n{cp.stdout}\nSTDERR:\n{cp.stderr}")


def scp_send(local: Path, userhost: str, remote_dir: str):
    dest = f"{userhost}:{remote_dir.rstrip('/') + '/'}"
    cp = run_cmd(['scp', str(local), dest])
    if cp.returncode != 0:
        raise RuntimeError(f"SCP failed sending {local} to {dest}\nSTDOUT:\n{cp.stdout}\nSTDERR:\n{cp.stderr}")


async def ws_send(uri: str, payload: dict) -> bool:
    import websockets

    try:
        ws = await websockets.connect(uri)
    except Exception as e:
        print(f"Failed to connect to WebSocket server at {uri}: {e}")
        return False

    try:
        await ws.send(json.dumps(payload))
        # wait for ack
        try:
            resp = await ws.recv()
            print('WS response:', resp)
        except Exception:
            pass
        return True
    except Exception as e:
        print(f"Failed to send payload: {e}")
        return False
    finally:
        try:
            await ws.close()
        except Exception:
            pass


def get_resized_png_bytes(png_path: Path, size=224) -> bytes:
    import io
    img = Image.open(png_path).convert('RGBA')
    # Já está cortado e transparente, só precisamos de redimensionar se necessário
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    out_buf = io.BytesIO()
    img.save(out_buf, format='PNG')
    return out_buf.getvalue()


def send_result(result, args, json_path) -> bool:
    """Envia uma imagem PNG transparente e o JSON de resultado para o PC."""
    png_path = result['png_path']
    json_path.write_text(json.dumps({
        'label': result['label'],
        'index': result['index'],
        'confidence': result['confidence']
    }))

    if args.ws_server:
        import base64
        import asyncio
        img_b64 = base64.b64encode(png_path.read_bytes()).decode()

        crop_path = png_path.with_name(png_path.stem + "_crop.jpg")
        crop_b64 = None
        if crop_path.exists():
            crop_b64 = base64.b64encode(crop_path.read_bytes()).decode()

        # Encontrar a imagem original de alta resolução correspondente (.jpg)
        raw_path = png_path.with_suffix('.jpg')
        raw_b64 = None
        if raw_path.exists():
            raw_b64 = base64.b64encode(raw_path.read_bytes()).decode()

        payload = {
            'image_b64': raw_b64 if raw_b64 else img_b64,  # Alta resolução
            'crop_image_b64': crop_b64,                    # Crop RANSAC/Blob
            'image_resized_b64': img_b64,                  # Miniatura 224x224
            'label': result['label'],
            'confidence': result['confidence'],
            'filename': png_path.name
        }
        return asyncio.run(ws_send(args.ws_server, payload))
    else:
        scp_send(png_path, args.pc, args.remote_image_dir)
        crop_path = png_path.with_name(png_path.stem + "_crop.jpg")
        if crop_path.exists():
            scp_send(crop_path, args.pc, args.remote_image_dir)
        # Se existir imagem original de alta resolução, enviar também no modo SCP
        raw_path = png_path.with_suffix('.jpg')
        if raw_path.exists():
            scp_send(raw_path, args.pc, args.remote_image_dir)
        scp_send(json_path, args.pc, args.remote_json_dir)
        return True


def _frame_images_b64(png_path: Path) -> tuple[str, str | None, str | None]:
    """Devolve (image_resized_b64, crop_b64, raw_b64) para um frame."""
    import base64

    img_b64 = base64.b64encode(png_path.read_bytes()).decode()

    crop_path = png_path.with_name(png_path.stem + "_crop.jpg")
    crop_b64 = base64.b64encode(crop_path.read_bytes()).decode() if crop_path.exists() else None

    raw_path = png_path.with_suffix('.jpg')
    raw_b64 = base64.b64encode(raw_path.read_bytes()).decode() if raw_path.exists() else None

    return img_b64, crop_b64, raw_b64


def send_burst_results_ws(results, args, apple_id=None):
    """Usa a CNN2 como filtro de confiança, não como autoridade de diagnóstico:

    - Se TODOS os N frames forem 'Healthy' com confiança > 80%, a classificação
      final já é da CNN2: a maçã vai direto para o Supabase (apples/frames/
      cnn_predictions/producao_atual), só a imagem do frame mais fraco viaja
      (upload), sem tocar no ws_server/PC.
    - Caso contrário, a CNN2 não escreve nada na BD — envia as N imagens
      (crop + 224x224, não a rajada em alta resolução) por WebSocket; a CNN5
      no PC (GPU) classifica todas e decide sozinha qual é o worst_case.

    apple_id: se dado, usa-o (modo --multi-apple, um id por maçã); senão gera um.
    """
    import asyncio

    apple_id = apple_id or generate_apple_id()

    valid = [r for r in results if r.get('index', -1) >= 0]

    # Melhor frame = maior blur_score (mais nítido). Frames com blur < 50% do
    # melhor são excluídos da escolha do worst-case/thumbnail — um frame muito
    # desfocado não é fiável nem como classificação nem como imagem a mostrar.
    best_blur = max((r.get('blur_score', 0.0) for r in results), default=0.0)
    best_idx = max(range(len(results)), key=lambda i: results[i].get('blur_score', 0.0)) if results else -1
    if results and best_blur < 100:
        print(f"   [FOCO] AVISO: rajada inteira desfocada (melhor blur={best_blur:.0f} < 100) — "
              f"verificar --lens-position e iluminação.")
    sharp = [r for r in valid if r.get('blur_score', 0.0) >= 0.5 * best_blur]
    candidates = sharp if sharp else valid

    if not candidates:
        worst = None
    else:
        unhealthy = [r for r in candidates if r['label'] != 'Healthy']
        worst = min(unhealthy, key=lambda r: r['confidence']) if unhealthy else \
            min(candidates, key=lambda r: r['confidence'])

    frames_meta = [
        {
            'frame': i + 1,
            'label': r['label'],
            'confidence': r['confidence'],
            'blur_score': round(r.get('blur_score', 0.0), 1),
            'is_worst_case': worst is not None and r is worst,
            'is_best': i == best_idx,
        }
        for i, r in enumerate(results)
    ]

    is_confident_healthy = worst is not None and worst['label'] == 'Healthy' and worst['confidence'] > 0.80

    if is_confident_healthy and getattr(args, 'enable_supabase', False):
        try:
            _send_confident_healthy_to_supabase(apple_id, worst, frames_meta, args)
            print(f"[CONFIANTE] Maçã {apple_id}: 'Healthy' em todos os {len(results)} frames "
                  f"(pior frame {worst['confidence']:.2%}) — enviada direto ao Supabase.")
            return True
        except Exception as e:
            print(f"[CONFIANTE] Falha a enviar direto ao Supabase ({e}); a usar caminho normal (WebSocket).")
            # cai para o caminho normal abaixo

    # --- Caminho incerto: a CNN2 não decide nada, só entrega material à CNN5 ---
    frames_payload = []
    for i, r in enumerate(results):
        img_resized_b64, crop_b64, _ = _frame_images_b64(r['png_path'])
        frames_payload.append({
            'frame': i + 1,
            'crop_image_b64': crop_b64,
            'image_resized_b64': img_resized_b64,
            # Veredito da CNN2 por frame: a CNN5 continua a decidir sozinha, mas
            # isto fica registado na BD (cnn_predictions) para comparar CNN2 vs CNN5.
            'label': r['label'],
            'confidence': r['confidence'],
        })

    payload = {
        'is_burst': True,
        'apple_id': apple_id,
        'location': get_active_location(getattr(args, 'location', None)),
        'label': 'unknown',
        'confidence': 0.0,
        'frames': frames_payload,
    }

    print(f"Maçã {apple_id}: incerta — a enviar {len(results)} frames "
          f"(crop+224) para a CNN5 via WebSocket...")
    return asyncio.run(ws_send(args.ws_server, payload))


def _send_confident_healthy_to_supabase(apple_id: str, worst: dict, frames_meta: list, args) -> None:
    """Escreve as 4 tabelas no Supabase quando a CNN2 já é a classificação final.

    Convenções alinhadas com o resto do projeto (ver ingest_raspberry_data.py):
    model_name/final_source = 'CNN2', caminho de Storage
    '{STORAGE_FOLDER}/{label}_{apple_id}_frame{idx}.jpg' (o nome começa pela
    classe final, aqui sempre 'Healthy'), e cnn_predictions.frame_id a apontar
    para o id devolvido pelo INSERT em frames (é FK, não aceita null).
    """
    import datetime

    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    location = get_active_location(getattr(args, 'location', None))

    crop_path = worst['png_path'].with_name(worst['png_path'].stem + "_crop.jpg")
    if crop_path.exists():
        image_to_upload, content_type, ext = crop_path, 'image/jpeg', 'jpg'
    else:
        image_to_upload, content_type, ext = worst['png_path'], 'image/png', 'png'

    worst_frame_idx = next(fm['frame'] for fm in frames_meta if fm['is_worst_case'])
    # Nome começa pela classe final (aqui 'Healthy'): Healthy_{apple_id}_frame{idx}.
    safe_label = ''.join(ch if ch.isalnum() else '_' for ch in str(worst['label'])) or 'unknown'
    storage_path = f"{STORAGE_FOLDER}/{safe_label}_{apple_id}_frame{worst_frame_idx}.{ext}"
    thumbnail_url = supabase_upload_image(image_to_upload, storage_path, content_type)

    supabase_insert('apples', [{
        'apple_id': apple_id, 'timestamp': timestamp, 'location': location,
    }])

    frame_rows = [{
        'apple_id': apple_id,
        'frame_idx': fm['frame'],
        'label': fm['label'],
        'confidence': fm['confidence'],
        'is_worst_case': fm['is_worst_case'],
        'image_url': thumbnail_url if fm['is_worst_case'] else None,
    } for fm in frames_meta]
    inserted_frames = supabase_insert_returning('frames', frame_rows)

    # CNN2 confiante-Healthy: a CNN2 é a decisão final e está confiante em TODOS
    # os frames, por isso grava os metadados de todos (uma linha CNN2 por frame,
    # sempre 'Healthy'). Só a imagem do pior frame é que sobe ao Storage.
    prediction_rows = [{
        'apple_id': apple_id,
        'frame_id': row['id'],
        'model_name': 'CNN2',
        'label': row['label'],
        'confidence': row['confidence'],
        'timestamp': timestamp,
    } for row in inserted_frames]
    supabase_insert('cnn_predictions', prediction_rows)

    supabase_insert('producao_atual', [{
        'apple_id': apple_id,
        'final_class': 'Healthy',
        'final_confidence': worst['confidence'],
        'frame_thumbnail': thumbnail_url,
        'timestamp': timestamp,
        'location': location,
        'final_source': 'CNN2',
    }])


def resolve_latest_model(models_dir: Path) -> Path:
    """Escolhe o .onnx mais recente (mtime) em models_dir — usado quando
    --model não é dado, para o Pi apanhar automaticamente no arranque o
    último modelo publicado pela dashboard (POST /models/publish)."""
    if not models_dir.exists():
        raise FileNotFoundError(
            f'--models-dir {models_dir} não existe. Publica um modelo pela dashboard '
            'primeiro, ou passa --model explicitamente.'
        )

    candidates = sorted(models_dir.glob('*.onnx'), key=lambda p: p.stat().st_mtime, reverse=True)
    if not candidates:
        raise FileNotFoundError(
            f'Nenhum .onnx encontrado em {models_dir}. Publica um modelo pela dashboard '
            'primeiro, ou passa --model explicitamente.'
        )

    chosen = candidates[0]
    import datetime
    mtime = datetime.datetime.fromtimestamp(chosen.stat().st_mtime).strftime('%Y-%m-%d %H:%M:%S')
    print(f'[Modelo] --model não foi dado — a usar o mais recente em {models_dir}: '
          f'{chosen.name} (publicado em {mtime})')
    return chosen


def main():
    p = argparse.ArgumentParser(
        description='Captura, remove fundo e classifica maçãs com ONNX no Raspberry Pi.'
    )
    p.add_argument('--model', required=False, default=None,
                   help='Path to ONNX model on Pi. Se omitido, escolhe o .onnx mais '
                        'recente em --models-dir (permite publicar um modelo novo pela '
                        'dashboard e o Pi apanhá-lo automaticamente no próximo arranque).')
    p.add_argument('--models-dir', default='/home/minipc/models',
                   help='Pasta onde procurar o .onnx mais recente quando --model não é dado '
                        '(default /home/minipc/models — mesma pasta usada pelo endpoint '
                        '/models/publish da dashboard)')
    p.add_argument('--pc', required=False, help='remote user@HOST (PC running SSH)')
    p.add_argument('--remote-image-dir', required=False, help='Remote dir on PC for images')
    p.add_argument('--remote-json-dir', required=False, help='Remote dir on PC for json')
    p.add_argument('--labels', nargs='+', default=['Healthy', 'Unhealthy'])
    p.add_argument('--input_size', type=int, default=224)
    p.add_argument('--capture_time', type=int, default=10000,
                   help='Tempo de espera inicial em ms para autofocus (default 10000)')
    p.add_argument('--rpicam-cmd', default=None,
                   help='Comando de captura custom (apenas modo single)')
    p.add_argument('--ws-server', required=False,
                   help='WebSocket server URI, e.g. ws://PC_HOST:8765')
    p.add_argument('--enable-supabase', action='store_true',
                   help='Ativa o envio direto ao Supabase para maçãs classificadas como Healthy com alta confiança.')
    p.add_argument('--location', default=None,
                   help='Força a location/lote a usar, ignorando o lote ativo escolhido na dashboard '
                        '(por omissão consulta a tabela active_lote a cada 30s)')
    p.add_argument('--livestream-port', type=int, default=8000,
                   help='Porta HTTP do servidor MJPEG embutido /stream.mjpg em modo --stream '
                        '(default 8000)')
    p.add_argument('--no-livestream', action='store_true',
                   help='Desativa o servidor de livestream MJPEG embutido (debug/perf)')
    # --- Argumentos de Modo Burst ---
    p.add_argument('--burst', type=int, default=1,
                   help='Número de fotos em rajada (default 1 = modo single)')
    p.add_argument('--burst-interval', type=int, default=150,
                   help='Intervalo entre fotos em modo burst, em ms (default 150)')
    p.add_argument('--shutter-us', type=int, default=0,
                   help='Velocidade do obturador em microssegundos (default 0 = exposição automática).'
                        ' Valores baixos congelam objectos em movimento. '
                        'Reduz a exposição: em ambientes escuros aumente o valor.')
    p.add_argument('--stream', action='store_true',
                   help='Ativa o modo stream contínuo de vigilância com deteção de movimento em ROI')
    p.add_argument('--motion-threshold', type=int, default=500,
                   help='Número de píxeis em movimento necessários para ativar gatilho no ROI (default 500)')
    p.add_argument('--trigger-delay', type=int, default=100,
                   help='Atraso em ms antes de iniciar a captura do burst após o gatilho, '
                        'permitindo que a maçã entre no enquadramento (default 100)')
    p.add_argument('--width', type=int, default=2304,
                   help='Largura da imagem de captura em alta resolução (default 2304)')
    p.add_argument('--height', type=int, default=1296,
                   help='Altura da imagem de captura em alta resolução (default 1296)')
    p.add_argument('--lens-position', type=float, default=0.0,
                   help='Posição da lente para foco manual em dioptrias (ex: 2.5 para 40cm). 0.0 = autofocus.')
    p.add_argument('--sharpness', type=float, default=1.5,
                   help='Nitidez da imagem (default 1.5, default nativo é 1.0)')
    p.add_argument('--contrast', type=float, default=1.2,
                   help='Contraste da imagem (default 1.2, default nativo é 1.0)')
    p.add_argument('--saturation', type=float, default=1.2,
                   help='Saturação da imagem (default 1.2, default nativo é 1.0)')
    p.add_argument('--noise-reduction', choices=['off', 'fast', 'highquality'], default='fast',
                   help='Modo de redução de ruído por hardware (default fast, evita ghosting)')
    p.add_argument('--colour-gains', type=str, default=None,
                   help='Fixar balanço de brancos em formato "r,b" (ex: "1.6,1.5"). '
                        'Desativa o AWB automático — evita tons de cor a "ondular" entre frames '
                        'sob luz artificial (flicker). Calibrar com folha A4 branca. '
                        'None = AWB automático (default).')
    p.add_argument('--analogue-gain', type=float, default=0.0,
                   help='Fixa o ganho analógico (ISO). 0.0 = automático (default); '
                        '1.0 = ISO base (menos ruído, exige boa luz).')
    # --- Melhorias de qualidade de imagem (modo --stream) ---
    p.add_argument('--warmup-ms', type=int, default=3000,
                   help='Tempo (ms) a descartar frames no arranque do --stream para AF/AE/AWB '
                        'convergirem antes de vigiar (default 3000; 0 desativa).')
    p.add_argument('--lock-exposure', action=argparse.BooleanOptionalAction, default=True,
                   help='Após o warm-up, trava a exposição/ganho/AWB a que o auto convergiu '
                        '(exposição estável). Só se aplica com --shutter-us 0. Default ON.')
    p.add_argument('--focus-timeout-ms', type=int, default=500,
                   help='Janela (ms) após o gatilho a ler frames à procura do mais nítido antes '
                        'do burst (default 500; sai cedo ao atingir --focus-min-blur; 0 desativa).')
    p.add_argument('--focus-min-blur', type=float, default=150.0,
                   help='Blur score (Laplaciano) a partir do qual a corrida de foco para cedo '
                        '(default 150; escala: >200 nítido, 50-200 ligeiro, <50 muito desfocado).')
    p.add_argument('--require-apple', action=argparse.BooleanOptionalAction, default=True,
                   help='Não envia frames sem maçã detetada (falso gatilho / fundo vazio). Default ON.')
    p.add_argument('--min-apple-area', type=float, default=0.0,
                   help='Fração mínima do frame que a maçã tem de ocupar para o frame ser aceite '
                        '(0.0 = só exige deteção; ex. 0.01 rejeita blobs minúsculos de fundo).')
    p.add_argument('--min-frames', type=int, default=2,
                   help='Mínimo de frames com maçã para uma maçã ser enviada (a CNN5 precisa de '
                        '>=2 para patologias). Nunca exige mais do que os frames capturados '
                        '(ex. --burst 1 aceita 1). Default 2.')
    p.add_argument('--calibrate-focus', action='store_true',
                   help='Modo de calibração: maçã PARADA no ponto de passagem, imprime a '
                        'LensPosition mediana para usar em --lens-position. Não captura nada.')
    # --- Multi-maçã (BETA) ---
    p.add_argument('--multi-apple', action='store_true',
                   help='[BETA] Deteta VÁRIAS maçãs por frame e envia cada uma como imagem/apple_id '
                        'separado. OFF (default) = comportamento single-maçã atual, sem alterações.')
    p.add_argument('--max-apples', type=int, default=4,
                   help='Número máximo de maçãs a processar por frame com --multi-apple (default 4).')
    args = p.parse_args()

    # Modo de calibração de foco: corre e sai (não precisa de modelo nem rede).
    if args.calibrate_focus:
        calibrate_focus(args)
        return

    if args.model:
        model = Path(args.model)
        if not model.exists():
            raise FileNotFoundError(model)
    else:
        model = resolve_latest_model(Path(args.models_dir))

    # prepare remote dirs for SCP mode
    if not args.ws_server:
        if not args.pc or not args.remote_image_dir or not args.remote_json_dir:
            raise SystemExit(
                'When not using --ws-server, you must provide '
                '--pc, --remote-image-dir and --remote-json-dir'
            )
        ensure_remote_dir(args.pc, args.remote_image_dir)
        ensure_remote_dir(args.pc, args.remote_json_dir)

    tmp_base = Path('/tmp/onnx_capture')
    tmp_base.mkdir(parents=True, exist_ok=True)
    json_path = tmp_base / 'result.json'

    # ======================================================================
    # MODO STREAM (se --stream ativo)
    # ======================================================================
    if args.stream:
        stream_vigilance_and_classify(
            model_path=model,
            input_size=args.input_size,
            labels=args.labels,
            args=args
        )
        return

    # ======================================================================
    # MODO BURST (--burst N, com N > 1)
    # ======================================================================
    if args.burst > 1:
        results = burst_capture_and_classify(
            model_path=model,
            tmp_base=tmp_base,
            input_size=args.input_size,
            labels=args.labels,
            capture_time=args.capture_time,
            num_shots=args.burst,
            interval_ms=args.burst_interval,
            shutter_us=args.shutter_us
        )

        if args.ws_server:
            # Envio consolidado via WebSocket
            success = send_burst_results_ws(results, args)
        else:
            # Enviar cada resultado individualmente via SCP para manter retrocompatibilidade
            success = True
            for i, result in enumerate(results):
                burst_json = tmp_base / f'result_{i}.json'
                if not send_result(result, args, burst_json):
                    success = False

        mode_str = 'WebSocket' if args.ws_server else 'SCP'
        if success:
            print(f'Enviados {len(results)} resultados via {mode_str}.')
        else:
            print(f'Falha ao enviar resultados via {mode_str}. Verifique a ligação.')
        return

    # ======================================================================
    # MODO SINGLE (padrão, --burst 1)
    # ======================================================================
    img_path = tmp_base / 'capture.jpg'
    png_path = tmp_base / 'capture.png'

    if args.rpicam_cmd:
        cmd = shlex.split(args.rpicam_cmd)
    else:
        cmd = [
            'rpicam-still', '-t', str(args.capture_time),
            '--width', '2304', '--height', '1296',
            '--autofocus-mode', 'continuous',
            '--autofocus-range', 'macro',
            '--exposure', 'sport',
            '-q', '95', '-n',
            '-o', '{output}'
        ]

    # Headless safety
    if '-n' not in cmd and '--nopreview' not in cmd:
        cmd.insert(1, '-n')

    print('Capture output path:', img_path)
    print('Capture command:', ' '.join(cmd))

    try:
        capture_image(img_path, cmd)
    except RuntimeError as e:
        print('Capture failed:', e)
        import os
        print('CWD:', os.getcwd())
        from glob import glob
        tmp_jpgs = glob('/tmp/*.jpg')
        if tmp_jpgs:
            jpgs = sorted(tmp_jpgs, key=lambda p: os.path.getmtime(p), reverse=True)
            print('Recent JPEGs in /tmp:')
            for p in jpgs[:10]:
                print(' ', p, os.path.getsize(p), 'bytes')
        else:
            print('No JPEGs found in /tmp')

        fallback = Path('/tmp/capture_debug.jpg')
        print('Attempting fallback capture to', fallback)
        cmd2 = [
            p.replace('{output}', str(fallback)) if '{output}' in p else p
            for p in cmd
        ]
        if not any('{output}' in p for p in cmd):
            cmd2 += ['-o', str(fallback)]
        try:
            cp = run_cmd(cmd2)
            if cp.returncode == 0 and fallback.exists():
                print('Fallback capture succeeded, moving to expected path')
                fallback.replace(img_path)
            else:
                print('Fallback capture did not produce file. stdout/stderr:\n',
                      cp.stdout, cp.stderr)
                raise
        except Exception:
            raise RuntimeError(
                'Capture failed and fallback did not produce an image; '
                'see earlier logs for rpicam output'
            )

    # Inferência single
    pred, conf = infer(model, img_path, png_path, args.input_size)
    label = args.labels[pred] if pred < len(args.labels) else str(pred)
    single_result = {
        'label': label, 'index': int(pred),
        'confidence': float(conf), 'png_path': png_path
    }
    success = send_result(single_result, args, json_path)

    mode_str = 'WebSocket' if args.ws_server else 'SCP'
    if success:
        print(f'Sent transparent PNG image and JSON via {mode_str}.')
    else:
        print(f'Failed to send transparent PNG image and JSON via {mode_str}. Verifique a ligação.')


if __name__ == '__main__':
    main()
