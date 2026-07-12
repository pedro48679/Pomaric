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

Uso:
  python cnn5_watcher.py --json-dir "C:/.../TempRaspberry/Jsonn" --interval 5
"""
import argparse
import datetime
import json
import os
import tempfile
import time
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from torchvision import transforms

import shadow_runner

SUPABASE_URL = shadow_runner.SUPABASE_URL
SUPABASE_KEY = shadow_runner.SUPABASE_KEY
BUCKET_NAME = "Apple"
JPEG_QUALITY = 85

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
    img = Image.open(image_path).convert('RGB')
    tensor = transform(img).unsqueeze(0).to(device)

    with torch.no_grad():
        out = model(tensor)
        prob = F.softmax(out, dim=1)[0]
        conf, pred = torch.max(prob, dim=0)

    idx = int(pred.item())
    label = classes[idx] if idx < len(classes) else 'unknown'
    return label, float(conf.item())


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


def upload_to_supabase(sb, local_path: Path, apple_id: str, frame_idx, suffix: str = '') -> str | None:
    try:
        file_name = f"{apple_id}_frame{frame_idx}{suffix}.jpg"
        path_on_supa = f"{datetime.datetime.utcnow().year}/{file_name}"
        with open(local_path, 'rb') as f:
            sb.storage.from_(BUCKET_NAME).upload(
                file=f, path=path_on_supa,
                file_options={"content-type": "image/jpeg", "upsert": "true"},
            )
        return sb.storage.from_(BUCKET_NAME).get_public_url(path_on_supa)
    except Exception as e:
        print(f'[CNN5] Erro a fazer upload de {local_path}: {e}')
        return None


def process_burst_json(sb, model, classes, device, architecture, json_path: Path) -> bool:
    meta = json.loads(json_path.read_text(encoding='utf-8'))
    if meta.get('cnn5_processed'):
        return False

    saved_images = meta.get('saved_images') or []
    if not saved_images:
        print(f'[CNN5] {json_path.name}: sem imagens associadas, a ignorar.')
        return False

    apple_id = meta.get('apple_id') or str(meta.get('id'))
    location = meta.get('location') or 'Linha 1'
    timestamp = datetime.datetime.utcnow().isoformat()

    classified = []
    for entry in saved_images:
        img_path_str = entry.get('crop') or entry.get('resized')
        if not img_path_str or not Path(img_path_str).exists():
            continue
        img_path = Path(img_path_str)
        label, confidence = classify_only(model, classes, device, img_path)
        classified.append({
            'frame': entry.get('frame'), 'label': label, 'confidence': confidence,
            'path': img_path, 'entry': entry,
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
            image_url = upload_to_supabase(sb, c['path'], apple_id, c['frame'])
            upload_to_supabase(sb, gradcam_tmp, apple_id, c['frame'], suffix='_gradcam')
            frame_results[c['frame']] = (label, confidence, image_url)
            gradcam_tmp.unlink(missing_ok=True)

            if c is worst:
                worst_label, worst_conf = label, confidence
    else:
        # 'Healthy' final: só a imagem do worst_case sobe, sem Grad-CAM
        # (mesma regra do caminho confiante — não há doença para realçar).
        image_url = upload_to_supabase(sb, worst['path'], apple_id, worst['frame'])
        frame_results[worst['frame']] = (worst['label'], worst['confidence'], image_url)
        worst_label, worst_conf = worst['label'], worst['confidence']

    print(f'[CNN5] {apple_id}: {len(classified)} frames classificados '
          f'({len(frame_results)} enviados ao bucket), '
          f'worst_case=frame{worst["frame"]} -> {worst_label} ({worst_conf:.2%})')

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
        frame_rows.append({
            'apple_id': apple_id, 'frame_idx': c['frame'], 'image_url': image_url,
            'label': label, 'confidence': confidence, 'is_worst_case': is_worst,
        })

    for row in frame_rows:
        res = sb.table('frames').insert(row).execute()
        frame_id = res.data[0]['id'] if res.data else None
        if frame_id is not None:
            sb.table('cnn_predictions').insert({
                'apple_id': apple_id, 'frame_id': frame_id, 'model_name': 'CNN5',
                'label': row['label'], 'confidence': row['confidence'], 'timestamp': timestamp,
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

    return True


def run(json_dir: Path, interval: int):
    from supabase import create_client

    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    model_name, architecture = get_production_model_meta()
    model, classes, device = shadow_runner.load_shadow_model(model_name)

    print(f'[CNN5] Watcher a vigiar {json_dir} a cada {interval}s '
          f'(modelo: {model_name}, arquitetura: {architecture}, device: {device})')

    while True:
        try:
            for json_path in sorted(json_dir.glob('*.json')):
                try:
                    process_burst_json(sb, model, classes, device, architecture, json_path)
                except Exception as e:
                    print(f'[CNN5] Erro a processar {json_path.name}: {e}')
        except Exception as e:
            print(f'[CNN5] Erro no loop: {e}')

        time.sleep(interval)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--json-dir', required=True, help='Pasta de JSONs gravada pelo ws_server.py')
    p.add_argument('--interval', type=int, default=5, help='Segundos entre ciclos de polling (default 5)')
    args = p.parse_args()
    run(Path(args.json_dir), args.interval)


if __name__ == '__main__':
    main()
