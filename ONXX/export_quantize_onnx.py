#!/usr/bin/env python3
"""
export_quantize_onnx.py
-----------------------
Exporta o modelo MobileNetV2 (.pth) para ONNX, simplifica e quantiza (INT8 dinamico).

Uso:
    python export_quantize_onnx.py --weights ../ONNX_2.pth --onnx model2.onnx

CRITICO: O modelo e construido com a mesma arquitectura do CNN1.py:
  1. mobilenet_v2 com pesos ImageNet (NAO com num_classes=N no construtor)
  2. Substitui-se APENAS classifier[1] pela camada linear final
  Passar num_classes ao construtor cria uma arquitectura diferente e os
  pesos do .pth ficam mapeados incorrectamente -> previsoes erradas.
"""
import argparse
import json
import os
import subprocess

import torch
import torch.nn as nn
from torchvision import models


# ---------------------------------------------------------------------------
# Metadados (arquitectura/classes) — mesmo ficheiro .json que fica ao lado do
# .pth gravado por train_cnn.py / shadow_runner.py
# ---------------------------------------------------------------------------

def read_model_metadata(weights_path: str) -> dict:
    meta_path = os.path.splitext(weights_path)[0] + '.json'
    if os.path.exists(meta_path):
        with open(meta_path, encoding='utf-8') as f:
            return json.load(f)
    return {}


# ---------------------------------------------------------------------------
# Exportacao
# ---------------------------------------------------------------------------

def build_model(num_classes):
    """Constroi o modelo com a MESMA arquitectura usada em CNN1.py."""
    model = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.IMAGENET1K_V1)
    model.classifier[1] = nn.Linear(model.last_channel, num_classes)
    return model


def export_onnx(weights_path, onnx_path, input_size, num_classes):
    model = build_model(num_classes)

    state = torch.load(weights_path, map_location='cpu')
    # Suporta state_dict directo ou encapsulado em {'state_dict': ...}
    sd = state.get('state_dict', state) if isinstance(state, dict) else state
    # Remover prefixos 'module.' (DataParallel)
    sd = {k.replace('module.', ''): v for k, v in sd.items()}
    model.load_state_dict(sd)
    model.eval()

    dummy = torch.randn(1, 3, input_size, input_size)

    # dynamo=False -> usa o exportador TorchScript (legado, estavel no PyTorch 2.x).
    # O novo exportador dynamo requer onnxscript e causa erros de encoding no Windows.
    torch.onnx.export(
        model, dummy, onnx_path,
        input_names=['input'],
        output_names=['output'],
        opset_version=17,
        do_constant_folding=True,
        dynamic_axes={'input': {0: 'batch_size'}, 'output': {0: 'batch_size'}},
        dynamo=False,
    )
    print('ONNX exportado para:', onnx_path)


# ---------------------------------------------------------------------------
# Simplificacao (opcional)
# ---------------------------------------------------------------------------

def simplify_onnx(onnx_in, onnx_out, input_size):
    try:
        # pyrefly: ignore [missing-import]
        from onnxsim import simplify
        import onnx
        model = onnx.load(onnx_in)
        model_simp, check = simplify(model, input_shapes={'input': [1, 3, input_size, input_size]})
        if check:
            onnx.save(model_simp, onnx_out)
            print('ONNX simplificado guardado em:', onnx_out)
            return True
        else:
            print('Simplificador devolveu check=False; a ignorar.')
            return False
    except Exception as e:
        print('onnx-simplifier falhou, a tentar CLI:', e)
        try:
            subprocess.run(['python', '-m', 'onnxsim', onnx_in, onnx_out], check=True)
            print('ONNX simplificado guardado em:', onnx_out)
            return True
        except Exception as e2:
            print('Simplificacao via CLI falhou:', e2)
            return False


# ---------------------------------------------------------------------------
# Quantizacao INT8 dinamica (opcional, reduz o tamanho ~4x)
# ---------------------------------------------------------------------------

def quantize_dynamic_model(onnx_in, onnx_out):
    try:
        from onnxruntime.quantization import quantize_dynamic, QuantType
        quantize_dynamic(onnx_in, onnx_out, weight_type=QuantType.QInt8)
        print('ONNX quantizado (INT8) guardado em:', onnx_out)
        return True
    except Exception as e:
        print('Quantizacao falhou:', e)
        return False


# ---------------------------------------------------------------------------
# Pipeline reutilizável (usado pelo CLI abaixo e por mlops_server.py)
# ---------------------------------------------------------------------------

def export_pipeline(weights_path: str, onnx_path: str, input_size: int = 224,
                     num_classes: int | None = None) -> tuple[str, str, str]:
    """Lê metadados do .pth, bloqueia ResNet50 (demasiado pesado para o
    Raspberry — só MobileNetV2 é exportado), exporta, simplifica e quantiza.
    Devolve (onnx_path, onnx_simplified_path, onnx_quant_path).
    """
    meta = read_model_metadata(weights_path)
    architecture = meta.get('architecture', 'mobilenet_v2')
    if architecture == 'resnet50':
        raise ValueError(
            "ResNet50 é demasiado pesado para correr embutido no Raspberry Pi 5 — "
            "só modelos MobileNetV2 podem ser exportados para ONNX/Pi. "
            f"({os.path.basename(weights_path)} é '{architecture}')"
        )

    if num_classes is None:
        classes = meta.get('classes')
        num_classes = len(classes) if classes else meta.get('num_classes', 2)

    onnx_simp = os.path.splitext(onnx_path)[0] + '_simplified.onnx'
    onnx_quant = os.path.splitext(onnx_path)[0] + '_quant.onnx'

    export_onnx(weights_path, onnx_path, input_size, num_classes)

    if not simplify_onnx(onnx_path, onnx_simp, input_size):
        onnx_simp = onnx_path

    if not quantize_dynamic_model(onnx_simp, onnx_quant):
        print('Quantizacao falhou; a usar o modelo nao-quantizado:', onnx_simp)
        onnx_quant = onnx_simp

    return onnx_path, onnx_simp, onnx_quant


# ---------------------------------------------------------------------------
# Ponto de entrada
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(description='Exporta .pth MobileNetV2 para ONNX')
    p.add_argument('--weights',     default='../ONNX_2.pth', help='Caminho para o .pth treinado')
    p.add_argument('--onnx',        default='model2.onnx',   help='Nome do ficheiro ONNX de saida')
    p.add_argument('--input_size',  type=int, default=224)
    p.add_argument('--num_classes', type=int, default=None,
                   help='Força o número de classes; por omissão lê do .json de metadados ao lado do .pth')
    args = p.parse_args()

    if not os.path.exists(args.weights):
        print('Ficheiro de pesos nao encontrado:', args.weights)
        return

    try:
        onnx_path, onnx_simp, onnx_quant = export_pipeline(
            args.weights, args.onnx, args.input_size, args.num_classes
        )
    except ValueError as e:
        print('Erro:', e)
        return

    print('\nFicheiros gerados:')
    for f in [onnx_path, onnx_simp, onnx_quant]:
        if os.path.exists(f):
            print(' -', f)


if __name__ == '__main__':
    main()
