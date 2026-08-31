import os
import argparse
import torch
import torch.nn as nn
from torchvision import models, transforms, datasets
from torch.utils.data import DataLoader
from sklearn.metrics import classification_report, confusion_matrix
import numpy as np
from tqdm import tqdm
from PIL import Image
import csv

class FlexibleDataset(torch.utils.data.Dataset):
    def __init__(self, root_dir, transform=None):
        self.root_dir = root_dir
        self.transform = transform
        self.classes = ['Anthracnose', 'Blotch', 'Healthy', 'Rot', 'Scab']
        self.class_to_idx = {c: idx for idx, c in enumerate(self.classes)}
        
        # Verificar se existem subdiretórios (ignorando a pasta _rejeitadas)
        subdirs = [d for d in os.listdir(root_dir) if os.path.isdir(os.path.join(root_dir, d)) and d != '_rejeitadas']
        self.has_subdirs = len(subdirs) > 0
        
        self.samples = []
        if self.has_subdirs:
            print(f"[Dataset] Detetados subdiretórios em '{root_dir}'. A usar modo ImageFolder.")
            self.classes = sorted(subdirs)
            self.class_to_idx = {c: idx for idx, c in enumerate(self.classes)}
            for c in self.classes:
                class_path = os.path.join(root_dir, c)
                for f in os.listdir(class_path):
                    if f.lower().endswith(('.png', '.jpg', '.jpeg')):
                        self.samples.append((os.path.join(class_path, f), self.class_to_idx[c]))
        else:
            print(f"[Dataset] Não foram detetados subdiretórios em '{root_dir}'. A usar modo de parsing de nomes de ficheiros.")
            for f in os.listdir(root_dir):
                if f.lower().endswith(('.png', '.jpg', '.jpeg')):
                    file_path = os.path.join(root_dir, f)
                    inferred_class = self._infer_class(f)
                    self.samples.append((file_path, self.class_to_idx[inferred_class]))
                    
        if len(self.samples) == 0:
            raise FileNotFoundError(f"Nenhuma imagem válida encontrada em '{root_dir}'!")

    def _infer_class(self, filename):
        name = filename.lower()
        
        # Classes exatas no início do nome
        if name.startswith('healthy') or name.startswith('health'):
            return 'Healthy'
        if name.startswith('anthracnose'):
            return 'Anthracnose'
        if name.startswith('blotch'):
            return 'Blotch'
        if name.startswith('rot') or name.startswith('rotten'):
            return 'Rot'
        if name.startswith('scab') or name.startswith('pedrado'):
            return 'Scab'
            
        # Variedades conhecidas e outros marcadores de saudável
        healthy_markers = [
            'ambrosia', 'anna', 'annurca', 'atlas', 'autumn', 'baldwin', 
            'envy', 'evercrisp', 'fuji', 'haralson', 'honeycrisp', 
            'koru', 'lady alice', 'liberty', 'braeburn', '_0_', 'dsc_'
        ]
        for marker in healthy_markers:
            if name.startswith(marker):
                return 'Healthy'
                
        # Procurar por substrings
        if 'scab' in name:
            return 'Scab'
        if 'blotch' in name:
            return 'Blotch'
        if 'rot' in name or 'podrid' in name:
            return 'Rot'
        if 'anthrac' in name:
            return 'Anthracnose'
            
        return 'Healthy'

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, target = self.samples[idx]
        img = Image.open(path).convert('RGB')
        if self.transform:
            img = self.transform(img)
        return img, target

def format_latex_metrics_table(report_dict, classes, title, label):
    """Gera uma tabela LaTeX funcional a partir do dicionário de relatório do scikit-learn."""
    tex = "```latex\n\\begin{table}[H]\n\\centering\n"
    tex += f"\\caption{{{title}}}\n"
    tex += f"\\label{{{label}}}\n"
    tex += "\\begin{tabular}{lcccc}\n"
    tex += "\\toprule\n"
    tex += "\\textbf{Classe} & \\textbf{Precision} & \\textbf{Recall} & \\textbf{F1-Score} & \\textbf{Suporte (Imagens)} \\\\\n"
    tex += "\\midrule\n"
    
    for c in classes:
        metrics = report_dict.get(c, report_dict.get(str(classes.index(c)), {}))
        if metrics:
            p = metrics.get('precision', 0.0)
            r = metrics.get('recall', 0.0)
            f1 = metrics.get('f1-score', 0.0)
            sup = int(metrics.get('support', 0))
            p_str = f"{p:.3f}".replace(".", "{,}")
            r_str = f"{r:.3f}".replace(".", "{,}")
            f1_str = f"{f1:.3f}".replace(".", "{,}")
            tex += f"{c} & {p_str} & {r_str} & {f1_str} & {sup} \\\\\n"
            
    acc = report_dict.get('accuracy', 0.0)
    acc_str = f"{acc:.3f}".replace(".", "{,}")
    weighted = report_dict.get('weighted avg', {})
    if weighted:
        wp = weighted.get('precision', 0.0)
        wr = weighted.get('recall', 0.0)
        wf1 = weighted.get('f1-score', 0.0)
        wsup = int(weighted.get('support', 0))
        wp_str = f"{wp:.3f}".replace(".", "{,}")
        wr_str = f"{wr:.3f}".replace(".", "{,}")
        wf1_str = f"{wf1:.3f}".replace(".", "{,}")
        tex += "\\midrule\n"
        tex += f"\\textbf{{Acurácia Global}} & & & \\textbf{{{acc_str}}} & \\textbf{{{wsup}}} \\\\\n"
        tex += f"\\textbf{{Média Ponderada}} & \\textbf{{{wp_str}}} & \\textbf{{{wr_str}}} & \\textbf{{{wf1_str}}} & \\textbf{{{wsup}}} \\\\\n"
        
    tex += "\\bottomrule\n\\end{tabular}\n\\end{table}\n```"
    return tex

def format_latex_confusion_matrix(matrix, classes, title, label):
    """Gera uma matriz de confusão formatada em tabela LaTeX."""
    n_classes = len(classes)
    tex = "```latex\n\\begin{table}[H]\n\\centering\n"
    tex += f"\\caption{{{title}}}\n"
    tex += f"\\label{{{label}}}\n"
    
    col_spec = "cc|" + "c" * n_classes + "|c"
    tex += f"\\begin{{tabular}}{{{col_spec}}}\n"
    
    classes_str = " & ".join(f"\\textbf{{{c}}}" for c in classes)
    tex += f"\\multicolumn{{2}}{{c}} & \\multicolumn{{{n_classes}}}{{c}}{{\\textbf{{Previsão}}}} & \\\\\n"
    tex += f"\\multicolumn{{2}}{{c}} & {classes_str} & \\textbf{{Total Real}} \\\\\n"
    tex += "\\cline{3-" + str(2 + n_classes) + "}\n"
    
    for i, actual_class in enumerate(classes):
        row_prefix = f"\\multirow{{{n_classes}}}{{\\*}}{{\\textbf{{Real}}}}" if i == 0 else ""
        vals = " & ".join(str(int(matrix[i, j])) for j in range(n_classes))
        row_total = int(matrix[i].sum())
        tex += f"{row_prefix} & \\textbf{{{actual_class}}} & {vals} & {row_total} \\\\\n"
        
    tex += "\\cline{3-" + str(2 + n_classes) + "}\n"
    
    pred_totals = " & ".join(str(int(matrix[:, j].sum())) for j in range(n_classes))
    grand_total = int(matrix.sum())
    tex += f"\\multicolumn{{2}}{{r|}}{{\\textbf{{Total Previsto}}}} & {pred_totals} & {grand_total} \\\\\n"
    
    tex += "\\end{tabular}\n\\end{table}\n```"
    return tex

def evaluate_cnn2(weights_path, test_dataset, classes_cnn2, device):
    """Carrega e avalia um modelo CNN2 (MobileNetV2 binário)."""
    model = models.mobilenet_v2()
    model.classifier[1] = nn.Linear(model.last_channel, len(classes_cnn2))
    model.load_state_dict(torch.load(weights_path, map_location=device))
    model = model.to(device)
    model.eval()
    
    loader = DataLoader(test_dataset, batch_size=32, shuffle=False)
    preds = []
    targets_bin = []
    
    with torch.no_grad():
        for images, targets in loader:
            images = images.to(device)
            outputs = model(images)
            _, batch_preds = torch.max(outputs, 1)
            preds.extend(batch_preds.cpu().numpy())
            
            # Mapear classes do dataset para binário ('Healthy' -> 0, outras -> 1)
            for t in targets.numpy():
                class_name = test_dataset.classes[t]
                binary_target = 0 if class_name == 'Healthy' else 1
                targets_bin.append(binary_target)
                
    report = classification_report(targets_bin, preds, target_names=classes_cnn2, output_dict=True, zero_division=0)
    matrix = confusion_matrix(targets_bin, preds)
    return report, matrix

def evaluate_cnn5(weights_path, test_dataset, classes_cnn5_dummy, device):
    """Carrega e avalia um modelo CNN5 (ResNet50 multi-classe) mapeando as classes para strings."""
    model = models.resnet50()
    model.fc = nn.Sequential(
        nn.Dropout(p=0.5),
        nn.Linear(model.fc.in_features, 5) # Sempre 5 classes de treino
    )
    model.load_state_dict(torch.load(weights_path, map_location=device))
    model = model.to(device)
    model.eval()
    
    loader = DataLoader(test_dataset, batch_size=16, shuffle=False)
    preds_names = []
    targets_names = []
    
    classes_modelo = ['Anthracnose', 'Blotch', 'Healthy', 'Rot', 'Scab']
    
    with torch.no_grad():
        for images, targets in loader:
            images = images.to(device)
            outputs = model(images)
            _, batch_preds = torch.max(outputs, 1)
            
            for p in batch_preds.cpu().numpy():
                preds_names.append(classes_modelo[p])
                
            for t in targets.numpy():
                targets_names.append(test_dataset.classes[t])
                
    # Determinar a união de classes para avaliar no report
    classes_eval = list(set(targets_names + preds_names))
    classes_eval = sorted(classes_eval)
    
    report_multi = classification_report(targets_names, preds_names, labels=classes_eval, output_dict=True, zero_division=0)
    matrix_multi = confusion_matrix(targets_names, preds_names, labels=classes_eval)
    
    # Calcular métricas binárias colapsadas (Qualquer doença -> Unhealthy)
    preds_bin = [0 if p == 'Healthy' else 1 for p in preds_names]
    targets_bin = [0 if t == 'Healthy' else 1 for t in targets_names]
    
    classes_bin = ['Healthy', 'Unhealthy']
    report_bin = classification_report(targets_bin, preds_bin, target_names=classes_bin, output_dict=True, zero_division=0)
    matrix_bin = confusion_matrix(targets_bin, preds_bin)
    
    return report_multi, matrix_multi, report_bin, matrix_bin, classes_eval

def run_hierarchical_pipeline(cnn2_path, cnn5_path, test_dataset, classes_cnn2, classes_cnn5_dummy, device):
    """Simula o pipeline hierárquico com pesos específicos para cada modelo mapeando as classes para strings."""
    model_cnn2 = models.mobilenet_v2()
    model_cnn2.classifier[1] = nn.Linear(model_cnn2.last_channel, 2) # Sempre 2 classes de treino
    model_cnn2.load_state_dict(torch.load(cnn2_path, map_location=device))
    model_cnn2 = model_cnn2.to(device).eval()
    
    model_cnn5 = models.resnet50()
    model_cnn5.fc = nn.Sequential(
        nn.Dropout(p=0.5),
        nn.Linear(model_cnn5.fc.in_features, 5) # Sempre 5 classes de treino
    )
    model_cnn5.load_state_dict(torch.load(cnn5_path, map_location=device))
    model_cnn5 = model_cnn5.to(device).eval()
    
    loader = DataLoader(test_dataset, batch_size=1, shuffle=False)
    hier_preds_names = []
    hier_targets_names = []
    delegations = 0
    
    classes_modelo_cnn5 = ['Anthracnose', 'Blotch', 'Healthy', 'Rot', 'Scab']
    
    with torch.no_grad():
        for image, target in loader:
            image = image.to(device)
            target_idx = target.item()
            target_class = test_dataset.classes[target_idx]
            
            # 1. Inferência CNN2
            out1 = model_cnn2(image)
            prob1 = torch.softmax(out1, dim=1)[0]
            cnn2_pred_idx = torch.argmax(prob1).item()
            cnn2_pred_class = classes_cnn2[cnn2_pred_idx]
            cnn2_conf = prob1[cnn2_pred_idx].item()
            
            # Delegação se: pred = 'Unhealthy' OU pred = 'Healthy' com certeza < 80%
            if cnn2_pred_class == 'Unhealthy' or (cnn2_pred_class == 'Healthy' and cnn2_conf < 0.80):
                delegations += 1
                # 2. Inferência CNN5
                out2 = model_cnn5(image)
                prob2 = torch.softmax(out2, dim=1)[0]
                cnn5_pred_idx = torch.argmax(prob2).item()
                final_pred_class = classes_modelo_cnn5[cnn5_pred_idx]
            else:
                final_pred_class = 'Healthy'
                
            hier_preds_names.append(final_pred_class)
            hier_targets_names.append(target_class)
            
    classes_eval = list(set(hier_targets_names + hier_preds_names))
    classes_eval = sorted(classes_eval)
    
    report = classification_report(hier_targets_names, hier_preds_names, labels=classes_eval, output_dict=True, zero_division=0)
    matrix = confusion_matrix(hier_targets_names, hier_preds_names, labels=classes_eval)
    
    return report, matrix, delegations, classes_eval

def evaluate_ood(cnn2_path, cnn5_path, test_dataset, classes_cnn2, classes_cnn5_dummy, device, output_csv_path):
    """Executa os modelos CNN2 e CNN5 sobre todo o dataset para obter confianças detalhadas para análise Out-of-Distribution."""
    print(f"\n[OOD Analysis] A iniciar avaliação detalhada (OOD) para {len(test_dataset)} imagens...")
    
    model_cnn2 = models.mobilenet_v2()
    model_cnn2.classifier[1] = nn.Linear(model_cnn2.last_channel, 2)
    model_cnn2.load_state_dict(torch.load(cnn2_path, map_location=device))
    model_cnn2 = model_cnn2.to(device).eval()
    
    model_cnn5 = models.resnet50()
    model_cnn5.fc = nn.Sequential(
        nn.Dropout(p=0.5),
        nn.Linear(model_cnn5.fc.in_features, 5)
    )
    model_cnn5.load_state_dict(torch.load(cnn5_path, map_location=device))
    model_cnn5 = model_cnn5.to(device).eval()
    
    loader = DataLoader(test_dataset, batch_size=1, shuffle=False)
    classes_modelo_cnn5 = ['Anthracnose', 'Blotch', 'Healthy', 'Rot', 'Scab']
    
    results = []
    cnn2_confidences = []
    cnn5_confidences = []
    
    # Contadores exatos do objetivo
    cnn2_unhealthy_count = 0
    cnn5_low_conf_count = 0
    triage_success_count = 0
    
    with torch.no_grad():
        for idx, (image, target) in enumerate(tqdm(loader, desc="A avaliar OOD")):
            image = image.to(device)
            target_idx = target.item()
            target_class = test_dataset.classes[target_idx]
            
            file_path = test_dataset.samples[idx][0]
            filename = os.path.basename(file_path)
            
            # CNN2 Inferência
            out1 = model_cnn2(image)
            prob1 = torch.softmax(out1, dim=1)[0]
            cnn2_pred_idx = torch.argmax(prob1).item()
            cnn2_pred_class = classes_cnn2[cnn2_pred_idx]
            cnn2_conf = prob1[cnn2_pred_idx].item()
            
            if cnn2_pred_class == 'Unhealthy':
                cnn2_unhealthy_count += 1
            
            # CNN5 Inferência
            out2 = model_cnn5(image)
            prob2 = torch.softmax(out2, dim=1)[0]
            cnn5_pred_idx = torch.argmax(prob2).item()
            cnn5_pred_class = classes_modelo_cnn5[cnn5_pred_idx]
            cnn5_conf = prob2[cnn5_pred_idx].item()
            
            if cnn5_conf < 0.80:
                cnn5_low_conf_count += 1
                
            if cnn2_pred_class == 'Unhealthy' and cnn5_conf < 0.80:
                triage_success_count += 1
            
            results.append({
                'Ficheiro': filename,
                'Classe Original': target_class,
                'Previsao CNN2': cnn2_pred_class,
                'Confianca CNN2': f"{cnn2_conf:.4f}",
                'Previsao CNN5': cnn5_pred_class,
                'Confianca CNN5': f"{cnn5_conf:.4f}"
            })
            
            cnn2_confidences.append(cnn2_conf)
            cnn5_confidences.append(cnn5_conf)
            
    avg_conf_cnn2 = np.mean(cnn2_confidences) if cnn2_confidences else 0.0
    avg_conf_cnn5 = np.mean(cnn5_confidences) if cnn5_confidences else 0.0
    
    with open(output_csv_path, mode='w', newline='', encoding='utf-8') as f:
        fieldnames = ['Ficheiro', 'Classe Original', 'Previsao CNN2', 'Confianca CNN2', 'Previsao CNN5', 'Confianca CNN5']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        
        writer.writeheader()
        for row in results:
            writer.writerow(row)
            
        writer.writerow({})
        writer.writerow({
            'Ficheiro': 'MEDIA GLOBAL',
            'Classe Original': '-',
            'Previsao CNN2': '-',
            'Confianca CNN2': f"{avg_conf_cnn2:.4f}",
            'Previsao CNN5': '-',
            'Confianca CNN5': f"{avg_conf_cnn5:.4f}"
        })
        
    total_imgs = len(test_dataset)
    rate_cnn2_unhealthy = (cnn2_unhealthy_count / total_imgs) * 100
    rate_cnn5_low_conf = (cnn5_low_conf_count / total_imgs) * 100
    rate_triage_success = (triage_success_count / total_imgs) * 100
        
    print(f"\n[OOD Analysis] Resultados detalhados gravados em: {output_csv_path}")
    print(f"[OOD Analysis] Encaminhadas com sucesso para triagem manual: {rate_triage_success:.2f}%")
    
    return rate_cnn2_unhealthy, rate_cnn5_low_conf, rate_triage_success

def main():
    parser = argparse.ArgumentParser(description="Script Avançado de Comparação e Teste de Pesos")
    parser.add_argument("--data_dir", type=str, default=r"C:\Users\Utilizador\OneDrive\Área de Trabalho\Original Data_background", help="Diretório de imagens a testar ou pasta contendo a subpasta 'test'")
    parser.add_argument("--cnn2_weights", nargs="+", default=[], help="Lista de pesos .pth para a CNN2 (MobileNetV2)")
    parser.add_argument("--cnn5_weights", nargs="+", default=[], help="Lista de pesos .pth para a CNN5 (ResNet50)")
    parser.add_argument("--output_md", type=str, default="comparacao_modelos.md", help="Markdown de saída")
    parser.add_argument("--ood_csv", type=str, default="", help="Caminho para ficheiro CSV de análise OOD detalhada.")
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Motor a correr em: {device}")

    # Tenta usar a subpasta 'test' se existir, caso contrário usa a pasta base
    test_dir = os.path.join(args.data_dir, "test")
    if not os.path.exists(test_dir):
        test_dir = args.data_dir

    if not os.path.exists(test_dir) or not os.path.isdir(test_dir):
        print(f"Erro: O diretório de imagens '{test_dir}' não existe ou não é uma pasta.")
        return

    # Transformação padrão de avaliação (val_test_transform)
    val_test_transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    # Carregar dataset
    test_dataset = FlexibleDataset(test_dir, transform=val_test_transform)
    print(f"Dataset carregado com {len(test_dataset)} imagens de teste.")
    print(f"Classes detetadas: {test_dataset.classes}")

    classes_cnn2 = ['Healthy', 'Unhealthy']
    classes_cnn5 = test_dataset.classes  # ['Anthracnose', 'Blotch', 'Healthy', 'Rot', 'Scab']

    # Dicionários para guardar resultados comparativos
    cnn2_results = {}
    cnn5_results = {}
    
    md_content = f"# Comparativo de Pesos de Modelos (CNN2 e CNN5)\n\n"
    md_content += f"*   **Diretório de Teste:** `{test_dir}`\n"
    md_content += f"*   **Dispositivo de Inferência:** `{device.type.upper()}`\n\n"

    # ==================== AVALIAÇÃO DE MÚLTIPLOS PESOS DA CNN2 ====================
    if args.cnn2_weights:
        print("\n=== A iniciar avaliação da CNN2 ===")
        md_content += "## 1. Comparação de Pesos CNN2 (MobileNetV2 Binária - Healthy/Unhealthy)\n\n"
        
        cnn2_summary_data = []
        individual_details = "### 1.1. Detalhes Individuais CNN2\n\n"
        
        for w_path in args.cnn2_weights:
            if not os.path.exists(w_path):
                print(f"Aviso: Pesos '{w_path}' não encontrados. A ignorar...")
                continue
            
            w_name = os.path.basename(w_path)
            print(f"A avaliar {w_name}...")
            
            try:
                report, matrix = evaluate_cnn2(w_path, test_dataset, classes_cnn2, device)
                acc = report['accuracy']
                f1_h = report['Healthy']['f1-score']
                f1_u = report['Unhealthy']['f1-score']
                fp_triagem = matrix[1, 0]
                
                cnn2_results[w_path] = (report, matrix)
                cnn2_summary_data.append((w_name, acc, f1_h, f1_u, fp_triagem))
                
                w_escaped = w_name.replace("_", "\\_")
                w_label = w_name.replace(".", "_").replace("-", "_")
                individual_details += f"#### Ficheiro: `{w_name}`\n\n"
                individual_details += format_latex_metrics_table(
                    report, classes_cnn2, 
                    f"Métricas de Classificação Individuais para o Ficheiro \\texttt{{{w_escaped}}} (CNN2)", 
                    f"tab:metricas_{w_label}"
                ) + "\n\n"
                individual_details += format_latex_confusion_matrix(
                    matrix, classes_cnn2, 
                    f"Matriz de Confusão para o Ficheiro \\texttt{{{w_escaped}}} (CNN2)", 
                    f"tab:conf_{w_label}"
                ) + "\n\n"
                
            except Exception as e:
                print(f"Erro ao avaliar {w_name}: {e}")
                
        # Construir a tabela de resumo em LaTeX
        tex_summary = "```latex\n\\begin{table}[H]\n\\centering\n"
        tex_summary += "\\caption{Comparação de Desempenho dos Pesos da CNN2 (MobileNetV2 Binária)}\n"
        tex_summary += "\\label{tab:comparacao_cnn2}\n"
        tex_summary += "\\begin{tabular}{lcccc}\n\\toprule\n"
        tex_summary += "\\textbf{Ficheiro de Pesos} & \\textbf{Acurácia} & \\textbf{F1-Score Healthy} & \\textbf{F1-Score Unhealthy} & \\textbf{Falsos Positivos (Doente $\\rightarrow$ Sã)} \\\\\n\\midrule\n"
        for w_name, acc, f1_h, f1_u, fp in cnn2_summary_data:
            w_escaped = w_name.replace("_", "\\_")
            acc_str = f"{acc*100:.2f}".replace(".", "{,}") + "\\%"
            f1_h_str = f"{f1_h:.3f}".replace(".", "{,}")
            f1_u_str = f"{f1_u:.3f}".replace(".", "{,}")
            tex_summary += f"\\texttt{{{w_escaped}}} & {acc_str} & {f1_h_str} & {f1_u_str} & {fp} \\\\\n"
        tex_summary += "\\bottomrule\n\\end{tabular}\n\\end{table}\n```"
        
        md_content += tex_summary + "\n\n" + individual_details + "---\n\n"

    # ==================== AVALIAÇÃO DE MÚLTIPLOS PESOS DA CNN5 ====================
    if args.cnn5_weights:
        print("\n=== A iniciar avaliação da CNN5 ===")
        md_content += "## 2. Comparação de Pesos CNN5 (ResNet50 Multi-Classe)\n\n"
        
        cnn5_summary_data = []
        individual_details = "### 2.1. Detalhes Individuais CNN5 (Multi-Classe & Binário Colapsado)\n\n"
        
        for w_path in args.cnn5_weights:
            if not os.path.exists(w_path):
                print(f"Aviso: Pesos '{w_path}' não encontrados. A ignorar...")
                continue
            
            w_name = os.path.basename(w_path)
            print(f"A avaliar {w_name}...")
            
            try:
                report_multi, matrix_multi, report_bin, matrix_bin, classes_eval_cnn5 = evaluate_cnn5(w_path, test_dataset, classes_cnn5, device)
                acc_multi = report_multi['accuracy']
                acc_bin = report_bin['accuracy']
                f1_h = report_bin['Healthy']['f1-score']
                fp_bin = matrix_bin[1, 0]
                
                cnn5_results[w_path] = (report_multi, matrix_multi, report_bin, matrix_bin)
                cnn5_summary_data.append((w_name, acc_multi, acc_bin, f1_h, fp_bin))
                
                w_escaped = w_name.replace("_", "\\_")
                w_label = w_name.replace(".", "_").replace("-", "_")
                
                individual_details += f"#### Ficheiro: `{w_name}`\n\n"
                individual_details += "##### Métricas Multi-Classe\n\n"
                individual_details += format_latex_metrics_table(
                    report_multi, classes_eval_cnn5, 
                    f"Métricas Multi-Classe para o Ficheiro \\texttt{{{w_escaped}}} (CNN5)", 
                    f"tab:metricas_multiclass_{w_label}"
                ) + "\n\n"
                individual_details += format_latex_confusion_matrix(
                    matrix_multi, classes_eval_cnn5, 
                    f"Matriz de Confusão Multi-Classe para o Ficheiro \\texttt{{{w_escaped}}} (CNN5)", 
                    f"tab:conf_multi_{w_label}"
                ) + "\n\n"
                
                individual_details += "##### Métricas Binárias Colapsadas (Healthy vs Unhealthy)\n\n"
                individual_details += format_latex_metrics_table(
                    report_bin, ['Healthy', 'Unhealthy'], 
                    f"Métricas Binárias Colapsadas para o Ficheiro \\texttt{{{w_escaped}}} (CNN5)", 
                    f"tab:metricas_bin_{w_label}"
                ) + "\n\n"
                individual_details += format_latex_confusion_matrix(
                    matrix_bin, ['Healthy', 'Unhealthy'], 
                    f"Matriz de Confusão Binária Colapsada para o Ficheiro \\texttt{{{w_escaped}}} (CNN5)", 
                    f"tab:conf_bin_{w_label}"
                ) + "\n\n"
                
            except Exception as e:
                print(f"Erro ao avaliar {w_name}: {e}")
                
        # Construir a tabela de resumo da CNN5 em LaTeX
        tex_summary = "```latex\n\\begin{table}[H]\n\\centering\n"
        tex_summary += "\\caption{Comparação de Desempenho dos Pesos da CNN5 (ResNet50 Multi-Classe)}\n"
        tex_summary += "\\label{tab:comparacao_cnn5}\n"
        tex_summary += "\\begin{tabular}{lcccc}\n\\toprule\n"
        tex_summary += "\\textbf{Ficheiro de Pesos} & \\textbf{Acurácia Multi-Classe} & \\textbf{Acurácia Binária Colapsada} & \\textbf{F1-Score Healthy} & \\textbf{FP Binário (Doente $\\rightarrow$ Sã)} \\\\\n\\midrule\n"
        for w_name, acc_multi, acc_bin, f1_h, fp in cnn5_summary_data:
            w_escaped = w_name.replace("_", "\\_")
            acc_m_str = f"{acc_multi*100:.2f}".replace(".", "{,}") + "\\%"
            acc_b_str = f"{acc_bin*100:.2f}".replace(".", "{,}") + "\\%"
            f1_h_str = f"{f1_h:.3f}".replace(".", "{,}")
            tex_summary += f"\\texttt{{{w_escaped}}} & {acc_m_str} & {acc_b_str} & {f1_h_str} & {fp} \\\\\n"
        tex_summary += "\\bottomrule\n\\end{tabular}\n\\end{table}\n```"
        
        md_content += tex_summary + "\n\n" + individual_details + "---\n\n"

    # ==================== PIPELINE HIERÁRQUICO COMBINADO ====================
    # Se ambos os conjuntos de pesos estiverem disponíveis, corre a simulação do pipeline
    # cruzando o primeiro peso de cada lista como demonstração de fluxo de produção.
    if args.cnn2_weights and args.cnn5_weights:
        # Pega no primeiro elemento de cada lista que exista fisicamente
        valid_cnn2_weights = [w for w in args.cnn2_weights if os.path.exists(w)]
        valid_cnn5_weights = [w for w in args.cnn5_weights if os.path.exists(w)]
        
        if valid_cnn2_weights and valid_cnn5_weights:
            c2_path = valid_cnn2_weights[0]
            c5_path = valid_cnn5_weights[0]
            c2_name = os.path.basename(c2_path)
            c5_name = os.path.basename(c5_path)
            
            print(f"\n[Pipeline] A simular Pipeline Hierárquico combinando `{c2_name}` + `{c5_name}`...")
            try:
                report_hier, matrix_hier, delegations, classes_eval_hier = run_hierarchical_pipeline(
                    c2_path, c5_path, test_dataset, classes_cnn2, classes_cnn5, device
                )
                
                total_cases = len(test_dataset)
                del_rate = (delegations / total_cases) * 100
                
                # Converter decimais para vírgulas na frase de descrição
                del_rate_str = f"{del_rate:.2f}".replace(".", "{,}")
                
                md_content += "## 3. Simulação do Pipeline Hierárquico Combinado\n\n"
                md_content += f"Configuração combinada:\n"
                md_content += f"*   **CNN2 (Pesos):** `{c2_name}`\n"
                md_content += f"*   **CNN5 (Pesos):** `{c5_name}`\n\n"
                md_content += f"O pipeline de triagem avaliou {total_cases} imagens de teste. A CNN2 delegou {delegations} casos à CNN5 (Taxa de Delegação: **{del_rate_str}\\%**).\n\n"
                
                md_content += "### 3.1. Métricas do Pipeline Combinado\n\n"
                c2_escaped = c2_name.replace("_", "\\_")
                c5_escaped = c5_name.replace("_", "\\_")
                md_content += format_latex_metrics_table(
                    report_hier, classes_eval_hier, 
                    f"Métricas Globais do Pipeline Hierárquico Combinado (\\texttt{{{c2_escaped}}} + \\texttt{{{c5_escaped}}})", 
                    "tab:metricas_pipeline"
                ) + "\n\n"
                
                md_content += "### 3.2. Matriz de Confusão do Pipeline Combinado\n\n"
                md_content += format_latex_confusion_matrix(
                    matrix_hier, classes_eval_hier, 
                    "Matriz de Confusão do Pipeline Hierárquico Combinado", 
                    "tab:conf_pipeline"
                ) + "\n"
                
            except Exception as e:
                print(f"Erro ao simular pipeline hierárquico: {e}")

        # Análise OOD Adicional
        if args.ood_csv:
            try:
                rate_cnn2_unh, rate_cnn5_low, rate_triage = evaluate_ood(
                    valid_cnn2_weights[0], 
                    valid_cnn5_weights[0], 
                    test_dataset, 
                    classes_cnn2, 
                    classes_cnn5, 
                    device, 
                    args.ood_csv
                )
                
                md_content += "## 4. Análise Out-of-Distribution (OOD / Pior Caso)\n\n"
                md_content += "A tabela seguinte demonstra a eficácia do sistema em reencaminhar classes desconhecidas (patologias anómalas) para a triagem manual, avaliando a deteção primária pela CNN2 e a devida incerteza da CNN5.\n\n"
                
                r1_str = f"{rate_cnn2_unh:.2f}".replace(".", "{,}") + "\\%"
                r2_str = f"{rate_cnn5_low:.2f}".replace(".", "{,}") + "\\%"
                rt_str = f"{rate_triage:.2f}".replace(".", "{,}") + "\\%"
                
                tex_ood = "```latex\n\\begin{table}[H]\n\\centering\n"
                tex_ood += "\\caption{Avaliação da Resiliência do Sistema em Cenário Out-of-Distribution (OOD)}\n"
                tex_ood += "\\label{tab:resultados_ood}\n"
                tex_ood += "\\begin{tabular}{lc}\n\\toprule\n"
                tex_ood += "\\textbf{Comportamento do Sistema (OOD)} & \\textbf{Taxa de Ocorrência} \\\\\n\\midrule\n"
                tex_ood += f"Deteção de Anomalia na CNN2 (\\texttt{{Unhealthy}}) & {r1_str} \\\\\n"
                tex_ood += f"Incerteza na CNN5 (Confiança $< 80\\%$) & {r2_str} \\\\\n"
                tex_ood += "\\midrule\n"
                tex_ood += f"\\textbf{{Sucesso: Encaminhado para Triagem Manual}} & \\textbf{{{rt_str}}} \\\\\n"
                tex_ood += "\\bottomrule\n\\end{tabular}\n\\end{table}\n```\n\n"
                
                md_content += tex_ood
                
            except Exception as e:
                print(f"Erro ao gerar análise OOD: {e}")

    # Gravar ficheiro final
    with open(args.output_md, "w", encoding="utf-8") as f:
        f.write(md_content)
        
    print(f"\n[Sucesso] Relatório comparativo gravado em: {args.output_md}")

if __name__ == "__main__":
    main()
