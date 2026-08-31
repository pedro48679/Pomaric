#!/usr/bin/env python3
"""
Shadow CNN Runner — corre um modelo candidato em background.

O modelo shadow classifica as mesmas maçãs que entram em produção,
mas sem afetar as decisões reais. Após --promote-after maçãs, o runner
compara automaticamente com o modelo em produção:
  • Se shadow F1 > produção F1 → auto-promove e arquiva o modelo anterior
  • Se não → arquiva o shadow em shadow_history.json (sem promover)
Em ambos os casos o runner termina e o estado fica em 'promoted' ou 'archived'.

O processo corre de forma completamente autónoma — não precisa que o utilizador
esteja com a dashboard aberta.

Uso:
  python shadow_runner.py --model "cnn_multi_mobilenet_5cls_acc87_f185_20260630.pth"
  python shadow_runner.py --model "..." --promote-after 500 --interval 30

O estado é guardado em shadow_state.json (lido pelo mlops_server.py /shadow/status).
"""

import json
import os
import sys
import time
import argparse
import datetime
from pathlib import Path

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    sys.exit(
        "ERRO: define as variaveis de ambiente SUPABASE_URL e SUPABASE_SERVICE_KEY com a tua "
        "service_role key antes de correr este script."
    )

MODELS_DIR   = Path(__file__).parent.parent / 'models'
STATE_PATH   = Path(__file__).parent / 'shadow_state.json'
HISTORY_PATH = Path(__file__).parent / 'shadow_history.json'
PROD_PATH    = MODELS_DIR / 'production.json'


# ---------------------------------------------------------------------------
# Estado
# ---------------------------------------------------------------------------

def load_state() -> dict:
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text())
        except Exception:
            pass
    return {
        'model': None, 'apples_processed': 0,
        'accuracy': None, 'f1': None,
        'state': 'idle', 'comparison': {}, 'last_updated': None,
    }


def save_state(s: dict):
    # Escrita atómica: o mlops_server lê este ficheiro em /shadow/status a
    # cada poll de 2s do dashboard — um write_text direto podia ser lido a
    # meio (JSON truncado) e regredir o estado para 'idle' transitoriamente.
    s['last_updated'] = datetime.datetime.now().isoformat()
    tmp = STATE_PATH.with_suffix('.json.tmp')
    tmp.write_text(json.dumps(s, indent=2))
    os.replace(tmp, STATE_PATH)


def load_history() -> list:
    if HISTORY_PATH.exists():
        try:
            return json.loads(HISTORY_PATH.read_text())
        except Exception:
            pass
    return []


def append_history(entry: dict):
    h = load_history()
    h.insert(0, entry)
    if len(h) > 50:
        h = h[:50]
    HISTORY_PATH.write_text(json.dumps(h, indent=2))


# ---------------------------------------------------------------------------
# Modelo
# ---------------------------------------------------------------------------

def load_shadow_model(model_name: str):
    """Carrega o modelo shadow e devolve (model, classes, device)."""
    import torch
    import torch.nn as nn
    from torchvision import models as tv_models

    model_path = MODELS_DIR / model_name
    meta_path  = model_path.with_suffix('.json')

    meta = {}
    if meta_path.exists():
        meta = json.loads(meta_path.read_text())

    classes      = meta.get('classes', [])
    architecture = meta.get('architecture', 'mobilenet_v2')
    num_classes  = len(classes) if classes else meta.get('num_classes', 5)

    device = __import__('torch').device('cuda' if __import__('torch').cuda.is_available() else 'cpu')

    if architecture == 'resnet50':
        model = tv_models.resnet50(weights=None)
        model.fc = nn.Sequential(nn.Dropout(0.5), nn.Linear(model.fc.in_features, num_classes))
    else:
        model = tv_models.mobilenet_v2(weights=None)
        model.classifier[1] = nn.Linear(model.last_channel, num_classes)

    import torch
    model.load_state_dict(torch.load(model_path, map_location=device, weights_only=True))
    model = model.to(device).eval()

    print(f'[Shadow] Modelo carregado: {model_name}  ({num_classes} classes: {classes})')
    return model, classes, device


def classify_image(model, classes, device, url: str) -> tuple[str, float]:
    """Descarrega e classifica uma imagem. Devolve (label, confiança)."""
    import torch
    import torch.nn.functional as F
    from torchvision import transforms
    from PIL import Image
    import requests
    import io

    tf = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])

    headers = {}
    if SUPABASE_KEY:
        headers = {'apikey': SUPABASE_KEY, 'Authorization': f'Bearer {SUPABASE_KEY}'}
    resp = requests.get(url, headers=headers, timeout=15)
    resp.raise_for_status()
    img = Image.open(io.BytesIO(resp.content)).convert('RGB')
    tensor = tf(img).unsqueeze(0).to(device)

    with torch.no_grad():
        out = model(tensor)
        prob = F.softmax(out, dim=1)[0]
        conf, pred = torch.max(prob, dim=0)

    idx = int(pred.item())
    label = classes[idx] if idx < len(classes) else 'unknown'
    return label, float(conf.item())


# ---------------------------------------------------------------------------
# Comparação com produção
# ---------------------------------------------------------------------------

def get_production_f1() -> float | None:
    """Lê o F1 do modelo em produção a partir do seu ficheiro .json de metadados."""
    if not PROD_PATH.exists():
        return None
    try:
        prod_cfg = json.loads(PROD_PATH.read_text())
        prod_model = prod_cfg.get('model', '')
        if not prod_model:
            return None
        meta_path = MODELS_DIR / Path(prod_model).with_suffix('.json').name
        if not meta_path.exists():
            return None
        meta = json.loads(meta_path.read_text())
        return meta.get('best_f1')  # valor percentual (ex: 85.1)
    except Exception:
        return None


def auto_decide(state: dict, shadow_f1: float, shadow_acc: float) -> str:
    """
    Compara shadow vs produção.
    Devolve 'promoted' ou 'archived'.
    Escreve production.json se promoveu.
    """
    prod_f1 = get_production_f1()
    comparison = {
        'shadow_f1': round(shadow_f1, 1),
        'shadow_accuracy': round(shadow_acc, 1),
        'production_f1': prod_f1,
        'decided_at': datetime.datetime.now().isoformat(),
    }

    if prod_f1 is None or shadow_f1 > prod_f1:
        # Auto-promove
        old_model = None
        if PROD_PATH.exists():
            try:
                old_model = json.loads(PROD_PATH.read_text()).get('model')
            except Exception:
                pass

        PROD_PATH.write_text(json.dumps({
            'model': state['model'],
            'promoted_at': datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
            'promoted_from': 'shadow_auto',
            'shadow_f1': round(shadow_f1, 1),
            'shadow_accuracy': round(shadow_acc, 1),
            'previous_model': old_model,
        }, indent=2))

        comparison['result'] = 'promoted'
        comparison['reason'] = (
            f'Shadow F1={shadow_f1:.1f}% > Produção F1={prod_f1}%'
            if prod_f1 is not None else 'Sem modelo em produção — shadow promovido.'
        )
        print(f'[Shadow] AUTO-PROMOVIDO: {state["model"]}  '
              f'F1={shadow_f1:.1f}%  (produção era {prod_f1}%)')
        result = 'promoted'
    else:
        comparison['result'] = 'archived'
        comparison['reason'] = (
            f'Shadow F1={shadow_f1:.1f}% ≤ Produção F1={prod_f1:.1f}% — arquivado.'
        )
        print(f'[Shadow] ARQUIVADO: {state["model"]}  '
              f'F1={shadow_f1:.1f}%  (produção é {prod_f1:.1f}%)')
        result = 'archived'

    state['comparison'] = comparison

    # Guardar no histórico
    append_history({
        'model': state['model'],
        'apples_processed': state['apples_processed'],
        'f1': round(shadow_f1, 1),
        'accuracy': round(shadow_acc, 1),
        'production_f1': prod_f1,
        'result': result,
        'reason': comparison['reason'],
        'date': datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
    })

    return result


# ---------------------------------------------------------------------------
# Loop principal
# ---------------------------------------------------------------------------

def run(model_name: str, promote_after: int = 1000, interval: int = 30, simulate_count: int | None = None):
    import random
    from supabase import create_client
    from sklearn.metrics import f1_score, accuracy_score

    sb     = create_client(SUPABASE_URL, SUPABASE_KEY)
    model, classes, device = load_shadow_model(model_name)
    
    # Obter os F1 teóricos (de treino) para mostrar no dashboard imediatamente
    shadow_train_f1 = None
    try:
        meta_path = (MODELS_DIR / model_name).with_suffix('.json')
        if meta_path.exists():
            shadow_train_f1 = json.loads(meta_path.read_text()).get('best_f1')
    except: pass
    
    prod_train_f1 = get_production_f1()

    state = load_state()
    state.update({
        'model': model_name,
        'state': 'running',
        'apples_processed': 0,
        'accuracy': None,
        'f1': None,
        'comparison': {},
        'theoretical_f1': {
            'shadow': shadow_train_f1,
            'production': prod_train_f1,
        },
        # Detalhe por classe e discordâncias concretas: antes só os agregados
        # accuracy/f1 eram persistidos e o dashboard não conseguia mostrar
        # ONDE os dois modelos divergem, só quanto.
        'per_class_agreement': {},
        'disagreements': [],
    })
    save_state(state)

    last_apple_id: str | None    = None
    all_shadow_preds: list[str]  = []
    all_true_labels:  list[str]  = []
    disagreements: list[dict]    = []  # mais recentes primeiro, cap 50

    # Lógica de Simulação de Histórico
    if simulate_count is not None:
        print(f'[Shadow] MODO SIMULAÇÃO: A buscar até 5000 maçãs históricas filtradas pelas classes {classes}')
        try:
            res = sb.table('producao_atual').select(
                'apple_id, final_class, frame_thumbnail'
            ).in_('final_class', classes).limit(5000).execute().data
            
            # Baralhar e pegar no número pedido
            random.shuffle(res)
            rows = res[:simulate_count]
            print(f'[Shadow] Encontradas {len(res)} imagens válidas. Selecionadas {len(rows)} para simulação.')
            
            for i, row in enumerate(rows):
                apple_id   = row['apple_id']
                true_label = row.get('final_class', 'unknown')
                url        = row.get('frame_thumbnail', '')
                
                if not url or true_label == 'unknown':
                    continue
                
                try:
                    shadow_label, conf = classify_image(model, classes, device, url)
                    all_shadow_preds.append(shadow_label)
                    all_true_labels.append(true_label)
                    state['apples_processed'] += 1
                    
                    if shadow_label != true_label:
                        disagreements.insert(0, {
                            'apple_id': apple_id,
                            'production': true_label,
                            'shadow': shadow_label,
                            'conf': round(float(conf) * 100, 1),
                        })
                        del disagreements[50:]
                except Exception as e:
                    print(f'[Shadow] Erro em {apple_id}: {e}')
                
                # Guarda estado para a dashboard acompanhar o progresso rápido
                if state['apples_processed'] % 10 == 0 or i == len(rows) - 1:
                    if all_true_labels:
                        common_classes = sorted(set(all_true_labels) | set(all_shadow_preds))
                        acc = accuracy_score(all_true_labels, all_shadow_preds)
                        f1  = float(f1_score(all_true_labels, all_shadow_preds,
                                             average='weighted', zero_division=0,
                                             labels=common_classes))
                        state['accuracy'] = round(acc * 100, 1)
                        state['f1']       = round(f1  * 100, 1)
                        per_class: dict[str, dict] = {}
                        for t, s in zip(all_true_labels, all_shadow_preds):
                            entry = per_class.setdefault(t, {'total': 0, 'agree': 0})
                            entry['total'] += 1
                            if t == s:
                                entry['agree'] += 1
                        state['per_class_agreement'] = per_class
                        state['disagreements'] = disagreements
                        save_state(state)
            
            # Fim da simulação
            if all_true_labels:
                acc = accuracy_score(all_true_labels, all_shadow_preds)
                f1  = float(f1_score(all_true_labels, all_shadow_preds,
                                     average='weighted', zero_division=0,
                                     labels=sorted(set(all_true_labels) | set(all_shadow_preds))))
                result = auto_decide(state, f1 * 100, acc * 100)
                state['state'] = result
                save_state(state)
                print(f'[Shadow] Simulação concluída com resultado: {result}. A terminar.')
            return
        except Exception as e:
            print(f'[Shadow] Erro na simulação: {e}')
            return

    # Para não processar o histórico antigo de rajada, começamos no último ID atual:
    try:
        latest = sb.table('producao_atual').select('apple_id').order('apple_id', desc=True).limit(1).execute().data
        if latest:
            last_apple_id = latest[0]['apple_id']
    except Exception as e:
        print(f'[Shadow] Aviso ao buscar último ID: {e}')

    print(f'[Shadow] A monitorizar BD a cada {interval}s. Promoção após {promote_after} maçãs.')

    while True:
        try:
            query = sb.table('producao_atual').select(
                'apple_id, final_class, frame_thumbnail'
            ).order('apple_id', desc=False)

            if last_apple_id:
                query = query.gt('apple_id', last_apple_id)

            rows = query.limit(50).execute().data

            for row in rows:
                apple_id   = row['apple_id']
                true_label = row.get('final_class', 'unknown')
                url        = row.get('frame_thumbnail', '')

                if not url or true_label == 'unknown':
                    continue

                try:
                    shadow_label, conf = classify_image(model, classes, device, url)
                    all_shadow_preds.append(shadow_label)
                    all_true_labels.append(true_label)
                    state['apples_processed'] += 1
                    last_apple_id = apple_id
                    if shadow_label != true_label:
                        disagreements.insert(0, {
                            'apple_id': apple_id,
                            'production': true_label,
                            'shadow': shadow_label,
                            'conf': round(float(conf) * 100, 1),
                        })
                        del disagreements[50:]
                    print(f'[Shadow] {apple_id}: true={true_label}  shadow={shadow_label} ({conf:.2%})')
                except Exception as e:
                    print(f'[Shadow] Erro em {apple_id}: {e}')

            # Métricas acumuladas
            if all_true_labels:
                common_classes = sorted(set(all_true_labels) | set(all_shadow_preds))
                acc = accuracy_score(all_true_labels, all_shadow_preds)
                f1  = float(f1_score(all_true_labels, all_shadow_preds,
                                     average='weighted', zero_division=0,
                                     labels=common_classes))

                state['accuracy'] = round(acc * 100, 1)
                state['f1']       = round(f1  * 100, 1)

                # Concordância por classe (chave = decisão de produção):
                # cresce em direto durante o run, lida por /shadow/status.
                per_class: dict[str, dict] = {}
                for t, s in zip(all_true_labels, all_shadow_preds):
                    entry = per_class.setdefault(t, {'total': 0, 'agree': 0})
                    entry['total'] += 1
                    if t == s:
                        entry['agree'] += 1
                state['per_class_agreement'] = per_class
                state['disagreements'] = disagreements

                if state['apples_processed'] >= promote_after:
                    result = auto_decide(state, f1 * 100, acc * 100)
                    state['state'] = result
                    save_state(state)
                    print(f'[Shadow] Concluído com resultado: {result}. A terminar.')
                    return  # sai limpo — mlops_server nota que o processo terminou

            save_state(state)

        except Exception as e:
            print(f'[Shadow] Erro no loop: {e}')

        time.sleep(interval)


# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--model', required=True,
                   help='Nome do ficheiro .pth em script_apple/models/')
    p.add_argument('--promote-after', type=int, default=1000,
                   help='Número de maçãs para considerar promoção (default 1000)')
    p.add_argument('--interval', type=int, default=30,
                   help='Segundos entre polls ao Supabase (default 30)')
    p.add_argument('--simulate', type=int, default=None,
                   help='Corre em modo simulação com N imagens aleatórias históricas')
    args = p.parse_args()
    run(args.model, args.promote_after, args.interval, args.simulate)


if __name__ == '__main__':
    main()
