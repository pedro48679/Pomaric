import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms, models
import os
import copy
import shutil

def train_cnn(data_dir, num_classes=2, epochs=35, batch_size=32):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Usando o dispositivo: {device}")

    # 1. Definir os caminhos para as pastas já divididas
    train_dir = os.path.join(data_dir, 'train')
    valid_dir = os.path.join(data_dir, 'valid')
    test_dir = os.path.join(data_dir, 'test')

    # 2. Transformações (Augmentation só no Train, Normalização em todos)
    train_transform = transforms.Compose([
        transforms.Resize((224, 224)),
        
        # Estrategias de Data Augmentation para evitar Overfitting Espacial
        transforms.RandomHorizontalFlip(),
        transforms.RandomVerticalFlip(),
        transforms.RandomRotation(180),  # Garante invariabilidade rotacional completa
        
        # --- Otimização para Esteira (Conveyor) ---
        transforms.GaussianBlur(kernel_size=(3, 3), sigma=(0.1, 0.3)), # Blur mais suave para não apagar doenças
        transforms.RandomAdjustSharpness(sharpness_factor=2, p=0.5),   
        
        # Aumento da variabilidade de brilho 
        transforms.ColorJitter(brightness=0.4, contrast=0.4, saturation=0.2, hue=0.05),
        
        transforms.ToTensor(),
        
        # Tecnicas de Regularizacao Avancada: Random Erasing
        # Induz oclusao parcial induzindo a rede a focar-se na arquitetura global
        # mitigando a dependencia excessiva num unico padrao discriminativo.
        transforms.RandomErasing(p=0.2, scale=(0.02, 0.05)),
        
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]) 
    ])

    val_test_transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    # 3. Carregar Datasets usando a estrutura de pastas existentes
    train_dataset = datasets.ImageFolder(train_dir, transform=train_transform)
    valid_dataset = datasets.ImageFolder(valid_dir, transform=val_test_transform)
    test_dataset = datasets.ImageFolder(test_dir, transform=val_test_transform)

    print(f"Classes detetadas: {train_dataset.classes}")
    print(f"Imagens de Treino: {len(train_dataset)}")
    print(f"Imagens de Validação: {len(valid_dataset)}")
    print(f"Imagens de Teste: {len(test_dataset)}")

    # 4. Criar DataLoaders
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(valid_dataset, batch_size=batch_size, shuffle=False)
    test_loader = DataLoader(test_dataset, batch_size=batch_size, shuffle=False)

    # 5. Configurar o Modelo (MobileNetV2 é leve e muito bom)
    model = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.IMAGENET1K_V1)

    # Aplicacao de Fine-Tuning Descongelado (Unfrozen)
    # Permite a adaptacao dos pesos das camadas convolucionais pre-treinadas no ImageNet
    # para a identificacao de macro e microestruturas especificas destas patologias.
    for param in model.parameters():
        param.requires_grad = True

    # Substituir a camada final de classificação para ter o número de classes que temos (ex: 2)
    model.classifier[1] = nn.Linear(model.last_channel, num_classes)
    model = model.to(device)

    # 6. Configurar Loss, Optimizer e Variáveis de Controlo
    criterion = nn.CrossEntropyLoss()
    
    # Atualizacao Global de Pesos via Adam Optimizer (Taxa Conservadora para Fine-tuning)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-4)
    
    # Ajuste para garantir convergência sem "viciar"
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=4)

    best_model_wts = copy.deepcopy(model.state_dict())
    best_val_loss = float("inf")
    patience = 10 # Mais paciência para lidar com as augmentations de esteira
    patience_counter = 0

    # 7. Ciclo de Treino
    print("\n A Iniciar Treino...")
    for epoch in range(epochs):
        model.train()
        train_loss = 0.0

        for images, labels in train_loader:
            images, labels = images.to(device), labels.to(device)

            optimizer.zero_grad()
            outputs = model(images)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()

            # O loss gerado vem numa média por batch, por isso multiplicamos pelo batch_size real
            train_loss += loss.item() * images.size(0)
            
        train_loss = train_loss / len(train_dataset)

        # 8. Ciclo de Validação
        model.eval()
        val_loss = 0.0
        corrects = 0

        with torch.no_grad():
            for images, labels in val_loader:
                images, labels = images.to(device), labels.to(device)
                outputs = model(images)
                loss = criterion(outputs, labels)
                
                val_loss += loss.item() * images.size(0)
                _, preds = torch.max(outputs, 1)
                corrects += torch.sum(preds == labels.data)

        val_loss = val_loss / len(valid_dataset)
        val_acc = corrects.double() / len(valid_dataset)

        print(f"Epoch {epoch+1}/{epochs} | "
              f"Train Loss: {train_loss:.4f} | "
              f"Val Loss: {val_loss:.4f} | "
              f"Val Acc: {val_acc:.4f}")

        # Execucao do Scheduler baseado na metrica de Validacao
        scheduler.step(val_loss)

        # 9. Early Stopping e Gravacao Integral do State Dict
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            best_model_wts = copy.deepcopy(model.state_dict())
            patience_counter = 0
            # Guarda o modelo atualizado
            torch.save(best_model_wts, 'ONNX_CNN2.pth')
        else:
            patience_counter += 1

        if patience_counter >= patience:
            print(" Early stopping disparou. Validação parou de melhorar.")
            break

    # Carregar o melhor modelo
    model.load_state_dict(best_model_wts)

    # ---------------- TEST LOOP (Avaliação Final & Análise de Erros) ----------------
    print("\n A testar o modelo no dataset de Teste (imparcial)...")
    model.eval()
    test_corrects = 0
    
    # Criar pasta para guardar os erros visuais
    pasta_erros = os.path.join(data_dir, "erros_teste")
    os.makedirs(pasta_erros, exist_ok=True)
    # Limpar erros de sessões anteriores
    for f in os.listdir(pasta_erros):
        os.remove(os.path.join(pasta_erros, f))

    # Matriz de Confusão nativa
    classes = test_dataset.classes
    matriz_confusao = {c_real: {c_prev: 0 for c_prev in classes} for c_real in classes}
    
    current_idx = 0
    with torch.no_grad():
        for images, labels in test_loader:
            images, labels = images.to(device), labels.to(device)
            outputs = model(images)
            _, preds = torch.max(outputs, 1)
            
            # Analisar cada imagem individualmente dentro do batch
            for i in range(len(labels)):
                real_idx = labels[i].item()
                pred_idx = preds[i].item()
                
                nome_real = classes[real_idx]
                nome_previsto = classes[pred_idx]
                
                # Registar na Matriz de Confusão
                matriz_confusao[nome_real][nome_previsto] += 1
                
                if real_idx == pred_idx:
                    test_corrects += 1
                else:
                    # Encontrar a imagem original que falhou
                    caminho_img, _ = test_dataset.samples[current_idx]
                    nome_original = os.path.basename(caminho_img)
                    
                    # Copiar para a pasta de erros com nome explicativo
                    novo_nome = f"Real_{nome_real}___Previu_{nome_previsto}___{nome_original}"
                    shutil.copy(caminho_img, os.path.join(pasta_erros, novo_nome))
                    
                current_idx += 1
            
    test_acc = test_corrects / len(test_dataset)
    print(f"\n Precisao de Diagnostico Acumulada no Teste: {test_acc:.4f} ({(test_acc*100):.2f}%)")
    
    print("\n--- MATRIZ DE CONFUSAO DO MODELO ---")
    for c_real in classes:
        for c_prev in classes:
            qtd = matriz_confusao[c_real][c_prev]
            if c_real == c_prev:
                print(f" Eram {c_real} e o modelo acertou em: {qtd}")
            else:
                if qtd > 0:
                    print(f" Eram {c_real} mas o modelo confundiu com {c_prev}: {qtd}")
                
    falhas_totais = len(test_dataset) - test_corrects
    if falhas_totais > 0:
        print(f"\n Pode ver as {falhas_totais} imagens exatas que o modelo falhou na pasta: {pasta_erros}")
    else:
        print("\n O modelo acertou todas as imagens do Teste!")

    return model

if __name__ == "__main__":
    # Parametrizacao de Localizacao do Dataset Dividido
    DATA_DIR = "./data/background_distri"  # ajusta para o caminho local do dataset dividido (train/val/test)
    
    # Executar o treino. Como o RandomErasing dificulta muito a aprendizagem, foi imposto um máximo de 50 epochs
    train_cnn(DATA_DIR, num_classes=2, epochs=50)