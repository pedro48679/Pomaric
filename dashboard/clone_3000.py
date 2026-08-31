import os
import random
import uuid
import sys
from datetime import datetime, timedelta
from supabase import create_client, Client

# Carrega chaves do ficheiro secrets.local.ps1
supabase_url = os.environ.get("SUPABASE_URL")
supabase_key = os.environ.get("SUPABASE_SERVICE_KEY")

if not supabase_url or not supabase_key:
    print("ERRO: As variáveis de ambiente SUPABASE_URL e SUPABASE_SERVICE_KEY não estão definidas.")
    print("Corra este script na mesma sessão de PowerShell onde fez o load do secrets.local.ps1")
    sys.exit(1)

supabase: Client = create_client(supabase_url, supabase_key)

def run():
    print("A carregar maçãs originais...")
    response = supabase.table('apples').select('*').limit(3000).execute()
    original_apples = response.data
    
    if not original_apples:
        print("Nenhuma maçã encontrada na BD.")
        return

    # Buscar frames para clonar as imagens (para simplificar, clonamos tudo)
    print("A carregar frames originais...")
    original_apple_ids = [a['apple_id'] for a in original_apples]
    frames_res = supabase.table('frames').select('*').in_('apple_id', original_apple_ids).execute()
    original_frames = frames_res.data
    
    # Criar um mapa de apple_id -> lista de frames
    frames_by_apple = {}
    for f in original_frames:
        frames_by_apple.setdefault(f['apple_id'], []).append(f)
        
    new_apples = []
    new_frames = []
    
    now = datetime.now()
    
    print(f"A preparar {len(original_apples)} clones para dias antigos...")
    
    for apple in original_apples:
        new_apple_id = f"Cloned_{uuid.uuid4().hex[:8]}"
        
        # Gerar data entre 10 e 28 dias atrás
        days_ago = random.randint(10, 28)
        
        # Gerar hora entre 09:00 e 17:00
        random_hour = random.randint(9, 17)
        random_minute = random.randint(0, 59)
        random_second = random.randint(0, 59)
        
        past_date = now - timedelta(days=days_ago)
        new_timestamp = past_date.replace(hour=random_hour, minute=random_minute, second=random_second, microsecond=0)
        
        new_apple = {
            'apple_id': new_apple_id,
            'location': apple['location'],
            'timestamp': new_timestamp.isoformat()
        }
        new_apples.append(new_apple)
        
        # Clonar os frames associados
        old_frames = frames_by_apple.get(apple['apple_id'], [])
        for f in old_frames:
            new_frame = f.copy()
            del new_frame['frame_id'] # deixar a BD gerar novo id
            new_frame['apple_id'] = new_apple_id
            new_frames.append(new_frame)
            
    print("A inserir clones na tabela 'apples'...")
    # Inserir em chunks de 500 para não estoirar o limite de payload
    chunk_size = 500
    for i in range(0, len(new_apples), chunk_size):
        chunk = new_apples[i:i+chunk_size]
        supabase.table('apples').insert(chunk).execute()
        print(f"Inseridas {min(i+chunk_size, len(new_apples))}/{len(new_apples)} maçãs.")
        
    print("A inserir clones na tabela 'frames'...")
    for i in range(0, len(new_frames), chunk_size):
        chunk = new_frames[i:i+chunk_size]
        supabase.table('frames').insert(chunk).execute()
        print(f"Inseridos {min(i+chunk_size, len(new_frames))}/{len(new_frames)} frames.")

    print("\n✅ Sucesso! Foram injetadas maçãs clonadas para os dias de vista de 30 dias.")
    print("Por favor, execute também a query SQL gerada para agrupar as horas das maçãs atuais e futuras.")

if __name__ == '__main__':
    run()
