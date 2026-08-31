#!/usr/bin/env python3
"""CNN5 Watcher — autoridade única sobre as maçãs que a CNN2 do Pi marcou como
incertas (confiança <= 80% ou algum frame 'Unhealthy').

A CNN2 não escreve nada na BD para estas maçãs (ver raspberry_camera_format.py
e ws_server.py) — só entrega N imagens (crop + 224x224) numa pasta local.
Este watcher classifica TODAS as N imagens com a CNN5 (modelo em produção,
models/production.json; GPU se disponível — ~100 img/s), escolhe o
'worst_case' (maior confiança de uma doença específica; se a CNN5 achar que
afinal são todas 'Healthy', o frame 'Healthy' com menor confiança), gera o
Grad-CAM só para essa imagem, e é o único responsável por escrever
apples/frames/cnn_predictions/producao_atual no Supabase.

Em caso de sucesso apaga as imagens locais e marca o JSON como processado
('cnn5_processed': true) — o JSON fica como log leve e permanente; a ausência
dessa marca é o que identifica uma maçã nova por processar.

Deteta JSONs novos em tempo real via watchdog (Observer sobre a pasta), com um
varrimento periódico de segurança (--interval) que apanha ficheiros já presentes
no arranque e eventos eventualmente perdidos. JSONs concluídos são movidos para
Jsonn/done/; os que falham MAX_ATTEMPTS vezes para Jsonn/failed/.

Uso:
  python cnn5_watcher.py --json-dir "C:/auditoria_logs/Jsonn" --interval 60
"""
import argparse
import datetime
import json
import os
import tempfile
import threading
import time
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from torchvision import transforms
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

import shadow_runner

SUPABASE_URL = shadow_runner.SUPABASE_URL
SUPABASE_KEY = shadow_runner.SUPABASE_KEY
BUCKET_NAME = "Apple"
JPEG_QUALITY = 85

# Subpasta dentro do bucket 'Apple' para onde vão as imagens. Pasta de teste
# "2026" por agora; troca para a pasta real quando validado e reinicia.
# TEM de coincidir com STORAGE_FOLDER em raspberry_camera_format_FUNCIONA.py.
STORAGE_FOLDER = "2026"

# Número de tentativas antes de dar uma maçã como falhada (evita reprocessamento
# infinito de um JSON que rebenta sempre — ex. imagem corrompida, coluna em falta).
MAX_ATTEMPTS = 5
# Segundos que um JSON tem de estar "quieto" (sem escrita) antes de o processarmos.
# O ws_server.py escreve o ficheiro de forma não atómica, por isso um evento de
# criação pode chegar antes de o conteúdo estar completo.
STABILITY_SECONDS = 0.5
# Confiança mínima para gravar uma linha em cnn5_multi_confidence (multi-confiança
# por classe). Abaixo disto é ruído de softmax. Igual ao supabase_data.py.
MIN_CLASS_SCORE = 0.05

transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])


def get_production_model_meta() -> tuple[str, str]:
    """Devolve (nome_do_ficheiro, architecture) do modelo CNN5 em produção."""
    prod_path = shadow_runner.MODELS_DIR / 'production.json'
    if not prod_path.exists():
        raise RuntimeError(
            f'Sem modelo em produção: {prod_path} não existe. '
            'Treina/promove um modelo CNN5 primeiro (mlops_server.py).'
        )
    cfg = json.loads(prod_path.read_text())
    model_name = cfg.get('model')
    if not model_name:
        raise RuntimeError(f"{prod_path} não tem campo 'model'.")
    meta_path = shadow_runner.MODELS_DIR / Path(model_name).with_suffix('.json').name
    architecture = 'mobilenet_v2'
    if meta_path.exists():
        architecture = json.loads(meta_path.read_text()).get('architecture', 'mobilenet_v2')
    return model_name, architecture


def get_target_layer(model, architecture: str):
    """Última camada convolucional — alvo dos hooks do Grad-CAM."""
    if architecture == 'resnet50':
        return model.layer4
    return model.features[-1]  # mobilenet_v2


def classify_only(model, classes, device, image_path: Path) -> tuple[str, float]:
    """Classificação rápida (sem hooks/backward) — usada nos N frames para
    decidir qual é o worst_case antes de gastar o Grad-CAM só nesse."""
    label, conf, _ = classify_full(model, classes, device, image_path)
    return label, conf


def classify_full(model, classes, device, image_path: Path) -> tuple[str, float, dict]:
    """Como classify_only, mas devolve também o vetor completo de probabilidades
    por classe {classe: prob} — usado para preencher cnn5_multi_confidence."""
    img = Image.open(image_path).convert('RGB')
    tensor = transform(img).unsqueeze(0).to(device)

    with torch.no_grad():
        out = model(tensor)
        prob = F.softmax(out, dim=1)[0]
        conf, pred = torch.max(prob, dim=0)

    idx = int(pred.item())
    label = classes[idx] if idx < len(classes) else 'unknown'
    n = min(len(classes), prob.shape[0])
    probs = {classes[i]: float(prob[i].item()) for i in range(n)}
    return label, float(conf.item()), probs


def classify_with_gradcam(model, classes, device, architecture: str,
                           image_path: Path, save_gradcam_path: Path) -> tuple[str, float]:
    """Classifica e gera o heatmap Grad-CAM (hooks forward/backward na última
    camada convolucional). Só é chamada para o frame worst_case."""
    img = Image.open(image_path).convert('RGB')
    tensor = transform(img).unsqueeze(0).to(device)
    tensor.requires_grad_(True)

    data = {'activations': None, 'gradients': None}

    def save_act(module, inp, output):
        data['activations'] = output

    def save_grad(module, grad_input, grad_output):
        data['gradients'] = grad_output[0]

    target_layer = get_target_layer(model, architecture)
    handle_act = target_layer.register_forward_hook(save_act)
    handle_grad = target_layer.register_full_backward_hook(save_grad)

    out = model(tensor)
    prob = F.softmax(out, dim=1)[0]
    conf, pred = torch.max(prob, dim=0)
    idx = int(pred.item())
    label = classes[idx] if idx < len(classes) else 'unknown'

    model.zero_grad()
    out[0, idx].backward()

    if data['gradients'] is None or data['activations'] is None:
        img.resize((224, 224)).save(save_gradcam_path, quality=JPEG_QUALITY)
    else:
        gradients = data['gradients'][0].cpu().numpy()
        activations = data['activations'][0].cpu().detach().numpy()
        pooled_gradients = np.mean(gradients, axis=(1, 2))
        for i in range(activations.shape[0]):
            activations[i, :, :] *= pooled_gradients[i]

        heatmap = np.mean(activations, axis=0)
        heatmap = np.maximum(heatmap, 0)
        heatmap_max = np.max(heatmap)
        if heatmap_max > 0:
            heatmap = heatmap / heatmap_max

        heatmap_resized = cv2.resize(heatmap, (224, 224))
        heatmap_colored = cv2.applyColorMap(np.uint8(255 * heatmap_resized), cv2.COLORMAP_JET)
        heatmap_colored = cv2.cvtColor(heatmap_colored, cv2.COLOR_BGR2RGB)

        original_resized = np.array(img.resize((224, 224)))
        superimposed = heatmap_colored * 0.4 + original_resized * 0.6
        superimposed = np.clip(superimposed, 0, 255).astype(np.uint8)
        Image.fromarray(superimposed).convert('RGB').save(save_gradcam_path, quality=JPEG_QUALITY)

    handle_act.remove()
    handle_grad.remove()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()

    return label, float(conf.item())


def upload_to_supabase(sb, local_path: Path, apple_id: str, frame_idx, label: str, suffix: str = '') -> str | None:
    try:
        # Nome começa pela classe atribuída pela CNN5 a esta imagem (Healthy ou a
        # patologia), ex.: Scab_20260723T..._frame1.jpg. Facilita ler o dataset.
        safe_label = ''.join(ch if ch.isalnum() else '_' for ch in str(label)) or 'unknown'
        file_name = f"{safe_label}_{apple_id}_frame{frame_idx}{suffix}.jpg"
        path_on_supa = f"{STORAGE_FOLDER}/{file_name}"
        with open(local_path, 'rb') as f:
            sb.storage.from_(BUCKET_NAME).upload(
                file=f, path=path_on_supa,
                file_options={"content-type": "image/jpeg", "upsert": "true"},
            )
        return sb.storage.from_(BUCKET_NAME).get_public_url(path_on_supa)
    except Exception as e:
        print(f'[CNN5] Erro a fazer upload de {local_path}: {e}')
        return None


def _delete_apple_rows(sb, apple_id: str) -> None:
    """Apaga todas as linhas desta maçã, em ordem de dependência (filhos -> pai),
    para que um reprocessamento parta de estado limpo. Torna a escrita idempotente:
    se uma tentativa anterior falhou a meio (ex. inseriu 'apples' mas não os
    'frames'), a próxima não duplica nem rebenta em constraint de PK/UNIQUE."""
    for table in ('cnn_predictions', 'cnn5_multi_confidence', 'frames', 'producao_atual', 'apples'):
        try:
            sb.table(table).delete().eq('apple_id', apple_id).execute()
        except Exception as e:
            print(f'[CNN5] Aviso: falha a limpar {table} para {apple_id}: {e}')


def _archive_json(json_path: Path, subdir: str) -> None:
    """Move o JSON para Jsonn/<subdir>/ (done ou failed). O Observer vigia Jsonn/
    de forma não recursiva, por isso mover para uma subpasta não re-dispara eventos
    e o glob do sweep passa a varrer só pendentes."""
    try:
        dest_dir = json_path.parent / subdir
        dest_dir.mkdir(exist_ok=True)
        os.replace(str(json_path), str(dest_dir / json_path.name))  # os.replace sobrepõe no Windows
    except Exception as e:
        print(f'[CNN5] Aviso: não consegui arquivar {json_path.name} em {subdir}/: {e}')


def process_burst_json(sb, model, classes, device, architecture, json_path: Path) -> bool:
    meta = json.loads(json_path.read_text(encoding='utf-8'))
    if meta.get('cnn5_processed') or meta.get('cnn5_failed'):
        return False

    try:
        return _process_burst_json_inner(sb, model, classes, device, architecture, json_path, meta)
    except Exception as e:
        # Regista a tentativa; ao fim de MAX_ATTEMPTS desiste e arquiva em failed/.
        attempts = int(meta.get('cnn5_attempts', 0)) + 1
        meta['cnn5_attempts'] = attempts
        meta['cnn5_last_error'] = str(e)
        if attempts >= MAX_ATTEMPTS:
            meta['cnn5_failed'] = True
            meta['cnn5_failed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            json_path.write_text(json.dumps(meta, indent=2), encoding='utf-8')
            _archive_json(json_path, 'failed')
            print(f'[CNN5] {json_path.name}: falhou {attempts}x, arquivado em failed/ ({e})')
        else:
            json_path.write_text(json.dumps(meta, indent=2), encoding='utf-8')
            print(f'[CNN5] {json_path.name}: erro (tentativa {attempts}/{MAX_ATTEMPTS}): {e}')
        return False


def _process_burst_json_inner(sb, model, classes, device, architecture, json_path: Path, meta: dict) -> bool:
    saved_images = meta.get('saved_images') or []
    if not saved_images:
        print(f'[CNN5] {json_path.name}: sem imagens associadas, a ignorar.')
        return False

    apple_id = meta.get('apple_id') or str(meta.get('id'))
    location = meta.get('location') or 'Linha 1'
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()

    classified = []
    for entry in saved_images:
        img_path_str = entry.get('crop') or entry.get('resized')
        if not img_path_str or not Path(img_path_str).exists():
            continue
        img_path = Path(img_path_str)
        label, confidence, probs = classify_full(model, classes, device, img_path)
        classified.append({
            'frame': entry.get('frame'), 'label': label, 'confidence': confidence,
            'path': img_path, 'entry': entry, 'probs': probs,
        })

    if not classified:
        print(f'[CNN5] {json_path.name}: nenhuma imagem válida em disco, a ignorar.')
        return False

    disease_frames = [c for c in classified if c['label'] != 'Healthy']
    worst = max(disease_frames, key=lambda c: c['confidence']) if disease_frames \
        else min(classified, key=lambda c: c['confidence'])
    is_diseased = worst['label'] != 'Healthy'

    frame_results: dict = {}  # frame -> (label, confidence, image_url)

    if is_diseased:
        # Doença: sobem TODAS as imagens que a CNN5 viu, cada uma com o seu
        # próprio Grad-CAM — é isso que preenche a grelha com os N frames.
        for c in classified:
            fd, gradcam_tmp_str = tempfile.mkstemp(suffix='.jpg')
            os.close(fd)
            gradcam_tmp = Path(gradcam_tmp_str)

            label, confidence = classify_with_gradcam(
                model, classes, device, architecture, c['path'], gradcam_tmp
            )
            image_url = upload_to_supabase(sb, c['path'], apple_id, c['frame'], label)
            upload_to_supabase(sb, gradcam_tmp, apple_id, c['frame'], label, suffix='_gradcam')
            frame_results[c['frame']] = (label, confidence, image_url)
            gradcam_tmp.unlink(missing_ok=True)

            if c is worst:
                worst_label, worst_conf = label, confidence
    else:
        # 'Healthy' final: só a imagem do worst_case sobe, sem Grad-CAM
        # (mesma regra do caminho confiante — não há doença para realçar).
        image_url = upload_to_supabase(sb, worst['path'], apple_id, worst['frame'], worst['label'])
        frame_results[worst['frame']] = (worst['label'], worst['confidence'], image_url)
        worst_label, worst_conf = worst['label'], worst['confidence']

    print(f'[CNN5] {apple_id}: {len(classified)} frames classificados '
          f'({len(frame_results)} enviados ao bucket), '
          f'worst_case=frame{worst["frame"]} -> {worst_label} ({worst_conf:.2%})')

    # Idempotência: limpa qualquer escrita parcial desta maçã antes de reescrever.
    _delete_apple_rows(sb, apple_id)

    sb.table('apples').insert({
        'apple_id': apple_id, 'timestamp': timestamp, 'location': location,
    }).execute()

    worst_thumbnail_url = None
    frame_rows = []
    for c in classified:
        is_worst = c is worst
        if c['frame'] in frame_results:
            label, confidence, image_url = frame_results[c['frame']]
        else:
            label, confidence, image_url = c['label'], c['confidence'], None
        if is_worst:
            worst_thumbnail_url = image_url
        entry = c.get('entry') or {}
        frame_rows.append({
            'apple_id': apple_id, 'frame_idx': c['frame'], 'image_url': image_url,
            'label': label, 'confidence': confidence, 'is_worst_case': is_worst,
            # Veredito da CNN2 (Raspberry) para esta imagem, se veio no payload.
            'cnn2_label': entry.get('cnn2_label'),
            'cnn2_confidence': entry.get('cnn2_confidence'),
            # Vetor completo de probabilidades da CNN5 (para cnn5_multi_confidence).
            'probs': c.get('probs') or {},
        })

    worst_frame_id = None
    for row in frame_rows:
        res = sb.table('frames').insert({
            'apple_id': row['apple_id'], 'frame_idx': row['frame_idx'],
            'image_url': row['image_url'], 'label': row['label'],
            'confidence': row['confidence'], 'is_worst_case': row['is_worst_case'],
        }).execute()
        frame_id = res.data[0]['id'] if res.data else None
        if frame_id is not None:
            # CNN5: uma linha por frame (os n frames).
            sb.table('cnn_predictions').insert({
                'apple_id': apple_id, 'frame_id': frame_id, 'model_name': 'CNN5',
                'label': row['label'], 'confidence': row['confidence'], 'timestamp': timestamp,
            }).execute()
            if row['is_worst_case']:
                worst_frame_id = frame_id

            # Multi-confiança por classe: só para maçãs cujo veredito final é
            # doença (mesma regra do supabase_data.py). Uma linha por classe com
            # prob >= MIN_CLASS_SCORE — alimenta o radar/co-confusão da dashboard.
            if is_diseased and row.get('probs'):
                class_scores = [
                    {'apple_id': apple_id, 'frame_id': frame_id,
                     'class_label': cls, 'confidence': conf}
                    for cls, conf in row['probs'].items()
                    if conf >= MIN_CLASS_SCORE
                ]
                if class_scores:
                    sb.table('cnn5_multi_confidence').insert(class_scores).execute()

    # CNN2 (gatekeeper): UMA linha por maçã, ligada ao worst frame. 'Disease'
    # quando o resultado é patologia, senão 'Healthy' — nunca 'Unhealthy' na BD.
    # A opinião por frame da CNN2 fica só na pasta do PC (JSON + nome do ficheiro).
    if worst_frame_id is not None:
        worst_cnn2_conf = (worst.get('entry') or {}).get('cnn2_confidence')
        sb.table('cnn_predictions').insert({
            'apple_id': apple_id, 'frame_id': worst_frame_id, 'model_name': 'CNN2',
            'label': 'Disease' if is_diseased else 'Healthy',
            'confidence': worst_cnn2_conf, 'timestamp': timestamp,
        }).execute()

    sb.table('producao_atual').insert({
        'apple_id': apple_id,
        'final_class': worst_label,
        'final_confidence': worst_conf,
        'frame_thumbnail': worst_thumbnail_url,
        'timestamp': timestamp,
        'location': location,
        'final_source': 'CNN5',
    }).execute()

    # Sucesso: apaga as imagens locais e marca o JSON como processado (log)
    # (os ficheiros temporários de Grad-CAM já foram apagados a cada iteração)
    for entry in saved_images:
        for key in ('crop', 'resized'):
            p = entry.get(key)
            if p and Path(p).exists():
                Path(p).unlink()

    meta['saved_images'] = []
    meta['final_class'] = worst_label
    meta['final_confidence'] = worst_conf
    meta['cnn5_processed'] = True
    meta['cnn5_processed_at'] = timestamp
    json_path.write_text(json.dumps(meta, indent=2), encoding='utf-8')

    # Arquiva o JSON processado em Jsonn/done/ (o glob do sweep só vê pendentes).
    _archive_json(json_path, 'done')

    return True


class _JsonEventHandler(FileSystemEventHandler):
    """Enfileira JSONs novos/movidos para Jsonn/ assim que o watchdog os deteta.
    A via principal (tempo real); o sweep periódico em run() é só a rede de segurança."""

    def __init__(self, on_json):
        self._on_json = on_json

    def on_created(self, event):
        self._maybe(event.src_path, event.is_directory)

    def on_modified(self, event):
        self._maybe(event.src_path, event.is_directory)

    def on_moved(self, event):
        self._maybe(getattr(event, 'dest_path', ''), event.is_directory)

    def _maybe(self, path, is_directory):
        if is_directory or not path:
            return
        if str(path).lower().endswith('.json'):
            self._on_json(Path(path))


def run(json_dir: Path, interval: int):
    from supabase import create_client

    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    model_name, architecture = get_production_model_meta()
    model, classes, device = shadow_runner.load_shadow_model(model_name)

    json_dir.mkdir(parents=True, exist_ok=True)

    pending: set[Path] = set()
    lock = threading.Lock()

    def enqueue(p: Path):
        # Só ficheiros diretamente em json_dir; ignora Jsonn/done/ e Jsonn/failed/.
        try:
            if p.parent != json_dir:
                return
        except Exception:
            return
        with lock:
            pending.add(p)

    def sweep():
        for jp in json_dir.glob('*.json'):
            enqueue(jp)

    handler = _JsonEventHandler(enqueue)
    observer = Observer()
    observer.schedule(handler, str(json_dir), recursive=False)
    observer.start()

    sweep()  # arranque: apanha JSONs já presentes antes de o watcher iniciar
    last_sweep = time.time()

    print(f'[CNN5] watchdog a vigiar {json_dir} (sweep de segurança cada {interval}s) '
          f'(modelo: {model_name}, arquitetura: {architecture}, device: {device})')

    try:
        while True:
            now = time.time()
            if now - last_sweep >= interval:
                sweep()
                last_sweep = now

            with lock:
                batch = list(pending)

            for jp in batch:
                if not jp.exists():
                    with lock:
                        pending.discard(jp)
                    continue
                # Espera o ficheiro estabilizar (escrita não atómica do ws_server).
                try:
                    if time.time() - jp.stat().st_mtime < STABILITY_SECONDS:
                        continue  # ainda a ser escrito; volta a tentar no próximo ciclo
                except OSError:
                    continue
                with lock:
                    pending.discard(jp)
                try:
                    process_burst_json(sb, model, classes, device, architecture, jp)
                except Exception as e:
                    print(f'[CNN5] Erro a processar {jp.name}: {e}')

            time.sleep(1.0)
    except KeyboardInterrupt:
        print('[CNN5] A terminar (Ctrl+C)...')
    finally:
        observer.stop()
        observer.join()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--json-dir', required=True, help='Pasta de JSONs gravada pelo ws_server.py')
    p.add_argument('--interval', type=int, default=60,
                   help='Segundos entre varrimentos de segurança (rede; a via principal é o watchdog). Default 60')
    args = p.parse_args()
    run(Path(args.json_dir), args.interval)


if __name__ == '__main__':
    main()
