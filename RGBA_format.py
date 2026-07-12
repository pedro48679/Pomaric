import os
import torch
import cv2
import numpy as np
from PIL import Image
from rembg import remove, new_session

# Permitir que onnxruntime-gpu aceda às DLLs do CUDA instaladas via PyTorch
try:
    torch_lib_path = os.path.join(os.path.dirname(torch.__file__), "lib")
    os.environ["PATH"] = torch_lib_path + ";" + os.environ["PATH"]
except Exception as e:
    print(f"Aviso: não foi possível definir o path do torch: {e}")

# Iniciar a sessão (carrega o modelo) globalmente para não atrasar imagem a imagem
# Tenta usar a placa gráfica (CUDA), se falhar usa o processador (CPU)
session = new_session(providers=["CUDAExecutionProvider", "CPUExecutionProvider"])


def format_pipeline(input_path, output_path):
    print(f"--- A processar: {os.path.basename(input_path)} ---")
    
    if not os.path.exists(input_path):
        print(f"Erro: O ficheiro '{input_path}' não foi encontrado.")
        return False

    try:
        input_img = Image.open(input_path).convert("RGB")
    except Exception as e:
        print(f"Erro ao abrir a imagem: {e}")
        return False

    # 1. Remover fundo para obter a máscara inicial
    output_img = remove(input_img, session=session)
    # Garantir que output_img tem as mesmas dimensões que input_img
    if output_img.size != input_img.size:
        output_img = output_img.resize(input_img.size, Image.LANCZOS)
    # O .copy() é obrigatório para que o OpenCV consiga desenhar diretamente na matriz em memória
    mask = np.array(output_img)[:, :, 3].copy()
    
    # 2. Utilizar findContours para evitar ruídos soltos na máscara (garantindo que não usamos o ecrã inteiro)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    
    if contours:
        # Encontrar o maior contorno (a maçã)
        c_maca = max(contours, key=cv2.contourArea)
        
        # Encontrar a caixa delimitadora original e o seu centro
        x, y, w, h = cv2.boundingRect(c_maca)
        cx = x + w // 2
        cy = y + h // 2
        
        # 3. Estratégia de segurança: não cortar a uma certa distância do centro
        # Desenhamos um círculo na máscara protegendo toda a área central da remoção de fundo
        raio_protecao = int(max(w, h) * 0.45)
        cv2.circle(mask, (cx, cy), raio_protecao, 255, -1)
        
        # Aplicar também o Convex Hull para preencher qualquer "mordida" nas bordas
        contours_corrigidos, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if contours_corrigidos:
            c = max(contours_corrigidos, key=cv2.contourArea)
            hull = cv2.convexHull(c)
            # Limpar a máscara para eliminar ruidos de fundo remanescentes
            mask.fill(0)
            cv2.drawContours(mask, [hull], 0, 255, -1)
            # Recalcular os limites APENAS sobre a maçã processada e garantida
            x, y, w, h = cv2.boundingRect(hull)

        # 4. Integrar a máscara corrigida com os píxeis INTACTOS da imagem original!
        # Desta forma a CNN vai ver a textura saudável original nas partes que teriam sido recortadas.
        original_rgba = np.array(input_img.convert("RGBA"))
        original_rgba[:, :, 3] = mask
        
        # 5. Cortar focando-se estritamente na maçã! Em vez de usar os limites arbitrários que podiam apanhar ruído
        # Fazer um recorte quadrado em redor do centro para maximizar o aspeto
        lado_maximo = int(max(w, h) * 1.05) # adicionar 5% de margem
        y1 = max(0, cy - lado_maximo // 2)
        y2 = min(original_rgba.shape[0], cy + lado_maximo // 2)
        x1 = max(0, cx - lado_maximo // 2)
        x2 = min(original_rgba.shape[1], cx + lado_maximo // 2)
        
        cropped_matrix = original_rgba[y1:y2, x1:x2]
        cropped_apple = Image.fromarray(cropped_matrix)
        
        # --- NOVA LÓGICA DE REDIMENSIONAMENTO E TELA ---
        TAMANHO_TELA = 224
        
        # Calcular o rácio de redimensionamento mantendo a proporção exata recortada
        racio = TAMANHO_TELA / max(cropped_apple.width, cropped_apple.height)
        nova_largura = int(cropped_apple.width * racio)
        nova_altura = int(cropped_apple.height * racio)
        
        # Redimensionar a maçã usando um filtro de alta qualidade (LANCZOS)
        resized_apple = cropped_apple.resize((nova_largura, nova_altura), Image.Resampling.LANCZOS)
        
        # Criar uma tela 100% transparente de 224x224 (RGBA)
        final_canvas = Image.new("RGBA", (TAMANHO_TELA, TAMANHO_TELA), (0, 0, 0, 0))
        
        # Calcular as coordenadas X e Y para colar a maçã exatamente no centro da tela
        pos_x = (TAMANHO_TELA - nova_largura) // 2
        pos_y = (TAMANHO_TELA - nova_altura) // 2
        
        # Colar a maçã na tela transparente
        final_canvas.paste(resized_apple, (pos_x, pos_y))
        # -----------------------------------------------
        
        # Salvar
        pasta_destino = os.path.dirname(output_path)
        if pasta_destino:
            os.makedirs(pasta_destino, exist_ok=True)
            
        final_canvas.save(output_path, "PNG")
        print(f"   -> Sucesso! Imagem final tem {TAMANHO_TELA}x{TAMANHO_TELA} com a maçã ampliada/centrada.")
        return True
    else:
        print("Erro: O modelo de IA não conseguiu detetar nenhum objeto principal.")
        return False

if __name__ == "__main__":
    # Processar SCARPP diretamente: formata in-place 224x224 RGBA transparente
    pasta_base = "./data/scrappa"  # ajusta para a pasta local com as imagens raspadas

    IGNORE = {"_rejeitadas", "folhas", "manifest.csv", "manifest_inaturalist.csv"}

    if os.path.exists(pasta_base):
        # Percorrer todas as doenças
        count_total = 0
        for nome_doenca in sorted(os.listdir(pasta_base)):
            caminho_doenca = os.path.join(pasta_base, nome_doenca)

            # Ignorar ficheiros e pastas especiais
            if not os.path.isdir(caminho_doenca) or nome_doenca in IGNORE:
                continue

            print(f"\n[{nome_doenca}]")
            count_doenca = 0

            # Percorrer os ficheiros da doença
            for nome_ficheiro in sorted(os.listdir(caminho_doenca)):
                caminho_entrada = os.path.join(caminho_doenca, nome_ficheiro)

                if os.path.isfile(caminho_entrada):
                    nome_base, ext = os.path.splitext(nome_ficheiro)

                    # Ignorar ficheiros que não sejam imagens
                    if ext.lower() not in ['.jpg', '.jpeg', '.png']:
                        continue

                    # Salvar sempre como PNG para suportar o canal RGBA transparente
                    caminho_saida = os.path.join(caminho_doenca, f"{nome_base}.png")

                    if format_pipeline(caminho_entrada, caminho_saida):
                        count_doenca += 1
                        # Se a imagem original era .jpg/.jpeg (caminho diferente), eliminamo-la
                        if caminho_entrada != caminho_saida:
                            try:
                                os.remove(caminho_entrada)
                            except Exception as e:
                                print(f"Erro ao remover a imagem original {caminho_entrada}: {e}")

            count_total += count_doenca
            print(f"  -> {count_doenca} imagens formatadas")

        print(f"\nTotal formatado: {count_total} imagens")
    else:
        print(f"Erro: A pasta {pasta_base} não foi encontrada.")