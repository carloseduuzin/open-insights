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
