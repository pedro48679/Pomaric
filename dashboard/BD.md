-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.apples (
  apple_id text NOT NULL,
  timestamp timestamp with time zone DEFAULT now(),
  location text,
  CONSTRAINT apples_pkey PRIMARY KEY (apple_id)
);
CREATE TABLE public.frames (
  id integer NOT NULL DEFAULT nextval('frames_id_seq'::regclass),
  apple_id text NOT NULL,
  frame_idx integer,
  image_url text,
  label text,
  confidence double precision,
  is_worst_case boolean DEFAULT false,
  CONSTRAINT frames_pkey PRIMARY KEY (id),
  CONSTRAINT frames_apple_id_fkey FOREIGN KEY (apple_id) REFERENCES public.apples(apple_id)
);
CREATE TABLE public.cnn_predictions (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  apple_id text NOT NULL,
  frame_id integer,
  model_name text NOT NULL,
  label text,
  confidence double precision,
  timestamp timestamp with time zone DEFAULT now(),
  CONSTRAINT cnn_predictions_pkey PRIMARY KEY (id),
  CONSTRAINT cnn_predictions_apple_id_fkey FOREIGN KEY (apple_id) REFERENCES public.apples(apple_id),
  CONSTRAINT cnn_predictions_frame_id_fkey FOREIGN KEY (frame_id) REFERENCES public.frames(id)
);
CREATE TABLE public.producao_atual (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  apple_id text NOT NULL UNIQUE,
  timestamp timestamp with time zone DEFAULT now(),
  location text,
  final_class text,
  final_confidence double precision,
  final_source text,
  frame_thumbnail text,
  CONSTRAINT producao_atual_pkey PRIMARY KEY (id),
  CONSTRAINT producao_atual_apple_id_fkey FOREIGN KEY (apple_id) REFERENCES public.apples(apple_id)
);
CREATE TABLE public.manual_review (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  apple_id text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'pending'::text,
  updated_at timestamp with time zone DEFAULT now(),
  corrected_class text,
  updated_by text,
  original_class text,
  original_confidence bigint,
  CONSTRAINT manual_review_pkey PRIMARY KEY (id),
  CONSTRAINT manual_review_apple_id_fkey FOREIGN KEY (apple_id) REFERENCES public.apples(apple_id)
);
CREATE TABLE public.manual_annotation (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  apple_id text NOT NULL UNIQUE,
  primary_apple_disease text,
  updated_by text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT manual_annotation_pkey PRIMARY KEY (id),
  CONSTRAINT manual_annotation_apple_id_fkey FOREIGN KEY (apple_id) REFERENCES public.apples(apple_id)
);
CREATE TABLE public.circles_manual (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  apple_id text NOT NULL,
  circle_index integer NOT NULL CHECK (circle_index >= 0),
  crop text,
  disease text NOT NULL,
  x double precision NOT NULL,
  y double precision NOT NULL,
  radius double precision NOT NULL CHECK (radius > 0::double precision),
  updated_by text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT circles_manual_pkey PRIMARY KEY (id),
  CONSTRAINT circles_manual_apple_id_fkey FOREIGN KEY (apple_id) REFERENCES public.apples(apple_id)
);
CREATE TABLE public.train_dataset (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  apple_id text NOT NULL,
  class text,
  CONSTRAINT train_dataset_pkey PRIMARY KEY (id),
  CONSTRAINT train_dataset_apple_id_fkey FOREIGN KEY (apple_id) REFERENCES public.apples(apple_id)
);
CREATE TABLE public.workers (
  id text NOT NULL,
  username text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  role text NOT NULL CHECK (role = ANY (ARRAY['admin'::text, 'operator'::text])),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone,
  CONSTRAINT workers_pkey PRIMARY KEY (id)
);
CREATE TABLE public.cnn5_multi_confidence (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  apple_id text NOT NULL,
  frame_id integer NOT NULL,
  class_label text NOT NULL,
  confidence double precision NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT cnn5_multi_confidence_pkey PRIMARY KEY (id),
  CONSTRAINT cnn5_multi_confidence_apple_id_fkey FOREIGN KEY (apple_id) REFERENCES public.apples(apple_id),
  CONSTRAINT cnn5_multi_confidence_frame_id_fkey FOREIGN KEY (frame_id) REFERENCES public.frames(id)
);