-- Preparacao PR A: NAO APLICAR no Supabase hospedado nesta etapa.
CREATE SCHEMA IF NOT EXISTS sigo_interno;
REVOKE ALL ON SCHEMA sigo_interno FROM PUBLIC,anon,authenticated;
ALTER TABLE public.sla_config ADD COLUMN IF NOT EXISTS prazo_reentrega_dias integer NOT NULL DEFAULT 2 CHECK(prazo_reentrega_dias>0 AND prazo_reentrega_dias<=30);
ALTER TABLE public.sla_config ADD COLUMN IF NOT EXISTS status_gm_entregue text[] NOT NULL DEFAULT '{}';

CREATE TABLE public.motivos_reentrega(
 codigo text PRIMARY KEY,descricao text NOT NULL,
 responsabilidade text NOT NULL CHECK(responsabilidade IN ('OPERACAO','CLIENTE')),
 ativo boolean NOT NULL DEFAULT true
);
INSERT INTO public.motivos_reentrega(codigo,descricao,responsabilidade) VALUES
 ('TEMPO_EXCEDIDO','Tempo excedido','OPERACAO'),('FORA_HORARIO','Fora de horario','OPERACAO'),
 ('INVERSAO','Inversao','OPERACAO'),('AVARIA','Avaria','OPERACAO'),
 ('PDV_FECHADO','PDV fechado','CLIENTE'),('RESPONSAVEL_AUSENTE','Responsavel ausente','CLIENTE'),
 ('CANCELAMENTO_TARDIO','Cancelamento tardio','CLIENTE'),('PAGAMENTO_ERRADO','Forma de pagamento errada','CLIENTE')
 ON CONFLICT(codigo) DO NOTHING;
CREATE TABLE public.nf_reentregas(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),nf_id uuid NOT NULL REFERENCES public.notas_fiscais(id),
 prestacao_origem_id uuid NOT NULL REFERENCES public.prestacoes(id),tentativa integer NOT NULL CHECK(tentativa>0),
 motivo text NOT NULL REFERENCES public.motivos_reentrega(codigo),observacao text,
 responsabilidade text NOT NULL CHECK(responsabilidade IN ('OPERACAO','CLIENTE')),
 rota_falha_id uuid NOT NULL REFERENCES public.rotas(id),motorista_falha text,
 status text NOT NULL CHECK(status IN ('AGUARDANDO','EM_ROTA','FALHOU','ENTREGUE','DEVOLUCAO_PENDENTE','DEVOLVIDA')),
 pendencia_iniciada_em timestamptz NOT NULL,
 registrada_por uuid NOT NULL REFERENCES auth.users(id) DEFAULT auth.uid(),registrada_em timestamptz NOT NULL DEFAULT now(),
 rota_reentrega_id uuid REFERENCES public.rotas(id),carregada_em timestamptz,
 encerrada_em timestamptz,encerrada_por uuid REFERENCES auth.users(id),
 UNIQUE(nf_id,tentativa),
 CHECK((encerrada_em IS NULL)=(encerrada_por IS NULL)),
 CHECK((status IN ('FALHOU','ENTREGUE','DEVOLVIDA'))=(encerrada_em IS NOT NULL AND encerrada_por IS NOT NULL)),
 CHECK(status<>'EM_ROTA' OR (rota_reentrega_id IS NOT NULL AND carregada_em IS NOT NULL))
);
CREATE UNIQUE INDEX nf_reentrega_aberta_idx ON public.nf_reentregas(nf_id) WHERE status IN ('AGUARDANDO','EM_ROTA','DEVOLUCAO_PENDENTE');
CREATE INDEX nf_reentrega_fila_idx ON public.nf_reentregas(status,pendencia_iniciada_em);
CREATE TABLE public.nf_transferencias(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),nf_id uuid NOT NULL REFERENCES public.notas_fiscais(id),
 prestacao_origem_id uuid NOT NULL REFERENCES public.prestacoes(id),
 rota_origem_id uuid NOT NULL REFERENCES public.rotas(id),rota_destino_id uuid NOT NULL REFERENCES public.rotas(id),
 romaneio_destino text NOT NULL CHECK(romaneio_destino~'^[0-9]{12}$'),
 motivo text NOT NULL CHECK(motivo IN ('ROTA_MAIS_PROXIMA','REBALANCEAMENTO','VEICULO_INDISPONIVEL','MOTORISTA_AUSENTE','OUTRO')),
 observacao text,transferida_por uuid NOT NULL REFERENCES auth.users(id) DEFAULT auth.uid(),
 transferida_em timestamptz NOT NULL DEFAULT clock_timestamp(),
 conferencia_gm text NOT NULL DEFAULT 'PENDENTE' CHECK(conferencia_gm IN ('PENDENTE','CONFIRMADA','DIVERGENTE')),
 conferida_gm_em timestamptz,importacao_conferencia_id uuid REFERENCES public.gm_importacoes(id),
 CHECK(rota_origem_id<>rota_destino_id),CHECK(motivo<>'OUTRO' OR nullif(btrim(observacao),'') IS NOT NULL)
);
CREATE INDEX nf_transferencia_ultima_idx ON public.nf_transferencias(nf_id,transferida_em DESC,id DESC);
-- Multiplas passagens pela mesma rota sao historico, nao duplicata. Mantem uma unica execucao ABERTA por NF.
DROP INDEX public.nf_execucoes_nf_rota_unica_idx;
CREATE INDEX nf_execucoes_historico_rota_idx ON public.nf_execucoes(nf_id,rota_id,iniciada_em DESC);
ALTER TABLE public.pendencias_importacao ADD COLUMN IF NOT EXISTS nf_id uuid REFERENCES public.notas_fiscais(id);
ALTER TABLE public.pendencias_importacao DROP CONSTRAINT pendencias_importacao_motivo_check;
ALTER TABLE public.pendencias_importacao ADD CONSTRAINT pendencias_importacao_motivo_check CHECK(motivo IN
 ('SEM_NF','TRANSFERENCIA','SERIE_AMBIGUA','SERIE_ASSUMIDA','NF_INVALIDA','REENTREGA_SEM_ORIGEM','MOVIMENTACAO_SEM_REGISTRO'));
CREATE UNIQUE INDEX pendencia_movimento_nf_import_idx ON public.pendencias_importacao(importacao_id,nf_id,motivo) WHERE motivo='MOVIMENTACAO_SEM_REGISTRO';

ALTER TABLE public.motivos_reentrega ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nf_reentregas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nf_transferencias ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.motivos_reentrega,public.nf_reentregas,public.nf_transferencias FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.motivos_reentrega,public.nf_reentregas,public.nf_transferencias TO authenticated;
GRANT INSERT,UPDATE ON public.motivos_reentrega TO authenticated;
CREATE POLICY motivos_read ON public.motivos_reentrega FOR SELECT TO authenticated USING((SELECT public.sigo_is_active()));
CREATE POLICY motivos_insert ON public.motivos_reentrega FOR INSERT TO authenticated WITH CHECK((SELECT public.sigo_is_active()) AND (SELECT public.sigo_has_role('admin')));
CREATE POLICY motivos_update ON public.motivos_reentrega FOR UPDATE TO authenticated USING((SELECT public.sigo_is_active()) AND (SELECT public.sigo_has_role('admin'))) WITH CHECK((SELECT public.sigo_is_active()) AND (SELECT public.sigo_has_role('admin')));
CREATE POLICY reentregas_read ON public.nf_reentregas FOR SELECT TO authenticated USING((SELECT public.sigo_is_active()));
CREATE POLICY transferencias_read ON public.nf_transferencias FOR SELECT TO authenticated USING((SELECT public.sigo_is_active()));

CREATE FUNCTION sigo_interno.exigir_operador() RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE u uuid:=(SELECT auth.uid());
BEGIN IF u IS NULL OR NOT (SELECT public.sigo_is_active()) THEN RAISE EXCEPTION 'Usuário sem acesso ativo ao SIGO'; END IF; RETURN u; END; $$;

CREATE FUNCTION sigo_interno.localizar_nf(codigo text) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE norm text:=public.sigo_normalizar_codigo_canhoto(codigo); n text;s text;qt integer;nf public.notas_fiscais%ROWTYPE;
BEGIN
 PERFORM sigo_interno.exigir_operador();
 IF norm IS NULL THEN RETURN jsonb_build_object('resultado','CODIGO_INVALIDO','detalhe','FORMATO_INVALIDO'); END IF;
 IF length(norm)=44 THEN n:=substr(norm,26,9);s:=(substr(norm,23,3)::integer)::text;
 ELSE n:=split_part(norm,'-',1);s:=nullif(split_part(norm,'-',2),'?'); END IF;
 SELECT count(*) INTO qt FROM public.notas_fiscais f WHERE f.numero=n AND (s IS NULL OR f.serie=s);
 IF qt<>1 THEN RETURN jsonb_build_object('resultado','NAO_ENCONTRADA','detalhe',CASE WHEN qt>1 THEN 'AMBIGUA' END); END IF;
 SELECT * INTO STRICT nf FROM public.notas_fiscais f WHERE f.numero=n AND (s IS NULL OR f.serie=s) FOR UPDATE;
 IF length(norm)=44 AND nf.chave_acesso IS NOT NULL AND nf.chave_acesso::text<>norm THEN RETURN jsonb_build_object('resultado','NAO_ENCONTRADA','detalhe','CHAVE_DIVERGENTE'); END IF;
 IF EXISTS(SELECT 1 FROM public.rotas r WHERE r.id=nf.origem_rota_id AND r.tipo_rota='ABASTECIMENTO') OR EXISTS(SELECT 1 FROM public.nf_execucoes e JOIN public.rotas r ON r.id=e.rota_id WHERE e.nf_id=nf.id AND r.tipo_rota='ABASTECIMENTO') THEN RETURN jsonb_build_object('resultado','NAO_ENCONTRADA','detalhe','ABASTECIMENTO'); END IF;
 RETURN jsonb_build_object('resultado','LOCALIZADA','nf_id',nf.id,'nf',jsonb_build_object('id',nf.id,'numero',nf.numero,'serie',nf.serie));
END; $$;

CREATE FUNCTION sigo_interno.mover_execucao(p_nf uuid,p_rota uuid,p_tipo text,p_usuario uuid) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 PERFORM id FROM public.notas_fiscais WHERE id=p_nf FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.nf_execucoes WHERE nf_id=p_nf AND rota_id=p_rota AND encerrada_em IS NULL) THEN RETURN; END IF;
 UPDATE public.nf_execucoes SET encerrada_em=clock_timestamp() WHERE nf_id=p_nf AND encerrada_em IS NULL;
 INSERT INTO public.nf_execucoes(nf_id,rota_id,tipo,registrada_por) VALUES(p_nf,p_rota,p_tipo,p_usuario);
END; $$;

CREATE OR REPLACE FUNCTION sigo_interno.bipar_canhoto_base(p_codigo text, p_dispositivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_usuario uuid := (SELECT auth.uid());
  v_localizacao jsonb;
  v_norm text := public.sigo_normalizar_codigo_canhoto(p_codigo);
  v_numero text;v_serie text;v_nf public.notas_fiscais%ROWTYPE;
  v_p public.prestacoes%ROWTYPE;
  v_vinculo public.prestacao_notas%ROWTYPE;
  v_exec_rota_id uuid;v_exec_codigo text;v_exec_data date;
  v_origem_codigo text;v_origem_data date;v_usuario_anterior text;
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
  v_localizacao:=sigo_interno.localizar_nf(p_codigo);
  IF v_localizacao->>'resultado'<>'LOCALIZADA' THEN
    v_resultado:=v_localizacao->>'resultado';v_detalhe:=v_localizacao->>'detalhe';
    EXIT processar;
  END IF;
  SELECT * INTO STRICT v_nf FROM public.notas_fiscais WHERE id=(v_localizacao->>'nf_id')::uuid FOR UPDATE;
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

  SELECT e.rota_id,r.codigo,r.data_rota INTO v_exec_rota_id,v_exec_codigo,v_exec_data
  FROM public.nf_execucoes e JOIN public.rotas r ON r.id=e.rota_id
  WHERE e.nf_id=v_nf.id AND r.tipo_rota='ENTREGA'
  ORDER BY e.iniciada_em DESC,e.id DESC LIMIT 1;
  IF v_exec_rota_id IS NOT NULL AND v_nf.origem_rota_id IS DISTINCT FROM v_exec_rota_id THEN
    v_resultado:='ROTA_DIFERENTE';
    v_exec_json:=jsonb_build_object('codigo',v_exec_codigo,'data',v_exec_data);
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
    CASE WHEN v_resultado='ROTA_DIFERENTE' THEN v_exec_rota_id ELSE NULL END,
    v_usuario,p_dispositivo);
  IF v_nf_id IS NOT NULL THEN
    v_nf_json:=jsonb_build_object('id',v_nf.id,'numero',v_nf.numero,
      'serie',v_nf.serie,'chave_acesso',v_nf.chave_acesso);
    SELECT r.codigo,r.data_rota INTO v_origem_codigo,v_origem_data FROM public.rotas r
      WHERE r.id=v_nf.origem_rota_id;
    IF v_origem_codigo IS NOT NULL THEN
      v_origem_json:=jsonb_build_object('codigo',v_origem_codigo,'data',v_origem_data);
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
$function$;

CREATE OR REPLACE FUNCTION sigo_interno.importar_stopview_base(p_importacao_id uuid, p_linhas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_reentrega boolean;
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
    IF btrim(coalesce(v_linha->>'Descrição da rota','')) !~ '^[0-9]{1,12}$'
       AND btrim(coalesce(v_linha->>'Descrição da rota','')) !~* '^([1-9])[,.]\1{1,10}e[+]?11$' THEN
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
    v_oficial := NOT v_vt AND v_rom ~ '^[0-9]{12}$' AND v_rom !~ '^(.)\1{11}$' AND v_rom NOT LIKE '6000000000%';
    INSERT INTO public.rotas (data_rota,codigo,romaneio_gm,descricao_gm,tipo_romaneio,
      tipo_rota,motorista_gm,importacao_id)
    VALUES (v_data,v_cod,CASE WHEN v_rom ~ '^[0-9]{12}$' THEN v_rom ELSE NULL END,v_rom,
      CASE WHEN v_oficial THEN 'OFICIAL' ELSE 'AUXILIAR' END,
      CASE WHEN v_vt THEN 'ABASTECIMENTO' ELSE 'ENTREGA' END,
      NULLIF(btrim(coalesce(v_linha->>'Motoristas',v_linha->>'Motorista',v_linha->>'routeView.primaryDriver.name','')),''),
      p_importacao_id)
    ON CONFLICT (data_rota,codigo) DO NOTHING;
    SELECT id INTO STRICT v_rota_id FROM public.rotas
      WHERE data_rota=v_data AND codigo=v_cod;
    IF EXISTS(SELECT 1 FROM public.rotas WHERE id=v_rota_id
      AND coalesce(descricao_gm,romaneio_gm) IS DISTINCT FROM v_rom) THEN
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
    ORDER BY CASE WHEN btrim(a.value->>'Descrição da rota') ~ '^[0-9]{12}$' THEN 0 ELSE 1 END, a.ordinality
  LOOP
    v_cod := btrim(v_linha->>'Código da rota');
    v_rom := btrim(v_linha->>'Descrição da rota');
    v_data := (v_linha->>'Data da Rota')::date;
    v_id_parada := (v_linha->>'id')::bigint;
    v_valor := btrim(coalesce(v_linha->>'stop.orders.number',''));
    v_vt := upper(v_cod) ~ '(^|[-_])VT($|[-_A-Z0-9])' OR upper(v_cod) ~ '^SP-[0-9]+VT[A-Z0-9]*$';
    v_reentrega := v_rom !~ '^[0-9]{12}$';
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
    -- Reentrega sem origem conhecida fica pendente, sem criar NF nem romaneio artificial.
    IF v_reentrega AND (v_nf_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.notas_fiscais nf WHERE nf.id=v_nf_id
      AND nf.romaneio_origem IS NOT NULL AND nf.origem_rota_id IS NOT NULL
    )) THEN
      INSERT INTO public.pendencias_importacao
        (importacao_id,linha,codigo_rota,parada_id,valor_bruto,motivo,observacao)
      VALUES (p_importacao_id,v_ord,v_cod,v_id_parada,v_valor,'REENTREGA_SEM_ORIGEM',
        'Identificacao operacional: '||v_rom||'. Importar a carga de origem antes de vincular a NF.')
      ON CONFLICT (importacao_id,linha) DO NOTHING;
      v_pendencias := v_pendencias+1;
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
      WHERE nf_id=v_nf_id AND rota_id=v_rota_id AND encerrada_em IS NULL
    ) THEN
      UPDATE public.nf_execucoes
        SET encerrada_em=clock_timestamp()
      WHERE nf_id=v_nf_id AND rota_id IS DISTINCT FROM v_rota_id
        AND encerrada_em IS NULL;
    END IF;
    INSERT INTO public.nf_execucoes(nf_id,rota_id,tipo,registrada_por)
    SELECT v_nf_id,v_rota_id,v_tipo_execucao,v_usuario
    WHERE NOT EXISTS(SELECT 1 FROM public.nf_execucoes WHERE nf_id=v_nf_id AND rota_id=v_rota_id AND encerrada_em IS NULL)
    ON CONFLICT DO NOTHING;
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
$function$;

CREATE OR REPLACE FUNCTION sigo_interno.canhotos_faltantes_base(p_prestacao_id uuid)
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


CREATE FUNCTION public.sigo_registrar_reentrega(p_codigo text,p_motivo text,p_observacao text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();res jsonb;nf public.notas_fiscais%ROWTYPE;p public.prestacoes%ROWTYPE;
 anterior public.nf_reentregas%ROWTYPE;m public.motivos_reentrega%ROWTYPE;rota public.rotas%ROWTYPE;
 nova public.nf_reentregas%ROWTYPE;numero_tentativa integer;inicio timestamptz;
BEGIN
 res:=sigo_interno.localizar_nf(p_codigo);IF res->>'resultado'<>'LOCALIZADA' THEN RETURN res; END IF;
 SELECT * INTO STRICT nf FROM public.notas_fiscais WHERE id=(res->>'nf_id')::uuid;
 IF EXISTS(SELECT 1 FROM public.prestacao_notas WHERE nf_id=nf.id AND canhoto_recebido_em IS NOT NULL) THEN RETURN res||jsonb_build_object('resultado','JA_ENTREGUE'); END IF;
 SELECT * INTO m FROM public.motivos_reentrega WHERE codigo=p_motivo AND ativo;
 IF NOT FOUND THEN RETURN res||jsonb_build_object('resultado','MOTIVO_INVALIDO'); END IF;
 SELECT * INTO p FROM public.prestacoes WHERE romaneio_oficial=nf.romaneio_origem;
 IF p.id IS NULL THEN RETURN res||jsonb_build_object('resultado','SEM_PRESTACAO'); END IF;
 IF p.status IN ('ENVIADA_JTI','CONFIRMADA_JTI') THEN RETURN res||jsonb_build_object('resultado','PRESTACAO_FECHADA'); END IF;
 SELECT * INTO anterior FROM public.nf_reentregas WHERE nf_id=nf.id AND status IN ('AGUARDANDO','EM_ROTA','DEVOLUCAO_PENDENTE') FOR UPDATE;
 IF anterior.status='AGUARDANDO' THEN RETURN res||jsonb_build_object('resultado','JA_EM_REENTREGA','tentativa',anterior.tentativa,'status',anterior.status); END IF;
 IF anterior.status='DEVOLUCAO_PENDENTE' THEN RETURN res||jsonb_build_object('resultado','JA_EM_DEVOLUCAO'); END IF;
 SELECT r.* INTO rota FROM public.nf_execucoes e JOIN public.rotas r ON r.id=e.rota_id WHERE e.nf_id=nf.id AND e.encerrada_em IS NULL;
 IF rota.id IS NULL THEN SELECT * INTO rota FROM public.rotas WHERE id=nf.origem_rota_id; END IF;
 IF rota.id IS NULL OR rota.tipo_rota='ABASTECIMENTO' THEN RETURN res||jsonb_build_object('resultado','ROTA_INVALIDA'); END IF;
 IF anterior.id IS NOT NULL THEN
   IF anterior.status<>'EM_ROTA' OR anterior.rota_reentrega_id IS DISTINCT FROM rota.id THEN RETURN res||jsonb_build_object('resultado','SAIDA_NAO_CONFIRMADA'); END IF;
   inicio:=anterior.pendencia_iniciada_em;
   UPDATE public.nf_reentregas SET status='FALHOU',encerrada_em=clock_timestamp(),encerrada_por=u WHERE id=anterior.id;
 ELSE inicio:=clock_timestamp(); END IF;
 SELECT coalesce(max(tentativa),0)+1 INTO numero_tentativa FROM public.nf_reentregas WHERE nf_id=nf.id;
 IF NOT EXISTS(SELECT 1 FROM public.prestacao_nota_justificativas WHERE prestacao_id=p.id AND nf_id=nf.id) THEN
   IF p.status NOT IN ('ABERTA','RETORNADA') THEN RAISE EXCEPTION 'Prestacao nao permite nova justificativa de reentrega'; END IF;
   PERFORM public.sigo_justificar_faltante(p.id,nf.id,'REENTREGA_PROGRAMADA','Reentrega: '||m.descricao);
 END IF;
 INSERT INTO public.nf_reentregas(nf_id,prestacao_origem_id,tentativa,motivo,observacao,responsabilidade,rota_falha_id,motorista_falha,status,pendencia_iniciada_em,registrada_por)
 VALUES(nf.id,p.id,numero_tentativa,m.codigo,nullif(btrim(p_observacao),''),m.responsabilidade,rota.id,rota.motorista_gm,'AGUARDANDO',inicio,u) RETURNING * INTO nova;
 INSERT INTO public.nf_eventos(nf_id,tipo,motivo,usuario_id) VALUES(nf.id,'RETORNO','REENTREGA',u);
 RETURN res||jsonb_build_object('resultado','REENTREGA_REGISTRADA','reentrega_id',nova.id,'prestacao_origem',jsonb_build_object('id',p.id,'romaneio_oficial',p.romaneio_oficial),'tentativa',nova.tentativa,'status',nova.status,'motivo',m.codigo,'responsabilidade',nova.responsabilidade,'pendencia_iniciada_em',inicio,'motorista',rota.motorista_gm,'rota',rota.codigo);
END; $$;

CREATE FUNCTION public.sigo_transferir_nf(p_codigo text,p_romaneio_destino text,p_motivo text,p_observacao text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();res jsonb;nf public.notas_fiscais%ROWTYPE;p public.prestacoes%ROWTYPE;
 origem public.rotas%ROWTYPE;destino public.rotas%ROWTYPE;qt integer;transferencia uuid;
BEGIN
 res:=sigo_interno.localizar_nf(p_codigo);IF res->>'resultado'<>'LOCALIZADA' THEN RETURN res; END IF;
 SELECT * INTO STRICT nf FROM public.notas_fiscais WHERE id=(res->>'nf_id')::uuid;
 IF EXISTS(SELECT 1 FROM public.prestacao_notas WHERE nf_id=nf.id AND canhoto_recebido_em IS NOT NULL) THEN RETURN res||jsonb_build_object('resultado','JA_ENTREGUE'); END IF;
 IF p_motivo IS NULL OR p_motivo NOT IN ('ROTA_MAIS_PROXIMA','REBALANCEAMENTO','VEICULO_INDISPONIVEL','MOTORISTA_AUSENTE','OUTRO') OR (p_motivo='OUTRO' AND nullif(btrim(p_observacao),'') IS NULL) THEN RETURN res||jsonb_build_object('resultado','MOTIVO_INVALIDO'); END IF;
 IF EXISTS(SELECT 1 FROM public.nf_reentregas WHERE nf_id=nf.id AND status IN ('AGUARDANDO','DEVOLUCAO_PENDENTE')) THEN RETURN res||jsonb_build_object('resultado','NF_AGUARDANDO_REENTREGA'); END IF;
 SELECT * INTO p FROM public.prestacoes WHERE romaneio_oficial=nf.romaneio_origem;
 IF p.id IS NULL THEN RETURN res||jsonb_build_object('resultado','SEM_PRESTACAO'); END IF;
 IF p.status IN ('ENVIADA_JTI','CONFIRMADA_JTI') THEN RETURN res||jsonb_build_object('resultado','PRESTACAO_FECHADA'); END IF;
 SELECT r.* INTO origem FROM public.nf_execucoes e JOIN public.rotas r ON r.id=e.rota_id WHERE e.nf_id=nf.id AND e.encerrada_em IS NULL;
 IF origem.id IS NULL THEN SELECT * INTO origem FROM public.rotas WHERE id=nf.origem_rota_id; END IF;
 IF origem.id IS NULL THEN RETURN res||jsonb_build_object('resultado','ROTA_INVALIDA'); END IF;
 SELECT count(*) INTO qt FROM public.rotas WHERE romaneio_gm=btrim(p_romaneio_destino);
 IF qt<>1 THEN RETURN res||jsonb_build_object('resultado',CASE WHEN qt=0 THEN 'DESTINO_INEXISTENTE' ELSE 'DESTINO_AMBIGUO' END); END IF;
 SELECT * INTO STRICT destino FROM public.rotas WHERE romaneio_gm=btrim(p_romaneio_destino);
 IF destino.tipo_rota='ABASTECIMENTO' THEN RETURN res||jsonb_build_object('resultado','DESTINO_ABASTECIMENTO'); END IF;
 IF destino.id=origem.id THEN RETURN res||jsonb_build_object('resultado','MESMA_ROTA'); END IF;
 IF destino.data_rota<>origem.data_rota THEN RETURN res||jsonb_build_object('resultado','DATA_DIFERENTE'); END IF;
 PERFORM sigo_interno.mover_execucao(nf.id,destino.id,'TRANSFERENCIA',u);
 INSERT INTO public.nf_transferencias(nf_id,prestacao_origem_id,rota_origem_id,rota_destino_id,romaneio_destino,motivo,observacao,transferida_por)
 VALUES(nf.id,p.id,origem.id,destino.id,destino.romaneio_gm,p_motivo,nullif(btrim(p_observacao),''),u) RETURNING id INTO transferencia;
 INSERT INTO public.nf_eventos(nf_id,tipo,motivo,rota_destino_id,usuario_id) VALUES(nf.id,'TRANSFERENCIA',CASE WHEN p_motivo='REBALANCEAMENTO' THEN 'REBALANCEAMENTO' ELSE 'OUTRO_PADRONIZADO' END,destino.id,u);
 RETURN res||jsonb_build_object('resultado','TRANSFERIDA','transferencia_id',transferencia,'origem',jsonb_build_object('romaneio',p.romaneio_oficial,'rota',origem.codigo,'motorista',origem.motorista_gm),'destino',jsonb_build_object('romaneio',destino.romaneio_gm,'rota',destino.codigo,'motorista',destino.motorista_gm,'veiculo',destino.veiculo));
END; $$;

CREATE FUNCTION public.sigo_solicitar_devolucao(p_reentrega_id uuid,p_observacao text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();r public.nf_reentregas%ROWTYPE;
BEGIN
 SELECT * INTO STRICT r FROM public.nf_reentregas WHERE id=p_reentrega_id;
 PERFORM id FROM public.notas_fiscais WHERE id=r.nf_id FOR UPDATE;
 SELECT * INTO STRICT r FROM public.nf_reentregas WHERE id=p_reentrega_id FOR UPDATE;
 IF r.status='DEVOLUCAO_PENDENTE' THEN RETURN jsonb_build_object('resultado','JA_EM_DEVOLUCAO'); END IF;
 IF r.status NOT IN ('AGUARDANDO','EM_ROTA') OR nullif(btrim(p_observacao),'') IS NULL THEN RAISE EXCEPTION 'Estado ou observacao de devolucao invalido'; END IF;
 IF EXISTS(SELECT 1 FROM public.prestacao_notas WHERE nf_id=r.nf_id AND canhoto_recebido_em IS NOT NULL) THEN RAISE EXCEPTION 'NF ja recebida'; END IF;
 UPDATE public.nf_reentregas SET status='DEVOLUCAO_PENDENTE',observacao=concat_ws(E'\n',observacao,'Devolucao solicitada: '||p_observacao) WHERE id=r.id;
 INSERT INTO public.nf_eventos(nf_id,tipo,motivo,usuario_id) VALUES(r.nf_id,'RETORNO','DEVOLUCAO',u);
 RETURN jsonb_build_object('resultado','DEVOLUCAO_PENDENTE','reentrega_id',r.id);
END; $$;
CREATE FUNCTION public.sigo_encerrar_devolucao(p_reentrega_id uuid,p_observacao text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();r public.nf_reentregas%ROWTYPE;
BEGIN
 SELECT * INTO STRICT r FROM public.nf_reentregas WHERE id=p_reentrega_id;
 PERFORM id FROM public.notas_fiscais WHERE id=r.nf_id FOR UPDATE;
 SELECT * INTO STRICT r FROM public.nf_reentregas WHERE id=p_reentrega_id FOR UPDATE;
 IF r.status='DEVOLVIDA' THEN RETURN jsonb_build_object('resultado','JA_DEVOLVIDA'); END IF;
 IF r.status<>'DEVOLUCAO_PENDENTE' OR nullif(btrim(p_observacao),'') IS NULL THEN RAISE EXCEPTION 'Estado ou observacao de devolucao invalido'; END IF;
 UPDATE public.nf_reentregas SET status='DEVOLVIDA',encerrada_em=clock_timestamp(),encerrada_por=u,observacao=concat_ws(E'\n',observacao,'Devolvida: '||p_observacao) WHERE id=r.id;
 INSERT INTO public.nf_eventos(nf_id,tipo,motivo,usuario_id) VALUES(r.nf_id,'DEVOLUCAO','DEVOLUCAO',u);
 RETURN jsonb_build_object('resultado','DEVOLVIDA','reentrega_id',r.id);
END; $$;

CREATE FUNCTION sigo_interno.conciliar_movimentos(p_importacao uuid,p_linhas jsonb,p_antes jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();item record;re public.nf_reentregas%ROWTYPE;t public.nf_transferencias%ROWTYPE;
 destino uuid;anterior uuid;data_nova date;data_falha date;linha_nova integer:=jsonb_array_length(p_linhas);pendencias integer:=0;
BEGIN
 FOR item IN
 WITH linhas AS (
  SELECT l,ord,public.sigo_normalizar_codigo_canhoto(l->>'stop.orders.number') norm
  FROM jsonb_array_elements(p_linhas) WITH ORDINALITY x(l,ord)
  WHERE coalesce(l->>'stop.orders.number','') !~ '^[0-9]{1,2}$'
 ), correspondencias AS (
  SELECT nf.id nf_id,r.id rota_id,r.data_rota,linhas.ord FROM linhas
  JOIN public.rotas r ON r.codigo=btrim(l->>'Código da rota') AND r.data_rota=(l->>'Data da Rota')::date AND r.tipo_rota='ENTREGA'
  JOIN public.notas_fiscais nf ON nf.numero=CASE WHEN length(norm)=44 THEN substr(norm,26,9) ELSE split_part(norm,'-',1) END
   AND (CASE WHEN length(norm)=44 THEN nf.serie=(substr(norm,23,3)::integer)::text ELSE split_part(norm,'-',2)='?' OR nf.serie=split_part(norm,'-',2) END)
  WHERE norm IS NOT NULL AND (SELECT count(*) FROM public.notas_fiscais n2 WHERE n2.numero=nf.numero AND (length(norm)=44 AND n2.serie=nf.serie OR length(norm)<>44 AND (split_part(norm,'-',2)='?' OR n2.serie=split_part(norm,'-',2))))=1
 ) SELECT nf_id,array_agg(DISTINCT rota_id) rotas,max(data_rota) ultima_data,min(ord)::integer linha FROM correspondencias GROUP BY nf_id ORDER BY nf_id
 LOOP
  PERFORM id FROM public.notas_fiscais WHERE id=item.nf_id FOR UPDATE;
  anterior:=nullif(p_antes->>item.nf_id::text,'')::uuid;
  destino:=NULL;
  SELECT * INTO re FROM public.nf_reentregas WHERE nf_id=item.nf_id AND status IN ('AGUARDANDO','EM_ROTA','DEVOLUCAO_PENDENTE') FOR UPDATE;
  SELECT * INTO t FROM public.nf_transferencias WHERE nf_id=item.nf_id ORDER BY transferida_em DESC,id DESC LIMIT 1 FOR UPDATE;
  IF re.status='AGUARDANDO' THEN
    SELECT data_rota INTO data_falha FROM public.rotas WHERE id=re.rota_falha_id;
    SELECT count(*),(array_agg(r.id ORDER BY r.id))[1] INTO linha_nova,destino FROM public.rotas r WHERE r.id=ANY(item.rotas) AND r.data_rota>greatest(data_falha,(re.registrada_em AT TIME ZONE 'America/Sao_Paulo')::date);
    IF linha_nova=1 THEN
      UPDATE public.nf_reentregas SET status='EM_ROTA',rota_reentrega_id=destino,carregada_em=clock_timestamp() WHERE id=re.id;
      PERFORM sigo_interno.mover_execucao(item.nf_id,destino,'REENTREGA',u);
      CONTINUE;
    END IF;
    -- Reimportacao de carga antiga nao e nova saida nem deve substituir a rota em planejamento.
    IF anterior IS NOT NULL THEN PERFORM sigo_interno.mover_execucao(item.nf_id,anterior,'REENTREGA',u); END IF;
    CONTINUE;
  ELSIF re.status='EM_ROTA' THEN
    destino:=re.rota_reentrega_id;
    PERFORM sigo_interno.mover_execucao(item.nf_id,destino,'REENTREGA',u);
    CONTINUE;
  ELSIF re.status='DEVOLUCAO_PENDENTE' THEN
    IF anterior IS NOT NULL THEN PERFORM sigo_interno.mover_execucao(item.nf_id,anterior,'REENTREGA',u); END IF;
    CONTINUE;
  END IF;
  IF t.id IS NOT NULL AND item.ultima_data >= (t.transferida_em AT TIME ZONE 'America/Sao_Paulo')::date THEN
    IF t.rota_destino_id=ANY(item.rotas) THEN
      IF t.conferencia_gm<>'CONFIRMADA' THEN UPDATE public.nf_transferencias SET conferencia_gm='CONFIRMADA',conferida_gm_em=clock_timestamp(),importacao_conferencia_id=p_importacao WHERE id=t.id; END IF;
      PERFORM sigo_interno.mover_execucao(item.nf_id,t.rota_destino_id,'TRANSFERENCIA',u);
      CONTINUE;
    ELSIF t.conferencia_gm='PENDENTE' THEN
      UPDATE public.nf_transferencias SET conferencia_gm='DIVERGENTE',conferida_gm_em=clock_timestamp(),importacao_conferencia_id=p_importacao WHERE id=t.id;
      -- Divergencia nao reverte uma transferencia que o operador registrou.
      PERFORM sigo_interno.mover_execucao(item.nf_id,t.rota_destino_id,'TRANSFERENCIA',u);
      CONTINUE;
    END IF;
  END IF;
  IF cardinality(item.rotas)=1 THEN destino:=item.rotas[1]; END IF;
  IF anterior IS NOT NULL AND (destino IS NULL OR destino<>anterior) THEN
    SELECT data_rota INTO data_nova FROM public.rotas WHERE id=anterior;
    IF item.ultima_data>=data_nova THEN
      INSERT INTO public.pendencias_importacao(importacao_id,linha,codigo_rota,valor_bruto,motivo,nf_id,observacao)
      SELECT p_importacao,jsonb_array_length(p_linhas)+pendencias+1,coalesce(r.codigo,'MULTIPLAS_ROTAS'),nf.numero::text||'-'||nf.serie,'MOVIMENTACAO_SEM_REGISTRO',nf.id,'Linha original do StopView: '||item.linha
      FROM public.notas_fiscais nf LEFT JOIN public.rotas r ON r.id=destino WHERE nf.id=item.nf_id
      ON CONFLICT DO NOTHING;
      IF FOUND THEN pendencias:=pendencias+1; END IF;
    END IF;
  END IF;
 END LOOP;
 RETURN jsonb_build_object('pendencias_movimentacao',pendencias);
END; $$;

-- A funcao-base e gerada a partir da migration anterior, sem alterar o historico.
-- Sua persistencia e protegida por SHA e pelo wrapper abaixo.
CREATE OR REPLACE FUNCTION public.sigo_importar_stopview(p_importacao_id uuid,p_linhas jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();antes jsonb;resultado jsonb;conferencia jsonb;
BEGIN
 SELECT coalesce(jsonb_object_agg(nf_id::text,rota_id::text),'{}') INTO antes FROM public.nf_execucoes WHERE encerrada_em IS NULL;
 resultado:=sigo_interno.importar_stopview_base(p_importacao_id,p_linhas);
 IF resultado->>'status'='JA_IMPORTADO' THEN RETURN resultado; END IF;
 conferencia:=sigo_interno.conciliar_movimentos(p_importacao_id,p_linhas->'linhas',antes);
 RETURN resultado||conferencia;
END; $$;

CREATE OR REPLACE FUNCTION public.sigo_bipar_canhoto(p_codigo text,p_dispositivo text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();r jsonb;nf uuid;re public.nf_reentregas%ROWTYPE;t public.nf_transferencias%ROWTYPE;rota public.rotas%ROWTYPE;
BEGIN
 r:=sigo_interno.bipar_canhoto_base(p_codigo,p_dispositivo);
 nf:=(r->'nf'->>'id')::uuid;
 IF nf IS NULL THEN RETURN r; END IF;
 SELECT * INTO re FROM public.nf_reentregas WHERE nf_id=nf AND status IN ('AGUARDANDO','EM_ROTA') FOR UPDATE;
 IF r->>'resultado' IN ('OK','ROTA_DIFERENTE') AND re.id IS NOT NULL THEN
   UPDATE public.nf_reentregas SET status='ENTREGUE',encerrada_em=clock_timestamp(),encerrada_por=u WHERE id=re.id;
   r:=r||jsonb_build_object('resultado','OK_REENTREGA','tentativa',re.tentativa,'pendencia_iniciada_em',re.pendencia_iniciada_em);
 END IF;
 SELECT * INTO t FROM public.nf_transferencias WHERE nf_id=nf ORDER BY transferida_em DESC,id DESC LIMIT 1;
 IF t.id IS NOT NULL THEN
   SELECT * INTO STRICT rota FROM public.rotas WHERE id=t.rota_destino_id;
   r:=r||jsonb_build_object('transferencia',jsonb_build_object('romaneio',t.romaneio_destino,'rota',rota.codigo,'motorista',rota.motorista_gm),'rota_execucao',jsonb_build_object('codigo',rota.codigo,'data',rota.data_rota,'motorista',rota.motorista_gm));
   IF r->>'resultado'='OK' THEN r:=r||jsonb_build_object('resultado','ROTA_DIFERENTE'); END IF;
 END IF;
 SELECT rt.* INTO rota FROM public.notas_fiscais n JOIN public.rotas rt ON rt.id=n.origem_rota_id WHERE n.id=nf;
 r:=r||jsonb_build_object('rota_origem',jsonb_build_object('codigo',rota.codigo,'data',rota.data_rota,'motorista',rota.motorista_gm));
 RETURN r;
END; $$;

CREATE FUNCTION public.sigo_configurar_reentrega(p_prazo_dias integer,p_status_entregue text[]) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM sigo_interno.exigir_operador();
 IF NOT public.sigo_has_role('admin') THEN RAISE EXCEPTION 'Configuracao restrita ao administrador'; END IF;
 IF p_prazo_dias IS NULL OR p_prazo_dias NOT BETWEEN 1 AND 30 OR p_status_entregue IS NULL OR EXISTS(SELECT 1 FROM unnest(p_status_entregue) s WHERE s IS NULL OR nullif(btrim(s),'') IS NULL) THEN RAISE EXCEPTION 'Configuracao invalida'; END IF;
 UPDATE public.sla_config SET prazo_reentrega_dias=p_prazo_dias,status_gm_entregue=p_status_entregue WHERE id;
 RETURN jsonb_build_object('prazo_dias',p_prazo_dias,'status_gm_entregue',p_status_entregue);
END; $$;

CREATE VIEW public.v_nf_acompanhamento WITH(security_invoker=true) AS
SELECT nf.id nf_id,nf.numero::text numero,nf.serie,nf.romaneio_origem,p.id prestacao_id,p.status prestacao_status,
 origem.codigo rota_origem,origem.motorista_gm motorista_origem,atual.codigo rota_atual,atual.motorista_gm motorista_atual,atual.veiculo,
 pa.cliente,pa.status_gm,pn.canhoto_recebido_em,pn.canhoto_recebido_por,
 re.id reentrega_id,re.tentativa,re.motivo motivo_reentrega,re.responsabilidade,re.status status_reentrega,re.motorista_falha,
 re.pendencia_iniciada_em,re.pendencia_iniciada_em+cfg.prazo_reentrega_dias*interval '24 hours' vence_em,
 coalesce(re.status IN ('AGUARDANDO','EM_ROTA','DEVOLUCAO_PENDENTE') AND pn.canhoto_recebido_em IS NULL AND p.status NOT IN ('ENVIADA_JTI','CONFIRMADA_JTI')
   AND statement_timestamp()>re.pendencia_iniciada_em+cfg.prazo_reentrega_dias*interval '24 hours',false) atrasada,
 greatest(0,floor(extract(epoch FROM (statement_timestamp()-re.pendencia_iniciada_em))/86400))::integer dias_na_fila,
 tr.romaneio_destino,rd.codigo rota_destino,rd.motorista_gm motorista_destino,tr.conferencia_gm,
 j.motivo justificativa,
 CASE WHEN pn.canhoto_recebido_em IS NOT NULL THEN 'CANHOTO_RECEBIDO'
 WHEN re.status='DEVOLVIDA' THEN 'DEVOLVIDA'
 WHEN re.status='DEVOLUCAO_PENDENTE' THEN 'DEVOLUCAO_PENDENTE'
 WHEN pa.status_gm=ANY(cfg.status_gm_entregue) THEN 'ENTREGUE_AGUARDANDO_CANHOTO'
 WHEN re.status='AGUARDANDO' THEN 'AGUARDANDO_REENTREGA'
 WHEN re.status='EM_ROTA' THEN 'EM_REENTREGA'
 WHEN tr.id IS NOT NULL THEN 'TRANSFERIDA'
 WHEN j.nf_id IS NOT NULL THEN 'JUSTIFICADA' ELSE 'AGUARDANDO_CANHOTO' END situacao
FROM public.notas_fiscais nf
LEFT JOIN public.prestacoes p ON p.romaneio_oficial=nf.romaneio_origem
LEFT JOIN public.prestacao_notas pn ON pn.nf_id=nf.id AND pn.prestacao_id=p.id
LEFT JOIN public.rotas origem ON origem.id=nf.origem_rota_id
LEFT JOIN LATERAL(SELECT e.rota_id FROM public.nf_execucoes e WHERE e.nf_id=nf.id AND e.encerrada_em IS NULL ORDER BY e.iniciada_em DESC,e.id DESC LIMIT 1) ex ON true
LEFT JOIN public.rotas atual ON atual.id=coalesce(ex.rota_id,nf.origem_rota_id)
LEFT JOIN LATERAL(SELECT rr.* FROM public.nf_reentregas rr WHERE rr.nf_id=nf.id ORDER BY rr.tentativa DESC LIMIT 1) re ON true
LEFT JOIN LATERAL(SELECT t.* FROM public.nf_transferencias t WHERE t.nf_id=nf.id ORDER BY t.transferida_em DESC,t.id DESC LIMIT 1) tr ON true
LEFT JOIN public.rotas rd ON rd.id=tr.rota_destino_id
LEFT JOIN public.prestacao_nota_justificativas j ON j.nf_id=nf.id AND j.prestacao_id=p.id
LEFT JOIN LATERAL(SELECT par.cliente,par.status_gm FROM public.parada_notas pp JOIN public.paradas par ON par.id=pp.parada_id WHERE pp.nf_id=nf.id ORDER BY par.data_rota DESC,par.id DESC LIMIT 1) pa ON true
CROSS JOIN public.sla_config cfg WHERE cfg.id;

CREATE VIEW public.v_fila_reentrega WITH(security_invoker=true) AS
SELECT a.*,CASE WHEN dias_na_fila=0 THEN 'D0' WHEN dias_na_fila=1 THEN 'D+1' WHEN dias_na_fila=2 THEN 'D+2' ELSE 'D+3+' END faixa,
 CASE WHEN atrasada THEN 'ATRASADA' ELSE 'NO_PRAZO' END alerta_prestacao
FROM public.v_nf_acompanhamento a WHERE status_reentrega IN ('AGUARDANDO','EM_ROTA','DEVOLUCAO_PENDENTE') AND canhoto_recebido_em IS NULL;

CREATE VIEW public.v_transferencias_dia WITH(security_invoker=true) AS
SELECT t.id,t.nf_id,nf.numero::text numero,nf.serie,(t.transferida_em AT TIME ZONE 'America/Sao_Paulo')::date data,
 t.prestacao_origem_id,nf.romaneio_origem,ro.codigo rota_origem,ro.motorista_gm motorista_origem,
 t.romaneio_destino,rd.codigo rota_destino,rd.motorista_gm motorista_destino,rd.veiculo,t.motivo,t.observacao,
 t.transferida_por,t.transferida_em,t.conferencia_gm,t.conferida_gm_em,t.importacao_conferencia_id,
 (EXISTS(SELECT 1 FROM public.prestacao_notas pn WHERE pn.nf_id=t.nf_id AND pn.canhoto_recebido_em IS NOT NULL)
  AND NOT EXISTS(SELECT 1 FROM public.nf_reentregas re WHERE re.nf_id=t.nf_id)
  AND t.id=(SELECT x.id FROM public.nf_transferencias x WHERE x.nf_id=t.nf_id ORDER BY x.transferida_em DESC,x.id DESC LIMIT 1)) produtividade_positiva
FROM public.nf_transferencias t JOIN public.notas_fiscais nf ON nf.id=t.nf_id
JOIN public.rotas ro ON ro.id=t.rota_origem_id JOIN public.rotas rd ON rd.id=t.rota_destino_id;

CREATE VIEW public.v_reentrega_indicadores WITH(security_invoker=true) AS
WITH grupos AS (
 SELECT (re.registrada_em AT TIME ZONE 'America/Sao_Paulo')::date data,re.motivo,re.responsabilidade,re.motorista_falha,a.cliente,re.tentativa,
 count(*) quantidade,count(*) FILTER(WHERE re.status='ENTREGUE') entregues,
 count(*) FILTER(WHERE re.status IN ('FALHOU','ENTREGUE','DEVOLVIDA')) encerradas,
 count(*) FILTER(WHERE re.status IN ('DEVOLUCAO_PENDENTE','DEVOLVIDA')) devolucoes
 FROM public.nf_reentregas re JOIN public.v_nf_acompanhamento a ON a.nf_id=re.nf_id
 GROUP BY 1,2,3,4,5,6
)
SELECT g.*,round(100.0*entregues/nullif(encerradas,0),2) taxa_sucesso_tentativa,
 round(100.0*quantidade/nullif(sum(quantidade) OVER(PARTITION BY data,motivo,motorista_falha,cliente,tentativa),0),2) percentual_responsabilidade,
 0::bigint produtividade_positiva FROM grupos g;

CREATE VIEW public.v_divergencias_gm WITH(security_invoker=true) AS
SELECT 'TRANSFERENCIA_DIVERGENTE'::text tipo,t.id::text id,t.nf_id,t.prestacao_origem_id prestacao_id,t.importacao_conferencia_id importacao_id,t.conferida_gm_em registrada_em
FROM public.nf_transferencias t WHERE t.conferencia_gm='DIVERGENTE'
UNION ALL
SELECT pi.motivo,pi.importacao_id::text||':'||pi.linha,pi.nf_id,p.id,pi.importacao_id,gm.criado_em
FROM public.pendencias_importacao pi JOIN public.gm_importacoes gm ON gm.id=pi.importacao_id
LEFT JOIN public.notas_fiscais nf ON nf.id=pi.nf_id LEFT JOIN public.prestacoes p ON p.romaneio_oficial=nf.romaneio_origem
WHERE pi.motivo='MOVIMENTACAO_SEM_REGISTRO' AND pi.status='PENDENTE';

CREATE VIEW public.v_prestacoes_alertas_reentrega WITH(security_invoker=true) AS
SELECT prestacao_id,romaneio_origem,count(*) FILTER(WHERE atrasada) nfs_atrasadas,min(pendencia_iniciada_em) inicio_pendencia,min(vence_em) primeiro_vencimento
FROM public.v_fila_reentrega GROUP BY prestacao_id,romaneio_origem;

DROP FUNCTION public.sigo_canhotos_faltantes(uuid);
CREATE FUNCTION public.sigo_canhotos_faltantes(p_prestacao_id uuid)
RETURNS TABLE(nf_id uuid,numero text,serie text,cliente text,status_gm text,tipo_execucao text,justificativa text,
 situacao text,romaneio_destino text,rota_destino text,motorista text,pendencia_iniciada_em timestamptz,vence_em timestamptz,atrasada boolean,tentativa integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM sigo_interno.exigir_operador();
 RETURN QUERY SELECT f.nf_id,f.numero,f.serie,f.cliente,f.status_gm,f.tipo_execucao,f.justificativa,
 a.situacao,a.romaneio_destino,a.rota_destino,a.motorista_atual,a.pendencia_iniciada_em,a.vence_em,a.atrasada,a.tentativa
 FROM sigo_interno.canhotos_faltantes_base(p_prestacao_id) f LEFT JOIN public.v_nf_acompanhamento a ON a.nf_id=f.nf_id;
END; $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA sigo_interno FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.v_nf_acompanhamento,public.v_fila_reentrega,public.v_transferencias_dia,public.v_reentrega_indicadores,public.v_divergencias_gm,public.v_prestacoes_alertas_reentrega FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.v_nf_acompanhamento,public.v_fila_reentrega,public.v_transferencias_dia,public.v_reentrega_indicadores,public.v_divergencias_gm,public.v_prestacoes_alertas_reentrega TO authenticated;
REVOKE ALL ON FUNCTION public.sigo_registrar_reentrega(text,text,text),public.sigo_transferir_nf(text,text,text,text),public.sigo_solicitar_devolucao(uuid,text),public.sigo_encerrar_devolucao(uuid,text),public.sigo_configurar_reentrega(integer,text[]),public.sigo_canhotos_faltantes(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_registrar_reentrega(text,text,text),public.sigo_transferir_nf(text,text,text,text),public.sigo_solicitar_devolucao(uuid,text),public.sigo_encerrar_devolucao(uuid,text),public.sigo_configurar_reentrega(integer,text[]),public.sigo_canhotos_faltantes(uuid) TO authenticated;
