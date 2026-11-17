-- SIGO: deploy transacional de producao, preparado em 17/11/2026.
-- NAO EXECUTAR sem backup recente, conferencia de prestacoes e aprovacao.
-- Base: snapshot 20261116000200 JA EXISTENTE no Supabase hospedado; NUNCA inclui baseline.
-- Conteudo das 4 migrations reproduzido integralmente e sem alteracoes, em ordem.
-- DDL/DML todo numa unica transacao: qualquer falha reverte todos os comandos.
BEGIN;

DO $sigo_deploy_snapshot$
DECLARE
  v_prestacoes_antes bigint;
BEGIN
  SELECT count(*) INTO v_prestacoes_antes FROM public.prestacoes;
  PERFORM set_config('sigo.deploy_prestacoes_antes',v_prestacoes_antes::text,true);
END;
$sigo_deploy_snapshot$;

-- ==== BEGIN MIGRATION 20261116000300_sigo_sla_hardening_v2.sql (VERBATIM) ====
-- SIGO SLA hardening v2: reaplica incrementalmente a migration legacy 0500
-- sobre o snapshot public de 20261116000200, sem alterar registros existentes.
-- O único DML é o seed idempotente da configuração SLA, quando ausente.
-- NÃO aplicar no banco hospedado neste PR; validar apenas no CI isolado.

insert into public.sla_config (id) values (true) on conflict (id) do nothing;

-- P0: responsável original permanece imutável; executores são auditados nas respectivas etapas.
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
    set status='RETORNADA', retornada_em=clock_timestamp()
  where p.id=p_prestacao_id and p.status='ABERTA' and p.retornada_em is null
  returning p.id,p.status,p.retornada_em,p.responsavel_id;
 else
  return query
  update public.prestacoes p
    set status='CONFERIDA', conferida_em=clock_timestamp(), conferida_por=v_usuario
  where p.id=p_prestacao_id and p.status='RETORNADA' and p.conferida_em is null
  returning p.id,p.status,p.conferida_em,p.conferida_por;
 end if;
 if not found then raise exception 'Prestação não encontrada ou etapa anterior não concluída'; end if;
end; $function$;

-- Hardening: timestamp ownership and immutable SLA breach history (corpo original 0500).
create or replace function public.sigo_prestacao_timestamps() returns trigger language plpgsql set search_path='' as $$
declare dias_pendencia integer;
begin
 if tg_op='INSERT' then
  new.responsavel_id := auth.uid();
  if new.responsavel_id is null then raise exception 'Sessão obrigatória'; end if;
  new.status := 'ABERTA';
  new.retornada_em := null; new.conferida_em := null; new.conferida_por := null;
  new.enviada_em := null; new.enviada_por := null; new.confirmada_em := null; new.confirmada_por := null;
  new.pendencia_fora_sla := false;
  return new;
 end if;
 if new.responsavel_id is distinct from old.responsavel_id or new.d0 is distinct from old.d0 or new.romaneio_oficial is distinct from old.romaneio_oficial then
  raise exception 'Identidade e responsável são imutáveis';
 end if;
 new.retornada_em := old.retornada_em;
 new.conferida_em := old.conferida_em;
 new.conferida_por := old.conferida_por;
 new.enviada_em := old.enviada_em;
 new.enviada_por := old.enviada_por;
 new.confirmada_em := old.confirmada_em;
 new.confirmada_por := old.confirmada_por;
 if new.status is distinct from old.status then
  if (old.status,new.status) not in (('ABERTA','RETORNADA'),('RETORNADA','CONFERIDA'),('CONFERIDA','ENVIADA_JTI'),('ENVIADA_JTI','CONFIRMADA_JTI')) then raise exception 'Transição inválida'; end if;
  if new.status='RETORNADA' then new.retornada_em:=now(); end if;
  if new.status='CONFERIDA' then new.conferida_em:=now(); new.conferida_por:=auth.uid(); end if;
  if new.status='ENVIADA_JTI' then new.enviada_em:=now(); new.enviada_por:=auth.uid(); end if;
  if new.status='CONFIRMADA_JTI' then new.confirmada_em:=now(); new.confirmada_por:=auth.uid(); end if;
 end if;
 dias_pendencia := case when old.conferida_em is null then 0 else
 ((coalesce(new.enviada_em,now()) at time zone 'America/Sao_Paulo')::date -
 (old.conferida_em at time zone 'America/Sao_Paulo')::date) end;
 new.pendencia_fora_sla := old.pendencia_fora_sla or (old.conferida_em is not null and dias_pendencia >= 4);
 return new;
end; $$;
drop trigger if exists prestacao_auditoria on public.prestacoes;
create trigger prestacao_auditoria before insert or update on public.prestacoes for each row execute function public.sigo_prestacao_timestamps();
create or replace view public.v_prestacoes_sla with (security_invoker=true) as
select p.id,p.romaneio_oficial,p.d0,p.status,p.responsavel_id,p.conferida_em,p.enviada_em,p.pendencia_fora_sla,
 p.d0 + 3 as vence_em,
 case when p.enviada_em is not null and (p.enviada_em at time zone 'America/Sao_Paulo')::date > p.d0+3 then 'VENCIDO'
 when p.enviada_em is not null then 'ENVIADO'
 when (now() at time zone 'America/Sao_Paulo')::date>p.d0+3 then 'VENCIDO'
 when (now() at time zone 'America/Sao_Paulo')::date=p.d0+3 then 'URGENTE'
 when (now() at time zone 'America/Sao_Paulo')::date=p.d0+2 then 'ATENCAO'
 else 'NO_PRAZO' end as faixa_envio,
 case when p.conferida_em is null then 'NAO_INICIADA'
 when p.pendencia_fora_sla or (coalesce(p.enviada_em,now()) at time zone 'America/Sao_Paulo')::date >= (p.conferida_em at time zone 'America/Sao_Paulo')::date+4 then 'CRITICO'
 when p.enviada_em is not null then 'RESOLVIDA'
 when (now() at time zone 'America/Sao_Paulo')::date >= (p.conferida_em at time zone 'America/Sao_Paulo')::date+3 then 'URGENTE'
 when (now() at time zone 'America/Sao_Paulo')::date >= (p.conferida_em at time zone 'America/Sao_Paulo')::date+2 then 'ATENCAO'
 else 'NO_PRAZO' end as faixa_pendencia
from public.prestacoes p;
create or replace function public.sigo_canhoto_auditoria() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then
  new.canhoto_recebido_em := null; new.canhoto_recebido_por := null;
 elsif new.canhoto_recebido_em is distinct from old.canhoto_recebido_em or new.canhoto_recebido_por is distinct from old.canhoto_recebido_por then
  if old.canhoto_recebido_em is not null then raise exception 'Canhoto já recebido'; end if;
  if new.canhoto_recebido_em is null then raise exception 'Confirmação de recebimento obrigatória'; end if;
  new.canhoto_recebido_em := now(); new.canhoto_recebido_por := auth.uid();
 end if;
 return new;
end; $$;
drop trigger if exists prestacao_canhoto_auditoria on public.prestacao_notas;
create trigger prestacao_canhoto_auditoria before insert or update on public.prestacao_notas for each row execute function public.sigo_canhoto_auditoria();
revoke all on function public.sigo_canhoto_auditoria() from public,anon,authenticated;
-- ==== END MIGRATION 20261116000300_sigo_sla_hardening_v2.sql ====

-- ==== BEGIN MIGRATION 20261116000400_sigo_importacao_nf.sql (VERBATIM) ====
-- SIGO Etapa 3: importacao StopView atomica, sem alterar a origem fiscal existente.
-- Executar somente em banco descartavel no CI ate reconciliar migrations do Supabase hospedado.

-- Série padrão para NF inédita sem série explícita.
ALTER TABLE public.sla_config
  ADD COLUMN IF NOT EXISTS serie_padrao text NOT NULL DEFAULT '7';
DO $sigo_serie_padrao$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sla_config'::regclass
      AND conname = 'sla_config_serie_padrao_check'
  ) THEN
    ALTER TABLE public.sla_config ADD CONSTRAINT sla_config_serie_padrao_check
      CHECK (serie_padrao ~ '^[0-9]{1,3}$');
  END IF;
END;
$sigo_serie_padrao$;
INSERT INTO public.sla_config(id) VALUES (true)
  ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.pendencias_importacao (
  importacao_id uuid NOT NULL REFERENCES public.gm_importacoes(id),
  linha integer NOT NULL CHECK (linha > 0),
  codigo_rota text NOT NULL,
  parada_id bigint,
  valor_bruto text,
  motivo text NOT NULL CHECK (motivo IN ('SEM_NF', 'TRANSFERENCIA', 'SERIE_AMBIGUA', 'SERIE_ASSUMIDA', 'NF_INVALIDA')),
  status text NOT NULL DEFAULT 'PENDENTE' CHECK (status IN ('PENDENTE', 'TRATADA')),
  tratada_por uuid REFERENCES auth.users(id),
  tratada_em timestamptz,
  PRIMARY KEY (importacao_id, linha),
  CONSTRAINT pendencias_tratamento_consistente CHECK (
    (status = 'PENDENTE' AND tratada_por IS NULL AND tratada_em IS NULL) OR
    (status = 'TRATADA' AND tratada_por IS NOT NULL AND tratada_em IS NOT NULL)
  )
);

ALTER TABLE public.pendencias_importacao ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pendencias_importacao FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.pendencias_importacao TO authenticated;
DROP POLICY IF EXISTS sigo_pendencias_importacao_read ON public.pendencias_importacao;
CREATE POLICY sigo_pendencias_importacao_read ON public.pendencias_importacao
  FOR SELECT TO authenticated USING ((SELECT public.sigo_is_active()));
-- Sem politica/grant de INSERT direto: somente SECURITY DEFINER insere pendencias.

-- Protege duas importacoes concorrentes do mesmo documento sem emitente conhecido.
CREATE UNIQUE INDEX IF NOT EXISTS notas_fiscais_numero_serie_sem_emitente_idx
  ON public.notas_fiscais (numero, serie) WHERE emitente_documento IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS nf_execucoes_nf_rota_unica_idx
  ON public.nf_execucoes (nf_id, rota_id);

CREATE OR REPLACE FUNCTION public.sigo_importar_stopview(p_importacao_id uuid, p_linhas jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $sigo$
DECLARE
  v_usuario uuid := (SELECT auth.uid());
  v_linha jsonb;
  v_ord bigint;
  v_total integer;
  v_nome text;
  v_sha text;
  v_cod text;
  v_rom text;
  v_data_text text;
  v_data date;
  v_id_parada bigint;
  v_valor text;
  v_numero text;
  v_serie text;
  v_serie_assumida boolean;
  v_chave text;
  v_vt boolean;
  v_oficial boolean;
  v_rota_id uuid;
  v_parada_rota uuid;
  v_nf_id uuid;
  v_nf_origem uuid;
  v_rom_origem text;
  v_prestacao_id uuid;
  v_prestacao_d0 date;
  v_cont integer;
  v_existente_id uuid;
  v_novos integer := 0;
  v_nfs integer := 0;
  v_execucoes integer := 0;
  v_pendencias integer := 0;
  v_motivo text;
  v_tipo_execucao text;
  v_reimportada uuid;
BEGIN
  IF v_usuario IS NULL OR NOT (SELECT public.sigo_is_active()) THEN
    RAISE EXCEPTION 'Usuário sem permissão ativa para importar StopView';
  END IF;
  IF p_importacao_id IS NULL OR jsonb_typeof(p_linhas) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Importação inválida: informe ID UUID e objeto com sha256, arquivo_nome e linhas';
  END IF;
  v_nome := NULLIF(btrim(p_linhas->>'arquivo_nome'), '');
  v_sha := lower(coalesce(p_linhas->>'sha256', ''));
  IF v_nome IS NULL OR v_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Importação inválida: arquivo_nome e sha256 hexadecimal de 64 caracteres são obrigatórios';
  END IF;
  IF jsonb_typeof(p_linhas->'linhas') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'StopView inválido: linhas deve ser um array';
  END IF;
  v_total := jsonb_array_length(p_linhas->'linhas');
  IF v_total < 1 OR v_total > 20000 THEN
    RAISE EXCEPTION 'StopView inválido: lote deve ter entre 1 e 20000 linhas';
  END IF;

  -- Valida TODA a estrutura antes do primeiro INSERT. Qualquer falha cancela
  -- a chamada inteira: PostgreSQL executa esta RPC como uma transacao.
  FOR v_linha, v_ord IN
    SELECT a.value, a.ordinality FROM jsonb_array_elements(p_linhas->'linhas')
      WITH ORDINALITY AS a(value, ordinality)
  LOOP
    IF jsonb_typeof(v_linha) IS DISTINCT FROM 'object' OR
       NOT (v_linha ? 'Código da rota' AND v_linha ? 'Descrição da rota'
        AND v_linha ? 'id' AND v_linha ? 'stop.orders.number'
        AND v_linha ? 'Data da Rota') THEN
      RAISE EXCEPTION 'StopView: linha % sem coluna obrigatória: Código da rota, Descrição da rota, id, stop.orders.number ou Data da Rota', v_ord;
    END IF;
    IF btrim(coalesce(v_linha->>'Código da rota','')) = '' THEN
      RAISE EXCEPTION 'StopView: Código da rota vazio na linha %', v_ord;
    END IF;
    IF btrim(coalesce(v_linha->>'Descrição da rota','')) !~ '^[0-9]{12}$' THEN
      RAISE EXCEPTION 'StopView: Descrição da rota deve ser romaneio de 12 dígitos, linha %', v_ord;
    END IF;
    IF coalesce(v_linha->>'id','') !~ '^[0-9]{1,18}$' OR (v_linha->>'id')::bigint < 1 THEN
      RAISE EXCEPTION 'StopView: id de parada deve ser número inteiro positivo, linha %', v_ord;
    END IF;
    IF coalesce(v_linha->>'Data da Rota','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
      RAISE EXCEPTION 'StopView: Data da Rota inválida na linha %', v_ord;
    END IF;
    IF v_linha ? 'routeView.route.key' AND
       btrim(coalesce(v_linha->>'routeView.route.key','')) <> btrim(v_linha->>'Código da rota') THEN
      RAISE EXCEPTION 'StopView: Código da rota divergente entre Paradas e Pedidos, linha %', v_ord;
    END IF;
    IF v_linha ? 'routeView.route.date' AND
       left(coalesce(v_linha->>'routeView.route.date',''),10) <> (v_linha->>'Data da Rota') THEN
      RAISE EXCEPTION 'StopView: Data da Rota divergente entre Paradas e Pedidos, linha %', v_ord;
    END IF;
  END LOOP;

  -- A PK assegura que um ID jamais seja reutilizado em outro sha.
  -- A chave (tipo, sha256) garante replay inofensivo do mesmo arquivo.
  INSERT INTO public.gm_importacoes
    (id, tipo, arquivo_nome, sha256, registros, criado_por)
  VALUES
    (p_importacao_id, 'STOPVIEW_PEDIDOS', v_nome, v_sha, v_total, v_usuario)
  ON CONFLICT (tipo, sha256) DO NOTHING
  RETURNING id INTO v_existente_id;
  IF v_existente_id IS NULL THEN
    SELECT id INTO v_reimportada FROM public.gm_importacoes
      WHERE tipo = 'STOPVIEW_PEDIDOS' AND sha256 = v_sha;
    RETURN jsonb_build_object('status','JA_IMPORTADO', 'importacao_id',v_reimportada,
      'linhas', v_total, 'prestacoes_novas',0, 'notas_novas',0,
      'execucoes_novas',0,'pendencias_novas',0);
  END IF;

  -- 1) Persistir todas as rotas e paradas, inclusive as sem NF.
  FOR v_linha, v_ord IN
    SELECT a.value, a.ordinality FROM jsonb_array_elements(p_linhas->'linhas')
      WITH ORDINALITY AS a(value, ordinality)
  LOOP
    v_cod := btrim(v_linha->>'Código da rota');
    v_rom := btrim(v_linha->>'Descrição da rota');
    v_data := (v_linha->>'Data da Rota')::date;
    v_id_parada := (v_linha->>'id')::bigint;
    v_vt := upper(v_cod) ~ '(^|[-_])VT($|[-_A-Z0-9])' OR upper(v_cod) ~ '^SP-[0-9]+VT[A-Z0-9]*$';
    v_oficial := NOT v_vt AND v_rom !~ '^(.)\1{11}$' AND v_rom NOT LIKE '6000000000%';
    INSERT INTO public.rotas (data_rota,codigo,romaneio_gm,tipo_romaneio,
      motorista_gm,importacao_id)
    VALUES (v_data,v_cod,v_rom,
      CASE WHEN v_oficial THEN 'OFICIAL' ELSE 'AUXILIAR' END,
      NULLIF(btrim(coalesce(v_linha->>'Motoristas',v_linha->>'Motorista','')),''),
      p_importacao_id)
    ON CONFLICT (data_rota,codigo) DO NOTHING;
    SELECT id INTO STRICT v_rota_id FROM public.rotas
      WHERE data_rota=v_data AND codigo=v_cod;
    IF EXISTS(SELECT 1 FROM public.rotas WHERE id=v_rota_id
      AND romaneio_gm IS DISTINCT FROM v_rom) THEN
      RAISE EXCEPTION 'StopView: rota % em % já possui outro romaneio; revisão obrigatória',v_cod,v_data;
    END IF;
    INSERT INTO public.paradas (id,rota_id,data_rota,codigo_rota,
      codigo_localidade,cliente,status_gm,importacao_id)
    VALUES (v_id_parada,v_rota_id,v_data,v_cod,
      NULLIF(btrim(v_linha->>'Código da Localidade'),''),
      NULLIF(btrim(coalesce(v_linha->>'Cliente',v_linha->>'Nome da Localidade','')),''),
      NULLIF(btrim(v_linha->>'Status'),''),
      p_importacao_id)
    ON CONFLICT (id) DO NOTHING;
    SELECT rota_id INTO STRICT v_parada_rota FROM public.paradas WHERE id=v_id_parada;
    IF v_parada_rota IS DISTINCT FROM v_rota_id THEN
      RAISE EXCEPTION 'StopView: id de parada % pertence a outra rota',v_id_parada;
    END IF;
    IF v_oficial THEN
      INSERT INTO public.prestacoes (romaneio_oficial,d0,status,responsavel_id)
      VALUES (v_rom,v_data,'ABERTA',v_usuario)
      ON CONFLICT (romaneio_oficial) DO NOTHING
      RETURNING id INTO v_prestacao_id;
      IF v_prestacao_id IS NOT NULL THEN v_novos := v_novos + 1; END IF;
      SELECT id,d0 INTO STRICT v_prestacao_id,v_prestacao_d0
        FROM public.prestacoes WHERE romaneio_oficial=v_rom;
      IF v_prestacao_d0 IS DISTINCT FROM v_data THEN
        RAISE EXCEPTION 'Romaneio % já cadastrado com D0 diferente',v_rom;
      END IF;
    END IF;
  END LOOP;

  -- 2) Processar as NFs pelo valor original, sem gerar NF artificial.
  FOR v_linha, v_ord IN
    SELECT a.value, a.ordinality FROM jsonb_array_elements(p_linhas->'linhas')
      WITH ORDINALITY AS a(value, ordinality)
  LOOP
    v_cod := btrim(v_linha->>'Código da rota');
    v_rom := btrim(v_linha->>'Descrição da rota');
    v_data := (v_linha->>'Data da Rota')::date;
    v_id_parada := (v_linha->>'id')::bigint;
    v_valor := btrim(coalesce(v_linha->>'stop.orders.number',''));
    v_vt := upper(v_cod) ~ '(^|[-_])VT($|[-_A-Z0-9])' OR upper(v_cod) ~ '^SP-[0-9]+VT[A-Z0-9]*$';
    v_motivo := NULL;
    v_numero := NULL; v_serie := NULL; v_chave := NULL; v_nf_id := NULL;
    v_serie_assumida := false;
    SELECT id INTO STRICT v_rota_id FROM public.rotas
      WHERE data_rota=v_data AND codigo=v_cod;

    -- Identificar transferência VT antes de tratar valor curto como NF inválida.
    IF v_vt AND v_valor ~ '^[0-9]{1,2}$' THEN
      v_motivo := 'TRANSFERENCIA';
    ELSIF v_valor = '' OR v_valor ~ '^[0-9]{1,2}$' THEN
      v_motivo := 'SEM_NF';
    ELSIF v_valor ~ '^[0-9]{44}$' THEN
      v_numero := substring(v_valor from 26 for 9);
      v_serie := (substring(v_valor from 23 for 3)::integer)::text;
      v_chave := v_valor;
    ELSIF v_valor ~ '^[0-9]{1,9}-[0-9]{1,3}$' THEN
      v_numero := lpad(split_part(v_valor,'-',1),9,'0');
      v_serie := (split_part(v_valor,'-',2)::integer)::text;
    ELSIF v_valor ~ '^[0-9]{1,9}$' THEN
      v_numero := lpad(v_valor,9,'0');
    ELSE
      v_motivo := 'NF_INVALIDA';
    END IF;
    IF v_motivo IS NOT NULL THEN
      INSERT INTO public.pendencias_importacao
        (importacao_id,linha,codigo_rota,parada_id,valor_bruto,motivo)
      VALUES (p_importacao_id,v_ord,v_cod,v_id_parada,v_valor,v_motivo)
      ON CONFLICT (importacao_id,linha) DO NOTHING;
      v_pendencias := v_pendencias + 1;
      CONTINUE;
    END IF;

    -- Evita concorrencia que criaria duas origens para o mesmo numero.
    PERFORM pg_advisory_xact_lock(hashtextextended(v_numero,0));
    IF v_serie IS NULL THEN
      SELECT count(*),(array_agg(id ORDER BY id))[1] INTO v_cont,v_nf_id
        FROM public.notas_fiscais WHERE numero=v_numero;
      IF v_cont > 1 THEN
        v_motivo := 'SERIE_AMBIGUA';
      ELSIF v_cont = 0 THEN
        SELECT serie_padrao INTO STRICT v_serie
          FROM public.sla_config WHERE id IS TRUE;
        v_serie_assumida := true;
      END IF;
    ELSE
      SELECT count(*),(array_agg(id ORDER BY id))[1] INTO v_cont,v_nf_id
        FROM public.notas_fiscais
        WHERE numero=v_numero AND serie=v_serie;
      IF v_cont > 1 THEN v_motivo := 'SERIE_AMBIGUA'; END IF;
    END IF;
    IF v_motivo IS NOT NULL THEN
      INSERT INTO public.pendencias_importacao
        (importacao_id,linha,codigo_rota,parada_id,valor_bruto,motivo)
      VALUES (p_importacao_id,v_ord,v_cod,v_id_parada,v_valor,v_motivo)
      ON CONFLICT (importacao_id,linha) DO NOTHING;
      v_pendencias := v_pendencias + 1;
      CONTINUE;
    END IF;
    IF v_nf_id IS NULL THEN
      -- Primeira NF: série explícita ou padrão assumida, com origem fiscal fixa.
      INSERT INTO public.notas_fiscais
        (numero,serie,chave_acesso,romaneio_origem,origem_rota_id)
      VALUES (v_numero,v_serie,v_chave,v_rom,v_rota_id)
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_nf_id;
      IF v_nf_id IS NOT NULL THEN v_nfs := v_nfs + 1; END IF;
      IF v_nf_id IS NULL THEN
        SELECT count(*),(array_agg(id ORDER BY id))[1] INTO v_cont,v_nf_id
          FROM public.notas_fiscais WHERE numero=v_numero AND serie=v_serie;
        IF v_cont <> 1 THEN
          RAISE EXCEPTION 'NF % série % teve colisão não resolvida; importação cancelada',v_numero,v_serie;
        END IF;
      END IF;
    END IF;
    -- Informativa e já tratada: a origem foi registrada com série padrão.
    IF v_serie_assumida THEN
      INSERT INTO public.pendencias_importacao
        (importacao_id,linha,codigo_rota,parada_id,valor_bruto,motivo,status,tratada_por,tratada_em)
      VALUES (p_importacao_id,v_ord,v_cod,v_id_parada,v_valor,
        'SERIE_ASSUMIDA','TRATADA',v_usuario,clock_timestamp())
      ON CONFLICT (importacao_id,linha) DO NOTHING;
      v_pendencias := v_pendencias + 1;
    END IF;
    SELECT origem_rota_id,romaneio_origem INTO STRICT v_nf_origem,v_rom_origem
      FROM public.notas_fiscais WHERE id=v_nf_id;
    -- Guard do schema impede qualquer update de origem/número/série.
    INSERT INTO public.parada_notas(parada_id,nf_id,importacao_id)
    VALUES (v_id_parada,v_nf_id,p_importacao_id)
    ON CONFLICT (parada_id,nf_id) DO NOTHING;
    v_tipo_execucao := CASE
      WHEN v_nf_origem=v_rota_id AND NOT v_vt THEN 'CARGA'
      WHEN v_vt THEN 'TRANSFERENCIA' ELSE 'REENTREGA' END;
    -- O schema permite apenas uma execucao aberta por NF; ao mudar de rota,
    -- encerra a execucao anterior sem jamais alterar a origem fiscal.
    IF NOT EXISTS (
      SELECT 1 FROM public.nf_execucoes
      WHERE nf_id=v_nf_id AND rota_id=v_rota_id
    ) THEN
      UPDATE public.nf_execucoes
        SET encerrada_em=clock_timestamp()
      WHERE nf_id=v_nf_id AND rota_id IS DISTINCT FROM v_rota_id
        AND encerrada_em IS NULL;
    END IF;
    INSERT INTO public.nf_execucoes(nf_id,rota_id,tipo,registrada_por)
    VALUES (v_nf_id,v_rota_id,v_tipo_execucao,v_usuario)
    ON CONFLICT (nf_id,rota_id) DO NOTHING;
    IF FOUND THEN v_execucoes:=v_execucoes+1; END IF;
    -- Vínculo fiscal único continua na prestação da rota de ORIGEM.
    IF v_rom_origem IS NOT NULL AND v_nf_origem IS NOT NULL THEN
      SELECT id INTO v_prestacao_id FROM public.prestacoes WHERE romaneio_oficial=v_rom_origem;
      IF v_prestacao_id IS NOT NULL THEN
        INSERT INTO public.prestacao_notas(prestacao_id,nf_id)
        VALUES (v_prestacao_id,v_nf_id)
        ON CONFLICT (nf_id) DO NOTHING;
      END IF;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('status','IMPORTADO', 'importacao_id',p_importacao_id,
    'linhas',v_total,'prestacoes_novas',v_novos,
    'notas_novas',v_nfs,'execucoes_novas',v_execucoes,
    'pendencias_novas',v_pendencias);
END;
$sigo$;

REVOKE ALL ON FUNCTION public.sigo_importar_stopview(uuid,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_importar_stopview(uuid,jsonb)
  TO authenticated;
-- ==== END MIGRATION 20261116000400_sigo_importacao_nf.sql ====

-- ==== BEGIN MIGRATION 20261116000450_sigo_vt_abastecimento.sql (VERBATIM) ====
-- SIGO / Regra VT: rotas VTVU representam abastecimento VUC, não movimentação fiscal.
-- Snapshot incremental sobre 20261116000400. Não aplicar no Supabase hospedado.
-- O código de rota não define destino: utilizar exclusivamente Código da Localidade.

ALTER TABLE public.rotas
  ADD COLUMN IF NOT EXISTS tipo_rota text NOT NULL DEFAULT 'ENTREGA';
DO $vuc_schema$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rotas'::regclass AND conname='rotas_tipo_rota_check'
  ) THEN
    ALTER TABLE public.rotas ADD CONSTRAINT rotas_tipo_rota_check
      CHECK (tipo_rota IN ('ENTREGA','ABASTECIMENTO'));
  END IF;
END;
$vuc_schema$;

ALTER TABLE public.sla_config
  ADD COLUMN IF NOT EXISTS localidade_cross_proprio text NOT NULL DEFAULT 'CROSS-ZL';
ALTER TABLE public.paradas
  ADD COLUMN IF NOT EXISTS valor_bruto_pedido text;
ALTER TABLE public.pendencias_importacao
  ADD COLUMN IF NOT EXISTS observacao text;

-- Histórico: classificação derivada da rota, sem alterar código, romaneio, NF
-- ou demais valores brutos recebidos do GreenMile.
UPDATE public.rotas SET tipo_rota='ABASTECIMENTO'
WHERE (upper(codigo) ~ '^SP-[0-9]+VT[A-Z0-9]*$'
       OR upper(codigo) ~ '(^|[-_])VT($|[-_A-Z0-9])')
  AND tipo_rota IS DISTINCT FROM 'ABASTECIMENTO';

-- Se o único registro da informação bruta era a antiga pendência,
-- conserva o valor original na nova coluna da parada.
UPDATE public.paradas p
SET valor_bruto_pedido=pi.valor_bruto
FROM public.pendencias_importacao pi
WHERE pi.parada_id=p.id
  AND pi.motivo='TRANSFERENCIA'
  AND p.valor_bruto_pedido IS NULL;

-- Marcadores antigos são encerrados como auditoria automática. Não inventamos
-- um usuário: quando não há criado_por válido, "abastecimento VUC" identifica
-- um encerramento por migration (sem autoria humana).
ALTER TABLE public.pendencias_importacao
  DROP CONSTRAINT IF EXISTS pendencias_tratamento_consistente;
ALTER TABLE public.pendencias_importacao
  ADD CONSTRAINT pendencias_tratamento_consistente CHECK (
    (status='PENDENTE' AND tratada_por IS NULL AND tratada_em IS NULL)
    OR
    (status='TRATADA' AND tratada_em IS NOT NULL
      AND (tratada_por IS NOT NULL OR (motivo='TRANSFERENCIA' AND observacao='abastecimento VUC')))
  );
UPDATE public.pendencias_importacao pi
SET status='TRATADA',
    observacao='abastecimento VUC',
    tratada_em=coalesce(pi.tratada_em,clock_timestamp()),
    tratada_por=coalesce(pi.tratada_por,gi.criado_por)
FROM public.gm_importacoes gi
WHERE gi.id=pi.importacao_id AND pi.motivo='TRANSFERENCIA'
  AND (pi.status IS DISTINCT FROM 'TRATADA'
       OR pi.observacao IS DISTINCT FROM 'abastecimento VUC');

-- Retrocompatibilidade: o enum textual TRANSFERENCIA fica apenas para histórico.
-- Não é mais gerado por sigo_importar_stopview.

-- RPC integral: lógica original preservada salvo classificação VT e persistência
-- do valor bruto do pedido para visualização das chegadas de VUC.
CREATE OR REPLACE FUNCTION public.sigo_importar_stopview(p_importacao_id uuid, p_linhas jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $sigo$
DECLARE
  v_usuario uuid := (SELECT auth.uid());
  v_linha jsonb;
  v_ord bigint;
  v_total integer;
  v_nome text;
  v_sha text;
  v_cod text;
  v_rom text;
  v_data_text text;
  v_data date;
  v_id_parada bigint;
  v_valor text;
  v_numero text;
  v_serie text;
  v_serie_assumida boolean;
  v_chave text;
  v_vt boolean;
  v_oficial boolean;
  v_rota_id uuid;
  v_parada_rota uuid;
  v_nf_id uuid;
  v_nf_origem uuid;
  v_rom_origem text;
  v_prestacao_id uuid;
  v_prestacao_d0 date;
  v_cont integer;
  v_existente_id uuid;
  v_novos integer := 0;
  v_nfs integer := 0;
  v_execucoes integer := 0;
  v_pendencias integer := 0;
  v_motivo text;
  v_tipo_execucao text;
  v_reimportada uuid;
BEGIN
  IF v_usuario IS NULL OR NOT (SELECT public.sigo_is_active()) THEN
    RAISE EXCEPTION 'Usuário sem permissão ativa para importar StopView';
  END IF;
  IF p_importacao_id IS NULL OR jsonb_typeof(p_linhas) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Importação inválida: informe ID UUID e objeto com sha256, arquivo_nome e linhas';
  END IF;
  v_nome := NULLIF(btrim(p_linhas->>'arquivo_nome'), '');
  v_sha := lower(coalesce(p_linhas->>'sha256', ''));
  IF v_nome IS NULL OR v_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Importação inválida: arquivo_nome e sha256 hexadecimal de 64 caracteres são obrigatórios';
  END IF;
  IF jsonb_typeof(p_linhas->'linhas') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'StopView inválido: linhas deve ser um array';
  END IF;
  v_total := jsonb_array_length(p_linhas->'linhas');
  IF v_total < 1 OR v_total > 20000 THEN
    RAISE EXCEPTION 'StopView inválido: lote deve ter entre 1 e 20000 linhas';
  END IF;

  -- Valida TODA a estrutura antes do primeiro INSERT. Qualquer falha cancela
  -- a chamada inteira: PostgreSQL executa esta RPC como uma transacao.
  FOR v_linha, v_ord IN
    SELECT a.value, a.ordinality FROM jsonb_array_elements(p_linhas->'linhas')
      WITH ORDINALITY AS a(value, ordinality)
  LOOP
    IF jsonb_typeof(v_linha) IS DISTINCT FROM 'object' OR
       NOT (v_linha ? 'Código da rota' AND v_linha ? 'Descrição da rota'
        AND v_linha ? 'id' AND v_linha ? 'stop.orders.number'
        AND v_linha ? 'Data da Rota') THEN
      RAISE EXCEPTION 'StopView: linha % sem coluna obrigatória: Código da rota, Descrição da rota, id, stop.orders.number ou Data da Rota', v_ord;
    END IF;
    IF btrim(coalesce(v_linha->>'Código da rota','')) = '' THEN
      RAISE EXCEPTION 'StopView: Código da rota vazio na linha %', v_ord;
    END IF;
    IF btrim(coalesce(v_linha->>'Descrição da rota','')) !~ '^[0-9]{12}$' THEN
      RAISE EXCEPTION 'StopView: Descrição da rota deve ser romaneio de 12 dígitos, linha %', v_ord;
    END IF;
    IF coalesce(v_linha->>'id','') !~ '^[0-9]{1,18}$' OR (v_linha->>'id')::bigint < 1 THEN
      RAISE EXCEPTION 'StopView: id de parada deve ser número inteiro positivo, linha %', v_ord;
    END IF;
    IF coalesce(v_linha->>'Data da Rota','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
      RAISE EXCEPTION 'StopView: Data da Rota inválida na linha %', v_ord;
    END IF;
    IF v_linha ? 'routeView.route.key' AND
       btrim(coalesce(v_linha->>'routeView.route.key','')) <> btrim(v_linha->>'Código da rota') THEN
      RAISE EXCEPTION 'StopView: Código da rota divergente entre Paradas e Pedidos, linha %', v_ord;
    END IF;
    IF v_linha ? 'routeView.route.date' AND
       left(coalesce(v_linha->>'routeView.route.date',''),10) <> (v_linha->>'Data da Rota') THEN
      RAISE EXCEPTION 'StopView: Data da Rota divergente entre Paradas e Pedidos, linha %', v_ord;
    END IF;
  END LOOP;

  -- A PK assegura que um ID jamais seja reutilizado em outro sha.
  -- A chave (tipo, sha256) garante replay inofensivo do mesmo arquivo.
  INSERT INTO public.gm_importacoes
    (id, tipo, arquivo_nome, sha256, registros, criado_por)
  VALUES
    (p_importacao_id, 'STOPVIEW_PEDIDOS', v_nome, v_sha, v_total, v_usuario)
  ON CONFLICT (tipo, sha256) DO NOTHING
  RETURNING id INTO v_existente_id;
  IF v_existente_id IS NULL THEN
    SELECT id INTO v_reimportada FROM public.gm_importacoes
      WHERE tipo = 'STOPVIEW_PEDIDOS' AND sha256 = v_sha;
    RETURN jsonb_build_object('status','JA_IMPORTADO', 'importacao_id',v_reimportada,
      'linhas', v_total, 'prestacoes_novas',0, 'notas_novas',0,
      'execucoes_novas',0,'pendencias_novas',0);
  END IF;

  -- 1) Persistir todas as rotas e paradas, inclusive as sem NF.
  FOR v_linha, v_ord IN
    SELECT a.value, a.ordinality FROM jsonb_array_elements(p_linhas->'linhas')
      WITH ORDINALITY AS a(value, ordinality)
  LOOP
    v_cod := btrim(v_linha->>'Código da rota');
    v_rom := btrim(v_linha->>'Descrição da rota');
    v_data := (v_linha->>'Data da Rota')::date;
    v_id_parada := (v_linha->>'id')::bigint;
    v_vt := upper(v_cod) ~ '(^|[-_])VT($|[-_A-Z0-9])' OR upper(v_cod) ~ '^SP-[0-9]+VT[A-Z0-9]*$';
    v_oficial := NOT v_vt AND v_rom !~ '^(.)\1{11}$' AND v_rom NOT LIKE '6000000000%';
    INSERT INTO public.rotas (data_rota,codigo,romaneio_gm,tipo_romaneio,
      tipo_rota,motorista_gm,importacao_id)
    VALUES (v_data,v_cod,v_rom,
      CASE WHEN v_oficial THEN 'OFICIAL' ELSE 'AUXILIAR' END,
      CASE WHEN v_vt THEN 'ABASTECIMENTO' ELSE 'ENTREGA' END,
      NULLIF(btrim(coalesce(v_linha->>'Motoristas',v_linha->>'Motorista',v_linha->>'routeView.primaryDriver.name','')),''),
      p_importacao_id)
    ON CONFLICT (data_rota,codigo) DO NOTHING;
    SELECT id INTO STRICT v_rota_id FROM public.rotas
      WHERE data_rota=v_data AND codigo=v_cod;
    IF EXISTS(SELECT 1 FROM public.rotas WHERE id=v_rota_id
      AND romaneio_gm IS DISTINCT FROM v_rom) THEN
      RAISE EXCEPTION 'StopView: rota % em % já possui outro romaneio; revisão obrigatória',v_cod,v_data;
    END IF;
    -- Backfill idempotente de rotas criadas por imports anteriores.
    IF v_vt THEN
      UPDATE public.rotas SET tipo_rota='ABASTECIMENTO'
      WHERE id=v_rota_id AND tipo_rota IS DISTINCT FROM 'ABASTECIMENTO';
    END IF;
    INSERT INTO public.paradas (id,rota_id,data_rota,codigo_rota,
      codigo_localidade,cliente,status_gm,valor_bruto_pedido,importacao_id)
    VALUES (v_id_parada,v_rota_id,v_data,v_cod,
      NULLIF(btrim(v_linha->>'Código da Localidade'),''),
      NULLIF(btrim(coalesce(v_linha->>'Cliente',v_linha->>'Nome da Localidade',v_linha->>'Descrição da Localidade','')),''),
      NULLIF(btrim(v_linha->>'Status'),''),
      v_linha->>'stop.orders.number',
      p_importacao_id)
    ON CONFLICT (id) DO NOTHING;
    SELECT rota_id INTO STRICT v_parada_rota FROM public.paradas WHERE id=v_id_parada;
    IF v_parada_rota IS DISTINCT FROM v_rota_id THEN
      RAISE EXCEPTION 'StopView: id de parada % pertence a outra rota',v_id_parada;
    END IF;
    IF v_vt THEN
      -- Preserva o valor bruto que chegou do StopView; não infere semântica de NF.
      UPDATE public.paradas SET valor_bruto_pedido=v_linha->>'stop.orders.number'
      WHERE id=v_id_parada AND valor_bruto_pedido IS NULL;
    END IF;
    IF v_oficial THEN
      INSERT INTO public.prestacoes (romaneio_oficial,d0,status,responsavel_id)
      VALUES (v_rom,v_data,'ABERTA',v_usuario)
      ON CONFLICT (romaneio_oficial) DO NOTHING
      RETURNING id INTO v_prestacao_id;
      IF v_prestacao_id IS NOT NULL THEN v_novos := v_novos + 1; END IF;
      SELECT id,d0 INTO STRICT v_prestacao_id,v_prestacao_d0
        FROM public.prestacoes WHERE romaneio_oficial=v_rom;
      IF v_prestacao_d0 IS DISTINCT FROM v_data THEN
        RAISE EXCEPTION 'Romaneio % já cadastrado com D0 diferente',v_rom;
      END IF;
    END IF;
  END LOOP;

  -- 2) Processar as NFs pelo valor original, sem gerar NF artificial.
  FOR v_linha, v_ord IN
    SELECT a.value, a.ordinality FROM jsonb_array_elements(p_linhas->'linhas')
      WITH ORDINALITY AS a(value, ordinality)
  LOOP
    v_cod := btrim(v_linha->>'Código da rota');
    v_rom := btrim(v_linha->>'Descrição da rota');
    v_data := (v_linha->>'Data da Rota')::date;
    v_id_parada := (v_linha->>'id')::bigint;
    v_valor := btrim(coalesce(v_linha->>'stop.orders.number',''));
    v_vt := upper(v_cod) ~ '(^|[-_])VT($|[-_A-Z0-9])' OR upper(v_cod) ~ '^SP-[0-9]+VT[A-Z0-9]*$';
    v_motivo := NULL;
    v_numero := NULL; v_serie := NULL; v_chave := NULL; v_nf_id := NULL;
    v_serie_assumida := false;
    SELECT id INTO STRICT v_rota_id FROM public.rotas
      WHERE data_rota=v_data AND codigo=v_cod;

    -- Abastecimento VUC: não é nota fiscal, reentrega ou pendência.
    IF v_vt THEN
      CONTINUE;
    END IF;
    IF v_valor = '' OR v_valor ~ '^[0-9]{1,2}$' THEN
      v_motivo := 'SEM_NF';
    ELSIF v_valor ~ '^[0-9]{44}$' THEN
      v_numero := substring(v_valor from 26 for 9);
      v_serie := (substring(v_valor from 23 for 3)::integer)::text;
      v_chave := v_valor;
    ELSIF v_valor ~ '^[0-9]{1,9}-[0-9]{1,3}$' THEN
      v_numero := lpad(split_part(v_valor,'-',1),9,'0');
      v_serie := (split_part(v_valor,'-',2)::integer)::text;
    ELSIF v_valor ~ '^[0-9]{1,9}$' THEN
      v_numero := lpad(v_valor,9,'0');
    ELSE
      v_motivo := 'NF_INVALIDA';
    END IF;
    IF v_motivo IS NOT NULL THEN
      INSERT INTO public.pendencias_importacao
        (importacao_id,linha,codigo_rota,parada_id,valor_bruto,motivo)
      VALUES (p_importacao_id,v_ord,v_cod,v_id_parada,v_valor,v_motivo)
      ON CONFLICT (importacao_id,linha) DO NOTHING;
      v_pendencias := v_pendencias + 1;
      CONTINUE;
    END IF;

    -- Evita concorrencia que criaria duas origens para o mesmo numero.
    PERFORM pg_advisory_xact_lock(hashtextextended(v_numero,0));
    IF v_serie IS NULL THEN
      SELECT count(*),(array_agg(id ORDER BY id))[1] INTO v_cont,v_nf_id
        FROM public.notas_fiscais WHERE numero=v_numero;
      IF v_cont > 1 THEN
        v_motivo := 'SERIE_AMBIGUA';
      ELSIF v_cont = 0 THEN
        SELECT serie_padrao INTO STRICT v_serie
          FROM public.sla_config WHERE id IS TRUE;
        v_serie_assumida := true;
      END IF;
    ELSE
      SELECT count(*),(array_agg(id ORDER BY id))[1] INTO v_cont,v_nf_id
        FROM public.notas_fiscais
        WHERE numero=v_numero AND serie=v_serie;
      IF v_cont > 1 THEN v_motivo := 'SERIE_AMBIGUA'; END IF;
    END IF;
    IF v_motivo IS NOT NULL THEN
      INSERT INTO public.pendencias_importacao
        (importacao_id,linha,codigo_rota,parada_id,valor_bruto,motivo)
      VALUES (p_importacao_id,v_ord,v_cod,v_id_parada,v_valor,v_motivo)
      ON CONFLICT (importacao_id,linha) DO NOTHING;
      v_pendencias := v_pendencias + 1;
      CONTINUE;
    END IF;
    IF v_nf_id IS NULL THEN
      -- Primeira NF: série explícita ou padrão assumida, com origem fiscal fixa.
      INSERT INTO public.notas_fiscais
        (numero,serie,chave_acesso,romaneio_origem,origem_rota_id)
      VALUES (v_numero,v_serie,v_chave,v_rom,v_rota_id)
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_nf_id;
      IF v_nf_id IS NOT NULL THEN v_nfs := v_nfs + 1; END IF;
      IF v_nf_id IS NULL THEN
        SELECT count(*),(array_agg(id ORDER BY id))[1] INTO v_cont,v_nf_id
          FROM public.notas_fiscais WHERE numero=v_numero AND serie=v_serie;
        IF v_cont <> 1 THEN
          RAISE EXCEPTION 'NF % série % teve colisão não resolvida; importação cancelada',v_numero,v_serie;
        END IF;
      END IF;
    END IF;
    -- Informativa e já tratada: a origem foi registrada com série padrão.
    IF v_serie_assumida THEN
      INSERT INTO public.pendencias_importacao
        (importacao_id,linha,codigo_rota,parada_id,valor_bruto,motivo,status,tratada_por,tratada_em)
      VALUES (p_importacao_id,v_ord,v_cod,v_id_parada,v_valor,
        'SERIE_ASSUMIDA','TRATADA',v_usuario,clock_timestamp())
      ON CONFLICT (importacao_id,linha) DO NOTHING;
      v_pendencias := v_pendencias + 1;
    END IF;
    SELECT origem_rota_id,romaneio_origem INTO STRICT v_nf_origem,v_rom_origem
      FROM public.notas_fiscais WHERE id=v_nf_id;
    -- Guard do schema impede qualquer update de origem/número/série.
    INSERT INTO public.parada_notas(parada_id,nf_id,importacao_id)
    VALUES (v_id_parada,v_nf_id,p_importacao_id)
    ON CONFLICT (parada_id,nf_id) DO NOTHING;
    v_tipo_execucao := CASE
      WHEN v_nf_origem=v_rota_id THEN 'CARGA' ELSE 'REENTREGA' END;
    -- O schema permite apenas uma execucao aberta por NF; ao mudar de rota,
    -- encerra a execucao anterior sem jamais alterar a origem fiscal.
    IF NOT EXISTS (
      SELECT 1 FROM public.nf_execucoes
      WHERE nf_id=v_nf_id AND rota_id=v_rota_id
    ) THEN
      UPDATE public.nf_execucoes
        SET encerrada_em=clock_timestamp()
      WHERE nf_id=v_nf_id AND rota_id IS DISTINCT FROM v_rota_id
        AND encerrada_em IS NULL;
    END IF;
    INSERT INTO public.nf_execucoes(nf_id,rota_id,tipo,registrada_por)
    VALUES (v_nf_id,v_rota_id,v_tipo_execucao,v_usuario)
    ON CONFLICT (nf_id,rota_id) DO NOTHING;
    IF FOUND THEN v_execucoes:=v_execucoes+1; END IF;
    -- Vínculo fiscal único continua na prestação da rota de ORIGEM.
    IF v_rom_origem IS NOT NULL AND v_nf_origem IS NOT NULL THEN
      SELECT id INTO v_prestacao_id FROM public.prestacoes WHERE romaneio_oficial=v_rom_origem;
      IF v_prestacao_id IS NOT NULL THEN
        INSERT INTO public.prestacao_notas(prestacao_id,nf_id)
        VALUES (v_prestacao_id,v_nf_id)
        ON CONFLICT (nf_id) DO NOTHING;
      END IF;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('status','IMPORTADO', 'importacao_id',p_importacao_id,
    'linhas',v_total,'prestacoes_novas',v_novos,
    'notas_novas',v_nfs,'execucoes_novas',v_execucoes,
    'pendencias_novas',v_pendencias);
END;
$sigo$;


REVOKE ALL ON FUNCTION public.sigo_importar_stopview(uuid,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_importar_stopview(uuid,jsonb)
  TO authenticated;


CREATE OR REPLACE VIEW public.v_chegadas_vuc
WITH (security_invoker = true)
AS
SELECT
  r.data_rota AS data,
  r.codigo AS codigo_rota,
  r.motorista_gm AS motorista,
  p.codigo_localidade AS localidade_destino,
  p.valor_bruto_pedido AS valor_bruto_pedido
FROM public.rotas r
JOIN public.paradas p ON p.rota_id = r.id
JOIN public.sla_config cfg ON cfg.id = true
WHERE r.tipo_rota = 'ABASTECIMENTO'
  AND upper(btrim(p.codigo_localidade)) = upper(btrim(cfg.localidade_cross_proprio));

REVOKE ALL ON public.v_chegadas_vuc FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_chegadas_vuc TO authenticated;
-- ==== END MIGRATION 20261116000450_sigo_vt_abastecimento.sql ====

-- ==== BEGIN MIGRATION 20261117000100_sigo_bipagem_canhotos.sql (VERBATIM) ====
-- SIGO Etapa 4: backend de bipagem de canhotos.
-- Dependência: baseline 00200, SLA 00300, StopView 00400 e VT 00450.
-- Nunca aplicar no Supabase hospedado sem reconciliar seu histórico remoto.
-- Dados brutos de rotas, paradas e NF permanecem imutáveis; chave_acesso é
-- preenchida UMA vez por bipe de chave válida, por autorização explícita.

CREATE TABLE IF NOT EXISTS public.bipagens (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo_lido text NOT NULL,
  codigo_normalizado text,
  resultado text NOT NULL CHECK (resultado IN (
    'OK','JA_BIPADA','ROTA_DIFERENTE','NAO_ENCONTRADA',
    'PRESTACAO_FECHADA','SEM_PRESTACAO','CODIGO_INVALIDO')),
  nf_id uuid REFERENCES public.notas_fiscais(id),
  prestacao_id uuid REFERENCES public.prestacoes(id),
  rota_execucao_id uuid REFERENCES public.rotas(id),
  usuario_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  dispositivo text,
  bipado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS bipagens_prestacao_em_idx
  ON public.bipagens(prestacao_id, bipado_em DESC);
CREATE INDEX IF NOT EXISTS bipagens_em_idx
  ON public.bipagens(bipado_em DESC);
CREATE INDEX IF NOT EXISTS bipagens_falhas_idx
  ON public.bipagens(resultado) WHERE resultado IN ('NAO_ENCONTRADA','SEM_PRESTACAO');

ALTER TABLE public.bipagens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bipagens FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.bipagens TO authenticated;
DROP POLICY IF EXISTS bipagens_read ON public.bipagens;
CREATE POLICY bipagens_read ON public.bipagens FOR SELECT TO authenticated
  USING ((SELECT public.sigo_is_active()));

CREATE TABLE IF NOT EXISTS public.prestacao_nota_justificativas (
  prestacao_id uuid NOT NULL REFERENCES public.prestacoes(id),
  nf_id uuid NOT NULL REFERENCES public.notas_fiscais(id),
  motivo text NOT NULL CHECK (motivo IN
    ('DEVOLUCAO','REENTREGA_PROGRAMADA','REQUISICAO','RECOLHA','EXTRAVIO','OUTRO')),
  observacao text,
  usuario_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  criado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (prestacao_id,nf_id),
  CONSTRAINT justificativas_observacao_check CHECK (
    motivo NOT IN ('EXTRAVIO','OUTRO') OR NULLIF(btrim(observacao),'') IS NOT NULL)
);
ALTER TABLE public.prestacao_nota_justificativas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.prestacao_nota_justificativas FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.prestacao_nota_justificativas TO authenticated;
DROP POLICY IF EXISTS prestacao_nota_justificativas_read ON public.prestacao_nota_justificativas;
CREATE POLICY prestacao_nota_justificativas_read
  ON public.prestacao_nota_justificativas FOR SELECT TO authenticated
  USING ((SELECT public.sigo_is_active()));

CREATE INDEX IF NOT EXISTS notas_fiscais_numero_serie_idx
  ON public.notas_fiscais(numero,serie);

-- Equivalente estrito a normalizarNF(valor: string) no TypeScript:
-- .trim() APENAS nas extremidades; formato interno nunca é higienizado.
-- 44 dígitos -> chave; de 1 a 9 dígitos + hífen/série 1 a 3
-- -> número com 9 dígitos + série sem zeros; sem hífen -> número-?.
CREATE OR REPLACE FUNCTION public.sigo_normalizar_codigo_canhoto(codigo text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=''
AS $normalize$
DECLARE v text; v_num text; v_serie text;
BEGIN
  IF codigo IS NULL THEN RETURN NULL; END IF;
  -- ECMAScript String.prototype.trim: WhiteSpace + LineTerminator, incluindo
  -- NBSP, espaços Unicode, separadores de linha e BOM; sem remover nada no meio.
  v := btrim(codigo, E' \t\n\r\f\v' ||
    U&'\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF');
  IF v ~ '^[0-9]{44}$' THEN RETURN v; END IF;
  IF v ~ '^[0-9]{1,9}-[0-9]{1,3}$' THEN
    v_num := lpad(split_part(v,'-',1),9,'0');
    v_serie := (split_part(v,'-',2)::integer)::text;
    RETURN v_num||'-'||v_serie;
  END IF;
  IF v ~ '^[0-9]{1,9}$' THEN RETURN lpad(v,9,'0')||'-?'; END IF;
  RETURN NULL;
END;
$normalize$;

-- View agregada da prestação; NF da origem conta mesmo sem prestacao_notas
-- prévia. A NF justificada continua faltante fisicamente até receber canhoto.
CREATE OR REPLACE VIEW public.v_prestacao_progresso
WITH (security_invoker=true) AS
WITH universo AS (
  SELECT p.id prestacao_id,pn.nf_id
  FROM public.prestacoes p JOIN public.prestacao_notas pn ON pn.prestacao_id=p.id
  UNION
  SELECT p.id,nf.id
  FROM public.prestacoes p JOIN public.notas_fiscais nf
    ON nf.romaneio_origem=p.romaneio_oficial
),
agg AS (
  SELECT p.id prestacao_id,
    count(u.nf_id)::int AS total_nfs,
    count(u.nf_id) FILTER (WHERE pn.canhoto_recebido_em IS NOT NULL)::int AS bipados,
    min(pn.canhoto_recebido_em) primeiro_bipe_em,
    max(pn.canhoto_recebido_em) ultimo_bipe_em
  FROM public.prestacoes p
  LEFT JOIN universo u ON u.prestacao_id=p.id
  LEFT JOIN public.prestacao_notas pn
    ON pn.nf_id=u.nf_id AND pn.prestacao_id=p.id
  GROUP BY p.id
)
SELECT p.id AS prestacao_id,p.romaneio_oficial,p.status,
  a.total_nfs,a.bipados,(a.total_nfs-a.bipados) AS faltantes,
  CASE WHEN a.total_nfs=0 THEN 0::numeric
    ELSE round(100.0*a.bipados/a.total_nfs,2) END AS pct_bipado,
  a.primeiro_bipe_em,a.ultimo_bipe_em,
  CASE WHEN p.retornada_em IS NOT NULL AND p.conferida_em IS NOT NULL
    THEN extract(epoch FROM (p.conferida_em-p.retornada_em))/60
    ELSE NULL END AS minutos_retorno_ate_conferencia
FROM public.prestacoes p JOIN agg a ON a.prestacao_id=p.id;

REVOKE ALL ON public.v_prestacao_progresso FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_prestacao_progresso TO authenticated;

-- Somente a RPC pode justificar; perfil ativo + NF pertencente à origem.
CREATE OR REPLACE FUNCTION public.sigo_justificar_faltante(
  p_prestacao_id uuid,p_nf_id uuid,p_motivo text,p_observacao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $justify$
DECLARE v_usuario uuid := (SELECT auth.uid());
  v_rom text; v_nf_rom text; v_recebido timestamptz;
BEGIN
  IF v_usuario IS NULL OR NOT (SELECT public.sigo_is_active()) THEN
    RAISE EXCEPTION 'Usuário sem acesso ativo ao SIGO';
  END IF;
  IF p_motivo NOT IN ('DEVOLUCAO','REENTREGA_PROGRAMADA','REQUISICAO','RECOLHA','EXTRAVIO','OUTRO')
    OR p_motivo IS NULL THEN RAISE EXCEPTION 'Motivo de justificativa inválido'; END IF;
  IF p_motivo IN ('EXTRAVIO','OUTRO') AND NULLIF(btrim(p_observacao),'') IS NULL THEN
    RAISE EXCEPTION 'Observação obrigatória para EXTRAVIO ou OUTRO';
  END IF;
  SELECT romaneio_oficial INTO STRICT v_rom FROM public.prestacoes
    WHERE id=p_prestacao_id AND status IN ('ABERTA','RETORNADA');
  SELECT romaneio_origem INTO STRICT v_nf_rom FROM public.notas_fiscais WHERE id=p_nf_id;
  IF v_nf_rom IS DISTINCT FROM v_rom THEN
    RAISE EXCEPTION 'NF não pertence ao romaneio de origem da prestação';
  END IF;
  SELECT canhoto_recebido_em INTO v_recebido FROM public.prestacao_notas
    WHERE prestacao_id=p_prestacao_id AND nf_id=p_nf_id;
  IF v_recebido IS NOT NULL THEN RAISE EXCEPTION 'NF já possui canhoto recebido'; END IF;
  INSERT INTO public.prestacao_nota_justificativas(
    prestacao_id,nf_id,motivo,observacao,usuario_id)
  VALUES (p_prestacao_id,p_nf_id,p_motivo,NULLIF(btrim(p_observacao),''),v_usuario)
  ON CONFLICT (prestacao_id,nf_id) DO NOTHING;
  RETURN jsonb_build_object('prestacao_id',p_prestacao_id,'nf_id',p_nf_id,
    'motivo',p_motivo,'registrada',true);
END;
$justify$;

CREATE OR REPLACE FUNCTION public.sigo_canhotos_faltantes(p_prestacao_id uuid)
RETURNS TABLE(nf_id uuid,numero text,serie text,cliente text,status_gm text,tipo_execucao text,justificativa text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $missing$
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT (SELECT public.sigo_is_active()) THEN
    RAISE EXCEPTION 'Usuário sem acesso ativo ao SIGO';
  END IF;
  RETURN QUERY
  WITH ids AS (
    SELECT pn.nf_id FROM public.prestacao_notas pn
      WHERE pn.prestacao_id=p_prestacao_id
    UNION
    SELECT nf.id FROM public.notas_fiscais nf
      JOIN public.prestacoes p ON p.romaneio_oficial=nf.romaneio_origem
      WHERE p.id=p_prestacao_id
  )
  SELECT nf.id,nf.numero::text,nf.serie,pa.cliente,pa.status_gm,ne.tipo,j.motivo
  FROM ids JOIN public.notas_fiscais nf ON nf.id=ids.nf_id
  LEFT JOIN public.prestacao_notas pn ON pn.nf_id=nf.id AND pn.prestacao_id=p_prestacao_id
  LEFT JOIN LATERAL (
    SELECT p.cliente,p.status_gm FROM public.parada_notas pn2
      JOIN public.paradas p ON p.id=pn2.parada_id
      JOIN public.rotas r ON r.id=p.rota_id
    WHERE pn2.nf_id=nf.id AND r.tipo_rota='ENTREGA'
    ORDER BY p.data_rota DESC NULLS LAST,p.id DESC LIMIT 1
  ) pa ON true
  LEFT JOIN LATERAL (
    SELECT e.tipo FROM public.nf_execucoes e
      JOIN public.rotas r ON r.id=e.rota_id AND r.tipo_rota='ENTREGA'
    WHERE e.nf_id=nf.id
    ORDER BY e.iniciada_em DESC,e.id DESC LIMIT 1
  ) ne ON true
  LEFT JOIN public.prestacao_nota_justificativas j
    ON j.prestacao_id=p_prestacao_id AND j.nf_id=nf.id
  WHERE pn.canhoto_recebido_em IS NULL
  ORDER BY nf.numero,nf.serie;
END;
$missing$;

-- Imutabilidade no próprio banco (inclusive se um futuro grant mudar).
CREATE OR REPLACE FUNCTION public.sigo_guard_bipagens_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path=''
AS $append$
BEGIN RAISE EXCEPTION 'Bipagens são append-only'; END;
$append$;
DROP TRIGGER IF EXISTS bipagens_append_only ON public.bipagens;
CREATE TRIGGER bipagens_append_only BEFORE UPDATE OR DELETE ON public.bipagens
  FOR EACH ROW EXECUTE FUNCTION public.sigo_guard_bipagens_append_only();

CREATE OR REPLACE FUNCTION public.sigo_bipar_canhoto(
  p_codigo text,p_dispositivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $scan$
DECLARE
  v_usuario uuid := (SELECT auth.uid());
  v_norm text := public.sigo_normalizar_codigo_canhoto(p_codigo);
  v_numero text;v_serie text;v_nf public.notas_fiscais%ROWTYPE;
  v_p public.prestacoes%ROWTYPE;
  v_vinculo public.prestacao_notas%ROWTYPE;
  v_exec record;v_origem record;v_usuario_anterior text;
  v_nf_cont integer;v_resultado text;v_detalhe text;
  v_anterior jsonb;v_exec_json jsonb;v_origem_json jsonb;
  v_nf_json jsonb;v_p_json jsonb;v_progresso jsonb;
  v_now timestamptz;v_prestacao_id uuid;v_nf_id uuid;
BEGIN
  IF v_usuario IS NULL OR NOT (SELECT public.sigo_is_active()) THEN
    RAISE EXCEPTION 'Usuário sem acesso ativo ao SIGO';
  END IF;
  <<processar>>
  BEGIN
  v_resultado:='CODIGO_INVALIDO';
  IF v_norm IS NULL THEN
    v_detalhe:='FORMATO_INVALIDO';
    EXIT processar;
  END IF;
  IF length(v_norm)=44 THEN
    v_numero:=substr(v_norm,26,9);
    v_serie:=(substr(v_norm,23,3)::integer)::text;
    -- Pelo número/série, não pela chave ainda ausente no StopView.
    SELECT count(*) INTO v_nf_cont FROM public.notas_fiscais
      WHERE numero=v_numero AND serie=v_serie;
    IF v_nf_cont=1 THEN
      SELECT * INTO v_nf FROM public.notas_fiscais
        WHERE numero=v_numero AND serie=v_serie FOR UPDATE;
    ELSIF v_nf_cont>1 THEN
      v_detalhe:='AMBIGUA';
    END IF;
  ELSE
    v_numero:=split_part(v_norm,'-',1);
    v_serie:=split_part(v_norm,'-',2);
    IF v_serie='?' THEN
      SELECT count(*) INTO v_nf_cont FROM public.notas_fiscais WHERE numero=v_numero;
      IF v_nf_cont=1 THEN
        SELECT * INTO v_nf FROM public.notas_fiscais WHERE numero=v_numero FOR UPDATE;
      ELSIF v_nf_cont>1 THEN
        v_detalhe:='AMBIGUA';
      END IF;
    ELSE
      SELECT count(*) INTO v_nf_cont FROM public.notas_fiscais
        WHERE numero=v_numero AND serie=v_serie;
      IF v_nf_cont=1 THEN
        SELECT * INTO v_nf FROM public.notas_fiscais
          WHERE numero=v_numero AND serie=v_serie FOR UPDATE;
      ELSIF v_nf_cont>1 THEN
        v_detalhe:='AMBIGUA';
      END IF;
    END IF;
  END IF;
  v_resultado:='NAO_ENCONTRADA';
  IF v_nf.id IS NULL THEN EXIT processar; END IF;
  v_nf_id:=v_nf.id;

  -- NF de abastecimento VUC nunca pode entrar na bipagem.
  IF v_nf.origem_rota_id IS NOT NULL AND EXISTS(
    SELECT 1 FROM public.rotas WHERE id=v_nf.origem_rota_id
      AND tipo_rota='ABASTECIMENTO') THEN
    v_detalhe:='ABASTECIMENTO';v_nf_id:=NULL;
    EXIT processar;
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.nf_execucoes e
    JOIN public.rotas r ON r.id=e.rota_id
    WHERE e.nf_id=v_nf.id AND r.tipo_rota='ABASTECIMENTO') THEN
    v_detalhe:='ABASTECIMENTO';v_nf_id:=NULL;
    EXIT processar;
  END IF;
  IF length(v_norm)=44 AND v_nf.chave_acesso IS NOT NULL
     AND v_nf.chave_acesso::text<>v_norm THEN
    v_detalhe:='CHAVE_DIVERGENTE';EXIT processar;
  END IF;
  SELECT * INTO v_p FROM public.prestacoes
    WHERE romaneio_oficial=v_nf.romaneio_origem FOR UPDATE;
  v_resultado:='SEM_PRESTACAO';
  IF v_p.id IS NULL THEN EXIT processar; END IF;
  v_prestacao_id:=v_p.id;
  v_resultado:='PRESTACAO_FECHADA';
  IF v_p.status IN ('ENVIADA_JTI','CONFIRMADA_JTI') THEN EXIT processar; END IF;

  -- Campo fiscal opcional que o StopView não possuía na primeira importação.
  -- Gravar uma vez, nunca reescrever ou trocar número/série/romaneio de origem.
  IF length(v_norm)=44 AND v_nf.chave_acesso IS NULL THEN
    UPDATE public.notas_fiscais SET chave_acesso=v_norm WHERE id=v_nf.id
      AND chave_acesso IS NULL;
    v_nf.chave_acesso:=v_norm;
  END IF;

  INSERT INTO public.prestacao_notas(prestacao_id,nf_id)
    VALUES (v_p.id,v_nf.id) ON CONFLICT(nf_id) DO NOTHING;
  SELECT * INTO v_vinculo FROM public.prestacao_notas
    WHERE nf_id=v_nf.id FOR UPDATE;
  IF v_vinculo.prestacao_id IS DISTINCT FROM v_p.id THEN
    v_resultado:='SEM_PRESTACAO';v_detalhe:='VINCULO_DIVERGENTE';EXIT processar;
  END IF;
  IF v_vinculo.canhoto_recebido_em IS NOT NULL THEN
    v_resultado:='JA_BIPADA';
    SELECT nome INTO v_usuario_anterior FROM public.profiles
      WHERE id=v_vinculo.canhoto_recebido_por;
    v_anterior:=jsonb_build_object('nome',v_usuario_anterior,
      'usuario_id',v_vinculo.canhoto_recebido_por,'em',v_vinculo.canhoto_recebido_em);
    EXIT processar;
  END IF;

  v_now:=clock_timestamp();
  UPDATE public.prestacao_notas
    SET canhoto_recebido_em=v_now,canhoto_recebido_por=v_usuario
    WHERE prestacao_id=v_p.id AND nf_id=v_nf.id;
  INSERT INTO public.nf_eventos(nf_id,tipo,usuario_id)
    VALUES (v_nf.id,'CANHOTO',v_usuario);

  SELECT e.rota_id,r.codigo,r.data_rota INTO v_exec
  FROM public.nf_execucoes e JOIN public.rotas r ON r.id=e.rota_id
  WHERE e.nf_id=v_nf.id AND r.tipo_rota='ENTREGA'
  ORDER BY e.iniciada_em DESC,e.id DESC LIMIT 1;
  IF v_exec.rota_id IS NOT NULL AND v_nf.origem_rota_id IS DISTINCT FROM v_exec.rota_id THEN
    v_resultado:='ROTA_DIFERENTE';
    v_exec_json:=jsonb_build_object('codigo',v_exec.codigo,'data',v_exec.data_rota);
  ELSE v_resultado:='OK'; END IF;

  IF v_p.status='ABERTA' THEN
    PERFORM id FROM public.sigo_avancar_prestacao(v_p.id,'RETORNADA');
    SELECT * INTO v_p FROM public.prestacoes WHERE id=v_p.id;
  END IF;

  END processar;
  -- Registrar TODA leitura autorizada, inclusive códigos inválidos/sem NF.
  INSERT INTO public.bipagens(
    codigo_lido,codigo_normalizado,resultado,nf_id,prestacao_id,
    rota_execucao_id,usuario_id,dispositivo)
  VALUES(coalesce(p_codigo,''),v_norm,v_resultado,v_nf_id,v_prestacao_id,
    CASE WHEN v_resultado='ROTA_DIFERENTE' THEN v_exec.rota_id ELSE NULL END,
    v_usuario,p_dispositivo);
  IF v_nf_id IS NOT NULL THEN
    v_nf_json:=jsonb_build_object('id',v_nf.id,'numero',v_nf.numero,
      'serie',v_nf.serie,'chave_acesso',v_nf.chave_acesso);
    SELECT r.codigo,r.data_rota INTO v_origem FROM public.rotas r
      WHERE r.id=v_nf.origem_rota_id;
    IF v_origem.codigo IS NOT NULL THEN
      v_origem_json:=jsonb_build_object('codigo',v_origem.codigo,'data',v_origem.data_rota);
    END IF;
  END IF;
  IF v_prestacao_id IS NOT NULL THEN
    SELECT * INTO v_p FROM public.prestacoes WHERE id=v_prestacao_id;
    v_p_json:=jsonb_build_object('id',v_p.id,
      'romaneio_oficial',v_p.romaneio_oficial,'d0',v_p.d0,'status',v_p.status);
    SELECT jsonb_build_object('total',total_nfs,'bipados',bipados,'faltantes',faltantes)
      INTO v_progresso FROM public.v_prestacao_progresso
      WHERE prestacao_id=v_prestacao_id;
  END IF;
  RETURN jsonb_build_object('resultado',v_resultado,'detalhe',v_detalhe,
    'nf',v_nf_json,'prestacao',v_p_json,'rota_origem',v_origem_json,
    'rota_execucao',v_exec_json,'bipada_anteriormente_por',v_anterior,
    'progresso',v_progresso);
END;
$scan$;


-- Hardening: gate de conferência sem alterar outras transições.
CREATE OR REPLACE FUNCTION public.sigo_avancar_prestacao(p_prestacao_id uuid, p_etapa text)
 RETURNS TABLE(id uuid, status text, registrado_em timestamp with time zone, registrado_por uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_usuario uuid := (select auth.uid()); v_faltantes integer;
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
    set status='RETORNADA', retornada_em=clock_timestamp()
  where p.id=p_prestacao_id and p.status='ABERTA' and p.retornada_em is null
  returning p.id,p.status,p.retornada_em,p.responsavel_id;
 else
  -- Conferência requer bipe ou justificativa para toda NF da origem fiscal.
  select count(*) into v_faltantes
  from (
    select pn.nf_id from public.prestacao_notas pn
      where pn.prestacao_id=p_prestacao_id
    union
    select nf.id from public.notas_fiscais nf
      join public.prestacoes p on p.romaneio_oficial=nf.romaneio_origem
      where p.id=p_prestacao_id
  ) todos
  left join public.prestacao_notas pn
    on pn.nf_id=todos.nf_id and pn.prestacao_id=p_prestacao_id
  left join public.prestacao_nota_justificativas j
    on j.nf_id=todos.nf_id and j.prestacao_id=p_prestacao_id
  where pn.canhoto_recebido_em is null and j.nf_id is null;
  if v_faltantes>0 then
    raise exception 'Prestação com % canhoto(s) sem bipagem nem justificativa',v_faltantes;
  end if;
  return query
  update public.prestacoes p
    set status='CONFERIDA', conferida_em=clock_timestamp(), conferida_por=v_usuario
  where p.id=p_prestacao_id and p.status='RETORNADA' and p.conferida_em is null
  returning p.id,p.status,p.conferida_em,p.conferida_por;
 end if;
 if not found then raise exception 'Prestação não encontrada ou etapa anterior não concluída'; end if;
end; $function$;


-- Privilégios explícitos das RPCs (não conceder INSERT direto em tabelas).
REVOKE ALL ON FUNCTION public.sigo_normalizar_codigo_canhoto(text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_normalizar_codigo_canhoto(text) TO authenticated;
REVOKE ALL ON FUNCTION public.sigo_bipar_canhoto(text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_bipar_canhoto(text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.sigo_canhotos_faltantes(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_canhotos_faltantes(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.sigo_justificar_faltante(uuid,uuid,text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_justificar_faltante(uuid,uuid,text,text)
  TO authenticated;
-- ==== END MIGRATION 20261117000100_sigo_bipagem_canhotos.sql ====

-- Validacoes obrigatorias de pre-commit. Qualquer exception faz ROLLBACK integral.
DO $sigo_deploy_validar$
DECLARE
  v_antes bigint;
  v_depois bigint;
  v_funcoes_ausentes text;
  v_view_sql text;
BEGIN
  v_antes := nullif(current_setting('sigo.deploy_prestacoes_antes', true),'')::bigint;
  IF v_antes IS NULL THEN RAISE EXCEPTION 'Snapshot inicial das prestações ausente'; END IF;

  SELECT string_agg(nome,', ' ORDER BY nome) INTO v_funcoes_ausentes
  FROM (
    VALUES
      ('sigo_bipar_canhoto',to_regprocedure('public.sigo_bipar_canhoto(text,text)')),
      ('sigo_importar_stopview',to_regprocedure('public.sigo_importar_stopview(uuid,jsonb)')),
      ('sigo_canhotos_faltantes',to_regprocedure('public.sigo_canhotos_faltantes(uuid)')),
      ('sigo_justificar_faltante',to_regprocedure('public.sigo_justificar_faltante(uuid,uuid,text,text)')),
      ('sigo_canhoto_auditoria',to_regprocedure('public.sigo_canhoto_auditoria()'))
  ) AS funcoes(nome,assinatura)
  WHERE assinatura IS NULL;
  IF v_funcoes_ausentes IS NOT NULL THEN
    RAISE EXCEPTION 'DEPLOY ABORTADO: funções obrigatórias ausentes: %',v_funcoes_ausentes;
  END IF;

  IF to_regclass('public.v_prestacoes_sla') IS NULL THEN
    RAISE EXCEPTION 'DEPLOY ABORTADO: v_prestacoes_sla ausente';
  END IF;
  v_view_sql := pg_get_viewdef('public.v_prestacoes_sla'::regclass,true);
  IF position('CURRENT_DATE' IN upper(v_view_sql))>0 THEN
    RAISE EXCEPTION 'DEPLOY ABORTADO: v_prestacoes_sla contém CURRENT_DATE';
  END IF;

  SELECT count(*) INTO v_depois FROM public.prestacoes;
  IF v_depois IS DISTINCT FROM v_antes THEN
    RAISE EXCEPTION 'DEPLOY ABORTADO: prestações alteradas (antes %, depois %)',v_antes,v_depois;
  END IF;

  RAISE NOTICE 'SIGO: verificações pré-COMMIT aprovadas; prestações preservadas: %',v_depois;
END;
$sigo_deploy_validar$;

COMMIT;
