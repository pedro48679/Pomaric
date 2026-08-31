import os
import shutil
from imagededup.methods import CNN
from tqdm import tqdm

def exportar_dataset_unico_mesclado(pasta_original, pasta_limpa, threshold=0.92):
    print("---  A iniciar Fusão e Limpeza (ImageDedup) ---")
    
    cnn = CNN()
    
    # 1. Mapear as pastas. Ex: {'Healthy': ['Healthy', 'Healthy_dupe'], 'Unhealthy': ['Unhealthy']}
    mapa_classes = {}
    
    for nome_pasta in os.listdir(pasta_original):
        caminho_completo = os.path.join(pasta_original, nome_pasta)
        if not os.path.isdir(caminho_completo):
            continue
            
        # Descobrir o nome "base" da classe (removendo '_dupe' se existir, ignorando maiúsculas/minúsculas)
        nome_base = nome_pasta
        if nome_base.lower().endswith('_dupe'):
            nome_base = nome_base[:-5] # Corta os últimos 5 caracteres ('_dupe')
            
        # Remover espaços extra caso existam
        nome_base = nome_base.strip()
            
        if nome_base not in mapa_classes:
            mapa_classes[nome_base] = []
        mapa_classes[nome_base].append(nome_pasta)

    # 2. Processar cada Classe Base (que agora pode conter múltiplas pastas originais)
    for classe_base, pastas_origem in mapa_classes.items():
        print(f"\n A processar a classe consolidada: '{classe_base}'")
        print(f"   -> Pastas de origem associadas: {pastas_origem}")
        
        pasta_destino = os.path.join(pasta_limpa, classe_base)
        os.makedirs(pasta_destino, exist_ok=True)
        
        total_copiados = 0
        
        # Passo A: Juntar todas as imagens das subpastas para a nova casa
        for nome_pasta_origem in pastas_origem:
            caminho_origem = os.path.join(pasta_original, nome_pasta_origem)
            ficheiros = [f for f in os.listdir(caminho_origem) if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
            
            for f in ficheiros:
                caminho_ficheiro_origem = os.path.join(caminho_origem, f)
                caminho_ficheiro_destino = os.path.join(pasta_destino, f)
                
                # Proteção: Se houver imagens com o mesmo nome na pasta original e na '_dupe'
                # o script adiciona um número no final para não esmagar ficheiros diferentes
                contador = 1
                while os.path.exists(caminho_ficheiro_destino):
                    nome, ext = os.path.splitext(f)
                    caminho_ficheiro_destino = os.path.join(pasta_destino, f"{nome}_{contador}{ext}")
                    contador += 1
                    
                shutil.copy2(caminho_ficheiro_origem, caminho_ficheiro_destino)
                total_copiados += 1

        print(f"    Total de imagens juntas na nova pasta provisória: {total_copiados}")
        
        if total_copiados == 0:
            continue
            
        # Passo B: Analisar e limpar os duplicados na NOVA pasta
        print("    A procurar duplicados no grupo...")
        copias_a_ignorar = cnn.find_duplicates_to_remove(
            image_dir=pasta_destino, 
            min_similarity_threshold=threshold
        )
        
        # Passo C: Apagar os clones da nova pasta (mantendo a original intacta)
        if copias_a_ignorar:
            for f_lixo in copias_a_ignorar:
                caminho_lixo = os.path.join(pasta_destino, f_lixo)
                try:
                    os.remove(caminho_lixo)
                except Exception as e:
                    print(f"    Erro ao remover clone {f_lixo}: {e}")
                    
            print(f"    {len(copias_a_ignorar)} clones fundidos e apagados do dataset limpo!")
        else:
            print("    Nenhuma imagem repetida encontrada neste grupo.")
            
        imagens_finais = len(os.listdir(pasta_destino))
        print(f"    Imagens ÚNICAS prontas para o modelo: {imagens_finais}")

    print("\n Processo concluído com sucesso!")
    print("As pastas foram fundidas logicamente e o dataset limpo está pronto para treino.")

if __name__ == "__main__":
    # 1. Pasta onde está o dataset original (Ex: contém 'Healthy', 'Healthy_dupe', etc.)
    PASTA_ORIGINAL = r"C:\Users\Utilizador\OneDrive\Área de Trabalho\Apple_novaDB - Cópia"
    
    # 2. Pasta onde vai nascer o dataset perfeito (já com as pastas mescladas e sem duplicados)
    PASTA_LIMPA = r"C:\Users\Utilizador\OneDrive\Área de Trabalho\novaDB_duped"
    
    exportar_dataset_unico_mesclado(PASTA_ORIGINAL, PASTA_LIMPA, threshold=0.95)