#!/usr/bin/env python3
"""Filtra as imagens em SCARPP: mantém só as que contêm uma maçã, usando rembg.

Corre ANTES do RGBA_format.py. Em vez de analisar cor crua (a abordagem frágil
de validate_apples.py, que rejeitava maçãs verdes na mão e aceitava folhas),
este script usa o MESMO rembg de RGBA_format.py para segmentar os objetos e
depois mede a FORMA de CADA contorno individualmente:

  - Fração de área  : área do contorno / área da imagem  (descarta ruído minúsculo)
  - Preench. círculo: area / área do círculo envolvente  (maçã ~redonda -> alto)
  - Aspect ratio    : lado_maior/lado_menor do minAreaRect (folha alongada -> alto)
  - Solidez         : area / area do convexHull           (serrilhado -> baixo)

IMPORTANTE — decisão por-contorno (não pelo maior): cada contorno que for maçã
vira um crop separado. Uma foto com 3 maçãs numa bandeja dá 3 crops; uma maçã
com um ramo ao lado dá 1 crop (o ramo, alongado, é ignorado). A imagem só é
rejeitada se NENHUM contorno for maçã. Crops mais pequenos que --min-size
(224x224 por defeito) são descartados para não haver upscaling de maçãs
minúsculas no RGBA_format.py a jusante.

NOTA: NÃO usamos a circularidade 4*pi*A/P^2 porque a máscara do rembg tem bordas
serrilhadas/anti-aliased que inflacionam o perímetro e destroem o valor mesmo
para maçãs perfeitamente redondas. O "preenchimento do círculo envolvente"
(cv2.minEnclosingCircle) mede redondeza só a partir de áreas, sendo robusto a
bordas irregulares. A máscara também é binarizada antes de medir.

Uma maçã é redonda, convexa e compacta -> passa todos os limiares.
Uma folha é alongada e serrilhada, um slide de texto é irregular -> falha.

As imagens rejeitadas NUNCA são apagadas: são movidas para
SCARPP/_rejeitadas/<pasta>/ para poderes rever e recuperar falsos rejeitados.

Uso:
  python filter_apples_rembg.py --dry-run          # só relata métricas, não move
  python filter_apples_rembg.py --dry-run --folder apple_fruit_scab_lesion
  python filter_apples_rembg.py                     # move não-maçãs para _rejeitadas
  python filter_apples_rembg.py --min-circularity 0.55 --max-aspect 1.8   # afinar
  python filter_apples_rembg.py --dry-run --preview-rejects --folder scab   # ver o que seria rejeitado, uma a uma
  python filter_apples_rembg.py --strict-classifier --dry-run --preview-rejects --folder scab   # revisão manual com a blacklist ligada
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

from apple_filters import (
    has_excessive_foliage,
    init_classifier,
    init_yolo,
    is_image_blocked_fruit,
    is_valid_apple_yolo,
)

OUT_DIR = Path(r"C:\Users\Utilizador\OneDrive\Área de Trabalho\scrappa")
REJECT_DIRNAME = "_rejeitadas"
IMG_EXTS = (".jpg", ".jpeg", ".png", ".webp")

try:
    torch_lib_path = os.path.join(os.path.dirname(torch.__file__), "lib")
    os.environ["PATH"] = torch_lib_path + ";" + os.environ["PATH"]
except Exception as e:
    print(f"Aviso: não foi possível definir o path do torch: {e}")

session = new_session(providers=["CUDAExecutionProvider", "CPUExecutionProvider"])


def rembg_mask(img: Image.Image) -> np.ndarray:
    """Corre rembg e devolve a máscara binária (0/255) limpa do objeto."""
    output_img = remove(img, session=session)
    mask = np.array(output_img)[:, :, 3].copy()
    _, mask = cv2.threshold(mask, 127, 255, cv2.THRESH_BINARY)
    kernel = np.ones((3, 3), np.uint8)
    return cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)


def contour_metrics(contour, img_area: float):
    """Descritores de forma de UM contorno. None se degenerado."""
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


def fit_circle_ransac(xs: np.ndarray, ys: np.ndarray, max_iters: int = 80, rel_threshold: float = 0.06):
    """Ajusta um círculo aos pontos (RANSAC), robusto a ramos/pés colados à maçã."""
    import random

    n = len(xs)
    if n < 3:
        return None
    pts = list(zip(xs.tolist(), ys.tolist()))
    random.seed(42)

    best = None
    max_inliers = -1
    for _ in range(max_iters):
        p1, p2, p3 = random.sample(pts, 3)
        x1, y1 = p1
        x2, y2 = p2
        x3, y3 = p3
        d = 2 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2))
        if abs(d) < 1e-5:
            continue
        cx = ((x1**2 + y1**2) * (y2 - y3) + (x2**2 + y2**2) * (y3 - y1) + (x3**2 + y3**2) * (y1 - y2)) / d
        cy = ((x1**2 + y1**2) * (x3 - x2) + (x2**2 + y2**2) * (x1 - x3) + (x3**2 + y3**2) * (x2 - x1)) / d
        R = math.sqrt((x1 - cx) ** 2 + (y1 - cy) ** 2)
        if R <= 0:
            continue
        thr = rel_threshold * R
        dist = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
        inliers = int(np.sum(np.abs(dist - R) < thr))
        if inliers > max_inliers:
            max_inliers = inliers
            best = (cx, cy, R)

    if best is None:
        return None
    cx, cy, R = best
    return cx, cy, R, max_inliers / n


def circle_crop(img_array: np.ndarray, cx: float, cy: float, R: float, margin: float = 1.05) -> np.ndarray:
    """Recorte quadrado à volta de um círculo (centro, raio) detetado por RANSAC."""
    half = R * margin
    y1 = max(0, int(cy - half))
    y2 = min(img_array.shape[0], int(cy + half))
    x1 = max(0, int(cx - half))
    x2 = min(img_array.shape[1], int(cx + half))
    return img_array[y1:y2, x1:x2]


def square_crop(img_array: np.ndarray, contour, margin: float = 1.05) -> np.ndarray:
    """Recorte quadrado dos píxeis RGB à volta do contorno."""
    x, y, bw, bh = cv2.boundingRect(contour)
    cx, cy = x + bw // 2, y + bh // 2
    lado = int(max(bw, bh) * margin)
    y1 = max(0, cy - lado // 2)
    y2 = min(img_array.shape[0], cy + lado // 2)
    x1 = max(0, cx - lado // 2)
    x2 = min(img_array.shape[1], cx + lado // 2)
    return img_array[y1:y2, x1:x2]


def is_apple(metrics: dict, args) -> tuple[bool, str]:
    """Decide se os descritores correspondem a uma maçã. Devolve (ok, motivo)."""
    if metrics["area_frac"] < args.min_area_frac:
        return False, f"area_frac={metrics['area_frac']:.3f}<{args.min_area_frac}"
    if metrics["circle_fill"] < args.min_circle_fill:
        return False, f"circ_fill={metrics['circle_fill']:.2f}<{args.min_circle_fill}"
    if metrics["aspect"] > args.max_aspect:
        return False, f"aspect={metrics['aspect']:.2f}>{args.max_aspect}"
    if metrics["solidity"] < args.min_solidity:
        return False, f"solidez={metrics['solidity']:.2f}<{args.min_solidity}"
    return True, "ok"


def load_rgb(path: Path):
    try:
        img = Image.open(path)
        img.load()
        return img.convert("RGB")
    except Exception as e:
        print(f"      [erro a abrir] {path.name}: {e}")
        return None


def extract_disease_name(folder_name: str) -> str:
    disease = folder_name.split("_-", 1)[0]
    disease = disease.replace("apple_fruit_", "", 1)
    for suffix in ("_lesion", "_disease", "_damage", "_disorder"):
        if disease.endswith(suffix):
            disease = disease[: -len(suffix)]
            break
    return disease or folder_name


def move_reject(img_path: Path, reject_dir: Path, folder_name: str, dry_run: bool):
    if dry_run:
        return
    if not img_path.exists():
        return
    reject_dir.mkdir(parents=True, exist_ok=True)
    disease = extract_disease_name(folder_name)
    dest = reject_dir / f"{disease}_{img_path.name}"
    if dest.exists():
        dest = reject_dir / f"{disease}_{img_path.stem}_{img_path.stat().st_mtime_ns}{img_path.suffix}"
    shutil.move(str(img_path), str(dest))


def save_crops(img_path: Path, crops: list, dry_run: bool):
    if dry_run:
        return
        
    if len(crops) == 1:
        out_path = img_path.with_suffix(".png")
        Image.fromarray(crops[0]).save(out_path, "PNG")
        if img_path.suffix.lower() != ".png" and img_path.exists():
            img_path.unlink()
    else:
        for i, cr in enumerate(crops):
            out = img_path.parent / f"{img_path.stem}_{i + 1:03d}.png"
            Image.fromarray(cr).save(out, "PNG")
        if img_path.exists():
            img_path.unlink()


def show_reject_preview(img: Image.Image, filename: str, reason: str):
    arr = cv2.cvtColor(np.array(img.convert("RGB")), cv2.COLOR_RGB2BGR)
    h, w = arr.shape[:2]
    max_dim = 800
    scale = min(1.0, max_dim / max(h, w))
    if scale < 1.0:
        arr = cv2.resize(arr, (int(w * scale), int(h * scale)))

    banner_h = 50
    canvas = np.zeros((arr.shape[0] + banner_h, arr.shape[1], 3), dtype=np.uint8)
    canvas[: arr.shape[0]] = arr
    cv2.putText(canvas, filename, (8, arr.shape[0] + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
    cv2.putText(canvas, str(reason)[:90], (8, arr.shape[0] + 42), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 255), 1, cv2.LINE_AA)

    cv2.imshow("Rejeitada -- qualquer tecla para continuar", canvas)
    cv2.waitKey(0)
    cv2.destroyAllWindows()


def filter_folder(folder: Path, args):
    images = [p for p in folder.glob("*") if p.suffix.lower() in IMG_EXTS]
    if not images:
        return 0, 0

    reject_dir = folder.parent / REJECT_DIRNAME
    kept, rejected = 0, 0

    for img_path in images:
        img = load_rgb(img_path)
        if img is None:
            rejected += 1
            move_reject(img_path, reject_dir, folder.name, args.dry_run)
            continue

        try:
            img_bytes = img_path.read_bytes()

            if has_excessive_foliage(img_bytes):
                rejected += 1
                print(f"      [rejeita] {img_path.name} (demasiada folhagem verde)")
                if args.preview_rejects:
                    show_reject_preview(img, img_path.name, "demasiada folhagem verde")
                move_reject(img_path, reject_dir, folder.name, args.dry_run)
                continue

            apple_ok, yolo_reason = is_valid_apple_yolo(img_bytes)
            if not apple_ok:
                rejected += 1
                print(f"      [rejeita] {img_path.name} ({yolo_reason})")
                if args.preview_rejects:
                    show_reject_preview(img, img_path.name, yolo_reason)
                move_reject(img_path, reject_dir, folder.name, args.dry_run)
                continue

            if args.strict_classifier:
                blocked, reason = is_image_blocked_fruit(img_bytes)
                if blocked:
                    rejected += 1
                    print(f"      [rejeita] {img_path.name} (classificador: {reason})")
                    if args.preview_rejects:
                        show_reject_preview(img, img_path.name, f"classificador: {reason}")
                    move_reject(img_path, reject_dir, folder.name, args.dry_run)
                    continue
        except Exception as e:
            print(f"      Aviso nos pré-filtros para {img_path.name}: {e}")

        mask = rembg_mask(img)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        img_area = float(mask.shape[0] * mask.shape[1])
        img_array = np.asarray(img)

        original_rgba = np.array(img.convert("RGBA"))
        contours_corrigidos, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        apple_crops = []
        rejected_notes = []
        
        valid_contours = []
        for c in contours_corrigidos:
            area = cv2.contourArea(c)
            area_frac = area / img_area
            if area_frac >= args.min_area_frac:
                valid_contours.append(c)
                
        for c in valid_contours:
            x, y, w, h = cv2.boundingRect(c)
            cx = x + w // 2
            cy = y + h // 2
            
            local_mask = np.zeros_like(mask)
            raio_protecao = int(max(w, h) * 0.45)
            cv2.circle(local_mask, (cx, cy), raio_protecao, 255, -1)
            
            hull = cv2.convexHull(c)
            cv2.drawContours(local_mask, [hull], 0, 255, -1)
            
            final_mask = cv2.bitwise_and(mask, local_mask)
            
            coords = cv2.findNonZero(final_mask)
            if coords is None:
                continue
            x, y, w, h = cv2.boundingRect(coords)
            cx = x + w // 2
            cy = y + h // 2
            
            apple_rgba = original_rgba.copy()
            apple_rgba[:, :, 3] = final_mask
            
            lado_maximo = int(max(w, h) * 1.05)
            y1 = max(0, cy - lado_maximo // 2)
            y2 = min(apple_rgba.shape[0], cy + lado_maximo // 2)
            x1 = max(0, cx - lado_maximo // 2)
            x2 = min(apple_rgba.shape[1], cx + lado_maximo // 2)
            
            cropped_matrix = apple_rgba[y1:y2, x1:x2]
            
            if cropped_matrix.shape[0] < args.min_size or cropped_matrix.shape[1] < args.min_size:
                rejected_notes.append(f"crop {cropped_matrix.shape[1]}x{cropped_matrix.shape[0]}<{args.min_size}")
                continue
            
            crop_h, crop_w = cropped_matrix.shape[:2]
            aspect_ratio = max(crop_w, crop_h) / max(min(crop_w, crop_h), 1)
            if aspect_ratio > 2.5:
                rejected_notes.append(f"forma muito alongada (aspect={aspect_ratio:.1f}>2.5)")
                continue
            
            perimeter = cv2.arcLength(c, True)
            contour_area = cv2.contourArea(c)
            if perimeter > 0:
                circularity = 4 * math.pi * contour_area / (perimeter ** 2)
                if circularity < 0.20:
                    rejected_notes.append(f"forma não circular (circularity={circularity:.2f}<0.20)")
                    continue

            apple_crops.append(cropped_matrix)

        if apple_crops:
            if args.no_crop:
                kept += 1
                if args.dry_run:
                    print(f"      [MANTEM] {img_path.name} ({len(apple_crops)} maca(s) detetada(s))")
            else:
                save_crops(img_path, apple_crops, args.dry_run)
                kept += len(apple_crops)
                if args.dry_run or len(apple_crops) > 1:
                    print(f"      [MANTEM] {img_path.name} -> {len(apple_crops)} maca(s)")
        else:
            rejected += 1
            motivo = rejected_notes[0] if rejected_notes else "sem contorno de maçã"
            print(f"      [rejeita] {img_path.name} ({motivo})")
            if args.preview_rejects:
                show_reject_preview(img, img_path.name, motivo)
            move_reject(img_path, reject_dir, folder.name, args.dry_run)

    return kept, rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--folder", type=str, default=None, help="processa só uma subpasta de SCARPP")
    parser.add_argument("--dry-run", action="store_true", help="só relata métricas, não move nada")
    parser.add_argument("--no-crop", action="store_true", help="modo validação: mantém as boas como estão (não re-cropa nem divide), só remove rejeitadas")
    parser.add_argument("--preview-rejects", action="store_true", help="mostra cada imagem antes de a rejeitar (janela com o motivo escrito por baixo); premir qualquer tecla para continuar.")
    parser.add_argument(
        "--strict-classifier",
        action="store_true",
        help="liga a blacklist MobileNetV3 (fruto errado/lixo). Desligada por omissão.",
    )

    parser.add_argument("--min-area-frac", type=float, default=0.02, help="fração mínima da imagem que a maçã tem de ocupar (default: 0.02)")
    parser.add_argument("--min-circle-fill", type=float, default=0.40, help="preenchimento mínimo do círculo envolvente area/(pi*R^2) (default: 0.40)")
    parser.add_argument("--max-aspect", type=float, default=2.20, help="aspect ratio máximo do minAreaRect (default: 2.20)")
    parser.add_argument("--min-solidity", type=float, default=0.50, help="solidez mínima area/hull (default: 0.50)")
    parser.add_argument("--min-size", type=int, default=100, help="descarta crops mais pequenos que N x N píxeis (default: 100)")
    parser.add_argument("--min-inlier", type=float, default=0.50, help="fração mínima de pontos do contorno no círculo RANSAC (default: 0.50)")

    args = parser.parse_args()

    SKIP = {REJECT_DIRNAME, "folhas"}
    if args.folder:
        folders = [OUT_DIR / args.folder]
    else:
        folders = [p for p in OUT_DIR.iterdir() if p.is_dir() and p.name not in SKIP]

    print("[setup] A pré-carregar modelos de visão...")
    init_classifier()
    init_yolo()
    print("[setup] Modelos prontos.\n")

    total_kept, total_rejected = 0, 0
    for folder in sorted(folders):
        if not folder.exists():
            print(f"[skip] pasta não existe: {folder}")
            continue
        print(f"[filtra] {folder.name}")
        kept, rejected = filter_folder(folder, args)
        print(f"  -> {kept} maçãs mantidas, {rejected} rejeitadas")
        total_kept += kept
        total_rejected += rejected

    mode = " (DRY-RUN, nada foi movido)" if args.dry_run else ""
    print(f"\nTotal: {total_kept} maçãs mantidas, {total_rejected} rejeitadas{mode}")
    if not args.dry_run and total_rejected:
        print(f"Rejeitadas movidas para: {OUT_DIR / REJECT_DIRNAME}")


if __name__ == "__main__":
    main()
