-- Fixtures sinteticas que reproduzem os cinco cenarios relatados do export
-- StopView de 16/11/2026. O CSV original nao foi disponibilizado.
\set ON_ERROR_STOP on
DO $test$
DECLARE
  v_usuario CONSTANT uuid := '11111111-1111-4111-8111-111111111111';
  v_sem_role CONSTANT uuid := '22222222-2222-4222-8222-222222222222';
  v_payload jsonb;
  v_linhas jsonb;
  v_resultado jsonb;
  v_count integer;
  v_nf_id uuid;
  v_origem text;
  v_tipo text;
  v_bloqueado boolean;
BEGIN
  INSERT INTO auth.users(id,raw_user_meta_data)
    VALUES (v_usuario,'{}'::jsonb),(v_sem_role,'{}'::jsonb);
  INSERT INTO public.profiles(id,nome,ativo)
    VALUES (v_usuario,'Operador teste',true),(v_sem_role,'Sem role',true);
  INSERT INTO public.user_roles(user_id,role)
    VALUES (v_usuario,'operacional');
  PERFORM set_config('sigo.uid',v_usuario::text,true);

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',parada::text,
      'Código da rota',codigo,
      'Descrição da rota',romaneio,
      'Data da Rota','2026-11-16',
      'stop.orders.number',bruto,
      'routeView.route.key',codigo,
      'routeView.route.date','2026-11-16'
    ) ORDER BY ordem
  ) INTO v_linhas FROM (VALUES
    ( 1, 1001, 'SP-1', '123456789012', '005605465-7'),
    ( 2, 1002, 'SP-2', '123456789013', '5605465'),
    ( 3, 1003, 'SP-1', '123456789012', '5605466'),
    ( 4, 1004, 'SP-1', '123456789012', '5605467'),
    ( 5, 1005, 'SP-1', '123456789012', '5605468'),
    ( 6, 1006, 'SP-1', '123456789012', '5605469'),
    ( 7, 1007, 'SP-1', '123456789012', '5605470'),
    ( 8, 1008, 'SP-1', '123456789012', '5605471'),
    ( 9, 1009, 'SP-1', '123456789012', ''),
    (10, 1010, 'SP-1', '123456789012', ''),
    (11, 1011, 'SP-1', '123456789012', ''),
    (12, 1012, 'VT-1', '333333333333', '5'),
    (13, 1013, 'VT-1', '333333333333', '5'),
    (14, 1014, 'SP-1', '123456789012', '005605466-7'),
    (15, 1015, 'VT-1', '333333333333', '005605465-7')
  ) AS f(ordem,parada,codigo,romaneio,bruto);
  v_payload := jsonb_build_object(
    'arquivo_nome','StopView-16-11-2026-pedidos.csv + paradas.csv',
    'sha256',repeat('a',64),
    'linhas',v_linhas
  );
  v_resultado := public.sigo_importar_stopview(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',v_payload);
  IF v_resultado->>'status' <> 'IMPORTADO' OR
     (v_resultado->>'linhas')::int <> 15 OR
     (v_resultado->>'prestacoes_novas')::int <> 2 OR
     (v_resultado->>'notas_novas')::int <> 8 OR
     (v_resultado->>'execucoes_novas')::int <> 10 OR
     (v_resultado->>'pendencias_novas')::int <> 11 THEN
    RAISE EXCEPTION 'Resumo importacao incorreto: %',v_resultado;
  END IF;
  SELECT count(*) INTO v_count FROM public.gm_importacoes;
  IF v_count <> 1 THEN RAISE EXCEPTION 'Esperada 1 importacao, obtido %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.rotas;
  IF v_count <> 3 THEN RAISE EXCEPTION 'Esperadas 3 rotas, obtido %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.paradas;
  IF v_count <> 15 THEN RAISE EXCEPTION 'Esperadas 15 paradas, obtido %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.notas_fiscais;
  IF v_count <> 8 THEN RAISE EXCEPTION 'Esperadas 8 NFs, obtido %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.nf_execucoes;
  IF v_count <> 10 THEN RAISE EXCEPTION 'Esperadas 10 execucoes, obtido %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.pendencias_importacao WHERE motivo='SERIE_AMBIGUA';
  IF v_count <> 0 THEN RAISE EXCEPTION 'Sem series concorrentes nao deve existir SERIE_AMBIGUA'; END IF;
  SELECT count(*) INTO v_count FROM public.pendencias_importacao
    WHERE motivo='SERIE_ASSUMIDA' AND status='TRATADA'
      AND tratada_por=v_usuario AND tratada_em IS NOT NULL;
  IF v_count <> 6 THEN RAISE EXCEPTION 'Esperadas 6 series assumidas TRATADA, obtido %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.pendencias_importacao WHERE motivo='SEM_NF';
  IF v_count <> 3 THEN RAISE EXCEPTION 'Esperados 3 vazios, obtido %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.pendencias_importacao WHERE motivo='TRANSFERENCIA';
  IF v_count <> 2 THEN RAISE EXCEPTION 'Esperados 2 VT com valor 5, obtido %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.prestacao_notas;
  IF v_count <> 8 THEN RAISE EXCEPTION 'Esperados 8 canhotos de origem, obtido %',v_count; END IF;

  SELECT id,romaneio_origem INTO STRICT v_nf_id,v_origem FROM public.notas_fiscais
    WHERE numero='005605465' AND serie='7';
  IF v_origem <> '123456789012' THEN RAISE EXCEPTION 'Origem fiscal foi alterada: %',v_origem; END IF;
  SELECT count(*) INTO v_count FROM public.nf_execucoes WHERE nf_id=v_nf_id;
  IF v_count <> 3 THEN RAISE EXCEPTION 'NF duplicada deveria ter tres execucoes, obtido %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.nf_execucoes
    WHERE nf_id=v_nf_id AND encerrada_em IS NULL;
  IF v_count <> 1 THEN RAISE EXCEPTION 'NF deve ter exatamente uma execução aberta'; END IF;
  SELECT tipo INTO STRICT v_tipo FROM public.nf_execucoes
    WHERE nf_id=v_nf_id AND rota_id=(SELECT id FROM public.rotas WHERE codigo='SP-2');
  IF v_tipo <> 'REENTREGA' THEN RAISE EXCEPTION 'Segunda rota nao marcada REENTREGA'; END IF;
  SELECT tipo INTO STRICT v_tipo FROM public.nf_execucoes
    WHERE nf_id=v_nf_id AND rota_id=(SELECT id FROM public.rotas WHERE codigo='VT-1');
  IF v_tipo <> 'TRANSFERENCIA' THEN RAISE EXCEPTION 'Rota VT nao marcada TRANSFERENCIA'; END IF;

  -- Reimportar mesmos bytes, com ID diferente: nenhuma tabela cresce.
  v_resultado := public.sigo_importar_stopview(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',v_payload);
  IF v_resultado->>'status' <> 'JA_IMPORTADO' THEN
    RAISE EXCEPTION 'Replay deveria ser ignorado: %',v_resultado;
  END IF;
  SELECT count(*) INTO v_count FROM public.gm_importacoes;
  IF v_count <> 1 THEN RAISE EXCEPTION 'Replay duplicou importacao'; END IF;
  SELECT count(*) INTO v_count FROM public.pendencias_importacao;
  IF v_count <> 11 THEN RAISE EXCEPTION 'Replay duplicou pendencias'; END IF;
  SELECT count(*) INTO v_count FROM public.nf_execucoes;
  IF v_count <> 10 THEN RAISE EXCEPTION 'Replay duplicou execucoes'; END IF;

  -- Contrato obrigatório: ausência de coluna cancela TODO o lote.
  v_bloqueado := false;
  BEGIN
    PERFORM public.sigo_importar_stopview(
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      jsonb_build_object('arquivo_nome','incompleto.csv','sha256',repeat('b',64),
        'linhas',jsonb_build_array((v_linhas->0) - 'Código da rota'))
    );
  EXCEPTION WHEN OTHERS THEN
    IF position('coluna obrigatória' in SQLERRM) = 0 THEN RAISE; END IF;
    v_bloqueado := true;
  END;
  IF NOT v_bloqueado THEN RAISE EXCEPTION 'Coluna ausente passou sem erro'; END IF;
  SELECT count(*) INTO v_count FROM public.gm_importacoes;
  IF v_count <> 1 THEN RAISE EXCEPTION 'Lote invalido criou importacao'; END IF;

  -- Perfil sem role nao pode invocar a RPC SECURITY DEFINER.
  PERFORM set_config('sigo.uid',v_sem_role::text,true);
  v_bloqueado := false;
  BEGIN
    PERFORM public.sigo_importar_stopview(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      jsonb_build_object('arquivo_nome','sem-role.csv','sha256',repeat('c',64),
        'linhas',v_linhas)
    );
  EXCEPTION WHEN OTHERS THEN
    IF position('sem permissão ativa' in SQLERRM)=0 THEN RAISE; END IF;
    v_bloqueado:=true;
  END;
  IF NOT v_bloqueado THEN RAISE EXCEPTION 'Usuário sem role foi autorizado'; END IF;

  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.pendencias_importacao'::regclass)
    OR has_table_privilege('authenticated','public.pendencias_importacao','INSERT') THEN
    RAISE EXCEPTION 'Pendencias sem RLS ou INSERT direto permitido';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_proc WHERE oid='public.sigo_importar_stopview(uuid,jsonb)'::regprocedure
      AND prosecdef AND proconfig @> ARRAY['search_path=""']
  ) THEN
    RAISE EXCEPTION 'RPC fora do padrao SECURITY DEFINER search_path';
  END IF;

  -- P1: cinco números reais do CSV de 16/11, rota SP-1MFV69.
  -- A NF ainda não existe: criar com série 7 e registrar SERIE_ASSUMIDA/TRATADA.
  PERFORM set_config('sigo.uid',v_usuario::text,true);
  IF (SELECT serie_padrao FROM public.sla_config WHERE id=true) <> '7' THEN
    RAISE EXCEPTION 'sla_config.serie_padrao deve iniciar em 7';
  END IF;
  SELECT jsonb_agg(jsonb_build_object(
    'id', parada::text,
    'Código da rota','SP-1MFV69',
    'Descrição da rota','123456789014',
    'Data da Rota','2026-11-16',
    'stop.orders.number', bruto,
    'routeView.route.key','SP-1MFV69',
    'routeView.route.date','2026-11-16'
  ) ORDER BY parada) INTO v_linhas
  FROM (VALUES
    (2001, '5603005'), (2002, '5604380'), (2003, '5605180'),
    (2004, '5606327'), (2005, '5607071')
  ) AS reais(parada, bruto);
  v_payload := jsonb_build_object(
    'arquivo_nome','StopView-16-11-2026-SP-1MFV69.csv',
    'sha256',repeat('d',64),'linhas',v_linhas
  );
  v_resultado := public.sigo_importar_stopview(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',v_payload);
  IF v_resultado->>'status' <> 'IMPORTADO'
    OR (v_resultado->>'notas_novas')::int <> 5
    OR (v_resultado->>'pendencias_novas')::int <> 5 THEN
    RAISE EXCEPTION 'P1: cinco NFs reais sem série não foram criadas: %',v_resultado;
  END IF;
  SELECT count(*) INTO v_count FROM public.notas_fiscais
    WHERE numero IN ('005603005','005604380','005605180','005606327','005607071')
      AND serie='7'
      AND romaneio_origem='123456789014'
      AND origem_rota_id=(SELECT id FROM public.rotas WHERE codigo='SP-1MFV69');
  IF v_count <> 5 THEN
    RAISE EXCEPTION 'P1: esperadas cinco NFs com série 7 e origem SP-1MFV69, obtido %',v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.pendencias_importacao
    WHERE importacao_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid
      AND motivo='SERIE_ASSUMIDA' AND status='TRATADA'
      AND tratada_por=v_usuario AND tratada_em IS NOT NULL;
  IF v_count <> 5 THEN
    RAISE EXCEPTION 'P1: esperadas cinco pendências informativas tratadas, obtido %',v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.pendencias_importacao
    WHERE importacao_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid
      AND motivo='SERIE_AMBIGUA';
  IF v_count <> 0 THEN RAISE EXCEPTION 'P1: série inexistente não é ambígua'; END IF;

  -- Reimportação dos cinco números: nenhuma NF ou pendência extra.
  v_resultado := public.sigo_importar_stopview(
    'ffffffff-ffff-4fff-8fff-ffffffffffff',v_payload);
  IF v_resultado->>'status' <> 'JA_IMPORTADO' THEN
    RAISE EXCEPTION 'P1: cinco números duplicados no replay: %',v_resultado;
  END IF;
  SELECT count(*) INTO v_count FROM public.pendencias_importacao
    WHERE importacao_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid
      AND motivo='SERIE_ASSUMIDA';
  IF v_count <> 5 THEN RAISE EXCEPTION 'P1: replay criou pendências extras'; END IF;

  -- P2: formato realista SP-1VT69 (VT após saída numérica);
  -- o valor 5 deve ser TRANSFERENCIA, não SEM_NF, mesmo sem série/NF.
  v_payload := jsonb_build_object(
    'arquivo_nome','StopView-VT-16-11-2026.csv',
    'sha256',repeat('e',64),
    'linhas',jsonb_build_array(jsonb_build_object(
      'id','3001', 'Código da rota','SP-1VT69',
      'Descrição da rota','333333333333','Data da Rota','2026-11-16',
      'stop.orders.number','5','routeView.route.key','SP-1VT69',
      'routeView.route.date','2026-11-16'
    ))
  );
  v_resultado := public.sigo_importar_stopview(
    '99999999-9999-4999-8999-999999999999',v_payload);
  IF v_resultado->>'status' <> 'IMPORTADO'
    OR (v_resultado->>'pendencias_novas')::int <> 1
    OR (v_resultado->>'notas_novas')::int <> 0 THEN
    RAISE EXCEPTION 'P2: VT 5 deve gerar só uma pendência: %',v_resultado;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.pendencias_importacao
    WHERE importacao_id='99999999-9999-4999-8999-999999999999'::uuid
      AND codigo_rota='SP-1VT69' AND valor_bruto='5'
      AND motivo='TRANSFERENCIA' AND status='PENDENTE'
  ) THEN
    RAISE EXCEPTION 'P2: valor 5 em VT foi classificado incorretamente';
  END IF;

  -- Número com DUAS séries existentes é a única condição de SERIE_AMBIGUA.
  INSERT INTO public.notas_fiscais (numero,serie)
    VALUES ('005607171','7'),('005607171','8');
  v_payload := jsonb_build_object(
    'arquivo_nome','StopView-ambiguidade.csv',
    'sha256',repeat('f',64),
    'linhas',jsonb_build_array(jsonb_build_object(
      'id','4001', 'Código da rota','SP-1MFV70',
      'Descrição da rota','123456789015','Data da Rota','2026-11-16',
      'stop.orders.number','5607171','routeView.route.key','SP-1MFV70',
      'routeView.route.date','2026-11-16'
    ))
  );
  v_resultado := public.sigo_importar_stopview(
    '88888888-8888-4888-8888-888888888888',v_payload);
  IF v_resultado->>'status' <> 'IMPORTADO'
    OR (v_resultado->>'notas_novas')::int <> 0 THEN
    RAISE EXCEPTION 'Duas séries existentes devem impedir nova NF: %',v_resultado;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.pendencias_importacao
    WHERE importacao_id='88888888-8888-4888-8888-888888888888'::uuid
      AND motivo='SERIE_AMBIGUA' AND status='PENDENTE'
  ) THEN
    RAISE EXCEPTION 'Duas séries existentes devem gerar SERIE_AMBIGUA pendente';
  END IF;
END
$test$;
