#!/usr/bin/env python3
"""Descarrega imagens de maçã (o FRUTO, não folha/árvore) para testar a
generalização do par CNN2/CNN5 a doenças e origens que nunca viram em treino.

Não classifica nada e não guarda nenhum rótulo "real" — só descarrega imagens
brutas para pastas locais. A query de busca fica registada num manifest.csv
apenas para tua referência (ex: perceber depois "isto veio da pesquisa X"),
não é um label e não deve ser tratado como ground truth.

Foco: qualquer doença/praga do FRUTO da maçã. As 4 já conhecidas do CNN5
(Anthracnose, Blotch, Rot, Scab) também estão na lista — servem para testar
generalização de origem (fonte nova, mesma doença). O resto são classes que
o CNN5 nunca viu, para testar o comportamento "não sei" (baixa confiança /
triagem manual).

POR QUE PLAYWRIGHT E NÃO icrawler/requests:
A tentativa anterior usava o endpoint interno `bing.com/images/async` (o que
o Bing chama via AJAX quando fazes scroll na página). Pedido diretamente por
um script, sem cookies de sessão nem execução de JS, esse endpoint devolveu
imagens completamente não relacionadas (celebridades, wallpapers) em vez de
maçãs — quase certamente uma defesa anti-scraping que responde 200 OK mas
com conteúdo envenenado para pedidos que não parecem vir de um browser real.
A própria página de busca normal (bing.com/images/search), a que vês no
browser, funciona bem. Por isso este script usa um Chromium real via
Playwright para carregar essa página como um utilizador faria, e só depois
lê as imagens já renderizadas no DOM.

SETUP (correr uma vez, antes do script):
  pip install playwright requests
  playwright install chromium

Uso:
  python scrape_apple_diseases.py                          # todas as queries, 120 imagens cada
  python scrape_apple_diseases.py --max-num 60              # menos imagens por query
  python scrape_apple_diseases.py --query "apple fruit fire blight"
  python scrape_apple_diseases.py --headed                  # abre o Chromium visível, para veres o que está a acontecer
"""
import argparse
import csv
import hashlib
import io
import json
import random
import time
from datetime import datetime, timezone
from pathlib import Path

import requests
from PIL import Image
from playwright.sync_api import sync_playwright

from apple_filters import (
    has_excessive_foliage,
    init_classifier,
    init_yolo,
    is_image_blocked_fruit,
    is_valid_apple_yolo,
)


OUT_DIR = Path("./data/scrappa")  # ajusta para a pasta de saída local
MANIFEST_PATH = OUT_DIR / "manifest.csv"

# Múltiplos user agents para variar entre queries
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
]

# Exclusões comuns aplicadas a TODAS as queries:
#  - Fora folhas/árvore/ramo/flor/casca: evitam as partes verdes não-fruto
#  - Fora outros frutos que partilham nomes de doença ou são confundíveis:
#    custard/sugar apple (anona), manga, morango, pêra, goiaba, tomate, uva, pêssego, etc.
#  - Fora microscopia, desenhos, infográficos, tabelas e vetores
#  - Fora dispositivos Apple Inc. (iphone, ipad, watch, etc.) que aparecem em certas queries (ex: superficial scald)
# EXCLUDE enxuto: apenas o essencial que a visão computacional não resolve facilmente.
# O excesso de operadores leva o Bing a ignorar a lista inteira.
EXCLUDE = (
    "-leaf -tree -branch "
    "-diagram -illustration -vector -microscope "
    "-iphone -ipad -macbook -computer -icon"
)

# SÓ doenças/desordens/pragas do FRUTO da maçã. Incluída agora a "anthracnose".
DISEASES = [
    "scab", "black rot", "white rot", "bitter rot", "brown rot",
    "blue mold rot", "gray mold rot", "bulls eye rot", "penicillium rot",
    "fire blight", "anthracnose", "bitter pit", "cork spot", "sooty blotch", "flyspeck",
    "sunscald", "sunburn", "hail damage", "frost damage", "russeting",
    "lenticel breakdown", "stink bug damage", "superficial scald",
    "bruise damage", "rotten",
]

# Metadados das doenças para guiar a expansão de queries com termos comuns e científicos.
# Isto ajuda a diversificar a busca e a encontrar fontes académicas, profissionais e de
# extensão agrícola que contêm apenas fotos de frutos verificados e de alta qualidade.
DISEASE_METADATA = {
    "scab": {
        "scientific": ["Venturia inaequalis"],
        "terms": ["scab lesion", "scab spot", "black spot disease"]
    },
    "black rot": {
        "scientific": ["Botryosphaeria obtusa", "Physalospora obtusa"],
        "terms": ["black rot decay", "black rot spot", "black rot canker"]
    },
    "white rot": {
        "scientific": ["Botryosphaeria dothidea"],
        "terms": ["white rot decay", "white rot spot"]
    },
    "bitter rot": {
        "scientific": ["Colletotrichum acutatum", "Colletotrichum gloeosporioides", "Glomerella cingulata"],
        "terms": ["bitter rot decay", "bitter rot lesion"]
    },
    "brown rot": {
        "scientific": ["Monilinia fructigena", "Monilinia laxa"],
        "terms": ["brown rot decay", "brown rot mold"]
    },
    "blue mold rot": {
        "scientific": ["Penicillium expansum"],
        "terms": ["blue mold decay", "blue mold lesion"]
    },
    "gray mold rot": {
        "scientific": ["Botrytis cinerea"],
        "terms": ["gray mold decay", "grey mold rot"]
    },
    "bulls eye rot": {
        "scientific": ["Neofabraea malicorticis", "Pezicula malicorticis"],
        "terms": ["bullseye rot decay", "bulls eye rot lesion"]
    },
    "penicillium rot": {
        "scientific": ["Penicillium expansum"],
        "terms": ["penicillium rot decay"]
    },
    "fire blight": {
        "scientific": ["Erwinia amylovora"],
        "terms": ["fire blight lesion", "fire blight damage"]
    },
    "anthracnose": {
        "scientific": ["Colletotrichum", "Colletotrichum acutatum", "Colletotrichum gloeosporioides"],
        "terms": ["anthracnose fruit rot", "anthracnose lesion", "anthracnose spot"]
    },
    "bitter pit": {
        "scientific": [],
        "terms": ["bitter pit calcium", "bitter pit spot", "bitter pit disorder"]
    },
    "cork spot": {
        "scientific": [],
        "terms": ["cork spot disorder", "cork spot lesion"]
    },
    "sooty blotch": {
        "scientific": ["Gloeodes pomigena", "Phyllachora pomigena"],
        "terms": ["sooty blotch fungus", "sooty blotch spot", "sooty blotch and flyspeck", "apple blotch", "blotch disease", "blotch lesion"]
    },
    "flyspeck": {
        "scientific": ["Schizothyrium pomi"],
        "terms": ["flyspeck disease", "flyspeck fungus"]
    },
    "sunscald": {
        "scientific": [],
        "terms": ["sunscald damage", "sunscald skin", "sunscald injury"]
    },
    "sunburn": {
        "scientific": [],
        "terms": ["sunburn damage", "sunburn skin", "sunburn necrosis"]
    },
    "hail damage": {
        "scientific": [],
        "terms": ["hail damage spot", "hail injury", "hail scar"]
    },
    "frost damage": {
        "scientific": [],
        "terms": ["frost damage ring", "frost injury", "frost blemish"]
    },
    "russeting": {
        "scientific": [],
        "terms": ["russeted skin", "russeting disorder", "russeting finish"]
    },
    "lenticel breakdown": {
        "scientific": [],
        "terms": ["lenticel breakdown spot", "lenticel spot", "lenticel pit"]
    },
    "codling moth damage": {
        "scientific": ["Cydia pomonella"],
        "terms": ["codling moth worm", "codling moth entry hole", "codling moth tunnel"]
    },
    "stink bug damage": {
        "scientific": ["Halyomorpha halys"],
        "terms": ["stink bug injury", "stink bug feeding spot", "stink bug bite"]
    },
    "superficial scald": {
        "scientific": [],
        "terms": ["superficial scald storage", "scald damage", "scalded skin"]
    },
    "bruise damage": {
        "scientific": [],
        "terms": ["bruised fruit", "bruising damage", "mechanical bruise"]
    },
    "rotten": {
        "scientific": [],
        "terms": ["rotten fruit", "decayed fruit", "decomposed fruit", "spoiled fruit"]
    }
}

MIN_BYTES = 3000  # descarta respostas demasiado pequenas para ser fotos reais


def get_query_variations(disease_or_query: str) -> list[str]:
    """Gera múltiplas queries de pesquisa para diversificar a busca e obter
    mais imagens com melhor cobertura de termos e nomes científicos.
    """
    clean = disease_or_query.strip().lower()
    
    # Se o utilizador inseriu exclusões manuais, limpa-as para usar o EXCLUDE padrão
    if " -" in clean:
        clean = clean.split(" -")[0].strip()
        
    # Tenta encontrar correspondência na lista de doenças conhecidas
    matched_disease = None
    clean_normalized = clean.replace("_", " ").strip()
    
    for d in DISEASES:
        d_norm = d.lower()
        if d_norm == clean_normalized or d_norm in clean_normalized or clean_normalized in d_norm:
            matched_disease = d
            break
            
    disease_key = matched_disease if matched_disease else clean_normalized
    
    variations = []
    
    # Se existe metadados definidos, usa-os para criar queries direcionadas
    meta = DISEASE_METADATA.get(disease_key)
    if meta:
        variations.append(f'"apple fruit" "{disease_key}"')
        for t in meta["terms"]:
            variations.append(f'"apple fruit" "{t}"')
        for sc in meta["scientific"]:
            variations.append(f'"apple fruit" "{sc}"')
            variations.append(f'"{sc}" "apple fruit"')
            variations.append(f'"malus domestica" "{sc}"')
    else:
        # Variações automáticas baseadas em termos genéricos
        variations.append(f'"apple fruit" "{disease_key}"')
        variations.append(f'"apple fruit" with "{disease_key}"')
        variations.append(f'"{disease_key}" symptoms on "apple fruit"')
        variations.append(f'"malus domestica" "{disease_key}"')

    # Modificadores de enquadramento: forçam planos fechados e isolados do fruto
    # Aplicados sobre o disease_key base para diversificar sem duplicar as queries principais
    variations.append(f'"apple fruit" "{disease_key}" close up')
    variations.append(f'isolated "apple fruit" "{disease_key}"')
    variations.append(f'macro "apple" "{disease_key}"')
        
    # Limpa duplicados mantendo a ordem original
    seen = set()
    unique_vars = []
    for var in variations:
        if var not in seen:
            seen.add(var)
            unique_vars.append(var)
            
    return unique_vars


def collect_image_urls(page, target_count: int, max_scrolls: int = 20) -> list[str]:
    """Faz scroll na página de resultados já carregada e recolhe os URLs de
    imagem originais a partir do atributo `m` (JSON) de cada resultado.
    """
    urls: dict[str, None] = {}

    for _ in range(max_scrolls):
        raw_attrs = page.eval_on_selector_all("a.iusc", "els => els.map(e => e.getAttribute('m'))")
        for raw in raw_attrs:
            if not raw:
                continue
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                continue
            murl = data.get("murl")
            if murl:
                urls[murl] = None

        if len(urls) >= target_count:
            break

        # Scroll lento: pequenos movimentos com pausas
        for _ in range(3):
            page.mouse.wheel(0, 1000)
            page.wait_for_timeout(random.uniform(400, 800))

        # O Bing às vezes esconde resultados extra atrás de um botão "ver mais"
        see_more = page.query_selector("a.btn_seemore, .btn_loading")
        if see_more:
            try:
                see_more.click(timeout=1000)
                page.wait_for_timeout(random.uniform(1500, 2500))
            except Exception:
                pass

    return list(urls.keys())[:target_count]


def compute_file_hash(data: bytes) -> str:
    """Calcula MD5 de um conteúdo de ficheiro para deduplicação."""
    return hashlib.md5(data).hexdigest()


def get_existing_hashes(folder: Path) -> set[str]:
    """Retorna hashes MD5 de todos os ficheiros já descarregados na pasta."""
    hashes = set()
    # Verifica tanto na pasta principal como nas subpastas (como _rejeitadas)
    for img_path in folder.glob("**/*.jpg"):
        try:
            data = img_path.read_bytes()
            hashes.add(compute_file_hash(data))
        except Exception:
            pass
    return hashes


def download_image(url: str, dest_path: Path, existing_hashes: set[str], min_size: int = 224, strict_classifier: bool = False) -> bool:
    """Descarrega e valida uma imagem pelo tamanho e proporção usando Pillow antes de guardar.
    Pipeline de validação (do mais rápido ao mais lento):
      1. Tamanho em bytes / integridade Pillow / dimensões mínimas / aspect ratio
      2. Filtro HSV de folhagem (~2ms) — rejeita pomares e imagens de fundo verde
      3. YOLOv8n de deteção (~50ms) — confirma presença de maçã ou objeto claramente
         fora do domínio (pessoa, carro, etc.); já não exige que o MobileNet
         "reconheça fruta" quando o YOLO não vê maçã (testado contra imagens reais
         de doenças tipo bolor/podridão: esse gate sozinho rejeitava 30-45% de
         maçãs verdadeiras, porque a textura da doença engana o classificador)
      4. MobileNetV3 blacklist (~80ms) -- SÓ corre com strict_classifier=True
         (--strict-classifier). Por omissão está desligado: testado contra
         imagens reais confirmadas boas, rejeitava até 43% delas (bolor/casca
         amarelada confundidos com "orange", "lemon", "petri dish", etc.). O
         filtro fica disponível para quem quiser mais rigor à entrada, mas o
         mais seguro é filtrar mais tarde (ex: filter_apples_rembg.py com
         --preview-rejects), depois de já se ver a imagem completa.
    """
    try:
        r = requests.get(url, headers={"User-Agent": random.choice(USER_AGENTS)}, timeout=15)
        if r.status_code == 200:
            if len(r.content) >= MIN_BYTES:
                # Validação rápida com Pillow
                try:
                    img = Image.open(io.BytesIO(r.content))
                    img.verify()  # Garante integridade física
                    
                    # Abre novamente porque verify() invalida o objeto para manipulação
                    img = Image.open(io.BytesIO(r.content))
                    w, h = img.size
                    
                    # Ignora se for menor que o tamanho padrão do pipeline (224x224)
                    if w < min_size or h < min_size:
                        print(f"      [skip] dimensões pequenas ({w}x{h} < {min_size}x{min_size})")
                        return False
                        
                    # Ignora se tiver proporção extrema (tabelas, banners, infográficos, etc.)
                    aspect_ratio = max(w, h) / min(w, h)
                    if aspect_ratio > 2.5:
                        print(f"      [skip] proporção extrema ({w}x{h}, r={aspect_ratio:.2f} > 2.5)")
                        return False
                except Exception as img_err:
                    print(f"      [skip] imagem inválida ou corrupta: {img_err}")
                    return False

                # Camada 2: Filtro colorimétrico HSV (folhagem verde excessiva)
                if has_excessive_foliage(r.content):
                    return False

                # Camada 3: Deteção YOLOv8 (confirma presença e tamanho da maçã)
                apple_ok, yolo_reason = is_valid_apple_yolo(r.content)
                if not apple_ok:
                    print(f"      [skip] {yolo_reason}")
                    return False

                # Camada 4: Blacklist MobileNetV3 (frutos intrusos estruturalmente similares)
                # -- opt-in, ver docstring desta função.
                blocked, reason = (is_image_blocked_fruit(r.content) if strict_classifier else (False, ""))
                if blocked:
                    print(f"      [skip] fruta intrusa bloqueada: {reason}")
                    return False

                # Verifica duplicação
                img_hash = compute_file_hash(r.content)
                if img_hash in existing_hashes:
                    print(f"      [dup] imagem duplicada")
                    return False
                
                dest_path.write_bytes(r.content)
                existing_hashes.add(img_hash)
                return True
            else:
                print(f"      [skip] muito pequeno ({len(r.content)} bytes)")
        else:
            print(f"      [skip] status {r.status_code}")
    except Exception as e:
        print(f"      [erro] {e}")
    return False



def scrape_disease_folder(browser, name: str, query_variations: list[str], max_num: int, manifest_writer, delay_min: float, delay_max: float, strict_classifier: bool = False) -> int:
    """Faz pesquisa e download para todas as variações de queries de uma doença,
    até que a pasta contenha o limite max_num de imagens válidas descarregadas.
    """
    folder = OUT_DIR / name
    folder.mkdir(parents=True, exist_ok=True)

    existing_files = [p for p in folder.glob("*") if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg")]
    existing = len(existing_files)
    if existing >= max_num:
        print(f"[skip] '{name}' já tem {existing} imagens (alvo: {max_num})")
        return 0

    existing_hashes = get_existing_hashes(OUT_DIR)
    total_downloaded = 0

    print(f"\n[doença] A iniciar recolha para '{name}' (alvo: {max_num}, atual: {existing})")
    print(f"  Variações de queries: {query_variations}")

    for idx, base_query in enumerate(query_variations):
        # Re-avalia o número de ficheiros locais antes de iniciar nova query
        existing_files = [p for p in folder.glob("*") if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg")]
        existing = len(existing_files)
        if existing >= max_num:
            print(f"  [concluído] Atingido o limite de {max_num} imagens para '{name}'.")
            break

        query = f"{base_query} {EXCLUDE}"

        # Novo contexto para esta query (reset de cookies/sessão, novo user agent)
        user_agent = random.choice(USER_AGENTS)
        context = browser.new_context(user_agent=user_agent, locale="en-US", viewport={"width": 1600, "height": 1000})
        page = context.new_page()

        try:
            print(f"  -> A pesquisar query {idx + 1}/{len(query_variations)}: '{base_query}'")
            search_url = f"https://www.bing.com/images/search?q={query.replace(' ', '+')}&qft=+filterui:photo-photo"
            page.goto(search_url, timeout=30000)
            page.wait_for_timeout(random.uniform(1500, 2500))

            needed = max_num - existing
            urls = collect_image_urls(page, needed)
            print(f"    '{base_query}': {len(urls)} URLs candidatos encontrados")

            now = datetime.now(timezone.utc).isoformat()
            query_downloads = 0
            
            for i, url in enumerate(urls):
                # Verifica a contagem de ficheiros dinamicamente a cada imagem
                existing_files = [p for p in folder.glob("*") if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg")]
                current_count = len(existing_files)
                if current_count >= max_num:
                    print(f"    [concluído] Atingido o limite de {max_num} imagens.")
                    break

                # Garante que não sobrescrevemos ficheiros existentes devido a gaps na numeração
                file_num = current_count + 1
                while (folder / f"{file_num:06d}.jpg").exists():
                    file_num += 1
                dest = folder / f"{file_num:06d}.jpg"
                if download_image(url, dest, existing_hashes, strict_classifier=strict_classifier):
                    manifest_writer.writerow([dest.relative_to(OUT_DIR), query, now])
                    query_downloads += 1
                    total_downloaded += 1
                
                # Delay entre downloads para evitar rate limits
                if i < len(urls) - 1:
                    time.sleep(random.uniform(1.0, 3.0))

            print(f"    [ok] Query '{base_query}' descarregou +{query_downloads} imagens.")
            
            # Se ainda houver queries pendentes e precisarmos de mais imagens, espera
            if idx < len(query_variations) - 1:
                existing_files = [p for p in folder.glob("*") if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg")]
                if len(existing_files) < max_num:
                    delay = random.uniform(delay_min, delay_max)
                    print(f"    [aguarda] {delay:.0f}s antes da próxima variação...")
                    time.sleep(delay)

        except Exception as query_err:
            print(f"    [erro na query] '{base_query}': {query_err}")
        finally:
            context.close()

    return total_downloaded


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--max-num", type=int, default=120, help="máximo de imagens por query (default: 120)")
    parser.add_argument("--query", type=str, default=None, help="corre só uma query específica em vez da lista toda")
    parser.add_argument(
        "--delay-min",
        type=float,
        default=30.0,
        help="pausa mínima entre queries, em segundos (default: 30 — anti-bloqueio)",
    )
    parser.add_argument(
        "--delay-max",
        type=float,
        default=60.0,
        help="pausa máxima entre queries, em segundos (default: 60 — anti-bloqueio)",
    )
    parser.add_argument("--headed", action="store_true", help="abre o Chromium visível (útil para debugging)")
    parser.add_argument(
        "--strict-classifier",
        action="store_true",
        help="liga a blacklist MobileNetV3 (fruto errado/lixo) à entrada. Desligado por omissão: "
             "testado contra imagens reais confirmadas boas, rejeitava até 43%% delas em categorias "
             "de bolor/podridão (a doença engana o classificador). Mais seguro filtrar isso mais "
             "tarde, com revisão (ex: filter_apples_rembg.py --preview-rejects).",
    )
    parser.add_argument("--blotch", action="store_true", help="Modo especial: recolhe no mínimo 300 imagens diversificadas apenas de 'blotch' / 'sooty blotch'")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest_is_new = not MANIFEST_PATH.exists()

    # Pré-carrega ambos os modelos ANTES do Playwright arrancar.
    # O carregamento lazy dentro do scraper pode causar deadlock (inicialização
    # CUDA/ONNX dentro de uma thread com I/O ativo do browser).
    print("[setup] A pré-carregar modelos de visão...")
    init_classifier()
    init_yolo()
    print("[setup] Modelos prontos. A iniciar o browser...\n")

    if args.query:
        # Nome da pasta a partir do termo de pesquisa (slug)
        # Tenta bater com uma doença conhecida para usar um slug limpo
        matched_disease = None
        clean_normalized = args.query.lower().replace("_", " ").strip()
        for d in DISEASES:
            if d.lower() == clean_normalized or d.lower() in clean_normalized or clean_normalized in d.lower():
                matched_disease = d
                break
        
        if matched_disease:
            slug = matched_disease.replace(" ", "_")
        else:
            slug = "_".join(w for w in args.query.split() if not w.startswith("-"))[:60] or "query"
            
        queries_to_run = [(slug, get_query_variations(args.query))]
    elif args.blotch:
        args.max_num = max(args.max_num, 300)
        # Lista massiva de variações só para Blotch, para garantir as 300 imagens
        blotch_vars = [
            '"apple fruit" "sooty blotch"',
            '"apple fruit" "blotch"',
            '"apple fruit" "sooty blotch and flyspeck"',
            '"apple" "blotch disease"',
            '"apple fruit" "apple blotch"',
            '"apple" "Gloeodes pomigena"',
            '"apple" "Phyllachora pomigena"',
            '"apple" "sooty blotch fungus"',
            '"malus domestica" "sooty blotch"',
            '"malus domestica" "blotch"',
            '"apple fruit" "blotch lesion"',
            '"apple fruit" "sooty blotch spot"',
            'isolated "apple fruit" "blotch"',
            'macro "apple" "blotch"'
        ]
        queries_to_run = [("blotch-new", blotch_vars)]
    else:
        queries_to_run = [(d.replace(" ", "_"), get_query_variations(d)) for d in DISEASES]

    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=not args.headed)

        with open(MANIFEST_PATH, "a", newline="", encoding="utf-8") as mf:
            writer = csv.writer(mf)
            if manifest_is_new:
                writer.writerow(["file", "search_query", "downloaded_at_utc"])

            total = 0
            for i, (name, variations) in enumerate(queries_to_run):
                total += scrape_disease_folder(
                    browser, name, variations, args.max_num, writer, args.delay_min, args.delay_max,
                    strict_classifier=args.strict_classifier,
                )
                
                # Pausa global entre doenças diferentes
                if i < len(queries_to_run) - 1:
                    delay = random.uniform(args.delay_min, args.delay_max)
                    print(f"  [aguarda] {delay:.0f}s antes da próxima doença...")
                    time.sleep(delay)

        browser.close()

    print(f"\nTotal descarregado nesta corrida: {total} imagens em {OUT_DIR}")


if __name__ == "__main__":
    main()
