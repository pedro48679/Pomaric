#!/usr/bin/env python3
"""WebSocket server to receive image+json from Raspberry Pi and save to folders.
Usage:
  python ws_server.py --host 0.0.0.0 --port 8765 --image-dir "./TempRaspberry/Imagens" --json-dir "./TempRaspberry/Jsonn"

Requires: websockets, asyncio, base64, json
"""
import argparse
import asyncio
import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import websockets

# ---------------------------------------------------------------------------
# Heartbeat state — shared between asyncio handler and HTTP server thread
# ---------------------------------------------------------------------------
_latest_heartbeat: dict = {}
_heartbeat_lock = threading.Lock()

# Comando pendente para enviar ao Pi no próximo heartbeat
_pending_command: dict | None = None
_command_lock = threading.Lock()


class _HeartbeatHTTPHandler(BaseHTTPRequestHandler):
    """HTTP server que expõe o heartbeat (GET /heartbeat) e recebe comandos (POST /command)."""

    def do_GET(self):
        if self.path != '/heartbeat':
            self.send_response(404)
            self.end_headers()
            return
        with _heartbeat_lock:
            data = dict(_latest_heartbeat) if _latest_heartbeat else {'status': 'offline'}
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != '/command':
            self.send_response(404)
            self.end_headers()
            return
        global _pending_command
        try:
            length = int(self.headers.get('Content-Length', 0))
            body_raw = self.rfile.read(length)
            cmd = json.loads(body_raw)
            with _command_lock:
                _pending_command = cmd
            resp = json.dumps({'status': 'queued'}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(resp)))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(resp)
        except Exception as e:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'error', 'error': str(e)}).encode())

    def do_OPTIONS(self):
        """Preflight CORS para chamadas HTTP do Flutter."""
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def log_message(self, format, *args):
        pass  # silence HTTP access logs


def _start_heartbeat_http_server(port: int = 8766):
    server = HTTPServer(('0.0.0.0', port), _HeartbeatHTTPHandler)
    t = threading.Thread(target=server.serve_forever, daemon=True, name='HeartbeatHTTP')
    t.start()
    print(f'[Heartbeat] HTTP endpoint activo em: http://localhost:{port}/heartbeat')
    print(f'[Heartbeat] Comando endpoint:        http://localhost:{port}/command')


async def handler(websocket, image_dir: Path, json_dir: Path):
    async for message in websocket:
        try:
            data = json.loads(message)

            # ------------------------------------------------------------------
            # Heartbeat — lightweight telemetry from the Raspberry Pi
            # ------------------------------------------------------------------
            if data.get('type') == 'heartbeat':
                with _heartbeat_lock:
                    _latest_heartbeat.clear()
                    _latest_heartbeat.update(data)
                # Verifica se existe um comando pendente para enviar ao Pi
                with _command_lock:
                    global _pending_command
                    cmd = _pending_command
                    _pending_command = None
                response = cmd if cmd else {'status': 'heartbeat_ack'}
                await websocket.send(json.dumps(response))
                continue

            image_dir.mkdir(parents=True, exist_ok=True)
            json_dir.mkdir(parents=True, exist_ok=True)

            is_burst = data.get('is_burst', False)

            if is_burst:
                # --- MODO BURST (caminho incerto) ---
                # A CNN2 no Pi já decidiu que esta maçã não é confiante-Healthy
                # (senão nunca chegava aqui — vai direto ao Supabase). A CNN2
                # não é autoridade aqui: não gravamos nada no Supabase agora,
                # só guardamos as N imagens localmente para a CNN5 classificar
                # todas e decidir o 'worst_case' sozinha.
                frames = data.get('frames', [])
                if not frames:
                    print("Received empty burst payload.")
                    await websocket.send(json.dumps({'status': 'error', 'error': 'Empty burst frames'}))
                    continue

                overall_label = data.get('label') or 'unknown'
                overall_conf = data.get('confidence') or 0.0
                location = data.get('location') or 'Linha 1'

                # apple_id vem do Pi (gerado lá, consistente com o caminho direto-a-Supabase).
                # Fallback ao esquema antigo (contagem de ficheiros) só se não vier no payload.
                apple_id = data.get('apple_id')
                if apple_id:
                    file_id = apple_id
                else:
                    existing_ids = []
                    prefix = f"{overall_label}_"
                    for p in image_dir.glob(f"{prefix}*.jpg"):
                        if "_224" in p.stem:
                            continue
                        stem = p.stem
                        num_str = stem[len(prefix):]
                        if "_frame" in num_str:
                            num_str = num_str.split("_frame")[0]
                        if num_str.isdigit():
                            existing_ids.append(int(num_str))
                    file_id = max(existing_ids) + 1 if existing_ids else 1

                prefix = f"{overall_label}_"
                saved_files = []

                for f_data in frames:
                    frame_num = f_data.get('frame')
                    f_crop_b64 = f_data.get('crop_image_b64')
                    f_img_resized_b64 = f_data.get('image_resized_b64')

                    fname_crop = f"{prefix}{file_id}_frame{frame_num}_crop.jpg"
                    fname_resized = f"{prefix}{file_id}_frame{frame_num}_224.jpg"

                    crop_path = None
                    if f_crop_b64:
                        crop_path = image_dir / fname_crop
                        with open(crop_path, 'wb') as f:
                            f.write(base64.b64decode(f_crop_b64))

                    img_resized_path = None
                    if f_img_resized_b64:
                        img_resized_path = image_dir / fname_resized
                        with open(img_resized_path, 'wb') as f:
                            f.write(base64.b64decode(f_img_resized_b64))

                    saved_files.append({
                        'frame': frame_num,
                        'crop': str(crop_path) if crop_path else None,
                        'resized': str(img_resized_path) if img_resized_path else None,
                    })

                # Salvar um único arquivo JSON unificado
                json_filename = f"{prefix}{file_id}.json"
                json_path = json_dir / json_filename

                meta = {
                    'apple_id': apple_id or str(file_id),
                    'location': location,
                    'label': overall_label,
                    'confidence': overall_conf,
                    'id': file_id,
                    'saved_images': saved_files,
                    'cnn5_processed': False,
                }

                with open(json_path, 'w', encoding='utf-8') as f:
                    json.dump(meta, f, indent=4)

                print(f"Saved burst #{file_id} ({overall_label}): "
                      f"{len(saved_files)} frame images saved for CNN5.")
                await websocket.send(json.dumps({
                    'status': 'ok',
                    'id': file_id,
                    'saved_json': str(json_path)
                }))

            else:
                # --- MODO SINGLE (Legado/Compatibilidade) ---
                img_b64 = data.get('image_b64')
                crop_img_b64 = data.get('crop_image_b64')
                img_resized_b64 = data.get('image_resized_b64')
                label = data.get('label') or 'unknown'
                conf = data.get('confidence')

                existing_ids = []
                prefix = f"{label}_"
                for p in image_dir.glob(f"{prefix}*.jpg"):
                    if "_224" in p.stem or "_crop" in p.stem:
                        continue
                    stem = p.stem
                    num_str = stem[len(prefix):]
                    if "_frame" in num_str:
                        num_str = num_str.split("_frame")[0]
                    if num_str.isdigit():
                        existing_ids.append(int(num_str))
                next_id = max(existing_ids) + 1 if existing_ids else 1
                
                fname = f"{prefix}{next_id}.jpg"
                fname_crop = f"{prefix}{next_id}_crop.jpg"
                fname_resized = f"{prefix}{next_id}_224.jpg"

                img_bytes = base64.b64decode(img_b64)
                img_path = image_dir / fname
                with open(img_path, 'wb') as f:
                    f.write(img_bytes)

                crop_path = None
                if crop_img_b64:
                    crop_bytes = base64.b64decode(crop_img_b64)
                    crop_path = image_dir / fname_crop
                    with open(crop_path, 'wb') as f:
                        f.write(crop_bytes)

                img_resized_path = None
                if img_resized_b64:
                    img_resized_bytes = base64.b64decode(img_resized_b64)
                    img_resized_path = image_dir / fname_resized
                    with open(img_resized_path, 'wb') as f:
                        f.write(img_resized_bytes)

                json_path = json_dir / f"{prefix}{next_id}.json"
                meta = {
                    'label': label,
                    'confidence': conf,
                    'original_image': str(img_path),
                    'crop_image': str(crop_path) if crop_path else None,
                    'resized_image': str(img_resized_path) if img_resized_path else None
                }
                with open(json_path, 'w', encoding='utf-8') as f:
                    json.dump(meta, f)

                await websocket.send(json.dumps({
                    'status': 'ok',
                    'saved_image': str(img_path),
                    'saved_image_resized': str(img_resized_path) if img_resized_path else None,
                    'saved_json': str(json_path)
                }))
        except Exception as e:
            print('Error handling message:', e)
            await websocket.send(json.dumps({'status': 'error', 'error': str(e)}))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--host', default='0.0.0.0')
    p.add_argument('--port', type=int, default=8765)
    p.add_argument('--image-dir', required=True)
    p.add_argument('--json-dir', required=True)
    p.add_argument('--heartbeat-port', type=int, default=8766,
                   help='Porta HTTP para expor o último heartbeat do Raspberry (default 8766)')
    args = p.parse_args()

    image_dir = Path(args.image_dir)
    json_dir = Path(args.json_dir)

    _start_heartbeat_http_server(args.heartbeat_port)
    print(f'Starting WebSocket server on {args.host}:{args.port}')
    async def main_async():
        async with websockets.serve(
            lambda ws, *args: handler(ws, image_dir, json_dir),
            args.host,
            args.port,
            max_size=10 * 1024 * 1024
        ):
            # run forever
            await asyncio.Future()

    asyncio.run(main_async())


if __name__ == '__main__':
    main()
