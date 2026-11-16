-- SIGO schema-only baseline: catalog snapshot of public, 2026-11-16.

-- Snapshot source: Supabase project sxgziltpoputrzhgpjof (PostgreSQL 17). No data.

-- Catalog-derived reconstruction; NOT produced by pg_dump. Requires Supabase auth schema/roles.

-- Idempotent for identical schema; differences in existing objects are not automatically reconciled.

-- NEVER execute on hosted Supabase without isolated review and migration history reconciliation.



CREATE SCHEMA IF NOT EXISTS public;

SET search_path TO public, auth, pg_catalog;



-- 1. Tables (identity sequences are created with GENERATED AS IDENTITY).

CREATE TABLE IF NOT EXISTS public."gm_importacoes" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "tipo" text NOT NULL,
  "arquivo_nome" text NOT NULL,
  "sha256" text NOT NULL,
  "registros" integer DEFAULT 0 NOT NULL,
  "criado_por" uuid DEFAULT auth.uid() NOT NULL,
  "criado_em" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public."nf_eventos" (
  "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  "nf_id" uuid NOT NULL,
  "tipo" text NOT NULL,
  "motivo" text,
  "rota_destino_id" uuid,
  "usuario_id" uuid DEFAULT auth.uid() NOT NULL,
  "ocorrido_em" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public."nf_execucoes" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "nf_id" uuid NOT NULL,
  "rota_id" uuid NOT NULL,
  "tipo" text NOT NULL,
  "iniciada_em" timestamp with time zone DEFAULT now() NOT NULL,
  "encerrada_em" timestamp with time zone,
  "registrada_por" uuid DEFAULT auth.uid() NOT NULL
);

CREATE TABLE IF NOT EXISTS public."notas_fiscais" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "numero" character(9) NOT NULL,
  "serie" text NOT NULL,
  "chave_acesso" character(44),
  "emitente_documento" text,
  "romaneio_origem" text,
  "origem_rota_id" uuid,
  "origem_confirmada" boolean DEFAULT false NOT NULL,
  "primeira_carga_em" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public."ocorrencias_roteirizacao" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "criado_em" timestamp with time zone DEFAULT now() NOT NULL,
  "criado_por" uuid NOT NULL,
  "atualizado_em" timestamp with time zone DEFAULT now() NOT NULL,
  "atualizado_por" uuid,
  "data_rota" date NOT NULL,
  "codigo_cliente" text NOT NULL,
  "cliente" text NOT NULL,
  "nf" text NOT NULL,
  "codigo_rota" text NOT NULL,
  "romaneio" text,
  "condutor" text,
  "vendedor" text,
  "tipo" text NOT NULL,
  "saida" text NOT NULL,
  "sequencia_planejada" integer,
  "sequencia_executada" integer,
  "horario_restricao" text,
  "detalhe" text NOT NULL,
  "impacto" text NOT NULL,
  "acao_imediata" text,
  "area_correcao" text NOT NULL,
  "responsavel_tratativa" text,
  "status" text DEFAULT 'ABERTA'::text NOT NULL,
  "retorno_gestao" text,
  "resolvido_em" timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public."parada_notas" (
  "parada_id" bigint NOT NULL,
  "nf_id" uuid NOT NULL,
  "importacao_id" uuid
);

CREATE TABLE IF NOT EXISTS public."paradas" (
  "id" bigint NOT NULL,
  "rota_id" uuid,
  "data_rota" date,
  "codigo_rota" text,
  "codigo_localidade" text,
  "cliente" text,
  "status_gm" text,
  "importacao_id" uuid,
  "atualizado_em" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public."prestacao_notas" (
  "prestacao_id" uuid NOT NULL,
  "nf_id" uuid NOT NULL,
  "canhoto_recebido_em" timestamp with time zone,
  "canhoto_recebido_por" uuid
);

CREATE TABLE IF NOT EXISTS public."prestacoes" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "romaneio_oficial" text NOT NULL,
  "d0" date NOT NULL,
  "status" text DEFAULT 'ABERTA'::text NOT NULL,
  "responsavel_id" uuid DEFAULT auth.uid() NOT NULL,
  "retornada_em" timestamp with time zone,
  "conferida_em" timestamp with time zone,
  "conferida_por" uuid,
  "enviada_em" timestamp with time zone,
  "enviada_por" uuid,
  "confirmada_em" timestamp with time zone,
  "confirmada_por" uuid,
  "pendencia_fora_sla" boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public."prestadores" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "nome" text NOT NULL,
  "documento" text NOT NULL,
  "veiculo" text NOT NULL,
  "placa" text NOT NULL,
  "base" text NOT NULL,
  "disponibilidade" text DEFAULT 'Disponível'::text NOT NULL,
  "status" text DEFAULT 'Ativo'::text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_by" uuid,
  "updated_by" uuid
);

CREATE TABLE IF NOT EXISTS public."profiles" (
  "id" uuid NOT NULL,
  "nome" text DEFAULT ''::text NOT NULL,
  "ativo" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public."rotas" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "data_rota" date NOT NULL,
  "codigo" text NOT NULL,
  "romaneio_gm" text,
  "tipo_romaneio" text DEFAULT 'A_CLASSIFICAR'::text NOT NULL,
  "motorista_gm" text,
  "veiculo" text,
  "saida" smallint,
  "km_planejado" numeric(12,3),
  "km_realizado" numeric(12,3),
  "gm_status" text,
  "importacao_id" uuid,
  "atualizado_em" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public."sla_config" (
  "id" boolean DEFAULT true NOT NULL,
  "limite_dias" integer DEFAULT 3 NOT NULL,
  "tipo_contagem" text DEFAULT 'corridos'::text NOT NULL,
  "meta_horas" integer DEFAULT 48 NOT NULL
);

CREATE TABLE IF NOT EXISTS public."user_roles" (
  "user_id" uuid NOT NULL,
  "role" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);



-- 2. Primary keys, unique constraints, checks; foreign keys after all tables exist.

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."gm_importacoes"'::regclass AND conname = 'gm_importacoes_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."gm_importacoes" ADD CONSTRAINT "gm_importacoes_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."gm_importacoes"'::regclass AND conname = 'gm_importacoes_registros_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."gm_importacoes" ADD CONSTRAINT "gm_importacoes_registros_check" CHECK (registros >= 0)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."gm_importacoes"'::regclass AND conname = 'gm_importacoes_sha256_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."gm_importacoes" ADD CONSTRAINT "gm_importacoes_sha256_check" CHECK (sha256 ~ '^[0-9a-f]{64}$'::text)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."gm_importacoes"'::regclass AND conname = 'gm_importacoes_tipo_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."gm_importacoes" ADD CONSTRAINT "gm_importacoes_tipo_check" CHECK (tipo = ANY (ARRAY['ROUTEVIEW'::text, 'STOPVIEW_PARADAS'::text, 'STOPVIEW_PEDIDOS'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."gm_importacoes"'::regclass AND conname = 'gm_importacoes_tipo_sha256_key') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."gm_importacoes" ADD CONSTRAINT "gm_importacoes_tipo_sha256_key" UNIQUE (tipo, sha256)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_eventos"'::regclass AND conname = 'nf_eventos_motivo_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_eventos" ADD CONSTRAINT "nf_eventos_motivo_check" CHECK (motivo IS NULL OR (motivo = ANY (ARRAY['APOIO'::text, 'REENTREGA'::text, 'REBALANCEAMENTO'::text, 'RECUSA'::text, 'DEVOLUCAO'::text, 'OUTRO_PADRONIZADO'::text])))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_eventos"'::regclass AND conname = 'nf_eventos_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_eventos" ADD CONSTRAINT "nf_eventos_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_eventos"'::regclass AND conname = 'nf_eventos_tipo_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_eventos" ADD CONSTRAINT "nf_eventos_tipo_check" CHECK (tipo = ANY (ARRAY['CARGA_GM'::text, 'SAIDA'::text, 'TRANSFERENCIA'::text, 'RETORNO'::text, 'CANHOTO'::text, 'DEVOLUCAO'::text, 'ORIGEM_VINCULADA'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_execucoes"'::regclass AND conname = 'nf_execucoes_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_execucoes" ADD CONSTRAINT "nf_execucoes_check" CHECK (encerrada_em IS NULL OR encerrada_em >= iniciada_em)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_execucoes"'::regclass AND conname = 'nf_execucoes_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_execucoes" ADD CONSTRAINT "nf_execucoes_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_execucoes"'::regclass AND conname = 'nf_execucoes_tipo_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_execucoes" ADD CONSTRAINT "nf_execucoes_tipo_check" CHECK (tipo = ANY (ARRAY['CARGA'::text, 'TRANSFERENCIA'::text, 'REENTREGA'::text, 'APOIO'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."notas_fiscais"'::regclass AND conname = 'notas_fiscais_chave_acesso_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."notas_fiscais" ADD CONSTRAINT "notas_fiscais_chave_acesso_check" CHECK (chave_acesso IS NULL OR chave_acesso ~ '^[0-9]{44}$'::text)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."notas_fiscais"'::regclass AND conname = 'notas_fiscais_chave_acesso_key') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."notas_fiscais" ADD CONSTRAINT "notas_fiscais_chave_acesso_key" UNIQUE (chave_acesso)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."notas_fiscais"'::regclass AND conname = 'notas_fiscais_emitente_documento_numero_serie_key') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."notas_fiscais" ADD CONSTRAINT "notas_fiscais_emitente_documento_numero_serie_key" UNIQUE (emitente_documento, numero, serie)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."notas_fiscais"'::regclass AND conname = 'notas_fiscais_numero_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."notas_fiscais" ADD CONSTRAINT "notas_fiscais_numero_check" CHECK (numero ~ '^[0-9]{9}$'::text)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."notas_fiscais"'::regclass AND conname = 'notas_fiscais_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."notas_fiscais" ADD CONSTRAINT "notas_fiscais_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."notas_fiscais"'::regclass AND conname = 'notas_fiscais_romaneio_origem_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."notas_fiscais" ADD CONSTRAINT "notas_fiscais_romaneio_origem_check" CHECK (romaneio_origem IS NULL OR romaneio_origem ~ '^[0-9]{12}$'::text)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."notas_fiscais"'::regclass AND conname = 'notas_fiscais_serie_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."notas_fiscais" ADD CONSTRAINT "notas_fiscais_serie_check" CHECK (serie ~ '^[0-9]{1,3}$'::text)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_area_correcao_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_area_correcao_check" CHECK (area_correcao = ANY (ARRAY['COMERCIAL'::text, 'ROTEIRIZACAO'::text, 'CADASTRO'::text, 'OPERACAO'::text, 'A_DEFINIR'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_impacto_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_impacto_check" CHECK (impacto = ANY (ARRAY['RISCO_REENTREGA'::text, 'REENTREGA'::text, 'ATRASO'::text, 'DESVIO_ROTA'::text, 'SEM_IMPACTO'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_saida_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_saida_check" CHECK (saida = ANY (ARRAY['PRIMEIRA'::text, 'SEGUNDA'::text, 'OUTRA'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_sequencia_executada_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_sequencia_executada_check" CHECK (sequencia_executada IS NULL OR sequencia_executada > 0)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_sequencia_planejada_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_sequencia_planejada_check" CHECK (sequencia_planejada IS NULL OR sequencia_planejada > 0)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_status_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_status_check" CHECK (status = ANY (ARRAY['ABERTA'::text, 'ENVIADA_GESTAO'::text, 'EM_TRATATIVA'::text, 'CORRIGIDA'::text, 'SEM_CORRECAO'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_tipo_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_tipo_check" CHECK (tipo = ANY (ARRAY['HORARIO_INCOMPATIVEL'::text, 'ENDERECO_INCORRETO'::text, 'SEQUENCIA_INCORRETA'::text, 'JANELA_ATENDIMENTO'::text, 'OUTRO'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."parada_notas"'::regclass AND conname = 'parada_notas_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."parada_notas" ADD CONSTRAINT "parada_notas_pkey" PRIMARY KEY (parada_id, nf_id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."paradas"'::regclass AND conname = 'paradas_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."paradas" ADD CONSTRAINT "paradas_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacao_notas"'::regclass AND conname = 'prestacao_notas_nf_id_key') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacao_notas" ADD CONSTRAINT "prestacao_notas_nf_id_key" UNIQUE (nf_id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacao_notas"'::regclass AND conname = 'prestacao_notas_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacao_notas" ADD CONSTRAINT "prestacao_notas_pkey" PRIMARY KEY (prestacao_id, nf_id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacoes"'::regclass AND conname = 'prestacoes_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacoes" ADD CONSTRAINT "prestacoes_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacoes"'::regclass AND conname = 'prestacoes_romaneio_oficial_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacoes" ADD CONSTRAINT "prestacoes_romaneio_oficial_check" CHECK (romaneio_oficial ~ '^[0-9]{12}$'::text)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacoes"'::regclass AND conname = 'prestacoes_romaneio_oficial_key') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacoes" ADD CONSTRAINT "prestacoes_romaneio_oficial_key" UNIQUE (romaneio_oficial)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacoes"'::regclass AND conname = 'prestacoes_status_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacoes" ADD CONSTRAINT "prestacoes_status_check" CHECK (status = ANY (ARRAY['ABERTA'::text, 'RETORNADA'::text, 'CONFERIDA'::text, 'ENVIADA_JTI'::text, 'CONFIRMADA_JTI'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_base_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_base_check" CHECK (char_length(btrim(base)) > 0)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_disponibilidade_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_disponibilidade_check" CHECK (disponibilidade = ANY (ARRAY['Disponível'::text, 'Em rota'::text, 'Indisponível'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_documento_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_documento_check" CHECK (char_length(btrim(documento)) >= 11 AND char_length(btrim(documento)) <= 20)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_nome_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_nome_check" CHECK (char_length(btrim(nome)) >= 3 AND char_length(btrim(nome)) <= 100)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_placa_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_placa_check" CHECK (char_length(btrim(placa)) >= 7 AND char_length(btrim(placa)) <= 8)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_status_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_status_check" CHECK (status = ANY (ARRAY['Ativo'::text, 'Pendente'::text, 'Inativo'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_veiculo_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_veiculo_check" CHECK (veiculo = ANY (ARRAY['Moto'::text, 'Fiorino'::text, 'VUC'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."profiles"'::regclass AND conname = 'profiles_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."profiles" ADD CONSTRAINT "profiles_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."rotas"'::regclass AND conname = 'rotas_data_rota_codigo_key') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."rotas" ADD CONSTRAINT "rotas_data_rota_codigo_key" UNIQUE (data_rota, codigo)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."rotas"'::regclass AND conname = 'rotas_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."rotas" ADD CONSTRAINT "rotas_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."rotas"'::regclass AND conname = 'rotas_romaneio_gm_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."rotas" ADD CONSTRAINT "rotas_romaneio_gm_check" CHECK (romaneio_gm IS NULL OR romaneio_gm ~ '^[0-9]{12}$'::text)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."rotas"'::regclass AND conname = 'rotas_saida_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."rotas" ADD CONSTRAINT "rotas_saida_check" CHECK (saida >= 1 AND saida <= 9)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."rotas"'::regclass AND conname = 'rotas_tipo_romaneio_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."rotas" ADD CONSTRAINT "rotas_tipo_romaneio_check" CHECK (tipo_romaneio = ANY (ARRAY['OFICIAL'::text, 'AUXILIAR'::text, 'A_CLASSIFICAR'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."sla_config"'::regclass AND conname = 'sla_config_id_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."sla_config" ADD CONSTRAINT "sla_config_id_check" CHECK (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."sla_config"'::regclass AND conname = 'sla_config_limite_dias_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."sla_config" ADD CONSTRAINT "sla_config_limite_dias_check" CHECK (limite_dias = 3)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."sla_config"'::regclass AND conname = 'sla_config_meta_horas_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."sla_config" ADD CONSTRAINT "sla_config_meta_horas_check" CHECK (meta_horas = 48)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."sla_config"'::regclass AND conname = 'sla_config_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."sla_config" ADD CONSTRAINT "sla_config_pkey" PRIMARY KEY (id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."sla_config"'::regclass AND conname = 'sla_config_tipo_contagem_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."sla_config" ADD CONSTRAINT "sla_config_tipo_contagem_check" CHECK (tipo_contagem = 'corridos'::text)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."user_roles"'::regclass AND conname = 'user_roles_pkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."user_roles" ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY (user_id, role)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."user_roles"'::regclass AND conname = 'user_roles_role_check') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."user_roles" ADD CONSTRAINT "user_roles_role_check" CHECK (role = ANY (ARRAY['admin'::text, 'operacional'::text]))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."gm_importacoes"'::regclass AND conname = 'gm_importacoes_criado_por_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."gm_importacoes" ADD CONSTRAINT "gm_importacoes_criado_por_fkey" FOREIGN KEY (criado_por) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_eventos"'::regclass AND conname = 'nf_eventos_nf_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_eventos" ADD CONSTRAINT "nf_eventos_nf_id_fkey" FOREIGN KEY (nf_id) REFERENCES notas_fiscais(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_eventos"'::regclass AND conname = 'nf_eventos_rota_destino_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_eventos" ADD CONSTRAINT "nf_eventos_rota_destino_id_fkey" FOREIGN KEY (rota_destino_id) REFERENCES rotas(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_eventos"'::regclass AND conname = 'nf_eventos_usuario_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_eventos" ADD CONSTRAINT "nf_eventos_usuario_id_fkey" FOREIGN KEY (usuario_id) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_execucoes"'::regclass AND conname = 'nf_execucoes_nf_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_execucoes" ADD CONSTRAINT "nf_execucoes_nf_id_fkey" FOREIGN KEY (nf_id) REFERENCES notas_fiscais(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_execucoes"'::regclass AND conname = 'nf_execucoes_registrada_por_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_execucoes" ADD CONSTRAINT "nf_execucoes_registrada_por_fkey" FOREIGN KEY (registrada_por) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."nf_execucoes"'::regclass AND conname = 'nf_execucoes_rota_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."nf_execucoes" ADD CONSTRAINT "nf_execucoes_rota_id_fkey" FOREIGN KEY (rota_id) REFERENCES rotas(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."notas_fiscais"'::regclass AND conname = 'notas_fiscais_origem_rota_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."notas_fiscais" ADD CONSTRAINT "notas_fiscais_origem_rota_id_fkey" FOREIGN KEY (origem_rota_id) REFERENCES rotas(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_atualizado_por_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_atualizado_por_fkey" FOREIGN KEY (atualizado_por) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."ocorrencias_roteirizacao"'::regclass AND conname = 'ocorrencias_roteirizacao_criado_por_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."ocorrencias_roteirizacao" ADD CONSTRAINT "ocorrencias_roteirizacao_criado_por_fkey" FOREIGN KEY (criado_por) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."parada_notas"'::regclass AND conname = 'parada_notas_importacao_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."parada_notas" ADD CONSTRAINT "parada_notas_importacao_id_fkey" FOREIGN KEY (importacao_id) REFERENCES gm_importacoes(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."parada_notas"'::regclass AND conname = 'parada_notas_nf_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."parada_notas" ADD CONSTRAINT "parada_notas_nf_id_fkey" FOREIGN KEY (nf_id) REFERENCES notas_fiscais(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."parada_notas"'::regclass AND conname = 'parada_notas_parada_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."parada_notas" ADD CONSTRAINT "parada_notas_parada_id_fkey" FOREIGN KEY (parada_id) REFERENCES paradas(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."paradas"'::regclass AND conname = 'paradas_importacao_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."paradas" ADD CONSTRAINT "paradas_importacao_id_fkey" FOREIGN KEY (importacao_id) REFERENCES gm_importacoes(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."paradas"'::regclass AND conname = 'paradas_rota_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."paradas" ADD CONSTRAINT "paradas_rota_id_fkey" FOREIGN KEY (rota_id) REFERENCES rotas(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacao_notas"'::regclass AND conname = 'prestacao_notas_canhoto_recebido_por_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacao_notas" ADD CONSTRAINT "prestacao_notas_canhoto_recebido_por_fkey" FOREIGN KEY (canhoto_recebido_por) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacao_notas"'::regclass AND conname = 'prestacao_notas_nf_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacao_notas" ADD CONSTRAINT "prestacao_notas_nf_id_fkey" FOREIGN KEY (nf_id) REFERENCES notas_fiscais(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacao_notas"'::regclass AND conname = 'prestacao_notas_prestacao_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacao_notas" ADD CONSTRAINT "prestacao_notas_prestacao_id_fkey" FOREIGN KEY (prestacao_id) REFERENCES prestacoes(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacoes"'::regclass AND conname = 'prestacoes_conferida_por_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacoes" ADD CONSTRAINT "prestacoes_conferida_por_fkey" FOREIGN KEY (conferida_por) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacoes"'::regclass AND conname = 'prestacoes_confirmada_por_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacoes" ADD CONSTRAINT "prestacoes_confirmada_por_fkey" FOREIGN KEY (confirmada_por) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacoes"'::regclass AND conname = 'prestacoes_enviada_por_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacoes" ADD CONSTRAINT "prestacoes_enviada_por_fkey" FOREIGN KEY (enviada_por) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestacoes"'::regclass AND conname = 'prestacoes_responsavel_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestacoes" ADD CONSTRAINT "prestacoes_responsavel_id_fkey" FOREIGN KEY (responsavel_id) REFERENCES auth.users(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_created_by_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."prestadores"'::regclass AND conname = 'prestadores_updated_by_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."prestadores" ADD CONSTRAINT "prestadores_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."profiles"'::regclass AND conname = 'profiles_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."profiles" ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."rotas"'::regclass AND conname = 'rotas_importacao_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."rotas" ADD CONSTRAINT "rotas_importacao_id_fkey" FOREIGN KEY (importacao_id) REFERENCES gm_importacoes(id)$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public."user_roles"'::regclass AND conname = 'user_roles_user_id_fkey') THEN
    EXECUTE $sigo_stmt$ALTER TABLE public."user_roles" ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE$sigo_stmt$;
  END IF;
END $sigo_block$;



-- 3. Independent indexes (PK and UNIQUE backing indexes are created by constraints).

CREATE UNIQUE INDEX IF NOT EXISTS nf_uma_execucao_aberta_idx ON public.nf_execucoes USING btree (nf_id) WHERE (encerrada_em IS NULL);

CREATE INDEX IF NOT EXISTS ocorrencias_rota_cliente_idx ON public.ocorrencias_roteirizacao USING btree (codigo_cliente, tipo);

CREATE INDEX IF NOT EXISTS ocorrencias_rota_dia_idx ON public.ocorrencias_roteirizacao USING btree (data_rota DESC, criado_em DESC);

CREATE INDEX IF NOT EXISTS prestadores_base_idx ON public.prestadores USING btree (base);

CREATE INDEX IF NOT EXISTS prestadores_status_idx ON public.prestadores USING btree (status);



-- 4. Functions as defined in the live catalog.

CREATE OR REPLACE FUNCTION public.sigo_avancar_prestacao(p_prestacao_id uuid, p_etapa text)
 RETURNS TABLE(id uuid, status text, registrado_em timestamp with time zone, registrado_por uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_usuario uuid := (select auth.uid());
begin
 if v_usuario is null or not (select public.sigo_is_active()) then
  raise exception 'Usuário sem acesso ativo ao SIGO';
 end if;
 if p_etapa not in ('RETORNADA','CONFERIDA') then
  raise exception 'Etapa não permitida';
 end if;
 if p_etapa='RETORNADA' then
  return query
  update public.prestacoes p
    set status='RETORNADA', retornada_em=clock_timestamp(), responsavel_id=v_usuario
  where p.id=p_prestacao_id and p.status='ABERTA' and p.retornada_em is null
  returning p.id,p.status,p.retornada_em,p.responsavel_id;
 else
  return query
  update public.prestacoes p
    set status='CONFERIDA', conferida_em=clock_timestamp(), conferida_por=v_usuario,
        responsavel_id=coalesce(p.responsavel_id,v_usuario)
  where p.id=p_prestacao_id and p.status='RETORNADA' and p.conferida_em is null
  returning p.id,p.status,p.conferida_em,p.conferida_por;
 end if;
 if not found then raise exception 'Prestação não encontrada ou etapa anterior não concluída'; end if;
end; $function$;

CREATE OR REPLACE FUNCTION public.sigo_criar_prestacao(p_romaneio text, p_d0 date)
 RETURNS TABLE(id uuid, romaneio_oficial text, d0 date, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := (select auth.uid());
begin
 if v_user is null or not (select public.sigo_is_active()) then
  raise exception 'Usuário sem acesso ativo ao SIGO';
 end if;
 if p_romaneio is null or p_romaneio !~ '^[0-9]{12}$' or p_romaneio ~ '^(.)\1{11}$' or p_romaneio like '6000000000%' then
  raise exception 'Informe um romaneio oficial válido com 12 dígitos (não auxiliar)';
 end if;
 if p_d0 is null or p_d0 > (now() at time zone 'America/Sao_Paulo')::date then
  raise exception 'A data D0 não pode estar no futuro';
 end if;
 return query
 insert into public.prestacoes as p (romaneio_oficial,d0,status,responsavel_id)
 values (p_romaneio,p_d0,'ABERTA',v_user)
 returning p.id,p.romaneio_oficial,p.d0,p.status;
exception when unique_violation then
 raise exception 'Esse romaneio já está cadastrado no SIGO';
end; $function$;

CREATE OR REPLACE FUNCTION public.sigo_enviar_prestacao_jti(p_prestacao_id uuid)
 RETURNS TABLE(id uuid, romaneio_oficial text, enviada_em timestamp with time zone, enviada_por uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_usuario uuid := (select auth.uid());
begin
  if v_usuario is null or not (select public.sigo_is_active()) then
    raise exception 'Acesso não autorizado ao SIGO';
  end if;
  return query
  update public.prestacoes p
  set status = 'ENVIADA_JTI',
      enviada_em = clock_timestamp(),
      enviada_por = v_usuario
  where p.id = p_prestacao_id
    and p.status = 'CONFERIDA'
    and p.enviada_em is null
  returning p.id, p.romaneio_oficial, p.enviada_em, p.enviada_por;
  if not found then
    raise exception 'Prestação não encontrada ou não está conferida e disponível para envio';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sigo_guard_eventos()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin raise exception 'Eventos são append-only'; end; $function$;

CREATE OR REPLACE FUNCTION public.sigo_guard_nf_origem()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if new.romaneio_origem is distinct from old.romaneio_origem
 or new.origem_rota_id is distinct from old.origem_rota_id
 or new.numero is distinct from old.numero
 or new.serie is distinct from old.serie then
  raise exception 'Origem e identidade fiscal são imutáveis; correções exigem procedimento auditado';
 end if;
 return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.sigo_guard_prestador_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.id is distinct from old.id
    or new.created_at is distinct from old.created_at
    or new.created_by is distinct from old.created_by then
    raise exception 'Campos de criação e identidade não podem ser alterados';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sigo_handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into public.profiles(id, nome)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nome', ''));
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sigo_has_role(requested_role text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.user_roles ur
    join public.profiles p on p.id = ur.user_id
    where ur.user_id = (select auth.uid())
      and ur.role = requested_role
      and p.ativo = true
  );
$function$;

CREATE OR REPLACE FUNCTION public.sigo_importar_prestacoes_gm(p_itens jsonb)
 RETURNS TABLE(inseridos integer, existentes integer, total integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_item jsonb; v_rom text; v_d0 date; v_count int := 0;
 v_novos int := 0; v_anteriores int := 0; v_existente date;
begin
 if (select auth.uid()) is null or not (select public.sigo_is_active()) then
   raise exception 'Acesso não autorizado ao SIGO';
 end if;
 if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens)=0 or jsonb_array_length(p_itens)>200 then
   raise exception 'Lote inválido (1 a 200 romaneios)';
 end if;
 if (select count(*) from jsonb_array_elements(p_itens) x where (x->>'romaneio') is null or (x->>'d0') is null or jsonb_typeof(x) <> 'object') > 0 then
   raise exception 'Dados obrigatórios ausentes';
 end if;
 if (select count(*) from jsonb_array_elements(p_itens)) <> (select count(distinct x->>'romaneio') from jsonb_array_elements(p_itens) x) then
   raise exception 'Romaneio repetido dentro do mesmo lote';
 end if;
 for v_item in select * from jsonb_array_elements(p_itens) loop
   v_rom := v_item->>'romaneio';
   if v_rom !~ '^[0-9]{12}$' or v_rom ~ '^(.)\1{11}$' or v_rom like '6000000000%' then
     raise exception 'Romaneio não oficial ou inválido';
   end if;
   if (v_item->>'d0') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'D0 inválido'; end if;
   v_d0 := (v_item->>'d0')::date;
   if v_d0 > (now() at time zone 'America/Sao_Paulo')::date then
     raise exception 'A rota é futura. Aguarde D0 para abrir a prestação';
   end if;
   select p.d0 into v_existente from public.prestacoes p where p.romaneio_oficial=v_rom;
   if found then
      if v_existente <> v_d0 then raise exception 'Romaneio já existe com D0 diferente'; end if;
      v_anteriores := v_anteriores + 1;
   else
      insert into public.prestacoes(romaneio_oficial,d0,status,responsavel_id)
      values(v_rom,v_d0,'ABERTA',(select auth.uid()))
      on conflict(romaneio_oficial) do nothing;
      if found then v_novos:=v_novos+1; else v_anteriores:=v_anteriores+1; end if;
   end if;
   v_count:=v_count+1;
 end loop;
 return query select v_novos,v_anteriores,v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sigo_is_active()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
    where p.id = (select auth.uid()) and p.ativo = true
      and ur.role in ('admin', 'operacional')
  );
$function$;

CREATE OR REPLACE FUNCTION public.sigo_prestacao_timestamps()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if tg_op='UPDATE' then
  if new.responsavel_id is distinct from old.responsavel_id or new.d0 is distinct from old.d0 or new.romaneio_oficial is distinct from old.romaneio_oficial then
   raise exception 'Identidade da prestação e responsável não podem ser alterados';
  end if;
  if new.status is distinct from old.status then
   if (old.status,new.status) not in (('ABERTA','RETORNADA'),('RETORNADA','CONFERIDA'),('CONFERIDA','ENVIADA_JTI'),('ENVIADA_JTI','CONFIRMADA_JTI')) then
    raise exception 'Transição de prestação inválida';
   end if;
   if new.status='RETORNADA' then new.retornada_em:=now(); end if;
   if new.status='CONFERIDA' then new.conferida_em:=now(); new.conferida_por:=auth.uid(); end if;
   if new.status='ENVIADA_JTI' then new.enviada_em:=now(); new.enviada_por:=auth.uid(); end if;
   if new.status='CONFIRMADA_JTI' then new.confirmada_em:=now(); new.confirmada_por:=auth.uid(); end if;
  end if;
  new.pendencia_fora_sla:=old.pendencia_fora_sla or (old.conferida_em is not null and now() >= old.conferida_em + interval '4 days' and old.status not in ('ENVIADA_JTI','CONFIRMADA_JTI'));
 end if;
 return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.sigo_registrar_ocorrencia(p_dados jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
 if v_uid is null or not (select public.sigo_is_active()) then raise exception 'Acesso não autorizado'; end if;
 if jsonb_typeof(p_dados) is distinct from 'object' then raise exception 'Dados inválidos'; end if;
 if length(trim(coalesce(p_dados->>'codigo_cliente','')))=0 or length(trim(coalesce(p_dados->>'cliente','')))=0 or
    length(trim(coalesce(p_dados->>'nf','')))=0 or length(trim(coalesce(p_dados->>'codigo_rota','')))=0 or
    length(trim(coalesce(p_dados->>'detalhe','')))<10 then raise exception 'Preencha cliente, código, NF, rota e descrição com pelo menos 10 caracteres'; end if;
 if (p_dados->>'data_rota')::date > (now() at time zone 'America/Sao_Paulo')::date then raise exception 'Data futura não permitida'; end if;
 insert into public.ocorrencias_roteirizacao(
  criado_por,data_rota,codigo_cliente,cliente,nf,codigo_rota,romaneio,condutor,vendedor,tipo,saida,
  sequencia_planejada,sequencia_executada,horario_restricao,detalhe,impacto,acao_imediata,area_correcao,responsavel_tratativa
 ) values(
  v_uid,(p_dados->>'data_rota')::date,trim(p_dados->>'codigo_cliente'),trim(p_dados->>'cliente'),
  trim(p_dados->>'nf'),trim(p_dados->>'codigo_rota'),nullif(trim(p_dados->>'romaneio'),''),
  nullif(trim(p_dados->>'condutor'),''),nullif(trim(p_dados->>'vendedor'),''),
  p_dados->>'tipo',p_dados->>'saida',
  nullif(p_dados->>'sequencia_planejada','')::integer,
  nullif(p_dados->>'sequencia_executada','')::integer,
  nullif(trim(p_dados->>'horario_restricao'),''),
  trim(p_dados->>'detalhe'),p_dados->>'impacto',
  nullif(trim(p_dados->>'acao_imediata'),''),p_dados->>'area_correcao',
  nullif(trim(p_dados->>'responsavel_tratativa'),'')
 ) returning id into v_id;
 return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sigo_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sigo_tratar_ocorrencia(p_id uuid, p_status text, p_retorno text, p_responsavel text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := (select auth.uid());
begin
 if v_uid is null or not (select public.sigo_is_active()) then raise exception 'Acesso não autorizado'; end if;
 if p_status not in ('ABERTA','ENVIADA_GESTAO','EM_TRATATIVA','CORRIGIDA','SEM_CORRECAO') then raise exception 'Status inválido'; end if;
 if p_status in ('CORRIGIDA','SEM_CORRECAO') and length(trim(coalesce(p_retorno,'')))<8 then raise exception 'Informe o retorno da tratativa'; end if;
 update public.ocorrencias_roteirizacao
 set status=p_status,retorno_gestao=nullif(trim(p_retorno),''),
     responsavel_tratativa=nullif(trim(p_responsavel),''),
     atualizado_em=now(),atualizado_por=v_uid,
     resolvido_em=case when p_status in ('CORRIGIDA','SEM_CORRECAO') then now() else null end
 where id=p_id;
 return found;
end; $function$;



-- 5. Views: dependents follow v_prestacoes_sla.

CREATE OR REPLACE VIEW public."v_prestacoes_sla" WITH (security_invoker = true) AS SELECT id,
    romaneio_oficial,
    d0,
    status,
    responsavel_id,
    conferida_em,
    enviada_em,
    pendencia_fora_sla,
    d0 + (( SELECT sla_config.limite_dias
           FROM sla_config
          WHERE sla_config.id = true)) AS vence_em,
        CASE
            WHEN enviada_em IS NOT NULL AND (enviada_em AT TIME ZONE 'America/Sao_Paulo'::text)::date > (d0 + 3) THEN 'VENCIDO'::text
            WHEN enviada_em IS NOT NULL THEN 'ENVIADO'::text
            WHEN CURRENT_DATE > (d0 + 3) THEN 'VENCIDO'::text
            WHEN CURRENT_DATE = (d0 + 3) THEN 'URGENTE'::text
            WHEN CURRENT_DATE = (d0 + 2) THEN 'ATENCAO'::text
            ELSE 'NO_PRAZO'::text
        END AS faixa_envio,
        CASE
            WHEN conferida_em IS NULL THEN 'NAO_INICIADA'::text
            WHEN pendencia_fora_sla OR enviada_em IS NULL AND CURRENT_DATE >= ((conferida_em AT TIME ZONE 'America/Sao_Paulo'::text)::date + 4) THEN 'CRITICO'::text
            WHEN enviada_em IS NOT NULL THEN 'RESOLVIDA'::text
            WHEN CURRENT_DATE >= ((conferida_em AT TIME ZONE 'America/Sao_Paulo'::text)::date + 3) THEN 'URGENTE'::text
            WHEN CURRENT_DATE >= ((conferida_em AT TIME ZONE 'America/Sao_Paulo'::text)::date + 2) THEN 'ATENCAO'::text
            ELSE 'NO_PRAZO'::text
        END AS faixa_pendencia
   FROM prestacoes p;

CREATE OR REPLACE VIEW public."v_alerta_fim_semana" WITH (security_invoker = true) AS SELECT id,
    romaneio_oficial,
    d0,
    status,
    responsavel_id,
    conferida_em,
    enviada_em,
    pendencia_fora_sla,
    vence_em,
    faixa_envio,
    faixa_pendencia
   FROM v_prestacoes_sla
  WHERE (status <> ALL (ARRAY['ENVIADA_JTI'::text, 'CONFIRMADA_JTI'::text])) AND (EXTRACT(isodow FROM (now() AT TIME ZONE 'America/Sao_Paulo'::text)) = ANY (ARRAY[4::numeric, 5::numeric])) AND (EXTRACT(isodow FROM vence_em) = ANY (ARRAY[6::numeric, 7::numeric])) AND vence_em >= (now() AT TIME ZONE 'America/Sao_Paulo'::text)::date AND vence_em <= ((now() AT TIME ZONE 'America/Sao_Paulo'::text)::date + 3);



-- 6. Existing triggers defined ON public tables.

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public."nf_eventos"'::regclass AND tgname = 'nf_eventos_append_only' AND NOT tgisinternal) THEN
    EXECUTE $sigo_stmt$CREATE TRIGGER nf_eventos_append_only BEFORE DELETE OR UPDATE ON public.nf_eventos FOR EACH ROW EXECUTE FUNCTION sigo_guard_eventos()$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public."notas_fiscais"'::regclass AND tgname = 'nf_origem_imutavel' AND NOT tgisinternal) THEN
    EXECUTE $sigo_stmt$CREATE TRIGGER nf_origem_imutavel BEFORE UPDATE ON public.notas_fiscais FOR EACH ROW EXECUTE FUNCTION sigo_guard_nf_origem()$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public."prestacoes"'::regclass AND tgname = 'prestacao_auditoria' AND NOT tgisinternal) THEN
    EXECUTE $sigo_stmt$CREATE TRIGGER prestacao_auditoria BEFORE UPDATE ON public.prestacoes FOR EACH ROW EXECUTE FUNCTION sigo_prestacao_timestamps()$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public."prestadores"'::regclass AND tgname = 'prestadores_guard_update' AND NOT tgisinternal) THEN
    EXECUTE $sigo_stmt$CREATE TRIGGER prestadores_guard_update BEFORE UPDATE ON public.prestadores FOR EACH ROW EXECUTE FUNCTION sigo_guard_prestador_update()$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public."prestadores"'::regclass AND tgname = 'prestadores_updated_at' AND NOT tgisinternal) THEN
    EXECUTE $sigo_stmt$CREATE TRIGGER prestadores_updated_at BEFORE UPDATE ON public.prestadores FOR EACH ROW EXECUTE FUNCTION sigo_set_updated_at()$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public."profiles"'::regclass AND tgname = 'profiles_updated_at' AND NOT tgisinternal) THEN
    EXECUTE $sigo_stmt$CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION sigo_set_updated_at()$sigo_stmt$;
  END IF;
END $sigo_block$;



-- 7. Row-level security flags.

ALTER TABLE public."gm_importacoes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."nf_eventos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."nf_execucoes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."notas_fiscais" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."ocorrencias_roteirizacao" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."parada_notas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."paradas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."prestacao_notas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."prestacoes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."prestadores" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."profiles" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."rotas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."sla_config" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."user_roles" ENABLE ROW LEVEL SECURITY;



-- 8. Policies (CREATE POLICY has no IF NOT EXISTS).

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'gm_importacoes' AND policyname = 'sigo_import_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_import_insert" ON public."gm_importacoes" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((( SELECT sigo_is_active() AS sigo_is_active) AND (criado_por = auth.uid())))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'gm_importacoes' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."gm_importacoes" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'nf_eventos' AND policyname = 'sigo_event_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_event_insert" ON public."nf_eventos" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((( SELECT sigo_is_active() AS sigo_is_active) AND (usuario_id = auth.uid())))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'nf_eventos' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."nf_eventos" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'nf_execucoes' AND policyname = 'sigo_exec_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_exec_insert" ON public."nf_execucoes" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((( SELECT sigo_is_active() AS sigo_is_active) AND (registrada_por = auth.uid())))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'nf_execucoes' AND policyname = 'sigo_exec_update') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_exec_update" ON public."nf_execucoes" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active)) WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'nf_execucoes' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."nf_execucoes" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'notas_fiscais' AND policyname = 'sigo_nf_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_nf_insert" ON public."notas_fiscais" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'notas_fiscais' AND policyname = 'sigo_nf_update') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_nf_update" ON public."notas_fiscais" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active)) WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'notas_fiscais' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."notas_fiscais" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ocorrencias_roteirizacao' AND policyname = 'sigo_ocorrencia_select') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_ocorrencia_select" ON public."ocorrencias_roteirizacao" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'parada_notas' AND policyname = 'sigo_parada_nf_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_parada_nf_insert" ON public."parada_notas" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'parada_notas' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."parada_notas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'paradas' AND policyname = 'sigo_paradas_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_paradas_insert" ON public."paradas" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'paradas' AND policyname = 'sigo_paradas_update') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_paradas_update" ON public."paradas" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active)) WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'paradas' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."paradas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestacao_notas' AND policyname = 'sigo_prest_nf_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_prest_nf_insert" ON public."prestacao_notas" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestacao_notas' AND policyname = 'sigo_prest_nf_update') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_prest_nf_update" ON public."prestacao_notas" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active)) WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestacao_notas' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."prestacao_notas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestacoes' AND policyname = 'sigo_prest_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_prest_insert" ON public."prestacoes" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((( SELECT sigo_is_active() AS sigo_is_active) AND (responsavel_id = auth.uid())))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestacoes' AND policyname = 'sigo_prest_update') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_prest_update" ON public."prestacoes" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active)) WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestacoes' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."prestacoes" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestadores' AND policyname = 'prestadores_delete') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "prestadores_delete" ON public."prestadores" AS PERMISSIVE FOR DELETE TO "authenticated" USING (( SELECT sigo_has_role('admin'::text) AS sigo_has_role))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestadores' AND policyname = 'prestadores_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "prestadores_insert" ON public."prestadores" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((( SELECT sigo_is_active() AS sigo_is_active) AND (created_by = ( SELECT auth.uid() AS uid)) AND (updated_by = ( SELECT auth.uid() AS uid))))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestadores' AND policyname = 'prestadores_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "prestadores_read" ON public."prestadores" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prestadores' AND policyname = 'prestadores_update') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "prestadores_update" ON public."prestadores" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active)) WITH CHECK ((( SELECT sigo_is_active() AS sigo_is_active) AND (updated_by = ( SELECT auth.uid() AS uid))))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_admin_update') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "profiles_admin_update" ON public."profiles" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT sigo_has_role('admin'::text) AS sigo_has_role)) WITH CHECK (( SELECT sigo_has_role('admin'::text) AS sigo_has_role))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "profiles_read" ON public."profiles" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((id = ( SELECT auth.uid() AS uid)) OR ( SELECT sigo_has_role('admin'::text) AS sigo_has_role)))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'rotas' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."rotas" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'rotas' AND policyname = 'sigo_rotas_insert') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_rotas_insert" ON public."rotas" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'rotas' AND policyname = 'sigo_rotas_update') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_rotas_update" ON public."rotas" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active)) WITH CHECK (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'sla_config' AND policyname = 'sigo_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "sigo_read" ON public."sla_config" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT sigo_is_active() AS sigo_is_active))$sigo_stmt$;
  END IF;
END $sigo_block$;

DO $sigo_block$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_roles' AND policyname = 'roles_read') THEN
    EXECUTE $sigo_stmt$CREATE POLICY "roles_read" ON public."user_roles" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT sigo_has_role('admin'::text) AS sigo_has_role)))$sigo_stmt$;
  END IF;
END $sigo_block$;



-- 9. Grants: catalog ACL for app roles. MAINTAIN introduced in PostgreSQL 17.

REVOKE ALL ON SCHEMA public FROM PUBLIC, anon, authenticated, service_role;

GRANT USAGE ON SCHEMA public TO PUBLIC;

GRANT USAGE ON SCHEMA public TO "anon";

GRANT USAGE ON SCHEMA public TO "authenticated";

GRANT USAGE ON SCHEMA public TO "service_role";

REVOKE ALL ON TABLE public."gm_importacoes" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."gm_importacoes" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."gm_importacoes" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."gm_importacoes" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."gm_importacoes" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."gm_importacoes" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."gm_importacoes" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."nf_eventos" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."nf_eventos" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."nf_eventos" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."nf_eventos" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."nf_eventos" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."nf_eventos" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."nf_eventos" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."nf_execucoes" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."nf_execucoes" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."nf_execucoes" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."nf_execucoes" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."nf_execucoes" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."nf_execucoes" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."nf_execucoes" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."notas_fiscais" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."notas_fiscais" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."notas_fiscais" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."notas_fiscais" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."notas_fiscais" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."notas_fiscais" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."notas_fiscais" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."ocorrencias_roteirizacao" FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public."ocorrencias_roteirizacao" TO "authenticated";

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."ocorrencias_roteirizacao" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."ocorrencias_roteirizacao" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."parada_notas" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."parada_notas" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."parada_notas" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."parada_notas" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."parada_notas" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."parada_notas" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."parada_notas" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."paradas" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."paradas" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."paradas" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."paradas" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."paradas" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."paradas" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."paradas" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."prestacao_notas" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."prestacao_notas" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."prestacao_notas" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."prestacao_notas" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."prestacao_notas" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."prestacao_notas" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."prestacao_notas" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."prestacoes" FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public."prestacoes" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."prestacoes" TO "anon"';
  END IF;
END $sigo_block$;

GRANT SELECT ON TABLE public."prestacoes" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."prestacoes" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."prestacoes" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."prestacoes" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."prestadores" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."prestadores" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."prestadores" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."prestadores" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."prestadores" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."profiles" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."profiles" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."profiles" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."profiles" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."profiles" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."rotas" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."rotas" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."rotas" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."rotas" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."rotas" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."rotas" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."rotas" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."sla_config" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."sla_config" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."sla_config" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."sla_config" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."sla_config" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."sla_config" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."sla_config" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."user_roles" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."user_roles" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."user_roles" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."user_roles" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."user_roles" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."v_alerta_fim_semana" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."v_alerta_fim_semana" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."v_alerta_fim_semana" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."v_alerta_fim_semana" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."v_alerta_fim_semana" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."v_alerta_fim_semana" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."v_alerta_fim_semana" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON TABLE public."v_prestacoes_sla" FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."v_prestacoes_sla" TO "anon";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."v_prestacoes_sla" TO "anon"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."v_prestacoes_sla" TO "authenticated";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."v_prestacoes_sla" TO "authenticated"';
  END IF;
END $sigo_block$;

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."v_prestacoes_sla" TO "service_role";

DO $sigo_block$ BEGIN
  IF current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'GRANT MAINTAIN ON TABLE public."v_prestacoes_sla" TO "service_role"';
  END IF;
END $sigo_block$;

REVOKE ALL ON SEQUENCE public."nf_eventos_id_seq" FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, UPDATE, USAGE ON SEQUENCE public."nf_eventos_id_seq" TO "anon";

GRANT SELECT, UPDATE, USAGE ON SEQUENCE public."nf_eventos_id_seq" TO "authenticated";

GRANT SELECT, UPDATE, USAGE ON SEQUENCE public."nf_eventos_id_seq" TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_avancar_prestacao(uuid,text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_avancar_prestacao(uuid,text) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.sigo_avancar_prestacao(uuid,text) TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_criar_prestacao(text,date) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_criar_prestacao(text,date) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.sigo_criar_prestacao(text,date) TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_enviar_prestacao_jti(uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_enviar_prestacao_jti(uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.sigo_enviar_prestacao_jti(uuid) TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_guard_eventos() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_guard_eventos() TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_guard_nf_origem() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_guard_nf_origem() TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_guard_prestador_update() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_guard_prestador_update() TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_handle_new_user() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_handle_new_user() TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_has_role(text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_has_role(text) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.sigo_has_role(text) TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_importar_prestacoes_gm(jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_importar_prestacoes_gm(jsonb) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.sigo_importar_prestacoes_gm(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_is_active() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_is_active() TO "authenticated";

GRANT EXECUTE ON FUNCTION public.sigo_is_active() TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_prestacao_timestamps() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_prestacao_timestamps() TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_registrar_ocorrencia(jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_registrar_ocorrencia(jsonb) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.sigo_registrar_ocorrencia(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_set_updated_at() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_set_updated_at() TO "service_role";

REVOKE ALL ON FUNCTION public.sigo_tratar_ocorrencia(uuid,text,text,text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.sigo_tratar_ocorrencia(uuid,text,text,text) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.sigo_tratar_ocorrencia(uuid,text,text,text) TO "service_role";



RESET search_path;

