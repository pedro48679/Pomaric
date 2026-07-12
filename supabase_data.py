import argparse
import os
import random
import sys
import datetime
import uuid
import cv2
import numpy as np
from supabase import create_client, Client
import torch
import torch.nn as nn
from torchvision import models, transforms
import torch.nn.functional as F
from PIL import Image

# ==========================================
# CONFIGURACOES DO SUPABASE
# ==========================================
SUPABASE_URL = "https://ypbqdeivphxerxgahxrd.supabase.co"
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")

if not SUPABASE_KEY:
    sys.exit(
        "ERRO: define a variavel de ambiente SUPABASE_SERVICE_KEY com a tua "
        "service_role key do projeto ypbqdeivphxerxgahxrd antes de correr "
        "este script."
    )

# ==========================================
# INICIALIZAR CLIENTE
# ==========================================
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Lista de doencas possiveis (cnn5)
DISEASES = ['Healthy', 'Rot', 'Scab', 'Blotch', 'Anthracnose']

# Confianca minima para gravar uma linha em cnn5_multi_confidence (multi-confianca
# por maca). Abaixo disto o valor e ruido de softmax, nao sinal util.
MIN_CLASS_SCORE = 0.05

# Bandas de confianca do veredito de doenca da CNN5 (so se final_disease != 'Healthy').
AUTO_ACCEPT_THRESHOLD = 0.85    # >= isto: aceite automaticamente, nome = doenca
REVIEW_QUEUE_THRESHOLD = 0.80   # < isto: entra sempre na fila de revisao (banda "pending")
AUDIT_SAMPLE_RATE = 0.05        # entre REVIEW_QUEUE_THRESHOLD e AUTO_ACCEPT_THRESHOLD: amostra aleatoria que tambem entra na fila (auditoria de qualidade)
AUTO_OUTROS_THRESHOLD = 0.30    # <  isto: perto do acaso (baseline ~20%/5 classes) -> "Incerta"

# Nome do bucket de Storage que criaste no Supabase
BUCKET_NAME = "Apple"

# Subpasta dentro do bucket para esta corrida. None => raiz do bucket (comportamento
# antigo, Apple/{ano}/...). "different" => Apple/different/{ano}/... (separacao opcional
# para poder tratar estas macas a parte no futuro; por defeito usa-se na mesma).
STORAGE_SUBFOLDER = "different"

# Pasta onde estao as imagens das tuas macas
LOCAL_IMAGES_DIR = "./data/local_apples"  # ajusta para a pasta local com as tuas imagens

# Qualidade JPEG usada ao gravar o Grad-CAM (sobreposta pelo --jpeg-quality do CLI)
JPEG_QUALITY = 85

# ==========================================
# INICIALIZAR PYTORCH (CNN2 e CNN5)
# ==========================================
print("A carregar Modelos PyTorch...")
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# Carregar CNN2 (Binario: Healthy vs Disease) - MobileNetV2
cnn2 = models.mobilenet_v2(weights=None)
cnn2.classifier[1] = nn.Linear(cnn2.last_channel, 2)
cnn2.load_state_dict(torch.load("melhor_modelo82_32.pth", map_location=device, weights_only=True))
cnn2 = cnn2.to(device)
cnn2.eval()

# Carregar CNN5 (Multi-classe) - ResNet50
cnn5 = models.resnet50(weights=None)
cnn5.fc = nn.Sequential(
    nn.Dropout(p=0.5),
    nn.Linear(cnn5.fc.in_features, 5)
)
cnn5.load_state_dict(torch.load("melhor_weight_multiclass_RESnet50_BEST.pth", map_location=device, weights_only=True))
cnn5 = cnn5.to(device)
cnn5.eval()

# Transform
transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
])


def run_cnn2(image_path):
    img = Image.open(image_path).convert("RGB")
    tensor = transform(img).unsqueeze(0).to(device)
    with torch.no_grad():
        out2 = cnn2(tensor)
        prob2 = F.softmax(out2, dim=1)[0]
        conf2, pred2 = torch.max(prob2, dim=0)
        lbl2 = 'Healthy' if pred2.item() == 0 else 'Disease'
        return lbl2, conf2.item(), prob2[0].item()  # Retorna label, conf e prob_healthy


import tempfile


def run_cnn5_with_gradcam(image_path, save_gradcam_path):
    img = Image.open(image_path).convert("RGB")
    tensor = transform(img).unsqueeze(0).to(device)
    tensor.requires_grad_(True)

    gradcam_data = {'activations': None, 'gradients': None}

    def save_act(module, input, output): gradcam_data['activations'] = output

    def save_grad(module, grad_input, grad_output): gradcam_data['gradients'] = grad_output[0]

    target_layer = cnn5.layer4
    handle_act = target_layer.register_forward_hook(save_act)
    handle_grad = target_layer.register_full_backward_hook(save_grad)

    out5 = cnn5(tensor)
    prob5 = F.softmax(out5, dim=1)[0]
    conf5, pred5 = torch.max(prob5, dim=0)

    cnn5_classes = {0: 'Anthracnose', 1: 'Blotch', 2: 'Healthy', 3: 'Rot', 4: 'Scab'}
    lbl5 = cnn5_classes[pred5.item()]
    probs5 = {cnn5_classes[idx]: prob5[idx].item() for idx in cnn5_classes}

    # Backward Pass para Grad-CAM
    cnn5.zero_grad()
    out5[0, pred5.item()].backward()

    # Garantir que temos gradientes e ativacoes
    if gradcam_data['gradients'] is None or gradcam_data['activations'] is None:
        print("Aviso: Falha ao capturar Grad-CAM hooks.")
        img.resize((224, 224)).save(save_gradcam_path, quality=JPEG_QUALITY)
    else:
        gradients = gradcam_data['gradients'][0].cpu().numpy()
        activations_cam = gradcam_data['activations'][0].cpu().detach().numpy()
        pooled_gradients = np.mean(gradients, axis=(1, 2))
        for i in range(activations_cam.shape[0]):
            activations_cam[i, :, :] *= pooled_gradients[i]

        heatmap = np.mean(activations_cam, axis=0)
        heatmap = np.maximum(heatmap, 0)

        # Normalizacao robusta
        heatmap_max = np.max(heatmap)
        if heatmap_max > 0:
            heatmap = heatmap / heatmap_max

        heatmap_resized = cv2.resize(heatmap, (224, 224))
        heatmap_colored = cv2.applyColorMap(np.uint8(255 * heatmap_resized), cv2.COLORMAP_JET)
        heatmap_colored = cv2.cvtColor(heatmap_colored, cv2.COLOR_BGR2RGB)

        original_img_resized = np.array(img.resize((224, 224)))
        superimposed = heatmap_colored * 0.4 + original_img_resized * 0.6
        superimposed = np.clip(superimposed, 0, 255).astype(np.uint8)
        Image.fromarray(superimposed).convert("RGB").save(save_gradcam_path, quality=JPEG_QUALITY)

    handle_act.remove()
    handle_grad.remove()

    # Limpar dicionario de hooks para nao acumular
    gradcam_data['activations'] = None
    gradcam_data['gradients'] = None

    # Libertar TODA a memoria GPU/CPU alocada nesta iteracao
    del img
    del tensor
    del out5
    del prob5

    if torch.cuda.is_available():
        torch.cuda.empty_cache()

    return lbl5, conf5.item(), probs5


def get_local_images():
    """Devolve a lista simples de imagens disponiveis em LOCAL_IMAGES_DIR.

    Nota: a classe final de cada maca vem sempre da CNN (CNN2 -> CNN5), nunca
    do nome da pasta/ficheiro. Por isso aqui so listamos os caminhos, sem
    tentar adivinhar a doenca a partir do nome (a versao anterior fazia isso
    e depois descartava a informacao sem usar).
    """
    images = []

    # 1. Tentar ler como subpastas (ex: _4_dataset_final/Rot/)
    for disease in DISEASES:
        folder = os.path.join(LOCAL_IMAGES_DIR, disease)
        if os.path.exists(folder) and os.path.isdir(folder):
            images.extend([
                os.path.join(folder, f) for f in os.listdir(folder)
                if f.endswith(('.png', '.jpg', '.jpeg'))
            ])

    # 2. Se nao houver subpastas, ler os ficheiros soltos diretamente
    if not images and os.path.exists(LOCAL_IMAGES_DIR):
        images = [
            os.path.join(LOCAL_IMAGES_DIR, f) for f in os.listdir(LOCAL_IMAGES_DIR)
            if f.endswith(('.png', '.jpg', '.jpeg'))
        ]

    print(f"Encontradas {len(images)} imagens locais em {LOCAL_IMAGES_DIR}")
    return images


IMAGE_SIZE = 224  # mesmo tamanho usado pelo input da CNN e pelo pipeline do Raspberry


def save_compressed(img: Image.Image, dest_path: str, quality: int):
    """Redimensiona para IMAGE_SIZE x IMAGE_SIZE e grava como JPEG comprimido.

    224x224 porque e o que a CNN2/CNN5 recebem (transforms.Resize((224,224))
    acima) e o que o resto do dashboard/pipeline do Raspberry ja usa. Isto e
    tambem o que evita voltar a encher o Storage: em vez de subir PNGs ao
    tamanho original, cada frame/gradcam fica sempre neste tamanho fixo e
    comprimido em JPEG.
    """
    img = img.convert("RGB").resize((IMAGE_SIZE, IMAGE_SIZE), Image.LANCZOS)
    img.save(dest_path, "JPEG", quality=quality)


def upload_image_to_supabase(local_path, apple_id, frame_idx, suffix="", is_healthy=False):
    try:
        if is_healthy and not suffix:
            # Healthy: sem "frame" no nome (so ha 1 imagem por maca)
            file_name = f"{apple_id}{suffix}.jpg"
        else:
            # Doente: com "frame" (multiplas imagens com mesmo apple_id)
            file_name = f"{apple_id}_frame{frame_idx}{suffix}.jpg"
        year_dir = f"{datetime.datetime.now().year}/{file_name}"
        path_on_supa = f"{STORAGE_SUBFOLDER}/{year_dir}" if STORAGE_SUBFOLDER else year_dir

        file_size_kb = os.path.getsize(local_path) / 1024
        print(f"  Upload: {file_name} ({file_size_kb:.1f} KB)")

        with open(local_path, 'rb') as f:
            supabase.storage.from_(BUCKET_NAME).upload(
                file=f,
                path=path_on_supa,
                file_options={"content-type": "image/jpeg"}
            )

        return supabase.storage.from_(BUCKET_NAME).get_public_url(path_on_supa)
    except Exception as e:
        print(f"Erro a carregar imagem {local_path} para o bucket {BUCKET_NAME}: {e}")
        return None


def clear_previous_data():
    print("A limpar registos antigos na Base de Dados...")
    tab_to_clean = [
        ("train_dataset", "id"),
        ("circles_manual", "id"),
        ("manual_annotation", "id"),
        ("manual_review", "id"),
        ("producao_atual", "id"),
        ("cnn5_multi_confidence", "id"),
        ("cnn_predictions", "id"),
        ("frames", "id"),
        ("apples", "apple_id"),
    ]
    for table, pk in tab_to_clean:
        try:
            if pk == "apple_id":
                supabase.table(table).delete().neq(pk, "000").execute()
            else:
                supabase.table(table).delete().gt(pk, -1).execute()
        except Exception as e:
            print(f"Aviso ao limpar {table}: {e}")

    print("A limpar imagens antigas do Storage (todos os anos + crops/)...")
    try:
        # Descobre dinamicamente as pastas de topo do bucket (anos, "crops", etc.)
        top_entries = supabase.storage.from_(BUCKET_NAME).list("") or []
        top_folders = [e["name"] for e in top_entries if e.get("name") and e.get("id") is None]

        for folder in top_folders:
            _clear_folder_recursive(folder)
    except Exception as e:
        print(f"Aviso ao limpar Storage: {e}")

    print("A limpar ficheiros temporarios locais...")
    import glob
    for f in glob.glob("temp_gradcam_*.png") + glob.glob("temp_gradcam_*.jpg"):
        try:
            os.remove(f)
        except Exception:
            pass


def _clear_folder_recursive(prefix: str):
    entries = supabase.storage.from_(BUCKET_NAME).list(prefix) or []
    file_paths = []
    for e in entries:
        name = e.get("name")
        if not name or name == ".emptyFolderPlaceholder":
            continue
        full_path = f"{prefix}/{name}"
        if e.get("id") is None:
            _clear_folder_recursive(full_path)
        else:
            file_paths.append(full_path)

    for i in range(0, len(file_paths), 100):
        supabase.storage.from_(BUCKET_NAME).remove(file_paths[i:i + 100])


def process_one_apple(i: int, local_img_path: str, jpeg_quality: int):
    """Processa uma imagem local: gera 3 frames (augmentacao), classifica com
    CNN2/CNN5 e insere tudo no Supabase. Lanca excecao em caso de erro - quem
    chama e responsavel por apanhar e continuar com a proxima imagem."""
    temp_files_to_clean = []

    img_orig = Image.open(local_img_path).convert("RGB")

    # Frame 1: original (comprimido, 224x224)
    fd1, path1 = tempfile.mkstemp(suffix=".jpg")
    os.close(fd1)
    save_compressed(img_orig, path1, jpeg_quality)
    temp_files_to_clean.append(path1)

    # Frame 2: rodar 90 graus
    fd2, path2 = tempfile.mkstemp(suffix=".jpg")
    os.close(fd2)
    save_compressed(img_orig.rotate(90, expand=True), path2, jpeg_quality)
    temp_files_to_clean.append(path2)

    # Frame 3: rodar 250 graus
    fd3, path3 = tempfile.mkstemp(suffix=".jpg")
    os.close(fd3)
    save_compressed(img_orig.rotate(250, expand=True), path3, jpeg_quality)
    temp_files_to_clean.append(path3)

    apple_frames_paths = [path1, path2, path3]

    try:
        # 2. Correr CNN2 em todos os frames (Sempre 3)
        cnn2_results = []
        for img_p in apple_frames_paths:
            lbl2, conf2, prob_h = run_cnn2(img_p)
            cnn2_results.append({'path': img_p, 'label': lbl2, 'conf': conf2, 'prob_healthy': prob_h})

        # 3. Decidir se precisa de CNN5 (Gatekeeper)
        uncertain_frames = [r for r in cnn2_results if r['label'] != 'Healthy' or r['conf'] < 0.80]
        needs_cnn5 = len(uncertain_frames) > 0

        final_disease = 'Healthy'
        disease_conf = 0.0
        final_source = "CNN2"
        worst_frame_idx = 1
        worst_gradcam_path = None
        worst_gradcam_label = None
        worst_gradcam_conf = None
        worst_gradcam_probs = None

        # naming_label: rotulo de apresentacao (apple_id / producao_atual.final_class).
        # Igual a final_disease exceto na banda auto_outros, onde vira "Incerta" -
        # o CNN nao pode decidir "outros" sozinho, so o operador/produtor. Nunca
        # substitui final_disease/disease_conf nas tabelas analiticas (cnn_predictions,
        # cnn5_multi_confidence, manual_review.original_class continuam com a
        # sugestao crua da CNN5).
        # review_band: None | "pending" (30-80% sempre, mais 5% aleatorio entre
        # 80-85% para auditoria de qualidade) | "auto_outros" (<30%, salta o
        # operador, vai para o pool do produtor/admin).
        naming_label = 'Healthy'
        review_band = None

        if needs_cnn5:
            worst_res = min(cnn2_results, key=lambda x: x['prob_healthy'])
            worst_frame_idx = cnn2_results.index(worst_res) + 1

            fd_gc, temp_gradcam = tempfile.mkstemp(suffix=".jpg")
            os.close(fd_gc)
            lbl5, conf5, probs5 = run_cnn5_with_gradcam(worst_res['path'], temp_gradcam)
            temp_files_to_clean.append(temp_gradcam)

            # Guardamos este resultado para reutilizar no loop abaixo e evitar
            # correr a CNN5 duas vezes sobre o mesmo frame (pior frame).
            worst_gradcam_path = temp_gradcam
            worst_gradcam_label = lbl5
            worst_gradcam_conf = conf5
            worst_gradcam_probs = probs5

            final_disease = lbl5
            disease_conf = conf5
            final_source = "CNN5"

            if final_disease == 'Healthy':
                # Um veredito Healthy da CNN5 fica sempre no caminho simples,
                # mesmo com confianca baixa - as bandas so se aplicam a doencas.
                naming_label = 'Healthy'
                review_band = None
            elif disease_conf >= AUTO_ACCEPT_THRESHOLD:
                naming_label = final_disease
                review_band = None
            elif disease_conf >= REVIEW_QUEUE_THRESHOLD:
                # 80-85%: auto-aceite, exceto uma amostra aleatoria de 5% que
                # vai na mesma para a fila de revisao (auditoria de qualidade).
                naming_label = final_disease
                review_band = "pending" if random.random() < AUDIT_SAMPLE_RATE else None
            elif disease_conf >= AUTO_OUTROS_THRESHOLD:
                naming_label = final_disease  # sugestao da CNN5, dica para o operador
                review_band = "pending"
            else:
                naming_label = "Incerta"
                review_band = "auto_outros"
        else:
            best_res = max(cnn2_results, key=lambda x: x['conf'])
            final_disease = 'Healthy'
            disease_conf = best_res['conf']
            final_source = "CNN2"
            naming_label = 'Healthy'
            review_band = None

        is_healthy = (final_disease == 'Healthy')

        apple_id = f"{naming_label}_{i:03d}_{uuid.uuid4().hex[:6]}"

        days_ago = random.randint(0, 3)
        timestamp = datetime.datetime.now() - datetime.timedelta(days=days_ago)
        locais = ["Bloco A", "Bloco B", "Bloco C", "Armazem"]
        lote_location = random.choice(locais)

        apple_data = {
            "apple_id": apple_id,
            "timestamp": timestamp.isoformat(),
            "location": lote_location,
        }
        supabase.table("apples").insert(apple_data).execute()

        # 4. Inserir Frames e Predicoes
        worst_frame_url = None

        for idx, frame_info in enumerate(cnn2_results):
            frame_idx = idx + 1
            is_worst = (frame_idx == worst_frame_idx)
            img_p = frame_info['path']

            if is_healthy and not is_worst:
                # Maca saudavel: so o frame is_worst (o original, frame 1) sobe
                # para o Storage. Os outros ficam so como metadados (frame_idx,
                # label, confidence) - frame_data abaixo usa image_url=None.
                public_url = None
            else:
                public_url = upload_image_to_supabase(img_p, apple_id, frame_idx, is_healthy=is_healthy)
                if is_worst:
                    if public_url is None:
                        raise RuntimeError(f"Upload falhou para frame is_worst de {apple_id} - a abortar esta maca")
                    worst_frame_url = public_url

            current_frame_lbl = frame_info['label']
            current_frame_conf = frame_info['conf']

            # CNN5 classificou a maca como Healthy (overridou o CNN2) - normalizar
            # todos os frames para 'Healthy' para evitar 'Disease' em maca saudavel.
            if is_healthy and current_frame_lbl == 'Disease':
                current_frame_lbl = 'Healthy'

            current_frame_probs = None

            if not is_healthy:
                if is_worst and worst_gradcam_path is not None:
                    # Ja temos o Grad-CAM deste frame calculado acima - reutilizar.
                    upload_image_to_supabase(worst_gradcam_path, apple_id, frame_idx, suffix="_gradcam")
                    current_frame_lbl = worst_gradcam_label
                    current_frame_conf = worst_gradcam_conf
                    current_frame_probs = worst_gradcam_probs
                else:
                    fd_gc, temp_gc = tempfile.mkstemp(suffix=".jpg")
                    os.close(fd_gc)
                    lbl5, conf5, probs5 = run_cnn5_with_gradcam(img_p, temp_gc)
                    upload_image_to_supabase(temp_gc, apple_id, frame_idx, suffix="_gradcam")
                    current_frame_lbl = lbl5
                    current_frame_conf = conf5
                    current_frame_probs = probs5
                    try:
                        os.remove(temp_gc)
                    except Exception:
                        pass

            frame_data = {
                "apple_id": apple_id,
                "frame_idx": frame_idx,
                "image_url": public_url,
                "label": current_frame_lbl,
                "confidence": current_frame_conf,
                "is_worst_case": is_worst,
            }
            res_frame = supabase.table("frames").insert(frame_data).execute()
            if not res_frame.data:
                print(f"ERRO CRITICO: Frame nao inserido para {apple_id}")
                continue

            frame_id = res_frame.data[0]['id']

            preds = []
            if needs_cnn5:
                if is_worst:
                    preds.append({
                        "apple_id": apple_id,
                        "frame_id": frame_id,
                        "model_name": "CNN5",
                        "label": final_disease,
                        "confidence": disease_conf,
                        "timestamp": timestamp.isoformat(),
                    })
            else:
                preds.append({
                    "apple_id": apple_id,
                    "frame_id": frame_id,
                    "model_name": "CNN2",
                    "label": frame_info['label'],
                    "confidence": frame_info['conf'],
                    "timestamp": timestamp.isoformat(),
                })

            if preds:
                try:
                    supabase.table("cnn_predictions").insert(preds).execute()
                except Exception as e:
                    print(f"Erro ao inserir predicoes para frame {frame_id}: {e}")

            # Multi-confianca por classe (cnn5_multi_confidence) - so para macas
            # doentes (o veredito final da maca nao e Healthy), uma linha por
            # frame por classe com confianca >= MIN_CLASS_SCORE. 'Healthy' pode
            # aparecer aqui como classe secundaria (ex.: Scab 80%, Healthy 10%).
            if not is_healthy and current_frame_probs is not None:
                class_scores_rows = [
                    {
                        "apple_id": apple_id,
                        "frame_id": frame_id,
                        "class_label": label,
                        "confidence": conf,
                    }
                    for label, conf in current_frame_probs.items()
                    if conf >= MIN_CLASS_SCORE
                ]
                if class_scores_rows:
                    try:
                        supabase.table("cnn5_multi_confidence").insert(class_scores_rows).execute()
                    except Exception as e:
                        print(f"Erro ao inserir cnn5_multi_confidence para frame {frame_id}: {e}")

        # 5. Tabelas de Visao de Producao e Triagem
        producao_data = {
            "apple_id": apple_id,
            "timestamp": timestamp.isoformat(),
            "location": lote_location,
            "final_class": naming_label,
            "final_confidence": disease_conf,
            "final_source": final_source,
            "frame_thumbnail": worst_frame_url,
        }
        supabase.table("producao_atual").insert(producao_data).execute()

        if review_band is not None:
            review_data = {
                "apple_id": apple_id,
                "updated_at": timestamp.isoformat(),
                "original_class": final_disease,
                "original_confidence": int(disease_conf * 100),
                "status": review_band,
            }
            supabase.table("manual_review").insert(review_data).execute()

    finally:
        for tmp_p in temp_files_to_clean:
            try:
                if os.path.exists(tmp_p):
                    os.remove(tmp_p)
            except Exception:
                pass


def generate_data(limit: int | None, wipe: bool, skip_prompt: bool, jpeg_quality: int):
    # Tenta criar o bucket se nao existir (se der erro assume que ja existe)
    try:
        supabase.storage.create_bucket(BUCKET_NAME, {"public": True})
    except Exception:
        pass

    all_available = get_local_images()
    if not all_available:
        print("Nao ha imagens disponiveis. Abortando.")
        return

    random.shuffle(all_available)
    if limit is not None:
        all_available = all_available[:limit]

    print(f"A gerar {len(all_available)} macas com imagens reais para o Supabase Storage...")
    print(f"Compressao: {IMAGE_SIZE}x{IMAGE_SIZE}px, jpeg_quality={jpeg_quality}")

    if wipe:
        clear_previous_data()
    elif not skip_prompt:
        print("\nOpcoes de Base de Dados:")
        print("1 - Apagar dados anteriores")
        print("2 - Nao apagar")
        opcao = input("\n > ").strip()
        if opcao == "1":
            confirmacao = input("Tens a certeza? (Sim/Nao): ").strip().lower()
            if confirmacao in ['s', 'sim', 'y', 'yes']:
                clear_previous_data()
            else:
                print("Limpeza cancelada.")
        else:
            print("A manter dados anteriores.")
    else:
        print("A manter dados anteriores (--yes sem --wipe).")

    ok_count = 0
    err_count = 0
    for i, local_img_path in enumerate(all_available):
        try:
            process_one_apple(i, local_img_path, jpeg_quality)
            ok_count += 1
        except Exception as e:
            err_count += 1
            print(f"[{i + 1}/{len(all_available)}] ERRO ao processar '{local_img_path}': {e}")
            continue

        if (i + 1) % 10 == 0:
            print(f"[{i + 1}/{len(all_available)}] processadas ({ok_count} ok, {err_count} erros)...")

    print(f"\nInsercao concluida! {ok_count} macas inseridas, {err_count} falharam.")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Popula o Supabase (tabelas + Storage) com macas de teste.")
    p.add_argument("--limit", type=int, default=None,
                   help="Numero maximo de macas a gerar (default: todas as imagens encontradas).")
    p.add_argument("--wipe", action="store_true",
                   help="Apaga dados anteriores (tabelas + Storage) sem perguntar. Cuidado, é destrutivo.")
    p.add_argument("--yes", action="store_true",
                   help="Corre sem prompts interativos (assume 'nao apagar' se --wipe nao for indicado).")
    p.add_argument("--jpeg-quality", type=int, default=85,
                   help="Qualidade JPEG (1-95) usada na compressao antes do upload (default 85).")
    args = p.parse_args()

    JPEG_QUALITY = args.jpeg_quality
    generate_data(
        limit=args.limit,
        wipe=args.wipe,
        skip_prompt=args.yes,
        jpeg_quality=args.jpeg_quality,
    )
