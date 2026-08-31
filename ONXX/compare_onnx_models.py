#!/usr/bin/env python3
"""Compare ONNX models: file size, load time, inference latency, memory.
Usage:
    python compare_onnx_models.py --models model.onnx model_simplified.onnx model_quant.onnx

Requires: onnxruntime, numpy, psutil
"""
import argparse
import os
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
import psutil
from PIL import Image


def human_size(n):
    for unit in ['B','KB','MB','GB']:
        if n < 1024.0:
            return f"{n:.2f}{unit}"
        n /= 1024.0
    return f"{n:.2f}TB"


def preprocess_image(path, input_size):
    with Image.open(path) as img:
        img = img.convert('RGB')
        img = img.resize((input_size, input_size), Image.BILINEAR)
        arr = np.asarray(img, dtype=np.float32) / 255.0
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        arr = (arr - mean) / std
        arr = np.transpose(arr, (2, 0, 1))
        return arr[np.newaxis, :]


def load_dataset(dataset_root, phase='valid'):
    phase_dir = Path(dataset_root) / phase
    if not phase_dir.exists():
        raise FileNotFoundError(f"Dataset phase not found: {phase_dir}")
    classes = sorted([p.name for p in phase_dir.iterdir() if p.is_dir()])
    samples = []
    for cls in classes:
        cls_dir = phase_dir / cls
        for img_path in cls_dir.iterdir():
            if img_path.suffix.lower() in ['.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff']:
                samples.append((str(img_path), cls))
    return samples, classes


def evaluate_model(path, dataset_root, phase='valid', input_size=224):
    samples, classes = load_dataset(dataset_root, phase)
    if not samples:
        raise RuntimeError(f'No images found in {dataset_root}/{phase}')
    mapping = {cls: idx for idx, cls in enumerate(classes)}
    sess = ort.InferenceSession(path, providers=['CPUExecutionProvider'])
    input_name = sess.get_inputs()[0].name
    correct = 0
    for img_path, cls in samples:
        inp = preprocess_image(img_path, input_size)
        out = sess.run(None, {input_name: inp.astype(np.float32)})[0]
        out = np.asarray(out)
        if out.ndim == 1:
            pred = int(out[0] >= 0.0)
        else:
            pred = int(np.argmax(out, axis=1)[0])
        correct += int(pred == mapping[cls])
    return {
        'accuracy': correct / len(samples),
        'total': len(samples),
        'classes': classes,
    }


def benchmark_model(path, input_shape=(1,3,224,224), runs=100, warmup=10):
    info = {}
    info['path'] = path
    info['size_bytes'] = os.path.getsize(path)
    t0 = time.perf_counter()
    sess = ort.InferenceSession(path, providers=['CPUExecutionProvider'])
    info['load_time_s'] = time.perf_counter() - t0

    # prepare random input
    inp = np.random.randn(*input_shape).astype(np.float32)
    input_name = sess.get_inputs()[0].name

    # warmup
    for _ in range(warmup):
        sess.run(None, {input_name: inp})

    proc = psutil.Process()
    mem_before = proc.memory_info().rss
    t_start = time.perf_counter()
    for _ in range(runs):
        sess.run(None, {input_name: inp})
    t_end = time.perf_counter()
    mem_after = proc.memory_info().rss

    total_time = t_end - t_start
    info['avg_ms'] = total_time / runs * 1000.0
    info['throughput'] = runs / total_time
    info['mem_before_bytes'] = mem_before
    info['mem_after_bytes'] = mem_after
    return info


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--models', nargs='+', default=['model.onnx','model_simplified.onnx','model_quant.onnx'])
    p.add_argument('--input_size', type=int, default=224)
    p.add_argument('--runs', type=int, default=100)
    p.add_argument('--warmup', type=int, default=10)
    p.add_argument('--dataset', default=None, help='Root of dataset, e.g. "C:/.../CNN1ALL - 80"')
    p.add_argument('--phase', nargs='+', default=['valid'], help='Dataset phase(s) to evaluate: valid, test, train')
    args = p.parse_args()

    results = []
    for m in args.models:
        if not os.path.exists(m):
            print('Model not found, skipping:', m)
            continue
        print('\nBenchmarking', m)
        res = benchmark_model(m, input_shape=(1,3,args.input_size,args.input_size), runs=args.runs, warmup=args.warmup)
        results.append(res)
        print(f"Size: {human_size(res['size_bytes'])}, Load: {res['load_time_s']:.3f}s, Avg: {res['avg_ms']:.2f}ms, Throughput: {res['throughput']:.2f} runs/s, Mem delta: {human_size(res['mem_after_bytes']-res['mem_before_bytes'])}")
        if args.dataset:
            for phase in args.phase:
                try:
                    eval_res = evaluate_model(m, args.dataset, phase, args.input_size)
                    print(f"Accuracy on {phase}: {eval_res['accuracy']*100:.2f}% ({eval_res['total']} images, classes={eval_res['classes']})")
                except Exception as e:
                    print(f'Evaluation failed for phase {phase}:', e)

    print('\nSummary:')
    for r in results:
        print(f"- {r['path']}: size={human_size(r['size_bytes'])}, avg={r['avg_ms']:.2f}ms, throughput={r['throughput']:.2f}r/s")

if __name__ == '__main__':
    main()
