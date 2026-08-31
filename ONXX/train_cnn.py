#!/usr/bin/env python3
"""
Lógica de treino CNN, chamado pelo mlops_server.py.

Fontes de dados:
  1. producao_atual → frame_thumbnail + final_class  (imagens principais por classe)
  2. frames          → image_url onde confidence < hard_threshold  (casos difíceis)
  3. Augmentação aleatória para balancear classes sub-representadas

Métricas por época: train_acc, val_acc, loss, F1 (weighted), precision, recall, per_class_f1
Final: confusion_matrix, classification_report
"""

import os
import json
import copy
import time
import shutil
import datetime
import tempfile
import threading
from pathlib import Path
from typing import Callable
import random as _random

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", os.environ.get("SUPABASE_ANON_KEY", ""))

if not SUPABASE_URL or not SUPABASE_KEY:
    raise ValueError("Variaveis de ambiente SUPABASE_URL e SUPABASE_SERVICE_KEY (ou ANON_KEY) devem estar definidas.")

# Pasta central de modelos (script_apple/models/)
MODELS_DIR = Path(__file__).parent.parent / 'models'


def run(config: dict, status_cb: Callable, cancel: threading.Event | None = None):
    """
    config keys:
      classes          list[str]   classes a incluir (vazio = todas com imagens suficientes)
      is_binary        bool        True → CNN2 estilo (Healthy vs Disease) [default False]
      architecture     str         'mobilenet_v2' | 'resnet50'  [default mobilenet_v2]
      epochs           int         [default 10]
      lr               float       [default 1e-4]
      hard_threshold   float       confiança < X é caso difícil [default 0.75]
      min_images       int         mínimo de imagens por classe [default 20]
      batch_size       int         [default 32]
    """
    import torch
    import torch.nn as nn
    import torch.nn.functional as F_inner
    import torch.optim as optim
    import numpy as np
    from torchvision import models as tv_models, transforms, datasets
    from torch.utils.data import DataLoader
    from PIL import Image
    import requests
    from sklearn.metrics import (
        f1_score, precision_score, recall_score,
        confusion_matrix, classification_report,
        roc_curve, precision_recall_curve, auc,
    )
    from sklearn.preprocessing import label_binarize

    def cancelled():
        return cancel is not None and cancel.is_set()

    classes_requested: list[str] = config.get('classes', [])
    is_binary: bool = bool(config.get('is_binary', False))
    architecture: str = config.get('architecture', 'mobilenet_v2')
    epochs: int = max(1, int(config.get('epochs', 10)))
    lr: float = float(config.get('lr', 1e-4))
    hard_threshold: float = float(config.get('hard_threshold', 0.75))
    min_images: int = int(config.get('min_images', 20))
    max_images: int = int(config.get('max_images', 2000))
    max_images = max(max_images, min_images)  # Evitar paradoxo
    batch_size: int = int(config.get('batch_size', 32))
    # Cap total da amostra de avaliação "casos difíceis reais" (hard cases
    # confirmados + amostra representativa de produção) — limita tempo de
    # download.
    HARD_EVAL_CAP = 400

    from supabase import create_client
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)

    # -----------------------------------------------------------------------
    # 1. Consultar BD
    # -----------------------------------------------------------------------
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

    status_cb(state='downloading', progress=3, message='A consultar base de dados Supabase...')

    main_rows = fetch_all_paginated(
        'producao_atual', 'apple_id, final_class, final_confidence, frame_thumbnail'
    )

    # Active Learning (Crops e anotações manuais)
    train_rows = fetch_all_paginated('train_dataset', 'apple_id, class')
    # 'Lixo' marca imagens de má qualidade/falsas — não é uma classe de doença,
    # entrar no treino com esse rótulo corrompe o dataset.
    train_rows = [r for r in train_rows if (r.get('class') or '').strip().lower() != 'lixo']

    # Obter manualmente os crops criados a partir dos círculos
    circles_rows = fetch_all_paginated('circles_manual', 'apple_id, circle_index, disease, crop')
    circles_rows = [c for c in circles_rows if (c.get('disease') or '').strip().lower() != 'lixo']
    circles_by_apple = {}
    for c in circles_rows:
        aid = c.get('apple_id')
        if aid:
            circles_by_apple.setdefault(aid, []).append(c)

    # Mapear URLs originais para uso no train_dataset
    global_urls = {}
    for r in main_rows:
        if r.get('apple_id'): global_urls[r['apple_id']] = r.get('frame_thumbnail')
    
    # Pre-fetch frames: urls para hard cases que possam estar no train_dataset,
    # E a população completa usada abaixo tanto para os hard cases como para
    # a amostra representativa de avaliação (ver 2b) — evita duas queries à
    # mesma tabela.
    all_frames = fetch_all_paginated(
        'frames', 'apple_id, image_url, label, confidence, is_worst_case'
    )
    for r in all_frames:
        if r.get('apple_id'): global_urls[r['apple_id']] = r.get('image_url')

    # Injetar duplicados (2x peso) e os crops no dataset de treino
    expanded_train_rows = []
    for r in train_rows:
        aid = r.get('apple_id')
        if not aid: continue
        
        # 1. Imagem Original (peso 1)
        r['original_url'] = global_urls.get(aid)
        expanded_train_rows.append(r)
        
        # 2. Imagem Original Duplicada (peso 2, o sufixo _copy indica que é a original)
        r_copy = r.copy()
        r_copy['apple_id'] = f"{aid}_copy"
        r_copy['original_url'] = global_urls.get(aid)
        expanded_train_rows.append(r_copy)

        # 3. Cada um dos crops
        for circle in circles_by_apple.get(aid, []):
            if circle.get('crop') and circle.get('crop') != 'none':
                r_crop = r.copy()
                r_crop['apple_id'] = f"{aid}_crop_{circle.get('circle_index')}"
                r_crop['class'] = circle.get('disease')
                r_crop['crop_url'] = circle.get('crop')
                expanded_train_rows.append(r_crop)
                
    train_rows = expanded_train_rows

    # Hard cases: derivados de all_frames (já obtido acima), confiança abaixo
    # do limiar E sinalizados como pior-caso pela linha de produção.
    hard_rows = [
        {'apple_id': r.get('apple_id'), 'label': r.get('label'),
         'confidence': r.get('confidence'), 'image_url': r.get('image_url'),
         'source': 'hard'}
        for r in all_frames
        if r.get('is_worst_case') is True
        and r.get('confidence') is not None and r.get('confidence') < hard_threshold
    ]

    # Obter IDs pendentes na triagem manual para NÃO treinar com rótulos por verificar
    pending_reviews = fetch_all_paginated('manual_review', 'apple_id', eq_filter=('status', 'pending'))
    pending_ids = {r.get('apple_id') for r in pending_reviews if r.get('apple_id')}

    # Obter IDs que já estão no train_dataset para evitar duplicados conflituosos
    # (porque se já foi revisto, o rótulo correto está no train_rows, não queremos a predição antiga no hard_rows ou main_rows)
    train_ids = {r.get('apple_id') for r in train_rows if r.get('apple_id')}

    # Filtrar main_rows e hard_rows para remover pendentes e duplicados
    hard_ids = {r.get('apple_id') for r in hard_rows if r.get('apple_id')}
    main_rows = [r for r in main_rows if r.get('apple_id') not in pending_ids and r.get('apple_id') not in train_ids and r.get('apple_id') not in hard_ids]
    hard_rows = [r for r in hard_rows if r.get('apple_id') not in pending_ids and r.get('apple_id') not in train_ids]

    # Amostra representativa de produção para juntar aos hard cases na
    # avaliação de "casos difíceis reais": só o pior caso (confiança<limiar)
    # sobre-representa doenças fora do vocabulário (ex.: Frost, Bitter Rot)
    # auto-rotuladas para a classe mais próxima, o que puxava a curva para
    # baixo de forma injusta (não é erro de classificação, é ambiguidade
    # genuína/fora do vocabulário).
    #
    # IMPORTANTE: esta amostra tem de vir da mesma banda de confiança que a
    # app já usa para triagem/auditoria (<85%, ver isUncertainApple em
    # dashboard_provider.dart), NÃO de todo o espectro. A esmagadora maioria
    # da produção tem confiança alta (é fácil) — amostrar sem filtro dilui
    # os casos difíceis até desaparecerem e a curva regressa a ~100%, o
    # oposto do objetivo (imitar uma fila de triagem real: mistura de
    # difíceis + normais-mas-incertos, nunca a maioria trivial).
    REPR_CONF_CEILING = 0.85
    main_used_ids = {r.get('apple_id') for r in main_rows if r.get('apple_id')}
    repr_used_ids = pending_ids | train_ids | hard_ids | main_used_ids
    repr_pool = [
        r for r in all_frames
        if r.get('apple_id') not in repr_used_ids and r.get('label')
        and r.get('confidence') is not None and r.get('confidence') < REPR_CONF_CEILING
    ]
    _random.Random(42).shuffle(repr_pool)
    n_repr = max(0, HARD_EVAL_CAP - len(hard_rows))
    repr_sample = [
        {'apple_id': r.get('apple_id'), 'label': r.get('label'),
         'confidence': r.get('confidence'), 'image_url': r.get('image_url'),
         'source': 'production_sample'}
        for r in repr_pool[:n_repr]
    ]
    eval_rows = hard_rows + repr_sample

    if classes_requested:
        main_rows = [r for r in main_rows if r.get('final_class') in classes_requested]
        eval_rows = [r for r in eval_rows if r.get('label') in classes_requested]
        train_rows = [r for r in train_rows if r.get('class') in classes_requested]

    # Modo binário: colapsar todas as doenças em "Disease"
    if is_binary:
        for r in main_rows:
            if r.get('final_class') != 'Healthy':
                r['final_class'] = 'Disease'
        for r in eval_rows:
            if r.get('label') != 'Healthy':
                r['label'] = 'Disease'
        for r in train_rows:
            if r.get('class') != 'Healthy':
                r['class'] = 'Disease'

    # Agrupar por classe
    main_by_class: dict[str, list] = {}
    for r in main_rows:
        cls = r.get('final_class') or 'unknown'
        main_by_class.setdefault(cls, []).append(r)

    train_by_class: dict[str, list] = {}
    for r in train_rows:
        cls = r.get('class') or 'unknown'
        train_by_class.setdefault(cls, []).append(r)

    # NOTA: hard_by_class agora é a amostra de AVALIAÇÃO (hard cases
    # confirmados + amostra representativa), nunca a de treino.
    hard_by_class: dict[str, list] = {}
    for r in eval_rows:
        cls = r.get('label') or 'unknown'
        hard_by_class.setdefault(cls, []).append(r)

    valid_classes = {}
    for k, v in main_by_class.items():
        # Só o ouro (train_dataset, triado manualmente) conta como prioridade
        # de treino. Hard cases NÃO: são rótulos automáticos de baixa
        # confiança ainda não triados e ficam reservados para avaliação
        # (ver hard_eval_dir abaixo), nunca para treino.
        num_train = len(train_by_class.get(k, []))

        # Apenas permite main_rows suficientes para atingir o max_images
        num_main_allowed = max(0, max_images - num_train)

        valid_classes[k] = v[:num_main_allowed]

        # O critério de "min_images" é baseado no TOTAL que vamos treinar
        if (len(valid_classes[k]) + num_train) < min_images:
            valid_classes.pop(k, None)

    if len(valid_classes) < 2:
        status_cb(
            state='error',
            message=(
                f'Apenas {len(valid_classes)} classe(s) com >= {min_images} imagens. '
                'Reduza o mínimo ou adicione mais imagens à BD.'
            ),
            finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'),
        )
        return

    final_classes = sorted(valid_classes.keys())
    status_cb(message=f'Classes: {final_classes}')

    # -----------------------------------------------------------------------
    # 2. Download de imagens
    # -----------------------------------------------------------------------
    tmp_root = Path(tempfile.mkdtemp(prefix='cnn_train_'))
    # Separar treino e validação EM PASTAS DISTINTAS antes de qualquer augmentação.
    # Isto evita data leakage: imagens augmentadas do treino não aparecem na validação.
    train_dir = tmp_root / 'train'
    val_dir   = tmp_root / 'val'
    # Conjunto de teste: nunca visto pela seleção de checkpoint (best_f1),
    # scheduler ou early-stopping — só o val_loader influencia esses três.
    # Sem isto, a avaliação final (classification_report, ROC/PR, erros
    # inseridos em manual_review) reutilizava o mesmo conjunto usado para
    # escolher o modelo, inflando artificialmente as curvas/métricas finais.
    test_dir  = tmp_root / 'test'
    # Hard cases NÃO triados (frames de baixa confiança, rótulo automático):
    # excluídos do treino (envenenariam o modelo com rótulos por verificar);
    # avaliados no fim para medir generalização nas imagens que deram
    # problemas ao modelo em produção. Cap para limitar tempo de download.
    hard_eval_dir = tmp_root / 'hard_eval'
    # Ouro (train_dataset) de classes raras, abaixo de min_images: sem
    # imagens suficientes para uma classe de treino, mas valiosas como teste
    # open-set (o modelo devia dizer "não sei" / Disease, nunca Healthy
    # confiante).
    openset_dir = tmp_root / 'openset'

    try:
        session = requests.Session()
        n_hard_eval = min(HARD_EVAL_CAP,
                          sum(len(v) for k, v in hard_by_class.items() if k in final_classes))
        n_openset = sum(len(v) for k, v in train_by_class.items() if k not in final_classes)
        total_urls = (
            sum(len(v) for v in valid_classes.values()) +
            sum(len(v) for k, v in train_by_class.items() if k in final_classes) +
            n_hard_eval + n_openset
        )
        local_images_dir = Path(__file__).parent.parent / 'apples_2026'
        local_images_dir.mkdir(parents=True, exist_ok=True)
        import urllib.parse
        
        # Mapear todos os ficheiros locais (suporta subpastas como 2026/05/...)
        local_files_map = {}
        for p in local_images_dir.rglob('*.*'):
            if p.is_file():
                local_files_map[p.name] = p
        
        def fetch_image(img_url, target_path):
            if not img_url:
                return False
            basename = urllib.parse.unquote(os.path.basename(urllib.parse.urlparse(img_url).path))
            if basename in local_files_map:
                try:
                    shutil.copy2(local_files_map[basename], target_path)
                    return True
                except Exception:
                    pass
            try:
                resp = session.get(img_url, timeout=15)
                if resp.status_code == 200:
                    target_path.write_bytes(resp.content)
                    if 'Apple/training' not in img_url:
                        cache_path = local_images_dir / basename
                        if not cache_path.exists():
                            try:
                                cache_path.write_bytes(resp.content)
                            except Exception:
                                pass
                    return True
            except Exception:
                pass
            return False

        downloaded = 0  # BUG FIX: inicializar antes do loop

        for cls in final_classes:
            if cancelled():
                status_cb(state='cancelled', message='Cancelado.',
                          finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'))
                return

            # Agrupar os items desta classe por MAÇÃ base (apple_id sem _copy/_crop_N).
        val_path_to_apple_info = {}
        test_path_to_apple_info = {}

        for cls in final_classes:
            # O split é feito por grupo, por isso nenhuma maçã — nem os duplicados/crops
            # derivados dela — aparece simultaneamente em treino e validação.
            groups: dict[str, list] = {}  # base_key -> list[(url, fname, is_dup, apple_id, source)]
            safe_cls = cls.lower().replace(' damage', '').replace(' ', '_')

            for idx, row in enumerate(valid_classes[cls]):
                url = row.get('frame_thumbnail') or ''
                apple_id = row.get('apple_id')
                groups.setdefault(f'main_{idx}', []).append(
                    (url, f'{safe_cls}_main_{idx:05d}.jpg', False, apple_id, 'main'))

            # NOTA: hard cases NÃO entram nos groups (nem em treino/val/test).
            # São descarregados à parte para hard_eval_dir mais abaixo.

            for idx, row in enumerate(train_by_class.get(cls, [])):
                aid = row.get('apple_id') or ''
                if not aid:
                    continue
                # base = apple_id sem os sufixos _copy / _crop_N
                base_id = aid.replace('_copy', '')
                if '_crop_' in base_id:
                    base_id = base_id.split('_crop_')[0]
                is_dup = aid.endswith('_copy')  # cópia peso-2: só faz sentido no treino
                url = row.get('crop_url')
                if not url:
                    url = row.get('original_url')
                    if not url:
                        url = f"{SUPABASE_URL}/storage/v1/object/public/Apple/training/{base_id}.jpg"
                groups.setdefault(f'al_{base_id}', []).append(
                    (url, f'{safe_cls}_active_learn_{idx:05d}.jpg', is_dup, aid, 'train'))

            # Split ao nível do grupo (70/15/15 train/val/test), determinístico.
            # Garantir que pelo menos 1 grupo fica em cada balde quando há
            # grupos suficientes — val continua a orientar a seleção do
            # checkpoint/scheduler/early-stopping; test fica de fora disso
            # por completo, só usado na avaliação final (ver mais abaixo).
            group_keys = list(groups.keys())
            _random.Random(42).shuffle(group_keys)
            n_groups = len(group_keys)
            if n_groups <= 1:
                n_val_groups = 0
                n_test_groups = 0
            elif n_groups == 2:
                n_val_groups = 1
                n_test_groups = 0
            else:
                n_val_groups = max(1, int(n_groups * 0.15))
                n_test_groups = max(1, int(n_groups * 0.15))
                # Garante pelo menos 1 grupo no treino.
                while n_val_groups + n_test_groups >= n_groups:
                    if n_test_groups > 1:
                        n_test_groups -= 1
                    elif n_val_groups > 1:
                        n_val_groups -= 1
                    else:
                        break
            val_keys = set(group_keys[:n_val_groups])
            test_keys = set(group_keys[n_val_groups:n_val_groups + n_test_groups])

            (train_dir / cls).mkdir(parents=True, exist_ok=True)
            (val_dir / cls).mkdir(parents=True, exist_ok=True)
            (test_dir / cls).mkdir(parents=True, exist_ok=True)

            for key in group_keys:
                to_val = key in val_keys
                to_test = key in test_keys
                for url, fname, is_dup, apple_id, source in groups[key]:
                    if (to_val or to_test) and is_dup:
                        continue  # não pôr duplicados exatos fora do treino
                    dest_dir = test_dir if to_test else (val_dir if to_val else train_dir)
                    dest_path = dest_dir / cls / fname
                    fetch_image(url, dest_path)
                    if to_val and apple_id:
                        val_path_to_apple_info[str(dest_path.absolute())] = {
                            "apple_id": apple_id,
                            "source": source,
                            "url": url
                        }
                    if to_test and apple_id:
                        test_path_to_apple_info[str(dest_path.absolute())] = {
                            "apple_id": apple_id,
                            "source": source,
                            "url": url
                        }

                    downloaded += 1
                    pct = 3 + int(downloaded / max(total_urls, 1) * 42)
                    status_cb(state='downloading', progress=pct,
                              message=f'A obter {downloaded}/{total_urls}: {cls}')

        # -------------------------------------------------------------------
        # 2b. Casos difíceis reais + amostra representativa de produção:
        # NUNCA entram no treino. Misturados no MESMO conjunto de avaliação
        # do teste normal (ver secção 6, mais abaixo) — não um gráfico à
        # parte: avaliar só o pior caso sobre-representava doenças fora do
        # vocabulário (Frost, Bitter Rot) e dava uma métrica isolada que não
        # dizia nada sobre generalização real. Rótulo é sempre classificação
        # automática (não triada), por isso o conjunto combinado ainda é
        # indicativo, não ground truth absoluto. Estrutura por classe para
        # ImageFolder; guarda também a confiança de captura e a origem de
        # cada imagem (hard_eval_confidences / hard_eval_path_to_info) para
        # a métrica de composição e para a matriz de erros A/B.
        # -------------------------------------------------------------------
        hard_eval_downloaded = 0
        hard_eval_confidences: dict[str, float] = {}
        hard_eval_path_to_info: dict[str, dict] = {}
        for cls in final_classes:
            if hard_eval_downloaded >= HARD_EVAL_CAP:
                break
            rows_h = hard_by_class.get(cls, [])
            if not rows_h:
                continue
            safe_cls = cls.lower().replace(' damage', '').replace(' ', '_')
            (hard_eval_dir / cls).mkdir(parents=True, exist_ok=True)
            for idx, row in enumerate(rows_h):
                if hard_eval_downloaded >= HARD_EVAL_CAP:
                    break
                url = row.get('image_url') or ''
                dest = hard_eval_dir / cls / f'{safe_cls}_hardeval_{idx:05d}.jpg'
                if fetch_image(url, dest):
                    hard_eval_downloaded += 1
                    conf = row.get('confidence')
                    if conf is not None:
                        hard_eval_confidences[str(dest.absolute())] = float(conf)
                    apple_id = row.get('apple_id')
                    if apple_id:
                        hard_eval_path_to_info[str(dest.absolute())] = {
                            'apple_id': apple_id,
                            'source': row.get('source', 'hard'),
                            'url': url,
                        }
                downloaded += 1
                pct = 3 + int(downloaded / max(total_urls, 1) * 42)
                status_cb(state='downloading', progress=pct,
                          message=f'A obter {downloaded}/{total_urls} (avaliação difícil)')

        # -------------------------------------------------------------------
        # 2c. Ouro de classes raras (fora de final_classes) para teste
        # OPEN-SET: triadas manualmente mas com poucas imagens para treinar
        # (ex.: Frost com 1-3). Pasta plana; o rótulo verdadeiro vai no nome.
        # -------------------------------------------------------------------
        openset_files: list[tuple] = []  # (path, true_class)
        for cls, rows_t in train_by_class.items():
            if cls in final_classes:
                continue
            safe_cls = cls.lower().replace(' damage', '').replace(' ', '_')
            openset_dir.mkdir(parents=True, exist_ok=True)
            for idx, row in enumerate(rows_t):
                aid = row.get('apple_id') or ''
                if not aid or aid.endswith('_copy'):
                    continue  # duplicados de peso não interessam para teste
                base_id = aid.split('_crop_')[0].replace('_copy', '')
                url = row.get('crop_url') or row.get('original_url') or \
                    f"{SUPABASE_URL}/storage/v1/object/public/Apple/training/{base_id}.jpg"
                dest = openset_dir / f'{safe_cls}_{idx:05d}.jpg'
                if fetch_image(url, dest):
                    openset_files.append((dest, cls))
                downloaded += 1
                pct = 3 + int(downloaded / max(total_urls, 1) * 42)
                status_cb(state='downloading', progress=pct,
                          message=f'A obter {downloaded}/{total_urls} (open-set)')

        # -----------------------------------------------------------------------
        # 3. Contagem de imagens reais no disco (sem augmentação offline)
        # -----------------------------------------------------------------------
        status_cb(state='augmenting', progress=46, message='A contabilizar classes...')

        class_counts: dict[str, int] = {
            cls: len(list((train_dir / cls).glob('*.jpg'))) for cls in final_classes
        }
        total_images = sum(class_counts.values()) + sum(
            len(list((val_dir / cls).glob('*.jpg'))) for cls in final_classes
        ) + sum(
            len(list((test_dir / cls).glob('*.jpg'))) for cls in final_classes
        )
        status_cb(message=f'Imagens reais por classe (treino): {class_counts}')

        # -----------------------------------------------------------------------
        # 4. DataLoaders com WeightedRandomSampler (balanceamento em memória)
        # -----------------------------------------------------------------------
        status_cb(state='training', progress=52, message='A criar DataLoader...')

        train_tf = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.RandomHorizontalFlip(),
            transforms.RandomVerticalFlip(),
            transforms.RandomRotation(180),
            transforms.GaussianBlur(kernel_size=(3, 3), sigma=(0.1, 0.3)),
            transforms.RandomAdjustSharpness(sharpness_factor=2, p=0.5),
            transforms.ColorJitter(brightness=0.4, contrast=0.4, saturation=0.2, hue=0.05),
            transforms.ToTensor(),
            transforms.RandomErasing(p=0.2, scale=(0.02, 0.05)),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
        ])
        val_tf = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
        ])

        train_ds = datasets.ImageFolder(str(train_dir), transform=train_tf)
        val_ds   = datasets.ImageFolder(str(val_dir),   transform=val_tf)
        folder_classes = train_ds.classes  # ordem alfabética = índices do modelo

        train_size = len(train_ds)
        val_size   = len(val_ds)
        if train_size < batch_size:
            status_cb(state='error', message='Imagens insuficientes para treino.',
                      finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'))
            return
        if val_size == 0:
            status_cb(state='error', message='Conjunto de validação vazio. Adicione mais maçãs.',
                      finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'))
            return
        if train_ds.classes != val_ds.classes:
            status_cb(state='error',
                      message=f'Mismatch de classes treino/val: {train_ds.classes} vs {val_ds.classes}',
                      finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'))
            return

        # Conjunto de teste (ver comentário junto a test_dir acima): pode
        # ficar vazio em datasets pequenos (poucos grupos por classe para
        # reservar 15%) — nesse caso cai-se de volta para o val_loader na
        # avaliação final, em vez de rebentar o treino. `using_held_out_test`
        # fica gravado em meta para se saber, a olhar para o modelo depois,
        # se a ROC/relatório final são de um conjunto honesto ou não.
        test_size = sum(len(list((test_dir / c).glob('*.jpg'))) for c in final_classes)
        test_ds = None
        if test_size > 0:
            candidate = datasets.ImageFolder(str(test_dir), transform=val_tf)
            if candidate.classes == train_ds.classes:
                test_ds = candidate
            else:
                status_cb(message='Aviso: mismatch de classes treino/teste, avaliação final cai para o val_loader.')
        using_held_out_test = test_ds is not None
        if not using_held_out_test:
            status_cb(message='Teste insuficiente para um conjunto próprio: avaliação final usa o val_loader (menos honesto, mas não bloqueia o treino).')

        # WeightedRandomSampler: cada amostra recebe peso inverso ao tamanho da sua classe.
        # Isto faz com que o DataLoader puxe imagens das classes raras com muito mais frequência,
        # sem criar ficheiros falsos no disco. O número de amostras por época = num_classes * max_images
        # (limitado ao máximo configurado), garantindo que nenhuma classe domina.
        from torch.utils.data import WeightedRandomSampler
        targets = train_ds.targets  # lista de índices de classe para cada imagem
        class_sample_counts = [0] * len(folder_classes)
        for t in targets:
            class_sample_counts[t] += 1
        # peso por amostra = 1 / count da sua classe; imagens OURO (triadas
        # manualmente, ficheiros 'active_learn') recebem um multiplicador
        # extra — rótulo verificado por humano vale mais do que um rótulo
        # automático. Combinado com a duplicação _copy existente, o ouro tem
        # ~4x a presença de uma imagem normal (2x cópia × 2x boost).
        gold_boost = float(config.get('gold_boost', 2.0))
        sample_weights = []
        n_gold_train = 0
        for i, t in enumerate(targets):
            w = 1.0 / class_sample_counts[t]
            if 'active_learn' in os.path.basename(train_ds.samples[i][0]):
                w *= gold_boost
                n_gold_train += 1
            sample_weights.append(w)
        if n_gold_train:
            status_cb(message=f'{n_gold_train} imagens ouro no treino (boost x{gold_boost:g} no sampler)')
        # Total de draws por época: min(max_images, count_real) por classe × nº de classes
        target_per_class = min(max_images, max(class_sample_counts))
        num_samples = target_per_class * len(folder_classes)
        sampler = WeightedRandomSampler(
            weights=sample_weights,
            num_samples=num_samples,
            replacement=True,
        )
        status_cb(message=(
            f'WeightedRandomSampler: {target_per_class} amostras/classe × '
            f'{len(folder_classes)} classes = {num_samples} draws/época'
        ))

        train_loader = DataLoader(train_ds, batch_size=batch_size, sampler=sampler, num_workers=0)
        val_loader   = DataLoader(val_ds,   batch_size=batch_size, shuffle=False,  num_workers=0)
        # Avaliação final (classification_report, ROC/PR, misclassified_samples)
        # corre sobre eval_loader — test_loader quando há dados suficientes
        # (using_held_out_test=True), senão cai para o próprio val_loader.
        eval_loader = DataLoader(test_ds, batch_size=batch_size, shuffle=False, num_workers=0) if using_held_out_test else val_loader
        eval_ds = test_ds if using_held_out_test else val_ds
        eval_path_to_apple_info = test_path_to_apple_info if using_held_out_test else val_path_to_apple_info

        num_classes = len(folder_classes)
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        status_cb(message=f'Device: {device} | {num_classes} classes | Treino real: {train_size} | Val: {val_size}')

        # -----------------------------------------------------------------------
        # 5. Modelo
        # -----------------------------------------------------------------------
        if architecture == 'resnet50':
            model = tv_models.resnet50(weights='IMAGENET1K_V2')
            for param in model.parameters():
                param.requires_grad = False
            for param in model.layer3.parameters():
                param.requires_grad = True
            for param in model.layer4.parameters():
                param.requires_grad = True
            model.fc = nn.Sequential(
                nn.Dropout(p=0.5), 
                nn.Linear(model.fc.in_features, num_classes)
            )
        else:
            model = tv_models.mobilenet_v2(weights='IMAGENET1K_V1')
            for param in model.parameters():
                param.requires_grad = True
            model.classifier[1] = nn.Linear(model.last_channel, num_classes)

        model = model.to(device)
        criterion = nn.CrossEntropyLoss()
        optimizer = optim.Adam(
            filter(lambda p: p.requires_grad, model.parameters()), 
            lr=lr, 
            weight_decay=1e-4
        )
        scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=2)

        # -----------------------------------------------------------------------
        # 6. Loop de treino com métricas completas
        # -----------------------------------------------------------------------
        best_val_acc = 0.0
        best_f1 = 0.0
        best_state = None
        best_val_loss = float("inf")
        patience = 5
        patience_counter = 0
        history = []

        for epoch in range(epochs):
            if cancelled():
                status_cb(state='cancelled', message='Cancelado.',
                          finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'))
                return

            # --- Treino ---
            model.train()
            running_loss, correct, n = 0.0, 0, 0
            for inputs, labels in train_loader:
                if cancelled():
                    break
                inputs, labels = inputs.to(device), labels.to(device)
                optimizer.zero_grad()
                out = model(inputs)
                loss = criterion(out, labels)
                loss.backward()
                optimizer.step()
                running_loss += loss.item() * inputs.size(0)
                correct += out.argmax(1).eq(labels).sum().item()
                n += inputs.size(0)

            train_acc = correct / n if n > 0 else 0.0
            train_loss = running_loss / n if n > 0 else 0.0

            # --- Validação com métricas completas ---
            model.eval()
            all_preds, all_labels = [], []
            val_loss_sum, val_n = 0.0, 0
            with torch.no_grad():
                for inputs, labels in val_loader:
                    inputs, labels = inputs.to(device), labels.to(device)
                    out = model(inputs)
                    loss = criterion(out, labels)
                    val_loss_sum += loss.item() * inputs.size(0)
                    val_n += inputs.size(0)
                    all_preds.extend(out.argmax(1).cpu().tolist())
                    all_labels.extend(labels.tolist())

            val_loss = val_loss_sum / val_n if val_n > 0 else 0.0
            val_acc = sum(p == l for p, l in zip(all_preds, all_labels)) / len(all_labels) if all_labels else 0.0
            
            scheduler.step(val_loss)

            label_range = list(range(num_classes))

            f1_w       = float(f1_score(all_labels, all_preds, average='weighted', zero_division=0, labels=label_range))
            precision_w = float(precision_score(all_labels, all_preds, average='weighted', zero_division=0, labels=label_range))
            recall_w    = float(recall_score(all_labels, all_preds, average='weighted', zero_division=0, labels=label_range))
            per_class_f1 = f1_score(all_labels, all_preds, average=None, zero_division=0, labels=label_range).tolist()
            per_class_prec = precision_score(all_labels, all_preds, average=None, zero_division=0, labels=label_range).tolist()
            per_class_rec  = recall_score(all_labels, all_preds, average=None, zero_division=0, labels=label_range).tolist()
            conf_mat = confusion_matrix(all_labels, all_preds, labels=label_range).tolist()

            entry = {
                'epoch': epoch + 1,
                'train_acc': round(train_acc * 100, 1),
                'val_acc': round(val_acc * 100, 1),
                'loss': round(train_loss, 4),
                'f1': round(f1_w, 4),
                'precision': round(precision_w, 4),
                'recall': round(recall_w, 4),
                'per_class_f1': [round(x, 4) for x in per_class_f1],
                'per_class_precision': [round(x, 4) for x in per_class_prec],
                'per_class_recall': [round(x, 4) for x in per_class_rec],
                'confusion_matrix': conf_mat,
            }
            history.append(entry)

            progress = 52 + int((epoch + 1) / epochs * 42)
            status_cb(
                state='training',
                progress=progress,
                epoch=epoch + 1,
                epochs=epochs,
                train_acc=round(train_acc * 100, 1),
                val_acc=round(val_acc * 100, 1),
                loss=round(train_loss, 4),
                f1=round(f1_w * 100, 1),
                precision=round(precision_w * 100, 1),
                recall=round(recall_w * 100, 1),
                per_class_f1={folder_classes[i]: round(per_class_f1[i] * 100, 1) for i in range(num_classes)},
                per_class_precision={folder_classes[i]: round(per_class_prec[i] * 100, 1) for i in range(num_classes)},
                per_class_recall={folder_classes[i]: round(per_class_rec[i] * 100, 1) for i in range(num_classes)},
                confusion_matrix=conf_mat,
                classes=folder_classes,
                # Série completa de épocas até agora: /status espalha o dict
                # inteiro, por isso o gráfico live do dashboard recebe a curva
                # toda a cada poll (sem WebSocket novo).
                history=history,
                message=(
                    f'Época {epoch + 1}/{epochs}: '
                    f'Acc {val_acc:.1%}  F1 {f1_w:.1%}  '
                    f'P {precision_w:.1%}  R {recall_w:.1%}  Loss {train_loss:.4f}'
                ),
            )

            # Guardar melhor modelo (por F1 weighted, não só accuracy)
            if f1_w > best_f1:
                best_f1 = f1_w
                best_val_acc = val_acc
                best_state = copy.deepcopy(model.state_dict())

            # Early Stopping baseado no val_loss (idêntico ao CNN2.py)
            if val_loss < best_val_loss:
                best_val_loss = val_loss
                patience_counter = 0
            else:
                patience_counter += 1

            if patience_counter >= patience:
                status_cb(message=f'Early stopping disparou na época {epoch + 1}. A validação parou de melhorar.')
                break

        # Guarda para o caso de não ter corrido nenhuma época (cancelamento imediato)
        if best_state is None:
            status_cb(state='cancelled', message='Treino cancelado sem completar nenhuma época.',
                      finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'))
            return

        # Final report e curvas usando o MELHOR MODELO (não o último epoch),
        # avaliado em eval_loader — o conjunto de teste nunca visto pela
        # seleção de checkpoint, quando existir dados suficientes para isso
        # (using_held_out_test); ver definição de eval_loader mais acima.
        model.load_state_dict(best_state)
        model.eval()
        best_preds, best_labels = [], []
        with torch.no_grad():
            for inputs, labels in eval_loader:
                inputs, labels = inputs.to(device), labels.to(device)
                out = model(inputs)
                best_preds.extend(out.argmax(1).cpu().tolist())
                best_labels.extend(labels.tolist())

        # --- Casos difíceis reais + amostra representativa (secção 2b):
        # avaliados AQUI, misturados com o conjunto de teste normal, não num
        # gráfico à parte. "Pegar em tudo o que nunca foi usado no treino"
        # (teste + hard + produção) dá uma única medida de generalização
        # mais honesta do que isolar só o pior caso. ---
        hard_ds = None
        hard_true: list[int] = []
        hard_preds: list[int] = []
        hard_probs: list[list[float]] = []
        try:
            if hard_eval_dir.exists() and any(hard_eval_dir.rglob('*.jpg')):
                hard_ds_candidate = datasets.ImageFolder(str(hard_eval_dir), transform=val_tf)
                if len(hard_ds_candidate) > 0 and all(c in folder_classes for c in hard_ds_candidate.classes):
                    hard_ds = hard_ds_candidate
                    # Reindexar rótulos locais do ImageFolder para os índices
                    # do vocabulário do modelo (folder_classes).
                    local_to_model = [folder_classes.index(c) for c in hard_ds.classes]
                    hard_true = [local_to_model[t] for t in hard_ds.targets]
                    hard_loader = DataLoader(hard_ds, batch_size=batch_size, shuffle=False, num_workers=0)
                    with torch.no_grad():
                        for inputs, _ in hard_loader:
                            inputs = inputs.to(device)
                            probs = F_inner.softmax(model(inputs), dim=1)
                            hard_probs.extend(probs.cpu().tolist())
                            hard_preds.extend(probs.argmax(dim=1).cpu().tolist())
        except Exception as e:
            status_cb(message=f'Casos difíceis/produção falharam a carregar (ignorado): {e}')
            hard_ds, hard_true, hard_preds, hard_probs = None, [], [], []

        # Conjunto combinado: teste normal + hard + produção, na mesma ordem
        # em que cada bloco foi avaliado acima (necessário para alinhar com
        # y_probs mais abaixo).
        combined_labels = best_labels + hard_true
        combined_preds  = best_preds + hard_preds
        combined_samples = list(eval_ds.samples) + (list(hard_ds.samples) if hard_ds is not None else [])
        combined_path_to_info = {**eval_path_to_apple_info, **hard_eval_path_to_info}

        # --- Registo por imagem dos erros de avaliação (para a matriz de
        # comparação A/B no MLOps) + inserção na triagem manual (baixa
        # urgência) ---
        from supabase import create_client
        sb = create_client(SUPABASE_URL, SUPABASE_KEY)
        now_iso = time.strftime('%Y-%m-%dT%H:%M:%S')

        erros_triagem = 0
        erros_treino_reforco = 0
        misclassified_samples: list[dict] = []
        for i, (real_idx, pred_idx) in enumerate(zip(combined_labels, combined_preds)):
            if real_idx != pred_idx:
                path, _ = combined_samples[i]
                info = combined_path_to_info.get(str(Path(path).absolute()))
                if info:
                    apple_id = info["apple_id"]
                    source = info["source"]
                    url = info["url"]

                    misclassified_samples.append({
                        "apple_id": apple_id,
                        "true_class": folder_classes[real_idx],
                        "predicted_class": folder_classes[pred_idx],
                        "source": source,
                        "url": url,
                    })

                    if source == 'train':
                        # A imagem já passou por triagem manual (é de alta confiança humana). 
                        # Vamos duplicar no dataset para reforçar o treino na próxima vez.
                        try:
                            # Tentar extrair o base_id limpo
                            base_id = apple_id.replace('_copy', '')
                            if '_crop_' in base_id:
                                base_id = base_id.split('_crop_')[0]
                            
                            novo_id = f"{base_id}_copy_{int(time.time()*1000)}"
                            sb.table('train_dataset').insert({
                                "apple_id": novo_id,
                                "original_url": url,
                                "crop_url": url,
                                "class": folder_classes[real_idx],
                                "reviewed_at": now_iso
                            }).execute()
                            erros_treino_reforco += 1
                        except Exception as e:
                            print(f"Erro ao duplicar treino para {apple_id}: {e}")
                            
                    else:
                        try:
                            sb.table('manual_review').insert({
                                "apple_id": apple_id,
                                "updated_at": now_iso,
                                "original_class": folder_classes[real_idx],
                                "original_confidence": 100, # Baixa urgência na lista
                                "status": "pending"
                            }).execute()
                            erros_triagem += 1
                        except Exception:
                            pass # Pode já existir
                        
        mensagens_final = []
        if erros_triagem > 0:
            mensagens_final.append(f'{erros_triagem} p/ triagem')
        if erros_treino_reforco > 0:
            mensagens_final.append(f'{erros_treino_reforco} p/ treino extra')
        if mensagens_final:
            status_cb(message=" | ".join(mensagens_final))

        # Classification report final (do melhor modelo), sobre o conjunto
        # COMBINADO (teste normal + hard + produção nunca usados no treino).
        final_report = classification_report(
            combined_labels, combined_preds,
            target_names=folder_classes,
            output_dict=True,
            zero_division=0,
        )

        # -----------------------------------------------------------------------
        # 6b. Curvas ROC e Precision-Recall (probabilidades do melhor modelo)
        # -----------------------------------------------------------------------
        # model já tem best_state carregado (feito acima). Mesmo eval_loader
        # do relatório final acima — nunca o val_loader que escolheu o
        # checkpoint, quando using_held_out_test é True.
        all_probs_np: list[list[float]] = []
        with torch.no_grad():
            for inputs, _ in eval_loader:
                inputs = inputs.to(device)
                out = model(inputs)
                probs = F_inner.softmax(out, dim=1).cpu().tolist()
                all_probs_np.extend(probs)

        # Combinado com as probabilidades dos casos difíceis/produção (mesma
        # ordem de combined_labels: teste primeiro, depois hard/produção).
        y_true_np  = np.array(combined_labels)
        y_probs_np = np.array(all_probs_np + hard_probs)  # shape (N, num_classes)

        healthy_idx = folder_classes.index('Healthy') if 'Healthy' in folder_classes else None

        def _add_curve(roc_dst: dict, pr_dst: dict, cls_name: str, y_true_i, y_score_i):
            # ROC
            try:
                fpr, tpr, _ = roc_curve(y_true_i, y_score_i)
                roc_auc = auc(fpr, tpr)
                # Decimação para não exceder 200 pontos por classe
                step = max(1, len(fpr) // 200)
                roc_dst[cls_name] = {
                    'fpr':     fpr[::step].tolist(),
                    'tpr':     tpr[::step].tolist(),
                    'auc':     round(float(roc_auc), 4),
                }
            except Exception:
                pass

            # Precision-Recall
            try:
                prec_c, rec_c, _ = precision_recall_curve(y_true_i, y_score_i)
                pr_auc = auc(rec_c, prec_c)
                step = max(1, len(prec_c) // 200)
                pr_dst[cls_name] = {
                    'precision': prec_c[::step].tolist(),
                    'recall':    rec_c[::step].tolist(),
                    'auc':       round(float(pr_auc), 4),
                }
            except Exception:
                pass

        def _build_curves(y_true_sub, y_probs_sub, roc_dst: dict, pr_dst: dict):
            """Gera curvas ROC/PR para um (sub)conjunto de avaliação, com as
            mesmas regras nos dois casos: binário guarda só 'Disease' (a curva
            de 'Healthy' seria o espelho exato); multiclasse guarda as classes
            individuais + a agregada 'Disease' (1-P(Healthy)) para permitir
            comparação direta com um CNN2 binário."""
            if len(y_true_sub) == 0:
                return
            if is_binary and num_classes == 2 and healthy_idx is not None:
                disease_idx = 1 - healthy_idx
                _add_curve(roc_dst, pr_dst, 'Disease',
                           (y_true_sub == disease_idx).astype(int), y_probs_sub[:, disease_idx])
            else:
                y_bin_sub = label_binarize(y_true_sub, classes=list(range(num_classes)))
                for i, cls_name in enumerate(folder_classes):
                    y_true_i = y_bin_sub[:, i] if num_classes > 2 else (y_true_sub == i).astype(int)
                    _add_curve(roc_dst, pr_dst, cls_name, y_true_i, y_probs_sub[:, i])

                if not is_binary and healthy_idx is not None and num_classes > 2:
                    y_true_disease = (y_true_sub != healthy_idx).astype(int)
                    y_score_disease = 1.0 - y_probs_sub[:, healthy_idx]
                    _add_curve(roc_dst, pr_dst, 'Disease', y_true_disease, y_score_disease)

        roc_curves_data: dict = {}
        pr_curves_data:  dict = {}
        _build_curves(y_true_np, y_probs_np, roc_curves_data, pr_curves_data)

        # -------------------------------------------------------------------
        # 6c. Composição da avaliação: quanto do conjunto combinado acima
        # (teste normal + hard + produção) veio de cada origem, e que fração
        # dos casos hard/produção já era ambígua na própria captura (conf
        # <80%). Não é uma curva à parte — é só contexto para interpretar o
        # ÚNICO accuracy/F1/AUC final: um valor mais baixo pode refletir uma
        # amostra genuinamente mais difícil, não um modelo pior.
        # -------------------------------------------------------------------
        orig_confs = [hard_eval_confidences.get(p) for p, _ in (hard_ds.samples if hard_ds is not None else [])]
        known_confs = [c for c in orig_confs if c is not None]
        pct_low_conf = (
            round(sum(1 for c in known_confs if c < 0.80) / len(known_confs) * 100, 1)
            if known_confs else None
        )
        eval_composition = {
            'test_count': len(best_labels),
            'hard_mixed_count': len(hard_true),
            # None se nenhuma imagem hard/produção tinha confiança registada.
            'pct_low_confidence_in_mixed': pct_low_conf,
        }
        if hard_true:
            status_cb(message=(
                f'Avaliação combinada: {len(best_labels)} teste + {len(hard_true)} hard/produção'
                + (f' ({pct_low_conf}% destas já era ambígua na captura)' if pct_low_conf is not None else '')))

        # -------------------------------------------------------------------
        # 6d. Teste OPEN-SET: ouro de classes raras fora do vocabulário
        # (ex.: Frost triado com 1-3 imagens). O melhor resultado é o modelo
        # NÃO ter confiança (iria para triagem/auto-"Outros"); o pior é
        # classificar Healthy com confiança alta.
        # -------------------------------------------------------------------
        open_set_eval: dict = {}
        try:
            if openset_files:
                accept_thr = 0.80
                os_per_class: dict[str, int] = {}
                os_confs: list[float] = []
                n_conf_healthy = 0
                n_below_accept = 0
                n_pred_disease = 0
                healthy_model_idx = folder_classes.index('Healthy') if 'Healthy' in folder_classes else None
                with torch.no_grad():
                    for fpath, true_cls in openset_files:
                        try:
                            img = Image.open(fpath).convert('RGB')
                        except Exception:
                            continue
                        x = val_tf(img).unsqueeze(0).to(device)
                        probs = F_inner.softmax(model(x), dim=1)[0]
                        conf, pred_idx = float(probs.max()), int(probs.argmax())
                        os_per_class[true_cls] = os_per_class.get(true_cls, 0) + 1
                        os_confs.append(conf)
                        if conf < accept_thr:
                            n_below_accept += 1
                        if healthy_model_idx is not None:
                            if pred_idx == healthy_model_idx and conf >= accept_thr:
                                n_conf_healthy += 1
                            if pred_idx != healthy_model_idx:
                                n_pred_disease += 1
                n_os = len(os_confs)
                if n_os > 0:
                    open_set_eval = {
                        'count': n_os,
                        'per_class': os_per_class,
                        'avg_top1_conf': round(sum(os_confs) / n_os * 100, 1),
                        # Bom: o modelo hesita e a maçã iria para triagem/"Outros"
                        'pct_below_accept': round(n_below_accept / n_os * 100, 1),
                        # Mau: Healthy confiante numa patologia desconhecida
                        'pct_confident_healthy': round(n_conf_healthy / n_os * 100, 1),
                        # Para binário: Frost e afins DEVEM cair em Disease
                        'pct_predicted_disease': round(n_pred_disease / n_os * 100, 1),
                    }
                    status_cb(message=(
                        f'Open-set ({n_os} imagens ouro de classes raras): '
                        f'{open_set_eval["pct_below_accept"]}% iriam a triagem, '
                        f'{open_set_eval["pct_confident_healthy"]}% Healthy confiante (mau)'))
        except Exception as e:
            status_cb(message=f'Teste open-set falhou (ignorado): {e}')

        # -----------------------------------------------------------------------
        # 7. Guardar modelo
        # -----------------------------------------------------------------------
        if cancelled():
            status_cb(state='cancelled', message='Cancelado antes de guardar.',
                      finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'))
            return

        status_cb(state='saving', progress=95, message='A guardar modelo...')

        MODELS_DIR.mkdir(exist_ok=True)
        ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        mode_tag = 'bin' if is_binary else 'multi'
        acc_str = f'{best_val_acc * 100:.0f}'
        f1_str  = f'{best_f1 * 100:.0f}'
        model_name = f'cnn_{mode_tag}_{architecture}_{num_classes}cls_acc{acc_str}_f1{f1_str}_{ts}.pth'
        model_path = MODELS_DIR / model_name

        # best_state já está carregado no model (foi feito para o final_report)
        torch.save(model.state_dict(), model_path)

        meta = {
            'created_at': datetime.datetime.now().isoformat(),
            'architecture': architecture,
            'is_binary': is_binary,
            'classes': folder_classes,
            'num_classes': num_classes,
            'val_accuracy': round(best_val_acc * 100, 1),
            'best_f1': round(best_f1 * 100, 1),
            'total_images': total_images,
            'train_images': train_size,
            'val_images': val_size,
            'test_images': len(eval_ds) if using_held_out_test else 0,
            # False quando o dataset era pequeno demais para reservar um
            # conjunto de teste próprio — nesse caso o relatório/ROC/PR acima
            # foram avaliados no val_loader (menos honesto, ver comentário
            # junto a test_dir). Consultar antes de citar a AUC numa tese.
            'using_held_out_test': using_held_out_test,
            'epochs': epochs,
            'lr': lr,
            'hard_threshold': hard_threshold,
            'class_counts': class_counts,
            'history': history,
            'final_report': final_report,
            # roc_curves/pr_curves/final_report já incluem os casos difíceis
            # reais + amostra representativa de produção (nunca usados no
            # treino), misturados com o teste normal num ÚNICO conjunto de
            # avaliação — ver eval_composition para a composição exata.
            'roc_curves': roc_curves_data,
            'pr_curves':  pr_curves_data,
            'eval_composition': eval_composition,
            # Ouro (train_dataset) usado no treino + teste open-set das
            # classes raras que ficaram fora do vocabulário.
            'gold_boost': gold_boost,
            'gold_train_images': n_gold_train,
            'open_set_eval': open_set_eval,
            # Uma linha por imagem mal classificada na avaliação final —
            # apple_id, classe real, classe prevista errada — para a matriz
            # de comparação A/B no MLOps (ver mlops_dashboard.dart).
            'misclassified_samples': misclassified_samples,
        }
        with open(model_path.with_suffix('.json'), 'w', encoding='utf-8') as f:
            json.dump(meta, f, indent=2)

        status_cb(
            state='done',
            progress=100,
            message=f'Modelo guardado: {model_name}  (Acc: {best_val_acc:.1%}  F1: {best_f1:.1%})',
            model_path=str(model_path),
            metrics={
                'val_accuracy': round(best_val_acc * 100, 1),
                'best_f1': round(best_f1 * 100, 1),
                'class_counts': class_counts,
                'history': history,
                'final_report': final_report,
                'classes': folder_classes,
            },
            finished_at=time.strftime('%Y-%m-%dT%H:%M:%S'),
        )

    finally:
        try:
            shutil.rmtree(tmp_root, ignore_errors=True)
        except Exception:
            pass
