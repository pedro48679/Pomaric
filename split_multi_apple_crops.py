#!/usr/bin/env python3
"""Separa imagens em bruto com múltiplas maçãs em imagens individuais (1 maçã por ficheiro).

CORRE ANTES do RGBA_format.py, diretamente sobre as imagens em bruto de OUT_DIR
(as mesmas pastas de doença usadas por scrape_apple_diseases.py e
filter_apples_rembg.py) -- não sobre um dataset já formatado a 224x224. Algumas
fotos trazem 2+ maçãs (pares de frutas, bandeja com várias, etc.); dividi-las
aqui em vez de deixar o RGBA_format.py escolher só a maior evita perder as
outras. Este script:

  1. Processa cada imagem da pasta
  2. Deteta contornos individuais de maçã (usando rembg + forma) e separa os
     que se tocam com Watershed
  3. Para cada maçã claramente separável, faz um recorte simples (caixa
     delimitadora + margem, RGB, resolução nativa) -- SEM remover o fundo e
     SEM redimensionar. Isso é trabalho do RGBA_format.py, que corre depois
     disto sobre cada recorte.
  4. Se há N maçãs separáveis, guarda N ficheiros: 000001_001.png, 000001_002.png, ...
  5. Se há 1 maçã, ou se não dá para separar com confiança, deixa a imagem
     como está (não mexe) -- a validação de "é ou não é uma maçã boa" já foi
     feita pelo filter_apples_rembg.py, não é este script que decide isso.
  6. Só vai para _rejeitadas_splits/ o que estiver mesmo ilegível ou onde o
     rembg não encontrar nenhum primeiro plano.

Isto aumenta o dataset: 1 imagem com 2 maçãs = 2 imagens de treino. Perfeito para
balancear doenças fracas.

Uso:
  python split_multi_apple_crops.py --dry-run          # só relata, não grava
  python split_multi_apple_crops.py                     # divide mesmo
  python split_multi_apple_crops.py --folder scab      # só uma doença
"""

import argparse
import math
import os
import shutil
from pathlib import Path

import numpy as np
import cv2
import torch
from PIL import Image
from rembg import remove, new_session

OUT_DIR = Path("./data/scrappa")  # ajusta para a pasta de saída local
REJECT_DIRNAME = "_rejeitadas_splits"
IMG_EXTS = (".png", ".jpg", ".jpeg", ".webp")

# Setup do PATH do torch para CUDA (como em filter_apples_rembg.py)
try:
    torch_lib_path = os.path.join(os.path.dirname(torch.__file__), "lib")
    os.environ["PATH"] = torch_lib_path + ";" + os.environ["PATH"]
except Exception as e:
    print(f"Aviso: não foi possível definir o path do torch: {e}")

session = new_session(providers=["CUDAExecutionProvider", "CPUExecutionProvider"])


def rembg_mask(img: Image.Image) -> np.ndarray:
    """Máscara binária do rembg, pronta para contornos."""
    output_img = remove(img, session=session)
    if output_img.size != img.size:
        output_img = output_img.resize(img.size, Image.LANCZOS)
    mask = np.array(output_img)[:, :, 3].copy()
    _, mask = cv2.threshold(mask, 127, 255, cv2.THRESH_BINARY)
    kernel = np.ones((3, 3), np.uint8)
    return cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)


def contour_metrics(contour, img_area: float):
    """Descritores de forma de um contorno."""
    area = cv2.contourArea(contour)
    if area <= 0:
        return None

    (_, _), radius = cv2.minEnclosingCircle(contour)
    circle_area = math.pi * radius * radius
    circle_fill = area / circle_area if circle_area > 0 else 0.0

    (_, (rw, rh), _) = cv2.minAreaRect(contour)
    if min(rw, rh) <= 0:
        return None
    aspect = max(rw, rh) / min(rw, rh)

    hull = cv2.convexHull(contour)
    hull_area = cv2.contourArea(hull)
    solidity = area / hull_area if hull_area > 0 else 0.0

    return {
        "area_frac": area / img_area,
        "circle_fill": circle_fill,
        "aspect": aspect,
        "solidity": solidity,
    }


def square_crop(img_array: np.ndarray, contour, margin: float = 1.05) -> np.ndarray:
    """Recorte quadrado à volta do contorno."""
    x, y, bw, bh = cv2.boundingRect(contour)
    cx, cy = x + bw // 2, y + bh // 2
    lado = int(max(bw, bh) * margin)
    y1 = max(0, cy - lado // 2)
    y2 = min(img_array.shape[0], cy + lado // 2)
    x1 = max(0, cx - lado // 2)
    x2 = min(img_array.shape[1], cx + lado // 2)
    return img_array[y1:y2, x1:x2]


def is_valid_apple(m, args) -> tuple[bool, str]:
    """Valida uma maçã por forma (mesmos critérios que filter_apples_rembg.py)."""
    if m["area_frac"] < args.min_area_frac:
        return False, f"area_frac={m['area_frac']:.3f}<{args.min_area_frac}"
    if m["circle_fill"] < args.min_circle_fill:
        return False, f"circ_fill={m['circle_fill']:.2f}<{args.min_circle_fill}"
    if m["aspect"] > args.max_aspect:
        return False, f"aspect={m['aspect']:.2f}>{args.max_aspect}"
    if m["solidity"] < args.min_solidity:
        return False, f"solidez={m['solidity']:.2f}<{args.min_solidity}"
    return True, "ok"


def load_rgb(path: Path):
    """Carrega PNG/JPG como RGB."""
    try:
        img = Image.open(path)
        img.load()
        return img.convert("RGB")
    except Exception as e:
        print(f"      [erro a abrir] {path.name}: {e}")
        return None


def extract_crops(img: Image.Image, contours, args) -> list:
    """Extrai cada maçã como um recorte simples: caixa delimitadora + 5% de
    margem, em RGB, à resolução nativa -- sem remover o fundo e sem
    redimensionar. Isso é trabalho do RGBA_format.py, que corre a seguir a
    este script; aqui só separamos.
    """
    img_array = np.array(img.convert("RGB"))

    crops = []
    for c in contours:
        cropped_matrix = square_crop(img_array, c, margin=1.05)
        if cropped_matrix.size == 0:
            continue
        crops.append(Image.fromarray(cropped_matrix))

    return crops


def split_touching_apples(comp_mask: np.ndarray, dist_thresh: float, img_array: np.ndarray) -> list[np.ndarray]:
    """Divide um componente de máscara que contém múltiplas maçãs tocando-se
    usando o algoritmo Distance Transform + local maxima + Watershed baseada em gradiente.
    Retorna uma lista de sub-máscaras individuais.
    """
    dist_transform = cv2.distanceTransform(comp_mask, cv2.DIST_L2, 5)
    dist_smooth = cv2.GaussianBlur(dist_transform, (5, 5), 0)
    
    max_val = dist_smooth.max()
    if max_val <= 0:
        return [comp_mask]
    
    # 1. Encontrar picos locais usando dilatação com tamanho adaptativo ao raio do fruto
    kernel_size = max(5, int(max_val * 0.25) | 1)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
    dilated = cv2.dilate(dist_smooth, kernel)
    peaks = (dist_smooth == dilated) & (dist_smooth > 0.15 * max_val)
    sure_fg = peaks.astype(np.uint8) * 255
    
    num_labels, markers = cv2.connectedComponents(sure_fg)
    if num_labels <= 2:
        return [comp_mask]
        
    # 2. Configurar marcadores:
    # Desloca os rótulos dos picos de 2 em diante (para não colidir com o -1 da borda)
    markers = np.where(markers > 0, markers + 1, 0)
    # Define a região fora da máscara como -1 (barreira intransponível para o watershed)
    markers[comp_mask == 0] = -1
    markers = markers.astype(np.int32)
    
    # 3. Calcular gradiente morfológico para guiar o crescimento nas bordas reais dos frutos
    kernel_grad = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
    gradient = cv2.morphologyEx(img_array, cv2.MORPH_GRADIENT, kernel_grad)
    
    # 4. Correr Watershed
    markers = cv2.watershed(gradient, markers)
    
    sub_masks = []
    for label in range(2, num_labels + 1):
        sub_mask = np.zeros_like(comp_mask)
        sub_mask[markers == label] = 255
        
        # Preencher pequenas falhas nas bordas de partição
        kernel_close = np.ones((3, 3), np.uint8)
        sub_mask = cv2.morphologyEx(sub_mask, cv2.MORPH_CLOSE, kernel_close)
        
        sub_masks.append(sub_mask)
        
    return sub_masks


# Contornos-pai mais pequenos do que isto nunca são tentados no watershed --
# são ruído (poeira da máscara, orlas de anti-aliasing), e forçar o watershed
# sobre uma mancha minúscula é o que produzia o bug abaixo.
MIN_PARENT_AREA_FRAC_FOR_SPLIT = 0.03

# Testado contra fotos em bruto (não pré-formatadas): o watershed por vezes
# "separa" um blob em pedaços onde um deles ainda cobre quase a imagem
# inteira (rembg não limpou bem o fundo, ex: mesa de madeira ou fundo cinza
# complexo que ficou colado ao primeiro plano). Esse pedaço passa nos
# limites relaxados (é convexo e nem muito alongado, porque a MOLDURA da
# foto também é convexa e "redonda-ish") mas não é uma maçã isolada -- é a
# cena toda outra vez. Foi confirmado visualmente em várias imagens reais
# (área a chegar a 99.7% e 99.8% da imagem). Este teto rejeita esses casos.
MAX_SPLIT_AREA_FRAC = 0.35


def process_image(img_path: Path, args):
    """Processa uma imagem: detecta maçãs, valida-as e retorna a contagem de maçãs válidas,
    os contornos correspondentes, a imagem carregada, uma lista de razões de rejeição, e se
    o rembg encontrou pelo menos algum primeiro plano (para distinguir "não há nada aqui" de
    "há coisas mas nenhuma passou nos critérios de separação").
    """
    img = load_rgb(img_path)
    if img is None:
        return 0, [], None, ["erro ao abrir"], False

    mask = rembg_mask(img)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    img_area = float(mask.shape[0] * mask.shape[1])
    img_array = np.array(img)

    valid_contours = []
    rejected_reasons = []

    for c in contours:
        # Gerar uma máscara binária do componente conectado
        comp_mask = np.zeros_like(mask)
        cv2.drawContours(comp_mask, [c], -1, 255, -1)

        # Contornos minúsculos não valem a pena tentar separar (ruído, e o
        # watershed sobre uma mancha ínfima podia "explodir" para a imagem
        # inteira) -- tratamos como um único candidato sem split.
        parent_area_frac = cv2.contourArea(c) / img_area
        if parent_area_frac < MIN_PARENT_AREA_FRAC_FOR_SPLIT:
            sub_masks = [comp_mask]
        else:
            # Tentar separar componentes que se tocam usando Watershed
            sub_masks = split_touching_apples(comp_mask, args.dist_thresh, img_array)
        is_split = (len(sub_masks) >= 2)

        for sub_mask in sub_masks:
            sub_contours, _ = cv2.findContours(sub_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if not sub_contours:
                continue

            # Pegamos no maior contorno dessa sub-máscara
            sc = max(sub_contours, key=cv2.contourArea)
            m = contour_metrics(sc, img_area)
            if m is None:
                continue

            # Se for um componente dividido, aplicamos limites mais tolerantes
            # porque cortes do Watershed reduzem a circularidade e solidez
            if is_split:
                if m["area_frac"] < 0.08:
                    continue
                if m["area_frac"] > MAX_SPLIT_AREA_FRAC:
                    # O watershed não separou de facto -- este pedaço ainda é
                    # grande demais para ser "uma" maçã isolada.
                    rejected_reasons.append(f"split falhou, pedaço ainda cobre {m['area_frac']*100:.0f}% da imagem")
                    continue
                class RelaxedArgs:
                    min_area_frac = 0.08
                    min_circle_fill = 0.25
                    # 2.4 deixava passar tiras largas de figuras académicas em grelha
                    # (várias fotos coladas lado a lado) -- essas tiras têm aspect
                    # ~2.2, medido em dados reais, bem acima de uma maçã isolada
                    # (~1.0-1.3 mesmo depois de cortada pelo watershed).
                    max_aspect = 1.8
                    min_solidity = 0.55
                ok, reason = is_valid_apple(m, RelaxedArgs)
            else:
                if m["area_frac"] < args.min_area_frac:
                    continue
                ok, reason = is_valid_apple(m, args)

            if not ok:
                rejected_reasons.append(reason)
                continue

            # Validamos o tamanho da caixa delimitadora antes de aceitar
            x, y, w, h = cv2.boundingRect(sc)
            if max(w, h) * 1.05 < args.min_size:
                rejected_reasons.append(f"bounding box {max(w,h)}<{args.min_size}")
                continue

            valid_contours.append(sc)

    return len(valid_contours), valid_contours, img, rejected_reasons, len(contours) > 0


def save_splits(img_path: Path, crops, dry_run: bool):
    """Guarda os crops com sufixos _001, _002, etc. Se houver 1 crop, deixa como está."""
    if len(crops) == 0:
        return
    if len(crops) == 1:
        # Uma só maçã: deixa como está (não mexe no PNG original)
        return

    # Múltiplas maçãs: guarda cada uma como _001, _002, ...
    for i, canvas in enumerate(crops):
        out = img_path.parent / f"{img_path.stem}_{i + 1:03d}.png"
        if not dry_run:
            canvas.save(out, "PNG")


def move_reject_split(img_path: Path, reject_dir: Path, reason: str, dry_run: bool):
    """Move imagem rejeitada para _rejeitadas_splits/ (só se houve rejeição, nunca apaga)."""
    if dry_run:
        return
    if not img_path.exists():
        return
    reject_dir.mkdir(parents=True, exist_ok=True)
    dest = reject_dir / img_path.name
    if dest.exists():
        dest = reject_dir / f"{img_path.stem}_{img_path.stat().st_mtime_ns}{img_path.suffix}"
    shutil.move(str(img_path), str(dest))


def process_folder(folder: Path, args):
    """Processa todas as PNGs de uma doença.

    Retorna (kept, split_count, split_originals)
    """
    images = [p for p in folder.glob("*") if p.suffix.lower() in IMG_EXTS]
    if not images:
        return 0, 0, []

    reject_dir = folder.parent / REJECT_DIRNAME
    kept, split_count = 0, 0
    split_originals = []

    for img_path in sorted(images):
        num_crops, valid_contours, img, rejected_reasons, had_any_contour = process_image(img_path, args)

        if num_crops == 0:
            if img is None or not had_any_contour:
                # Ficheiro ilegível ou o rembg não encontrou mesmo nada -- isto sim é lixo.
                reason = rejected_reasons[0] if rejected_reasons else "sem primeiro plano"
                print(f"      [rejeita] {img_path.name} ({reason})")
                if not args.dry_run:
                    move_reject_split(img_path, reject_dir, reason, False)
            else:
                # Havia algo, só não passou nos critérios de "claramente separável em
                # várias maçãs". Não é trabalho deste script decidir se a maçã é boa
                # ou não -- isso já foi decidido pelo filter_apples_rembg.py. Deixa o
                # ficheiro como está.
                kept += 1
        elif num_crops == 1:
            # Uma maçã: mantém original, não mexe
            kept += 1
        else:
            # Múltiplas maçãs: cria splits
            kept += 1
            split_count += num_crops
            split_originals.append(img_path)
            if args.dry_run:
                print(f"      [split] {img_path.name} -> {num_crops} maçãs")
            else:
                crops = extract_crops(img, valid_contours, args)
                save_splits(img_path, crops, False)
                print(f"      [split] {img_path.name} -> {len(crops)} maçãs")

    return kept, split_count, split_originals


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--folder", type=str, default=None, help="processa só uma subpasta de SCARPP")
    parser.add_argument("--image", type=str, default=None, help="processa só um ficheiro de imagem específico")
    parser.add_argument("--dry-run", action="store_true", help="só relata, não grava nada")
    # Estes 4 só se aplicam a contornos JÁ isolados (não tocam em mais nenhum --
    # portanto sem qualquer ambiguidade sobre onde uma maçã acaba e outra
    # começa). Por isso usam os mesmos valores calibrados e testados contra
    # dados reais em filter_apples_rembg.py, em vez de exigir quase-perfeição
    # geométrica: uma maçã seca/enrugada (bem visível, só com a casca
    # deformada) não devia ser excluída só por causa disso -- essa validação
    # de "é ou não é uma maçã aceitável" já é feita a jusante.
    parser.add_argument("--min-area-frac", type=float, default=0.02, help="fração mínima (default: 0.02)")
    parser.add_argument("--min-circle-fill", type=float, default=0.40, help="circle_fill mínimo (default: 0.40)")
    parser.add_argument("--max-aspect", type=float, default=2.20, help="aspect máximo (default: 2.20)")
    parser.add_argument("--min-solidity", type=float, default=0.50, help="solidez mínima (default: 0.50)")
    parser.add_argument("--min-size", type=int, default=224, help="tamanho mínimo do crop (default: 224)")
    parser.add_argument("--dist-thresh", type=float, default=0.38, help="limiar da distância para separar maçãs (default: 0.38)")
    args = parser.parse_args()

    total_kept, total_split = 0, 0
    all_split_originals = []

    if args.image:
        img_path = Path(args.image)
        if not img_path.exists():
            print(f"Erro: O ficheiro de imagem '{img_path}' não existe.")
            return
        print(f"[processa imagem] {img_path.name}")
        num_crops, valid_contours, img, rejected_reasons, had_any_contour = process_image(img_path, args)
        if num_crops == 0:
            if img is None or not had_any_contour:
                reason = rejected_reasons[0] if rejected_reasons else "sem primeiro plano"
                print(f"      [rejeita] {img_path.name} ({reason})")
                if not args.dry_run:
                    reject_dir = img_path.parent / REJECT_DIRNAME
                    move_reject_split(img_path, reject_dir, reason, False)
            else:
                print(f"      [mantém] {img_path.name} (não separável com confiança, não mexe)")
                total_kept = 1
        elif num_crops == 1:
            print(f"      [mantém] {img_path.name} (1 maçã, não mexe)")
            total_kept = 1
        else:
            print(f"      [split] {img_path.name} -> {num_crops} maçãs")
            if not args.dry_run:
                crops = extract_crops(img, valid_contours, args)
                save_splits(img_path, crops, False)
            total_kept = 1
            total_split = num_crops
            all_split_originals.append(img_path)
    else:
        SKIP = {REJECT_DIRNAME, "_rejeitadas", "folhas", "manifest.csv", "manifest_inaturalist.csv"}
        if args.folder:
            folders = [OUT_DIR / args.folder]
        else:
            folders = [p for p in OUT_DIR.iterdir() if p.is_dir() and p.name not in SKIP]

        for folder in sorted(folders):
            if not folder.exists():
                print(f"[skip] pasta não existe: {folder}")
                continue
            print(f"[processa] {folder.name}")
            kept, split, split_origs = process_folder(folder, args)
            print(f"  -> {kept} imagens, +{split} splits")
            total_kept += kept
            total_split += split
            all_split_originals.extend(split_origs)

    mode = " (DRY-RUN)" if args.dry_run else ""
    print(f"\nTotal: {total_kept} imagens, +{total_split} splits de múltiplas maçãs{mode}")

    # Pergunta interativa para apagar as originais que foram divididas
    if all_split_originals and not args.dry_run:
        print(f"\nForam divididas {len(all_split_originals)} imagens originais em múltiplos crops.")
        resp = input("Deseja apagar estas imagens originais que foram divididas? (s/n): ").strip().lower()
        if resp in ("s", "sim", "y", "yes"):
            print("A apagar originais divididas...")
            for path in all_split_originals:
                try:
                    if path.exists():
                        path.unlink()
                        print(f"  [removido] {path.name}")
                except Exception as e:
                    print(f"  [erro ao apagar] {path.name}: {e}")
            print("Concluído!")
        else:
            print("As imagens originais foram mantidas.")


if __name__ == "__main__":
    main()
