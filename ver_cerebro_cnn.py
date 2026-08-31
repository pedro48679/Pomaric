import torch
import torch.nn as nn
from torchvision import models, transforms
from PIL import Image
import os
import sys
import numpy as np
import cv2
import torch.nn.functional as F

def visualize_feature_maps_and_cam(image_path, model_path=None, num_classes=5):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"A usar: {device}")

    model = models.resnet50(weights=models.ResNet50_Weights.IMAGENET1K_V2)
    model.fc = nn.Linear(model.fc.in_features, num_classes)
    
    if model_path and os.path.exists(model_path):
        print(f"A carregar os pesos do modelo: {model_path}")
        model.load_state_dict(torch.load(model_path, map_location=device))
    
    model = model.to(device)
    # IMPORTANTE: Grad-CAM necessita do fluxo backward no evaluation mode
    model.eval()

    if not os.path.exists(image_path):
        print("Erro: Imagem nao encontrada.")
        return

    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    image = Image.open(image_path).convert("RGB")
    input_tensor = transform(image).unsqueeze(0).to(device)

    # --- 1. Preparar Hooks para o Grad-CAM na Ultima Camada Conv ---
    gradcam_data = {'activations': None, 'gradients': None}
    
    def save_act(module, input, output):
        gradcam_data['activations'] = output

    def save_grad(module, grad_input, grad_output):
        gradcam_data['gradients'] = grad_output[0]

    # Atribuir a escuta as ativacoes da camada 4 do Resnet
    target_layer_cam = model.layer4
    target_layer_cam.register_forward_hook(save_act)
    target_layer_cam.register_full_backward_hook(save_grad)

    # --- 2. Hooks para visualizacao cinzenta tradicional nas malhas antigas ---
    activation = {}
    def get_activation(name):
        def hook(model, input, output):
            activation[name] = output.detach() # o detach isola grafos extra
        return hook

    model.conv1.register_forward_hook(get_activation('conv1'))
    model.layer2[0].conv1.register_forward_hook(get_activation('layer2'))
    model.layer3[0].conv1.register_forward_hook(get_activation('layer3'))

    # FORWARD PASS (A Imagem entra e as Sondas Extraem Dados)
    outputs = model(input_tensor)
    
    # Extrair DECISAO e PERCENTAGEM!
    probs = F.softmax(outputs, dim=1)[0]
    max_prob, pred_idx = torch.max(probs, dim=0)
    certeza = max_prob.item() * 100
    indice_classe = pred_idx.item()
    
    classes_map = {0: 'Anthracnose', 1: 'Blotch', 2: 'Healthy', 3: 'Rot', 4: 'Scab'}
    nome_classe = classes_map.get(indice_classe, f"Classe {indice_classe}")
    
    titulo_decisao = f"Decidido: {nome_classe} - Certeza: {certeza:.2f}%"
    print(f"\n---> {titulo_decisao} <---")

    # BACKWARD PASS (Apenas na neuronio vencedor para pintar de calor os responsaveis por ele ganhar)
    model.zero_grad()
    outputs[0, indice_classe].backward()

    # --- 3. Calcular a Mancha de Calor do Grad-CAM ---
    gradients = gradcam_data['gradients'][0].cpu().numpy() 
    activations_cam = gradcam_data['activations'][0].cpu().detach().numpy() 
    
    # Peso matematico de cada grelha abstrata com base nas derivadas
    pooled_gradients = np.mean(gradients, axis=(1, 2))
    
    for i in range(activations_cam.shape[0]):
        activations_cam[i, :, :] *= pooled_gradients[i]
        
    heatmap = np.mean(activations_cam, axis=0)
    heatmap = np.maximum(heatmap, 0) # Ignorar atencoes negativas (ReLU)
    if np.max(heatmap) == 0:
        heatmap_norm = heatmap
    else:
        heatmap_norm = heatmap / np.max(heatmap) # Meter tudo balizado entre 0 e 1!
    
    heatmap_resized = cv2.resize(heatmap_norm, (224, 224))
    heatmap_colored = cv2.applyColorMap(np.uint8(255 * heatmap_resized), cv2.COLORMAP_JET)
    heatmap_colored = cv2.cvtColor(heatmap_colored, cv2.COLOR_BGR2RGB)
    
    # Sobrepor calor na imagem natural
    original_img_resized = np.array(image.resize((224, 224)))
    superimposed = heatmap_colored * 0.4 + original_img_resized * 0.6
    superimposed = np.clip(superimposed, 0, 255).astype(np.uint8)

    # --- FUNCOES PARA CRIAR AS JANELAS CONJUNTAS S/ CRASHS ---
    plt.close('all') # Matar todo o lixo preso do passado
    
    def create_feature_map_figure(feature_maps, title):
        feature_maps = feature_maps.cpu().numpy()
        maps = feature_maps[0] 
        num_channels = maps.shape[0]
        disp_channels = min(num_channels, 64)
        
        size = int(np.ceil(np.sqrt(disp_channels)))
        fig, axes = plt.subplots(size, size, figsize=(10, 10))
        fig.canvas.manager.set_window_title(title)
        fig.suptitle(title, fontsize=14)

        for i, ax in enumerate(axes.flat):
            if i < disp_channels:
                ax.imshow(maps[i], cmap='gray')
            ax.axis('off')
        plt.tight_layout()

    # Como agora tiramos o plt.show() entre eles, os plots criam-se e escondem-se na RAM em bloco
    create_feature_map_figure(activation['conv1'], title="Camada 1 (Bordas)")
    create_feature_map_figure(activation['layer2'], title="Camada Secundaria")
    create_feature_map_figure(activation['layer3'], title="Camada Terciaria")

    # A Quarta Janela: O Milagre Colorido Final!
    fig_cam, (ax1, ax2, ax3) = plt.subplots(1, 3, figsize=(15, 6))
    fig_cam.canvas.manager.set_window_title("Analise de Rastreio Final (Grad-CAM)")
    fig_cam.suptitle(titulo_decisao, fontsize=20, fontweight='bold', color='darkred')

    ax1.imshow(original_img_resized)
    ax1.set_title("1. A sua Fotografia", fontsize=14)
    ax1.axis('off')

    ax2.imshow(heatmap_colored)
    ax2.set_title("2. Calor Interno GAP (Focos Termicos)", fontsize=14)
    ax2.axis('off')

    ax3.imshow(superimposed)
    ax3.set_title("3. Cruzamento Hibrido (Onde a IA focou)", fontsize=14)
    ax3.axis('off')

    plt.tight_layout()
    
    # RESOLUCAO DO BUg DA BLOCKING QUEUE DO MATPLOTLIB!
    # Chamar uma unica vez o show de bloqueio aqui no final do script
    # Faz com que todas as janelas surjam aglomeradas e em paralelo. 
    # Pode fechar A Layer 1 em separado, ou qualquer ordem que quiseres livremente!
    print("Graficos renderizados! O programa so terminará em definitivo quando desligar as 4 janelas do grafico (X).")
    plt.show(block=True)


if __name__ == "__main__":
    print("-" * 60)
    print(" Explorador de Cerebro CNN + Rastreamento GRAD-CAM ")
    print("-" * 60)
    
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        import subprocess, sys
        subprocess.check_call([sys.executable, "-m", "pip", "install", "matplotlib"])
        import matplotlib.pyplot as plt

    img_teste = input("Arraste o caminho de uma IMAGEM DE TESTE para a janela e faca ENTER:\n > ").strip().strip('"').strip("'")
    
    modelo_default = "melhor_modelo_multiclass_resnet50_80.pth"
    
    if img_teste:
        visualize_feature_maps_and_cam(img_teste, model_path=modelo_default)
    else:
        print("Script concluido de forma permatura.")
