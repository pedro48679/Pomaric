"""
Servidor de Inferência CNN2 + Servidor de Imagens
Combina o servidor de imagens (CORS) com a API de classificação ResNet50.

Endpoints:
  GET  /                        → lista as imagens disponíveis
  GET  /<filename>              → serve a imagem (com CORS)
  POST /classify                → classifica uma imagem
       Body JSON: {"image_url": "http://localhost:8000/Baldwin (151)_mask.png"}
       Resposta:  {"class": "Rot", "confidence": 0.88, "all_probs": {...}}

Uso:
  python inference_server.py
  (Abre num terminal à parte, não fecha enquanto a dashboard estiver a correr)
"""

import http.server
import json
import os
import threading
import urllib.request
from io import BytesIO
from urllib.parse import urlparse, unquote

import torch
import torch.nn as nn
from torchvision import models, transforms
from PIL import Image

# ─── Configuração ────────────────────────────────────────────────────────────

IMAGES_DIR   = "./sample_images"  # ajusta para uma pasta local de imagens de teste
MODEL_PATH   = os.path.join(os.path.dirname(os.path.abspath(__file__)), "melhor_weight_multiclass_RESnet50_BEST.pth")
PORT         = 8000
CLASS_NAMES  = ['Anthracnose', 'Blotch', 'Healthy', 'Rot', 'Scab']  # ordem alfabética do ImageFolder
DEVICE       = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# ─── Carregar Modelo ──────────────────────────────────────────────────────────

print(f"[CNN2] A carregar ResNet50 de {MODEL_PATH}...")
_model = models.resnet50(weights=None)
_model.fc = nn.Sequential(
    nn.Dropout(p=0.5),
    nn.Linear(_model.fc.in_features, len(CLASS_NAMES))
)
_model.load_state_dict(torch.load(MODEL_PATH, map_location=DEVICE))
_model.to(DEVICE)
_model.eval()
print(f"[CNN2] Modelo carregado! A correr em: {DEVICE}")

# ─── Transformação de Imagem (igual ao val_test_transform do CNN2.py) ─────────

_transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406],
                         std=[0.229, 0.224, 0.225])
])

# ─── Função de Inferência ─────────────────────────────────────────────────────

def classify_image_from_url(image_url: str) -> dict:
    """Faz download da imagem e corre o ResNet50 nela."""
    parsed    = urlparse(image_url)
    filename  = unquote(parsed.path.lstrip("/"))
    full_path = os.path.join(IMAGES_DIR, filename)

    if os.path.exists(full_path):
        img = Image.open(full_path).convert("RGB")
    else:
        # Fallback: tenta fazer download via URL
        with urllib.request.urlopen(image_url) as response:
            img = Image.open(BytesIO(response.read())).convert("RGB")

    tensor = _transform(img).unsqueeze(0).to(DEVICE)

    with torch.no_grad():
        outputs    = _model(tensor)
        probs_raw  = torch.softmax(outputs, dim=1)[0]
        probs      = {CLASS_NAMES[i]: round(float(probs_raw[i]), 4)
                      for i in range(len(CLASS_NAMES))}
        top_class  = max(probs, key=probs.get)
        confidence = probs[top_class]

    return {
        "class":      top_class,
        "confidence": confidence,
        "all_probs":  probs
    }

# ─── Handler HTTP ─────────────────────────────────────────────────────────────

class InferenceHandler(http.server.SimpleHTTPRequestHandler):

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin",  "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        if self.path == "/classify":
            try:
                length  = int(self.headers.get("Content-Length", 0))
                body    = json.loads(self.rfile.read(length).decode())
                url     = body.get("image_url", "")

                if not url:
                    self._json_error(400, "Campo 'image_url' em falta.")
                    return

                result = classify_image_from_url(url)
                self._json_ok(result)

            except Exception as e:
                self._json_error(500, str(e))
        else:
            self.send_response(404)
            self.end_headers()

    def _json_ok(self, data: dict):
        payload = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _json_error(self, code: int, msg: str):
        payload = json.dumps({"error": msg}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):
        # Só mostra logs de erros e de classificação
        if "/classify" in self.path or (len(args) > 1 and args[1] not in ('200', '304')):
            super().log_message(format, *args)

# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    os.chdir(IMAGES_DIR)
    print(f"\n[Servidor] Ativo em http://localhost:{PORT}")
    print(f"[Servidor] Imagens servidas de: {IMAGES_DIR}")
    print(f"[Servidor] Endpoint de classificação: POST http://localhost:{PORT}/classify")
    print("[Servidor] Prima Ctrl+C para parar.\n")

    with http.server.HTTPServer(("", PORT), InferenceHandler) as httpd:
        httpd.serve_forever()
