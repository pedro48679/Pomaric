import cv2
import torch
import torch.nn as nn
from torchvision import models, transforms
from PIL import Image
import os
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Button

class CNNLayerViewer:
    def __init__(self, image_folder, model_path="melhor_weight_multiclass_RESnet50_BEST.pth", num_classes=5):
        self.image_folder = image_folder
        self.image_list = sorted([os.path.join(image_folder, f) for f in os.listdir(image_folder)
                                  if f.lower().endswith(('.png', '.jpg', '.jpeg'))])
        
        if not self.image_list:
            print("Nenhuma imagem encontrada na pasta escolhida!")
            return
            
        self.current_idx = 0
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        print(f"A inicializar (Dispositivo: {self.device})...")
        
        self.model = models.resnet50()
        self.model.fc = nn.Sequential(
            nn.Dropout(p=0.5),
            nn.Linear(self.model.fc.in_features, num_classes)
        )
        if os.path.exists(model_path):
            self.model.load_state_dict(torch.load(model_path, map_location=self.device, weights_only=True))
        
        self.model = self.model.to(self.device)
        self.model.eval()

        self.transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])

        self.activations = {}
        def get_activation(name):
            def hook(model, input, output):
                self.activations[name] = output.detach().cpu()
            return hook

        # Conectar ganchos
        self.model.conv1.register_forward_hook(get_activation('Conv1 (Limites e Bordas)'))
        self.model.layer1.register_forward_hook(get_activation('Layer 1 (Texturas Básicas)'))
        self.model.layer2.register_forward_hook(get_activation('Layer 2 (Foco Inicial)'))
        self.model.layer3.register_forward_hook(get_activation('Layer 3 (Foco Avançado)'))
        self.model.layer4.register_forward_hook(get_activation('Layer 4 (Decisão Semântica)'))

        dummy = torch.zeros(1, 3, 224, 224).to(self.device)
        self.model(dummy)

        self.available_layers = list(self.activations.keys())
        self.layer_idx = 0
        self.current_layer_name = self.available_layers[self.layer_idx]

        self._setup_plot()
        self.update_plot()
        plt.show(block=True)
        
    def _setup_plot(self):
        self.fig = plt.figure(figsize=(16, 9))
        self.fig.canvas.manager.set_window_title("Visão de Raio-X CNN - Layers de Pensamento")
        
        # Imagem Original (Esquerda)
        self.ax_orig = plt.axes([0.05, 0.35, 0.25, 0.4])
        self.ax_orig.axis('off')
        
        # Grelha de Feature Maps (Centro/Direita)
        self.ax_features = []
        for i in range(16): # 4x4 grelha
            row = i // 4
            col = i % 4
            ax = plt.axes([0.35 + col*0.15, 0.15 + (3-row)*0.18, 0.14, 0.16])
            ax.axis('off')
            self.ax_features.append(ax)
            
        # Botões: Navegar Imagem
        self.ax_prev_img = plt.axes([0.05, 0.25, 0.1, 0.05])
        self.btn_prev_img = Button(self.ax_prev_img, '< Imagem')
        self.btn_prev_img.on_clicked(self.prev_image)
        
        self.ax_next_img = plt.axes([0.2, 0.25, 0.1, 0.05])
        self.btn_next_img = Button(self.ax_next_img, 'Imagem >')
        self.btn_next_img.on_clicked(self.next_image)

        # Botões: Navegar Camada (Removidos os RadioButtons gigantes)
        self.ax_prev_lyr = plt.axes([0.05, 0.15, 0.1, 0.05])
        self.btn_prev_lyr = Button(self.ax_prev_lyr, '< Camada')
        self.btn_prev_lyr.on_clicked(self.prev_layer)
        
        self.ax_next_lyr = plt.axes([0.2, 0.15, 0.1, 0.05])
        self.btn_next_lyr = Button(self.ax_next_lyr, 'Camada >')
        self.btn_next_lyr.on_clicked(self.next_layer)

    def prev_layer(self, event):
        if self.layer_idx > 0:
            self.layer_idx -= 1
            self.current_layer_name = self.available_layers[self.layer_idx]
            self.render_features()
            self.fig.canvas.draw_idle()

    def next_layer(self, event):
        if self.layer_idx < len(self.available_layers) - 1:
            self.layer_idx += 1
            self.current_layer_name = self.available_layers[self.layer_idx]
            self.render_features()
            self.fig.canvas.draw_idle()

    def prev_image(self, event):
        if self.current_idx > 0:
            self.current_idx -= 1
            self.update_plot()

    def next_image(self, event):
        if self.current_idx < len(self.image_list) - 1:
            self.current_idx += 1
            self.update_plot()

    def update_plot(self):
        img_path = self.image_list[self.current_idx]
        try:
            self.orig_image = Image.open(img_path).convert("RGB")
        except Exception as e:
            print(f"Erro ao ler imagem: {e}")
            return
            
        self.ax_orig.clear()
        self.ax_orig.imshow(self.orig_image)
        self.ax_orig.set_title(f"Imagem {self.current_idx+1}/{len(self.image_list)}\n{os.path.basename(img_path)}", fontsize=10)
        self.ax_orig.axis('off')
        
        tensor = self.transform(self.orig_image).unsqueeze(0).to(self.device)
        with torch.no_grad():
            self.model(tensor)
            
        self.render_features()
        self.fig.canvas.draw_idle()

    def render_features(self):
        if self.current_layer_name not in self.activations:
            return
            
        act = self.activations[self.current_layer_name].squeeze(0).numpy()
        
        # Escolher os 16 canais com maior energia
        mean_activations = np.mean(act, axis=(1, 2))
        top_channels = np.argsort(mean_activations)[::-1][:16]
        
        # Guardar a maçã original como plano de fundo (Background)
        orig_bg = np.array(self.orig_image.resize((224, 224)))
        
        for i, ax in enumerate(self.ax_features):
            ax.clear()
            if i < len(top_channels):
                c = top_channels[i]
                feature_map = act[c]
                
                # Resize do heatmap para coincidir em precisão fotográfica (224x224)
                if feature_map.shape[0] < 224:
                    feature_map = cv2.resize(feature_map, (224, 224), interpolation=cv2.INTER_CUBIC)
                
                if feature_map.max() > 0:
                    feature_map = feature_map / feature_map.max()
                
                # 1º Passo: Colocar a Maçã a cores por trás do filtro (fundo fotorrealista)
                ax.imshow(orig_bg)
                
                # 2º Passo: Colocar o Filtro da Layer (pensamento da rede) em cima como aura termal semi-transparente
                # cmap='magma' ou 'jet' é ótimo para não esconder a fruta, onde escuro é transparente.
                ax.imshow(feature_map, cmap='jet', alpha=0.45)
                
                ax.set_title(f"Filtro {c}", fontsize=8)
            ax.axis('off')
            
        self.fig.suptitle(f"Visão Raio-X Sobreposta: {self.current_layer_name}", fontsize=16, fontweight='bold')

if __name__ == "__main__":
    print("-" * 60)
    print(" Explorador de Camadas de Pensamento da CNN ")
    print(" (Visualização de Feature Maps) ")
    print("-" * 60)
    pasta = input("\nArraste a pasta com imagens para analisar:\n > ").strip().strip('"').strip("'")
    
    if os.path.isdir(pasta):
        CNNLayerViewer(pasta)
    else:
        print("Pasta inválida. Tente novamente.")
