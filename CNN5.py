import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms, models
import os
import copy
import shutil
import numpy as np
from torch.utils.data.sampler import WeightedRandomSampler

def train_cnn(data_dir, num_classes=5, epochs=50, batch_size=16):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Usando o dispositivo: {device}")

    # 1. Definir os caminhos para as pastas já divididas
    train_dir = os.path.join(data_dir, 'train')
    valid_dir = os.path.join(data_dir, 'valid')
    test_dir = os.path.join(data_dir, 'test')

    # Definicao de Transformacoes Multidimensionais e Normalizacao de Tensores
    train_transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.RandomHorizontalFlip(),
        transforms.RandomVerticalFlip(), # Prevencao de features baseadas na orientacao
        transforms.RandomRotation(180), # Invariancia vetorial rotacional
        transforms.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.2, hue=0.05), # Aumento da robustez a ruido
        transforms.ToTensor(),
        transforms.RandomErasing(p=0.2, scale=(0.02, 0.1)), # Regularizacao por oclusao local sistematica
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]) 
    ])

    val_test_transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    # 3. Carregar Datasets usando a estrutura de pastas originais
    train_dataset = datasets.ImageFolder(train_dir, transform=train_transform)
    valid_dataset = datasets.ImageFolder(valid_dir, transform=val_test_transform)
    
    # Tornar a carga do teste Opcional (para quando se quer treinar versao final de producao)
    has_test = os.path.exists(test_dir)
    if has_test:
        test_dataset = datasets.ImageFolder(test_dir, transform=val_test_transform)
    else:
        test_dataset = []

    print(f"\nClasses detetadas automaticamente: {train_dataset.classes}")
    
    # Ajusta automaticamente as classes caso detecte pastas a mais/a menos
    num_classes_reais = len(train_dataset.classes)
    if num_classes_reais != num_classes:
        print(f"Aviso: Foram detetadas {num_classes_reais} classes na pasta em vez de {num_classes}. A reajustar...")
        num_classes = num_classes_reais

    print(f"Imagens de Treino: {len(train_dataset)}")
    print(f"Imagens de Validacao: {len(valid_dataset)}")
    
    if has_test:
        print(f"Imagens de Teste: {len(test_dataset)}")
    else:
        print("Imagens de Teste: 0 (Ocultadas para Forcar Treino de Producao Definitiva)")

    # 4. Criar DataLoaders Padrão
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(valid_dataset, batch_size=batch_size, shuffle=False)
    
    if has_test:
        test_loader = DataLoader(test_dataset, batch_size=batch_size, shuffle=False)
    else:
        test_loader = None

    # 5. Configurar o Modelo: Substituímos o ligeiro MobileNetV2 pelo poderoso ResNet50
    # O ResNet50 é arquitetonicamente mais profundo e captura melhores micro-padrões e texturas (fundamental em doenças).
    model = models.resnet50(weights=models.ResNet50_Weights.IMAGENET1K_V2)

    # CONGELAMENTO HIERARQUICO (Transfer Learning Otimizado para Datasets Pequenos)
    # 1. Congelar toda a base estrutural (camadas iniciais) para impedir que o modelo destrua o seu 
    #    conhecimento de 'iluminacao' e 'bordas' tentando decorar o maximo de imagens de macas.
    for param in model.parameters():
        param.requires_grad = False
        
    # 2. Descongelar o Layer 3 e Layer 4 para refinar a alta definicao da doenca.
    for param in model.layer3.parameters():
        param.requires_grad = True
    for param in model.layer4.parameters():
        param.requires_grad = True

    # 3. Integracao de bloco de classificacao Linear Blindado com Dropout Rigoroso (50%)
    model.fc = nn.Sequential(
        nn.Dropout(p=0.5), # Obriga o modelo a nao confiar sempre nos mesmos neuronios 
        nn.Linear(model.fc.in_features, num_classes)
    )
    model = model.to(device)

    # 6. Configurar Loss, Optimizer e Variáveis de Controlo
    criterion = nn.CrossEntropyLoss()
    # Diminuimos o ritmo base e reativamos o amortecedor L2 (Weight Decay)
    # IMPORTANTE: Apenas carregamos para o Optimizador os tensores que estao Descongelados!
    optimizer = torch.optim.Adam(
        filter(lambda p: p.requires_grad, model.parameters()), 
        lr=5e-5, 
        weight_decay=1e-4
    )
    
    # Scheduler: Se a Validacao (Val Loss) encravar durante 2 epocas seguidas, 
    # corta automaticamente o learning rate para metade.
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=2)

    best_model_wts = copy.deepcopy(model.state_dict())
    best_val_loss = float("inf")
    patience = 5  # Early stopping tolerância
    patience_counter = 0

    # 7. Ciclo de Treino
    print("\nA Iniciar Treino Multi-Class (ResNet50)...")
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

            # O loss gerado vem numa média por batch, multiplicamos pelo batch_size real
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

        print(f"Epoch {epoch+1:02d}/{epochs} | "
              f"Train Loss: {train_loss:.4f} | "
              f"Val Loss: {val_loss:.4f} | "
              f"Val Acc: {val_acc:.4f}")
              
        # Informar o Scheduler do Valor da Validacao para ele atuar
        scheduler.step(val_loss)

        # 9. Early Stopping & Guardar o melhor modelo
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            best_model_wts = copy.deepcopy(model.state_dict())
            patience_counter = 0
            # Guardamos como resnet50 para destrinçar.
            torch.save(best_model_wts, 'melhor_weight_multiclass_RESnet50_FINAL2.pth')
        else:
            patience_counter += 1

        if patience_counter >= patience:
            print(f"Early stopping disparou. Validacao parou de melhorar ha {patience} epocas seguidas.")
            break

    # Carregar o melhor modelo
    model.load_state_dict(best_model_wts)

    # ---------------- TEST LOOP (Avaliação Final & Análise de Erros) ----------------
    if test_loader is not None:
        print("\nA testar o modelo no dataset de Teste (imparcial)...")
        model.eval()
        test_corrects = 0
        
        # Criar pasta para guardar os erros visuais
        pasta_erros = os.path.join(data_dir, "erros_teste_multiclass")
        os.makedirs(pasta_erros, exist_ok=True)
        
        # Limpar erros de sessões anteriores
        for f in os.listdir(pasta_erros):
            os.remove(os.path.join(pasta_erros, f))

        # Matriz de Confusão Múltipla
        classes = train_dataset.classes # Mudou para train_dataset pois test pode nao existir
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
                    
                    matriz_confusao[nome_real][nome_previsto] += 1
                    
                    if real_idx == pred_idx:
                        test_corrects += 1
                    else:
                        caminho_img, _ = test_dataset.samples[current_idx]
                        nome_original = os.path.basename(caminho_img)
                        
                        novo_nome = f"Esperava_{nome_real}__Previu_{nome_previsto}___{nome_original}"
                        shutil.copy(caminho_img, os.path.join(pasta_erros, novo_nome))
                        
                    current_idx += 1
                
        test_acc = test_corrects / len(test_dataset)
        print(f"\nPrecisao Final no Teste: {test_acc:.4f} ({(test_acc*100):.2f}%)")
        
        print("\n--- MATRIZ DE CONFUSAO (MULTIPLAS CLASSES) ---")
        for c_real in classes:
            for c_prev in classes:
                qtd = matriz_confusao[c_real][c_prev]
                if c_real == c_prev:
                    print(f"[Certo] Eram {c_real} e acertou: {qtd}")
                elif qtd > 0:
                    print(f"[Erro] Eram {c_real} mas confundiu com {c_prev}: {qtd}")
                    
        falhas_totais = len(test_dataset) - test_corrects
        if falhas_totais > 0:
            print(f"\nPode ver as imagens onde o modelo fez confusao na pasta: {pasta_erros}")
        else:
            print("\nO modelo acertou todas as imagens do Teste!")
    else:
        print("\nTreino Concluido! Como a pasta 'test' nao existe, o modelo foi finalizado para producao (100% blindado sem metricas de teste).")

    return model

if __name__ == "__main__":
    print("-" * 60)
    print(" Treino Multi-Categoria (5 Classes) - Doencas de Macas ")
    print(" Arquitetura: ResNet50 (Extraida do ImageNet V2) ")
    print("-" * 60)
    
    # Caminho base que contém as pastas train/ valid/ test/ divididas
    user_dir = input("Cole o caminho da pasta raiz do seu dataset (contem train, valid e test):\n > ").strip().strip('"').strip("'")
    
    if os.path.exists(user_dir):
        # Data Augmentation aumenta a longevidade antes do overfitting
        train_cnn(user_dir, num_classes=5, epochs=50, batch_size=16)
    else:
        print("Erro: Pasta nao encontrada.")
