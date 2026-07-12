import torch
import torch.nn as nn
from torchvision import models, transforms
from PIL import Image
import os
import glob
import numpy as np
import cv2
import shutil
import torch.nn.functional as F
import matplotlib.pyplot as plt
from matplotlib.widgets import Button, RectangleSelector

class GradCamViewer:
    def __init__(self, image_folder, model_path="melhor_weight_multiclass_RESnet50_BEST.pth", num_classes=5, tipo_modelo="resnet", modo_pasta=1):
        self.image_folder = image_folder
        if modo_pasta == 2:
            # É um diretório com subpastas
            subfolders = sorted([os.path.join(image_folder, d) for d in os.listdir(image_folder) 
                                 if os.path.isdir(os.path.join(image_folder, d))])
            self.image_list = []
            for sf in subfolders:
                sf_images = sorted([os.path.join(sf, f) for f in os.listdir(sf)
                                    if f.lower().endswith(('.png', '.jpg', '.jpeg'))])
                self.image_list.extend(sf_images)
        else:
            # É uma pasta simples
            self.image_list = sorted([os.path.join(image_folder, f) for f in os.listdir(image_folder)
                                      if f.lower().endswith(('.png', '.jpg', '.jpeg'))])
        
        if not self.image_list:
            print("Nenhuma imagem encontrada na pasta ou subpastas escolhidas!")
            return
            
        self.current_idx = 0
        self.num_classes = num_classes
        self.tipo_modelo = tipo_modelo
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        print(f"A usar ambiente: {self.device}")
        
        # Mapa de classes dinâmico
        if self.num_classes == 2:
            self.classes_map = {0: 'Healthy', 1: 'Unhealthy'}
        else:
            self.classes_map = {0: 'Anthracnose', 1: 'Blotch', 2: 'Healthy', 3: 'Rot', 4: 'Scab'}
        
        self._load_model(model_path)
        
        # Configurar interface do plot
        self.fig, (self.ax1, self.ax2, self.ax3) = plt.subplots(1, 3, figsize=(15, 6))
        self.fig.canvas.manager.set_window_title("Galeria Interativa Grad-CAM")
        plt.subplots_adjust(bottom=0.2) # Espaço em baixo para os botões
        
        # Criar os botões na janela
        axprev = plt.axes([0.15, 0.05, 0.15, 0.075])
        axinject = plt.axes([0.4, 0.05, 0.2, 0.075]) # Botao central de injeção
        axnext = plt.axes([0.7, 0.05, 0.15, 0.075])
        
        self.bnext = Button(axnext, 'Seguinte >')
        self.bnext.on_clicked(self.next_image)
        
        self.bprev = Button(axprev, '< Anterior')
        self.bprev.on_clicked(self.prev_image)
        
        self.binject = Button(axinject, 'Forçar Injeção (Treino)', color='gold')
        self.binject.on_clicked(self.inject_current_image)
        
        # Variável para guardar o crop do utilizador e o selector
        self.manual_crop_coords = None
        self.rs = None
        
        # Mostrar primeira imagem (o que também invoca o criador do quadrado)
        self.update_plot()
        
        print("Graficos renderizados! Use os botões para navegar. Desenhe um quadrado na Foto 1 para Seleção de Doença!")
        plt.show(block=True)
        
    def on_select(self, eclick, erelease):
        """Guarda as coordenadas quando o utilizador arrasta o rato na Imagem 1"""
        x1, y1 = int(eclick.xdata), int(eclick.ydata)
        x2, y2 = int(erelease.xdata), int(erelease.ydata)
        self.manual_crop_coords = (min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))
        print(f" -> Nova crop criada. Coordenadas temporárias guardadas.")
        
    def _load_model(self, model_path):
        if model_path and model_path.lower().endswith('.onnx'):
            raise ValueError(
                f"\n[ERRO CRÍTICO] O ficheiro '{model_path}' é um modelo exportado para ONNX.\n"
                f"O script de Grad-CAM é dinâmico e necessita do modelo original do PyTorch (.pth) "
                f"para registar os hooks de gradientes no grafo computacional.\n"
                f"Para analisar a CNN1, deve usar o ficheiro de pesos original 'ONNX_2.pth' em vez do exportado 'model2.onnx'."
            )

        if self.tipo_modelo == "resnet":
            self.model = models.resnet50(weights=models.ResNet50_Weights.IMAGENET1K_V2)
            self.model.fc = nn.Sequential(
                nn.Dropout(p=0.5),
                nn.Linear(self.model.fc.in_features, self.num_classes)
            )
        elif self.tipo_modelo == "mobilenet":
            self.model = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.DEFAULT)
            self.model.classifier[1] = nn.Linear(self.model.last_channel, self.num_classes)
        
        if os.path.exists(model_path):
            print(f"A carregar os pesos do modelo: {model_path}")
            self.model.load_state_dict(torch.load(model_path, map_location=self.device, weights_only=True))
        else:
            print("Peso do modelo não encontrado. Será usado o ResNet base (resultados aleatórios).")
            
        self.model = self.model.to(self.device)
        self.model.eval()

    def process_image(self, image_path):
        transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])

        try:
            image = Image.open(image_path).convert("RGB")
        except Exception as e:
            print(f"Erro ao abrir imagem {image_path}: {e}")
            return None, None, None, None, None

        input_tensor = transform(image).unsqueeze(0).to(self.device)

        # Preparar Hooks Grad-CAM
        gradcam_data = {'activations': None, 'gradients': None}
        
        def save_act(module, input, output):
            gradcam_data['activations'] = output

        def save_grad(module, grad_input, grad_output):
            gradcam_data['gradients'] = grad_output[0]

        if self.tipo_modelo == "resnet":
            target_layer = self.model.layer4
        elif self.tipo_modelo == "mobilenet":
            target_layer = self.model.features[-1]
        handle_act = target_layer.register_forward_hook(save_act)
        handle_grad = target_layer.register_full_backward_hook(save_grad)

        # Forward Pass
        outputs = self.model(input_tensor)
        probs = F.softmax(outputs, dim=1)[0]
        max_prob, pred_idx = torch.max(probs, dim=0)
        
        certeza = max_prob.item() * 100
        indice_classe = pred_idx.item()
        nome_classe = self.classes_map.get(indice_classe, f"Classe {indice_classe}")
        
        # Obter a distribuição completa de probabilidades
        distribuicao = [f"{self.classes_map.get(i, f'Cl{i}')}: {probs[i].item()*100:.1f}%" for i in range(self.num_classes)]
        dist_str = "  |  ".join(distribuicao)
        
        # Imprimir no terminal para confirmação
        print(f" -> Distribuição de probabilidades: {dist_str}")
        
        titulo_decisao = f"[{os.path.basename(image_path)}] Decidido: {nome_classe} ({certeza:.2f}%)\n{dist_str}"

        # Backward Pass
        self.model.zero_grad()
        outputs[0, indice_classe].backward()

        # Limpar Hooks
        handle_act.remove()
        handle_grad.remove()

        # Calcular calor
        gradients = gradcam_data['gradients'][0].cpu().numpy()
        activations_cam = gradcam_data['activations'][0].cpu().detach().numpy()
        pooled_gradients = np.mean(gradients, axis=(1, 2))
        
        for i in range(activations_cam.shape[0]):
            activations_cam[i, :, :] *= pooled_gradients[i]
            
        heatmap = np.mean(activations_cam, axis=0)
        heatmap = np.maximum(heatmap, 0)
        if np.max(heatmap) != 0:
            heatmap = heatmap / np.max(heatmap)
            
        heatmap_resized = cv2.resize(heatmap, (224, 224))
        heatmap_colored = cv2.applyColorMap(np.uint8(255 * heatmap_resized), cv2.COLORMAP_JET)
        heatmap_colored = cv2.cvtColor(heatmap_colored, cv2.COLOR_BGR2RGB)
        
        original_img_resized = np.array(image.resize((224, 224)))
        superimposed = heatmap_colored * 0.4 + original_img_resized * 0.6
        superimposed = np.clip(superimposed, 0, 255).astype(np.uint8)

        return original_img_resized, heatmap_colored, superimposed, titulo_decisao, certeza

    def update_plot(self):
        img_path = self.image_list[self.current_idx]
        print(f"A processar {self.current_idx+1}/{len(self.image_list)}: {os.path.basename(img_path)}")
        
        orig, heat, superimg, title, certeza = self.process_image(img_path)
        
        if orig is None:
            return

        # Limpar o estado de seleção manual para a nova imagem
        self.manual_crop_coords = None

        self.ax1.clear()
        self.ax1.imshow(orig)
        self.ax1.set_title("1. Fotografia (Arraste para Crop)", fontsize=12)
        self.ax1.axis('off')

        self.ax2.clear()
        self.ax2.imshow(heat)
        self.ax2.set_title("2. Calor Grad-CAM", fontsize=12)
        self.ax2.axis('off')

        self.ax3.clear()
        self.ax3.imshow(superimg)
        self.ax3.set_title("3. Cruzamento Híbrido", fontsize=12)
        self.ax3.axis('off')

        cor_titulo = 'darkgreen' if certeza > 80.0 else 'darkred'
        self.fig.suptitle(title, fontsize=16, fontweight='bold', color=cor_titulo)
        
        # (Re)criar o Rectangle Selector limpo para esta nova imagem
        if self.rs is not None:
            self.rs.set_active(False)
        self.rs = RectangleSelector(self.ax1, self.on_select,
                                    useblit=True,
                                    button=[1], 
                                    minspanx=5, minspany=5,
                                    spancoords='pixels',
                                    interactive=True,
                                    props=dict(facecolor='red', edgecolor='red', alpha=0.3, fill=True))
        
        self.fig.canvas.draw_idle()

    def on_key_press(self, event):
        """Permite navegar com Setas do Teclado"""
        if event.key == 'right':
            self.next_image(None)
        elif event.key == 'left':
            self.prev_image(None)

    def next_image(self, event):
        if self.current_idx < len(self.image_list) - 1:
            self.current_idx += 1
            self.update_plot()
        else:
            print("Já está na última imagem.")

    def prev_image(self, event):
        if self.current_idx > 0:
            self.current_idx -= 1
            self.update_plot()
        else:
            print("Já está na primeira imagem.")

    def fazer_crop_doenca(self, img_bgr):
        img_hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
        _, canal_brilho = cv2.threshold(img_hsv[:,:,2], 15, 255, cv2.THRESH_BINARY) 
        mascara_doenca = cv2.inRange(img_hsv, (0, 10, 10), (180, 255, 120))
        mascara_doenca = cv2.bitwise_and(mascara_doenca, mascara_doenca, mask=canal_brilho)
        kernel = np.ones((5,5), np.uint8)
        mascara_doenca = cv2.morphologyEx(mascara_doenca, cv2.MORPH_OPEN, kernel)
        mascara_doenca = cv2.morphologyEx(mascara_doenca, cv2.MORPH_CLOSE, kernel)
        contornos, _ = cv2.findContours(mascara_doenca, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if contornos:
            maior_contorno = max(contornos, key=cv2.contourArea)
            if cv2.contourArea(maior_contorno) > 50:
                x, y, w, h = cv2.boundingRect(maior_contorno)
                padding = 20
                y1 = max(0, y - padding)
                y2 = min(img_bgr.shape[0], y + h + padding)
                x1 = max(0, x - padding)
                x2 = min(img_bgr.shape[1], x + w + padding)
                return img_bgr[y1:y2, x1:x2]
        return None

    def inject_current_image(self, event):
        img_path = self.image_list[self.current_idx]
        nome_ficheiro = os.path.basename(img_path)
        pasta_atual = os.path.dirname(img_path)
        
        # Tentar descobrir a classe real de forma à prova de bala
        classe_real = None
        if "Esperava_" in nome_ficheiro:
            classe_real = nome_ficheiro.split("Esperava_")[1].split("__")[0]
        elif "Real_" in nome_ficheiro:
            # O CNN1 usa a nomenclatura Real_Unhealthy___Previu_Healthy...
            classe_real = nome_ficheiro.split("Real_")[1].split("___")[0]
        else:
            # Assumir que se não foi um erro gerado, a classe é o próprio nome da pasta (ex: valid/Healthy)
            classe_real = os.path.basename(pasta_atual).capitalize()
            
        if classe_real not in self.classes_map.values():
            print(f"Erro: Não foi possível determinar a classe real. A classe detetada '{classe_real}' não está no mapa.")
            return

        # Encontrar a pasta 'train' dinamicamente "trepando" nas pastas
        pasta_varredura = pasta_atual
        pasta_treino_base = None
        
        while True:
            candidato_treino = os.path.join(pasta_varredura, "train")
            if os.path.exists(candidato_treino) and os.path.isdir(candidato_treino):
                pasta_treino_base = candidato_treino
                break
            pasta_pai = os.path.dirname(pasta_varredura)
            if pasta_pai == pasta_varredura: # Chegou à raiz do disco
                break
            pasta_varredura = pasta_pai
            
        if pasta_treino_base is None:
            print(f"Erro: Não consegui encontrar nenhuma pasta 'train' subindo os diretórios acima de {pasta_atual}")
            return
            
        pasta_treino = os.path.join(pasta_treino_base, classe_real)
        if not os.path.exists(pasta_treino):
            print(f"Erro: A pasta de treino destino não existe: {pasta_treino}")
            return
            
        # LEITURA E INJEÇÃO (FAZER ANTES DE APAGAR ORIGINAIS)
        # 1. Injetar Imagem Completa (x2 Globais)
        for i in range(2):
            shutil.copy(img_path, os.path.join(pasta_treino, f"MANUAL_INJECT_FULL_{i}_{nome_ficheiro}"))
            
        # 2. Injetar Crop Selecionado (Apenas 1 Crop Magnificado)
        if classe_real != "Healthy":
            recorte = None
            orig_bgr = cv2.imdecode(np.fromfile(img_path, dtype=np.uint8), cv2.IMREAD_COLOR)
            
            if self.manual_crop_coords is not None:
                x1, y1, x2, y2 = self.manual_crop_coords
                h_bgr, w_bgr, _ = orig_bgr.shape
                escala_x = w_bgr / 224.0
                escala_y = h_bgr / 224.0
                rx1 = max(0, int(x1 * escala_x))
                ry1 = max(0, int(y1 * escala_y))
                rx2 = min(w_bgr, int(x2 * escala_x))
                ry2 = min(h_bgr, int(y2 * escala_y))
                recorte = orig_bgr[ry1:ry2, rx1:rx2]
                prefixo = "HUMAN_DRAWN_CROP"
                print(" -> A usar Crop Desenhado Manualmente Pelo Humano.")
            else:
                recorte = self.fazer_crop_doenca(orig_bgr)
                prefixo = "OPENCV_INJECT_CROP"
                print(" -> O utilizador não desenhou na Imagem 1. A usar Crop Automático Inteligente (OpenCV).")
                
            if recorte is not None and recorte.size > 0:
                for i in range(1):
                    caminho_salvar = os.path.join(pasta_treino, f"{prefixo}_{i}_{nome_ficheiro}")
                    is_success, buffer = cv2.imencode(".png", recorte)
                    if is_success:
                        buffer.tofile(caminho_salvar)

        # PREVENÇÃO DE LEAKAGE E SUBSTITUIÇÃO (LIMPEZA SUPREMA)
        # Encontrar o nome limpo e original do ficheiro testado
        nome_original = nome_ficheiro
        if "Esperava_" in nome_original or "Real_" in nome_original:
            nome_original = nome_original.split("___")[-1]
            
        pasta_dataset_raiz = os.path.dirname(pasta_treino_base)
        
        # Procurar rigorosamente em 'train', 'valid' e 'test' pela maçã original para a eliminar (já que agora foi re-injetada como Hyper-Learning)
        for particao in ["train", "valid", "test"]:
            caminho_alvo = os.path.join(pasta_dataset_raiz, particao, classe_real, nome_original)
            if os.path.exists(caminho_alvo):
                try:
                    os.remove(caminho_alvo)
                    print(f" -> Substituição/Leakage Completa: A maçã original foi apagada de '{particao}'.")
                except Exception:
                    pass
                    
        # Apagar da galeria de erros (se estiveres a injetar fora do dataset normal)
        if os.path.exists(img_path):
             try:
                 os.remove(img_path)
             except Exception:
                 pass
                 
        print(f"\n[SUCESSO] Imagem '{nome_ficheiro}' Injetada na classe {classe_real}!")
        self.fig.suptitle("INJETADO COM SUCESSO! (Move para a Seguinte)", fontsize=16, fontweight='bold', color='purple')
        self.manual_crop_coords = None
        self.fig.canvas.draw_idle()

if __name__ == "__main__":
    print("-" * 60)
    print(" Galeria Interativa de Grad-CAM ")
    print(" Navegação Rápida com LLM desativado. ")
    print("-" * 60)
    
    print("\nQual o modo de avaliação pretendido?")
    print(" [1] - CNN1 (Filtro Binário)    -> ONNX_2.pth (Pesos de model2.onnx)")
    print(" [2] - CNN2 (Especialista) -> melhor_weight_multiclass_RESnet50_BEST.pth")
    opcao = input(" \n > ").strip()
    
    pasta = input("\nEscreva ou arraste o caminho contendo as imagens para testar:\n > ").strip().strip('"').strip("'")
    
    if os.path.isdir(pasta):
         print("\nO caminho fornecido é:")
         print(" [1] - Uma pasta simples (contém as imagens diretamente)")
         print(" [2] - Um diretório (contém subpastas com as imagens)")
         tipo_caminho = input(" \n > ").strip()
         modo_pasta = 2 if tipo_caminho == "2" else 1

         if opcao == "1":
             viewer = GradCamViewer(pasta, model_path="ONNX_2.pth", num_classes=2, tipo_modelo="mobilenet", modo_pasta=modo_pasta)
         else:
             # Por defeito assume Multi-Classe
             viewer = GradCamViewer(pasta, model_path="melhor_weight_multiclass_RESnet50_BEST.pth", num_classes=5, tipo_modelo="resnet", modo_pasta=modo_pasta)
    else:
        print(" O caminho indicado não é uma pasta válida.")
