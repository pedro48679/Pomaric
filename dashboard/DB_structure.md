Estrutura atual das tabelas (public)
public.apples
PK: apple_id (text)
Campos: timestamp (timestamptz, default now()), location (text, nullable)
FKs apontadas para ela (por outras tabelas):
frames.apple_id → apples.apple_id
cnn_predictions.apple_id → apples.apple_id
manual_annotation.apple_id → apples.apple_id (e manual_annotation.apple_id é UNIQUE)
circles_manual.apple_id → apples.apple_id
manual_review.apple_id → apples.apple_id
train_dataset.apple_id → apples.apple_id
producao_atual.apple_id → apples.apple_id
public.frames
PK: id (int identity)
Campos: apple_id (text nullable), frame_idx (int nullable), image_url (text nullable), label (text nullable), confidence (float8 nullable), is_worst_case (bool default false)
FKs:
frames.apple_id → apples.apple_id
cnn_predictions.frame_id → frames.id (outra tabela aponta para esta)
public.cnn_predictions
PK: id (int identity)
Campos: apple_id (text nullable), model_name, label, confidence, timestamp (timestamptz default now()), frame_id (int nullable)
FKs:
cnn_predictions.apple_id → apples.apple_id
cnn_predictions.frame_id → frames.id
public.producao_atual
PK: id (int identity)
Campos: apple_id (text), timestamp (timestamptz default now()), location, final_class, final_confidence, final_source, frame_thumbnail
FK:
producao_atual.apple_id → apples.apple_id
public.manual_review
PK: id (int identity)
Campos: apple_id, status (text default 'pending'), updated_timestamp (timestamptz default now()), corrected_class, updated_by, original_class, original_confidence
FK:
manual_review.apple_id → apples.apple_id
public.manual_annotation
PK: id (int identity)
Campos: apple_id (text UNIQUE), primary_apple_disease, updated_by, created_at (default now()), updated_at (default now())
FK:
manual_annotation.apple_id → apples.apple_id
public.circles_manual
PK: id (int identity)
Campos: apple_id (text nullable), circle_index (int com CHECK >= 0), crop, disease, x, y, radius (CHECK > 0), updated_by, created_at, updated_at
FK:
circles_manual.apple_id → apples.apple_id
✅ Sem UNIQUE em apple_id (logo permite múltiplas linhas por maçã)
public.train_dataset
PK: id (int identity)
Campos: apple_id (text), class (text nullable)
FK:
train_dataset.apple_id → apples.apple_id