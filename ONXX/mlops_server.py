#!/usr/bin/env python3
"""
MLOps HTTP server — gestão de treino CNN a partir do Supabase.

Uso:
  python mlops_server.py [--port 8767]

Endpoints:
  GET  /status         — estado do treino atual (polling a cada 2s)
  GET  /classes        — classes disponíveis no Supabase com contagens
  GET  /models         — modelos em script_apple/models/
  GET  /compare?a=X&b=Y — comparação de dois modelos (por metadados JSON)
  GET  /shadow/status  — estado do shadow runner
  POST /train          — iniciar treino (JSON body)
  POST /cancel         — cancelar treino
  POST /shadow/set     — definir modelo shadow {model: "nome.pth"}
  POST /shadow/start    — lança shadow_runner.py como subprocess {model, promote_after, interval}
  POST /shadow/stop     — termina o subprocess shadow
  POST /shadow/promote  — marca o shadow model como produção em models/production.json
"""

import json
import os
import subprocess
import sys
import threading
import time
import argparse
# ThreadingHTTPServer: o HTTPServer base serve 1 pedido de cada vez — um
# /classes lento (Supabase) bloqueava a fila inteira e o polling de 2s do
# dashboard acumulava timeouts (badge "online" a piscar durante demos).
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_ANON_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    sys.exit(
        "ERRO: define as variaveis de ambiente SUPABASE_URL e SUPABASE_ANON_KEY antes de "
        "correr este script (as mesmas usadas pela dashboard Flutter)."
    )

# Pasta central de modelos — mesma usada pelo train_cnn.py
MODELS_DIR = Path(__file__).parent.parent / 'models'

# ---------------------------------------------------------------------------
# Estado global de treino
# ---------------------------------------------------------------------------
_status: dict = {
    'state': 'idle',
    'progress': 0,
    'message': '',
    'epoch': 0,
    'epochs': 0,
    'train_acc': 0.0,
    'val_acc': 0.0,
    'loss': 0.0,
    'f1': 0.0,
    'precision': 0.0,
    'recall': 0.0,
    'per_class_f1': {},           # {class_name: f1_pct}
    'per_class_precision': {},    # {class_name: precision_pct}
    'per_class_recall': {},       # {class_name: recall_pct}
    'confusion_matrix': [],
    'classes': [],
    'metrics': {},
    'model_path': None,
    'started_at': None,
    'finished_at': None,
    'logs': [],
}
_status_lock = threading.Lock()
_cancel_flag = threading.Event()
_training_thread: threading.Thread | None = None

# Shadow CNN state (persistido em shadow_state.json)
_SHADOW_STATE_PATH   = Path(__file__).parent / 'shadow_state.json'
_SHADOW_HISTORY_PATH = Path(__file__).parent / 'shadow_history.json'
_shadow_process: subprocess.Popen | None = None  # subprocess do shadow_runner.py

# Estado da publicação para o Raspberry (export ONNX + scp), correndo em thread
# própria para não bloquear o servidor HTTP single-threaded durante o scp/ssh.
_publish_status: dict = {'state': 'idle', 'message': '', 'onnx_path': None, 'remote_path': None}
_publish_lock = threading.Lock()


def _set_publish_status(**kwargs):
    with _publish_lock:
        _publish_status.update(kwargs)


def _load_shadow_state() -> dict:
    if _SHADOW_STATE_PATH.exists():
        try:
            return json.loads(_SHADOW_STATE_PATH.read_text())
        except Exception:
            pass
    return {'model': None, 'apples_processed': 0, 'accuracy': None,
            'f1': None, 'state': 'idle', 'comparison': {}}


def _save_shadow_state(state: dict):
    # Escrita atómica (temp + os.replace): /shadow/status pode ler o ficheiro
    # a meio de um write_text direto e apanhar JSON truncado — o parse falhava
    # e o estado regredia transitoriamente para 'idle' (badge a piscar).
    tmp_path = _SHADOW_STATE_PATH.with_suffix('.json.tmp')
    tmp_path.write_text(json.dumps(state, indent=2))
    os.replace(tmp_path, _SHADOW_STATE_PATH)


def _set_status(**kwargs):
    with _status_lock:
        _status.update(kwargs)
        msg = kwargs.get('message', '')
        if msg:
            _status['logs'].append({'time': time.strftime('%H:%M:%S'), 'msg': msg})
            if len(_status['logs']) > 200:
                _status['logs'].pop(0)


# ---------------------------------------------------------------------------
# HTTP Handler
# ---------------------------------------------------------------------------
class MLOpsHandler(BaseHTTPRequestHandler):

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)

        if path == '/status':
            with _status_lock:
                self._ok(json.dumps(dict(_status)).encode())

        elif path == '/classes':
            self._handle_classes()

        elif path == '/models':
            self._handle_models()

        elif path == '/compare':
            a = qs.get('a', [None])[0]
            b = qs.get('b', [None])[0]
            self._handle_compare(a, b)

        elif path == '/shadow/status':
            # Também verifica se o subprocess terminou e atualiza o estado
            self._sync_shadow_process()
            self._ok(json.dumps(_load_shadow_state()).encode())

        elif path == '/shadow/history':
            history = []
            if _SHADOW_HISTORY_PATH.exists():
                try:
                    history = json.loads(_SHADOW_HISTORY_PATH.read_text())
                except Exception:
                    pass
            self._ok(json.dumps({'history': history}).encode())

        elif path == '/models/publish/status':
            with _publish_lock:
                self._ok(json.dumps(dict(_publish_status)).encode())

        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == '/train':
            self._handle_train()
        elif path == '/cancel':
            _cancel_flag.set()
            _set_status(state='cancelled', message='Cancelado pelo utilizador.')
            self._ok(json.dumps({'status': 'cancelled'}).encode())
        elif path == '/shadow/set':
            self._handle_shadow_set()
        elif path == '/shadow/start':
            self._handle_shadow_start()
        elif path == '/shadow/simulate':
            self._handle_shadow_simulate()
        elif path == '/shadow/stop':
            self._handle_shadow_stop()
        elif path == '/shadow/promote':
            self._handle_shadow_promote()
        elif path == '/models/publish':
            self._handle_publish()
        else:
            self.send_response(404)
            self.end_headers()

    # ------------------------------------------------------------------

    def _handle_classes(self):
        try:
            from supabase import create_client
            sb = create_client(SUPABASE_URL, SUPABASE_KEY)

            def fetch_all_paginated(table_name, select_cols, lt_filter=None, eq_filter=None):
                results = []
                limit = 1000
                offset = 0
                while True:
                    q = sb.table(table_name).select(select_cols)
                    if lt_filter:
                        q = q.lt(lt_filter[0], lt_filter[1])
                    if eq_filter:
                        q = q.eq(eq_filter[0], eq_filter[1])
                    data = q.range(offset, offset + limit - 1).execute().data
                    if not data:
                        break
                    results.extend(data)
                    if len(data) < limit:
                        break
                    offset += limit
                return results

            rows = fetch_all_paginated('producao_atual', 'final_class')
            counts: dict[str, int] = {}
            for r in rows:
                cls = r.get('final_class') or 'unknown'
                counts[cls] = counts.get(cls, 0) + 1

            # Hard cases: MESMO critério do treino (confidence < 0.75 E
            # is_worst_case) — antes o filtro divergia e o número mostrado
            # no dashboard não correspondia ao que o treino via. Estes são
            # rótulos automáticos não triados: reservados para avaliação,
            # NUNCA para treino.
            hard_rows = fetch_all_paginated('frames', 'label',
                                            lt_filter=('confidence', 0.75),
                                            eq_filter=('is_worst_case', True))
            hard: dict[str, int] = {}
            for r in hard_rows:
                cls = r.get('label') or 'unknown'
                hard[cls] = hard.get(cls, 0) + 1

            # Ouro: imagens triadas manualmente (train_dataset) — entram no
            # treino com peso reforçado. É este o número que o dashboard
            # mostra a amarelo.
            gold_rows = fetch_all_paginated('train_dataset', 'class')
            gold: dict[str, int] = {}
            for r in gold_rows:
                cls = r.get('class') or 'unknown'
                gold[cls] = gold.get(cls, 0) + 1

            classes = [
                {'name': k, 'count': v,
                 'gold': gold.get(k, 0),
                 'hard_cases': hard.get(k, 0)}
                for k, v in sorted(counts.items())
            ]
            self._ok(json.dumps({'classes': classes}).encode())
        except Exception as e:
            self._ok(json.dumps({'error': str(e), 'classes': []}).encode())

    def _handle_models(self):
        MODELS_DIR.mkdir(exist_ok=True)
        models = []
        for f in sorted(MODELS_DIR.glob('*.pth'), key=lambda x: x.stat().st_mtime, reverse=True):
            meta_path = f.with_suffix('.json')
            meta: dict = {}
            if meta_path.exists():
                try:
                    meta = json.loads(meta_path.read_text())
                except Exception:
                    pass
            models.append({
                'name': f.name,
                'size_mb': round(f.stat().st_size / 1_048_576, 1),
                'created_at': meta.get('created_at', ''),
                'val_accuracy': meta.get('val_accuracy', 0.0),
                'best_f1': meta.get('best_f1', 0.0),
                'classes': meta.get('classes', []),
                'architecture': meta.get('architecture', ''),
                'is_binary': meta.get('is_binary', False),
                'total_images': meta.get('total_images', 0),
                'epochs': meta.get('epochs', 0),
                'history': meta.get('history', []),
                'final_report': meta.get('final_report', {}),
                'roc_curves': meta.get('roc_curves', {}),
                'pr_curves':  meta.get('pr_curves',  {}),
            })
        self._ok(json.dumps({'models': models}).encode())

    def _handle_compare(self, a: str | None, b: str | None):
        """Compara dois modelos usando os metadados JSON guardados durante o treino."""
        def load_meta(name: str | None) -> dict:
            if not name:
                return {}
            p = MODELS_DIR / name
            meta_p = p.with_suffix('.json')
            if not meta_p.exists():
                return {}
            try:
                return json.loads(meta_p.read_text())
            except Exception:
                return {}

        meta_a = load_meta(a)
        meta_b = load_meta(b)

        result = {
            'model_a': {'name': a, **meta_a},
            'model_b': {'name': b, **meta_b},
        }
        self._ok(json.dumps(result).encode())

    def _handle_train(self):
        global _training_thread
        with _status_lock:
            state = _status['state']
        if state in ('downloading', 'augmenting', 'training', 'saving'):
            self._ok(json.dumps({'error': 'Treino já em curso'}).encode())
            return

        length = int(self.headers.get('Content-Length', 0))
        config = json.loads(self.rfile.read(length))
        _cancel_flag.clear()
        _training_thread = threading.Thread(
            target=_run_training, args=(config,), daemon=True
        )
        _training_thread.start()
        self._ok(json.dumps({'status': 'started'}).encode())

    def _handle_shadow_set(self):
        length = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(length))
        state = _load_shadow_state()
        state['model'] = body.get('model')
        state['state'] = 'running' if body.get('model') else 'idle'
        state['apples_processed'] = 0
        _save_shadow_state(state)
        self._ok(json.dumps({'status': 'ok', 'model': state['model']}).encode())

    def _handle_shadow_start(self):
        """Lança shadow_runner.py como subprocess gerido pelo servidor."""
        global _shadow_process

        # Verifica se já corre
        if _shadow_process and _shadow_process.poll() is None:
            self._ok(json.dumps({'status': 'already_running',
                                  'pid': _shadow_process.pid}).encode())
            return

        length = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(length))
        model = body.get('model', '')
        promote_after = int(body.get('promote_after', 1000))
        interval = int(body.get('interval', 30))

        if not model:
            self._ok(json.dumps({'error': 'model é obrigatório'}).encode())
            return

        script = Path(__file__).parent / 'shadow_runner.py'
        log_file = open(Path(__file__).parent.parent / 'logs' / 'shadow_runner.log', 'a')
        _shadow_process = subprocess.Popen(
            [sys.executable, str(script),
             '--model', model,
             '--promote-after', str(promote_after),
             '--interval', str(interval)],
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )

        state = _load_shadow_state()
        state.update({
            'model': model,
            'state': 'running',
            'apples_processed': 0,
            'accuracy': None,
            'f1': None,
            'pid': _shadow_process.pid,
        })
        _save_shadow_state(state)
        print(f'[Shadow] Iniciado PID={_shadow_process.pid}  modelo={model}')
        self._ok(json.dumps({'status': 'started', 'pid': _shadow_process.pid}).encode())

    def _handle_shadow_simulate(self):
        """Lança shadow_runner.py como subprocess no modo de simulação histórica."""
        global _shadow_process

        if _shadow_process and _shadow_process.poll() is None:
            self._ok(json.dumps({'status': 'already_running',
                                  'pid': _shadow_process.pid}).encode())
            return

        length = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(length))
        model = body.get('model', '')
        simulate_count = int(body.get('count', 1000))

        if not model:
            self._ok(json.dumps({'error': 'model é obrigatório'}).encode())
            return

        script = Path(__file__).parent / 'shadow_runner.py'
        log_file = open(Path(__file__).parent.parent / 'logs' / 'shadow_runner.log', 'a')
        _shadow_process = subprocess.Popen(
            [sys.executable, str(script),
             '--model', model,
             '--simulate', str(simulate_count)],
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )

        state = _load_shadow_state()
        state.update({
            'model': model,
            'state': 'running',
            'apples_processed': 0,
            'accuracy': None,
            'f1': None,
            'pid': _shadow_process.pid,
        })
        _save_shadow_state(state)
        print(f'[Shadow] Simulação Histórica PID={_shadow_process.pid} modelo={model} count={simulate_count}')
        self._ok(json.dumps({'status': 'started', 'pid': _shadow_process.pid}).encode())

    def _handle_shadow_stop(self):
        """Termina o subprocess shadow."""
        global _shadow_process
        if _shadow_process and _shadow_process.poll() is None:
            _shadow_process.terminate()
            try:
                _shadow_process.wait(timeout=5)
            except Exception:
                _shadow_process.kill()
            print(f'[Shadow] Parado PID={_shadow_process.pid}')
        _shadow_process = None

        state = _load_shadow_state()
        state['state'] = 'idle'
        _save_shadow_state(state)
        self._ok(json.dumps({'status': 'stopped'}).encode())

    def _handle_shadow_promote(self):
        """Marca o shadow model como produção em models/production.json."""
        state = _load_shadow_state()
        model = state.get('model')
        if not model:
            self._ok(json.dumps({'error': 'Nenhum modelo shadow definido'}).encode())
            return

        model_path = MODELS_DIR / model
        if not model_path.exists():
            self._ok(json.dumps({'error': f'Ficheiro não encontrado: {model}'}).encode())
            return

        prod_cfg = MODELS_DIR / 'production.json'
        prod_cfg.write_text(json.dumps({
            'model': model,
            'promoted_at': time.strftime('%Y-%m-%dT%H:%M:%S'),
            'promoted_from': 'shadow',
        }, indent=2))

        state['state'] = 'promoted'
        _save_shadow_state(state)
        print(f'[Shadow] Promovido: {model}')
        self._ok(json.dumps({'status': 'promoted', 'model': model}).encode())

    def _handle_publish(self):
        """Exporta um modelo MobileNetV2 (.pth) para ONNX quantizado e copia-o
        para o Raspberry Pi via scp. Corre em background — o resultado é lido
        via GET /models/publish/status. Nunca aceita ResNet50 (demasiado
        pesado para o Pi) — export_quantize_onnx.export_pipeline() recusa.
        """
        length = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(length)) if length else {}

        model = body.get('model')
        if not model:
            prod_cfg = MODELS_DIR / 'production.json'
            if prod_cfg.exists():
                try:
                    model = json.loads(prod_cfg.read_text()).get('model')
                except Exception:
                    model = None
        if not model:
            self._ok(json.dumps({'error': 'Sem modelo indicado nem modelo em produção definido'}).encode())
            return

        pi_host = body.get('pi_host')
        if not pi_host:
            self._ok(json.dumps({'error': 'pi_host é obrigatório (ex: minipc@192.168.1.50)'}).encode())
            return
        remote_dir = body.get('remote_dir') or '/home/minipc/models'

        with _publish_lock:
            if _publish_status['state'] in ('exporting', 'uploading'):
                self._ok(json.dumps({'error': 'Já há uma publicação em curso'}).encode())
                return

        threading.Thread(target=_run_publish, args=(model, pi_host, remote_dir), daemon=True).start()
        self._ok(json.dumps({'status': 'started', 'model': model}).encode())

    # ------------------------------------------------------------------

    def _sync_shadow_process(self):
        """Se o subprocess terminou, sincroniza o estado com shadow_state.json."""
        global _shadow_process
        if _shadow_process and _shadow_process.poll() is not None:
            # Processo terminou — o estado já foi atualizado pelo shadow_runner.py
            print(f'[Shadow] Subprocess PID={_shadow_process.pid} terminou '
                  f'(exit={_shadow_process.returncode})')
            _shadow_process = None

    def _ok(self, body: bytes):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def log_message(self, *args):
        pass


# ---------------------------------------------------------------------------
# Thread de treino
# ---------------------------------------------------------------------------
def _run_training(config: dict):
    try:
        import importlib
        import train_cnn
        importlib.reload(train_cnn)
        _set_status(
            state='downloading', progress=0,
            message='A iniciar treino...',
            started_at=time.strftime('%Y-%m-%dT%H:%M:%S'),
            finished_at=None, logs=[], model_path=None,
            metrics={}, epoch=0, train_acc=0.0, val_acc=0.0,
            loss=0.0, f1=0.0, precision=0.0, recall=0.0,
            per_class_f1={}, per_class_precision={}, per_class_recall={},
            confusion_matrix=[], classes=[],
        )
        train_cnn.run(config, _set_status, _cancel_flag)
    except Exception as e:
        import traceback
        _set_status(
            state='error',
            message=f'Erro: {e}',
            finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'),
        )
        print(traceback.format_exc())


# ---------------------------------------------------------------------------
# Publicação para o Raspberry (export ONNX + scp)
# ---------------------------------------------------------------------------
def _run_publish(model_name: str, pi_host: str, remote_dir: str):
    try:
        _set_publish_status(state='exporting', message=f'A exportar {model_name} para ONNX...',
                             onnx_path=None, remote_path=None)

        model_path = MODELS_DIR / model_name
        if not model_path.exists():
            raise FileNotFoundError(f'Modelo não encontrado: {model_name}')

        sys.path.insert(0, str(Path(__file__).parent))
        import export_quantize_onnx

        onnx_out = str(model_path.with_suffix('.onnx'))
        _, _, onnx_quant = export_quantize_onnx.export_pipeline(str(model_path), onnx_out)

        _set_publish_status(state='uploading',
                             message=f'A copiar {Path(onnx_quant).name} para o Pi...',
                             onnx_path=onnx_quant)

        remote_dir = remote_dir.rstrip('/')
        subprocess.run(['ssh', pi_host, f"mkdir -p '{remote_dir}'"],
                        check=True, capture_output=True, text=True, timeout=15)
        subprocess.run(['scp', onnx_quant, f'{pi_host}:{remote_dir}/'],
                        check=True, capture_output=True, text=True, timeout=60)

        remote_path = f'{remote_dir}/{Path(onnx_quant).name}'
        _set_publish_status(
            state='done',
            message='Publicado. O ficheiro só entra em vigor no próximo arranque do script no Pi.',
            remote_path=remote_path,
        )
        print(f'[Publish] {model_name} -> {pi_host}:{remote_path}')
    except subprocess.CalledProcessError as e:
        _set_publish_status(state='error', message=f'Falha no SSH/SCP: {e.stderr or e}')
    except ValueError as e:
        # export_pipeline recusa ResNet50 — mensagem já explica porquê
        _set_publish_status(state='error', message=str(e))
    except Exception as e:
        _set_publish_status(state='error', message=f'Erro: {e}')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    p = argparse.ArgumentParser()
    p.add_argument('--port', type=int, default=8767)
    args = p.parse_args()

    MODELS_DIR.mkdir(exist_ok=True)
    print(f'[MLOps] Modelos em: {MODELS_DIR}')
    print(f'[MLOps] Servidor activo em http://localhost:{args.port}')
    print(f'  GET /classes    GET /models    GET /status')
    print(f'  GET /compare?a=X&b=Y    GET /shadow/status')
    print(f'  POST /train    POST /cancel    POST /shadow/set')
    print(f'  POST /models/publish    GET /models/publish/status')

    server = ThreadingHTTPServer(('0.0.0.0', args.port), MLOpsHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\n[MLOps] Parado.')


if __name__ == '__main__':
    main()
