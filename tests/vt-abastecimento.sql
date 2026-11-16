-- SIGO — regressão de abastecimento VUC, PostgreSQL 17 descartável.
-- tests/fixtures/vuc_2026-11-16_regressao.csv contém:
--   SP-1VTVU005 / CROSS-ZL: ID, romaneio 600000000002, valor 5
--     transcritos do StopView real de 16/11/2026 (motorista omitido).
--   SP-1VTVU004 / CROSS-ZS: código e destino informados pelo usuário;
--     ID 99000004 e romaneio 999000000004 são FICTÍCIOS somente neste teste.
-- Não representar a segunda linha como leitura do export completo.
\set ON_ERROR_STOP on

CREATE TEMP TABLE vuc_fixture (
  id bigint NOT NULL,
  codigo_rota text NOT NULL,
  data_rota date NOT NULL,
  localidade_destino text NOT NULL,
  romaneio text NOT NULL,
  valor_bruto_pedido text,
  origem text NOT NULL
);
\copy vuc_fixture FROM 'tests/fixtures/vuc_2026-11-16_regressao.csv' WITH (FORMAT csv, HEADER true);

DO $vuc_test$
DECLARE
  v_a uuid := '66666666-6666-4666-8666-666666666666';
  v_b uuid := '77777777-7777-4777-8777-777777777777';
  v_resultado jsonb;
  v_linha jsonb;
  v_cont integer;
BEGIN
  IF (SELECT count(*) FROM vuc_fixture) <> 2
    OR NOT EXISTS(SELECT 1 FROM vuc_fixture
        WHERE codigo_rota='SP-1VTVU005' AND localidade_destino='CROSS-ZL'
          AND valor_bruto_pedido='5' AND romaneio='600000000002'
          AND origem='STOPVIEW_REAL_2026-11-16')
    OR NOT EXISTS(SELECT 1 FROM vuc_fixture
        WHERE codigo_rota='SP-1VTVU004' AND localidade_destino='CROSS-ZS'
          AND origem='CENARIO_INFORMADO_ROMANEIO_FICTICIO') THEN
    RAISE EXCEPTION 'Fixture VUC não corresponde aos dois casos documentados';
  END IF;

  INSERT INTO auth.users(id,raw_user_meta_data) VALUES
    (v_a,'{}'::jsonb),(v_b,'{}'::jsonb);
  INSERT INTO public.profiles(id,nome,ativo) VALUES
    (v_a,'Operador A',true),(v_b,'Operador B',true);
  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_a,'operacional'),(v_b,'operacional');

  IF (SELECT localidade_cross_proprio FROM public.sla_config WHERE id=true)
       IS DISTINCT FROM 'CROSS-ZL' THEN
    RAISE EXCEPTION 'Configuração do cross próprio deve iniciar em CROSS-ZL';
  END IF;

  -- A importa o abastecimento real de CROSS-ZL.
  PERFORM set_config('sigo.uid',v_a::text,true);
  SELECT jsonb_build_object(
    'id',id::text,'Código da rota',codigo_rota,
    'Descrição da rota',romaneio,'Data da Rota',data_rota::text,
    'Código da Localidade',localidade_destino,
    'stop.orders.number',valor_bruto_pedido,
    'routeView.route.key',codigo_rota,
    'routeView.route.date',data_rota::text)
    INTO STRICT v_linha
  FROM vuc_fixture WHERE codigo_rota='SP-1VTVU005';
  v_resultado := public.sigo_importar_stopview(
    '66666666-6666-4666-8666-666666666667',
    jsonb_build_object('arquivo_nome','VUC-CROSS-ZL.csv',
      'sha256',repeat('6',64),'linhas',jsonb_build_array(v_linha)));
  IF v_resultado->>'status'<>'IMPORTADO'
    OR (v_resultado->>'notas_novas')::int<>0
    OR (v_resultado->>'execucoes_novas')::int<>0
    OR (v_resultado->>'pendencias_novas')::int<>0 THEN
    RAISE EXCEPTION 'VUC CROSS-ZL não deve gerar NF, execução ou pendência: %',v_resultado;
  END IF;

  -- B importa outra base: CROSS-ZS também é abastecimento, mas não chegada nossa.
  PERFORM set_config('sigo.uid',v_b::text,true);
  SELECT jsonb_build_object(
    'id',id::text,'Código da rota',codigo_rota,
    'Descrição da rota',romaneio,'Data da Rota',data_rota::text,
    'Código da Localidade',localidade_destino,
    'stop.orders.number',valor_bruto_pedido,
    'routeView.route.key',codigo_rota,
    'routeView.route.date',data_rota::text)
    INTO STRICT v_linha
  FROM vuc_fixture WHERE codigo_rota='SP-1VTVU004';
  v_resultado := public.sigo_importar_stopview(
    '77777777-7777-4777-8777-777777777778',
    jsonb_build_object('arquivo_nome','VUC-CROSS-ZS-CENARIO.csv',
      'sha256',repeat('7',64),'linhas',jsonb_build_array(v_linha)));
  IF v_resultado->>'status'<>'IMPORTADO'
    OR (v_resultado->>'notas_novas')::int<>0
    OR (v_resultado->>'execucoes_novas')::int<>0
    OR (v_resultado->>'pendencias_novas')::int<>0 THEN
    RAISE EXCEPTION 'VUC CROSS-ZS não deve gerar registros fiscais: %',v_resultado;
  END IF;

  SELECT count(*) INTO v_cont FROM public.rotas
    WHERE codigo IN ('SP-1VTVU005','SP-1VTVU004') AND tipo_rota='ABASTECIMENTO';
  IF v_cont<>2 THEN RAISE EXCEPTION 'Esperadas duas rotas ABASTECIMENTO, obtido %',v_cont; END IF;
  SELECT count(*) INTO v_cont FROM public.paradas
    WHERE codigo_rota IN ('SP-1VTVU005','SP-1VTVU004')
      AND valor_bruto_pedido='5';
  IF v_cont<>2 THEN RAISE EXCEPTION 'Valor bruto 5 não foi preservado nas duas paradas'; END IF;
  SELECT count(*) INTO v_cont FROM public.v_chegadas_vuc
    WHERE codigo_rota='SP-1VTVU005' AND localidade_destino='CROSS-ZL'
      AND valor_bruto_pedido='5';
  IF v_cont<>1 THEN RAISE EXCEPTION 'VTVU005 deve gerar uma chegada no CROSS-ZL'; END IF;
  IF EXISTS(SELECT 1 FROM public.v_chegadas_vuc WHERE codigo_rota='SP-1VTVU004') THEN
    RAISE EXCEPTION 'VTVU004 CROSS-ZS não pode aparecer nas chegadas CROSS-ZL';
  END IF;
  IF EXISTS(SELECT 1 FROM public.notas_fiscais
      WHERE origem_rota_id IN (SELECT id FROM public.rotas
        WHERE codigo IN ('SP-1VTVU005','SP-1VTVU004')))
    OR EXISTS(SELECT 1 FROM public.nf_execucoes e
      JOIN public.rotas r ON r.id=e.rota_id
      WHERE r.codigo IN ('SP-1VTVU005','SP-1VTVU004'))
    OR EXISTS(SELECT 1 FROM public.pendencias_importacao
      WHERE codigo_rota IN ('SP-1VTVU005','SP-1VTVU004')) THEN
    RAISE EXCEPTION 'Abastecimento não pode gerar NF, execução nem pendência';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class
      WHERE oid='public.v_chegadas_vuc'::regclass
        AND reloptions @> ARRAY['security_invoker=true']) THEN
    RAISE EXCEPTION 'v_chegadas_vuc deve utilizar security_invoker=true';
  END IF;

  -- Seed histórico, deliberadamente legado, para validar a migração de
  -- TRANSFERENCIA pendente para TRATADA. A RPC nova não a produz.
  INSERT INTO public.pendencias_importacao
    (importacao_id,linha,codigo_rota,parada_id,valor_bruto,motivo)
  VALUES ('66666666-6666-4666-8666-666666666667',1,'SP-1VTVU005',
    11617893,'5','TRANSFERENCIA');
END
$vuc_test$;

-- Reaplica a migration idempotente no banco descartável para simular a
-- recuperação de um registro de transferência criado antes da correção.
\i supabase/migrations/20261116000450_sigo_vt_abastecimento.sql

DO $after_legacy$
DECLARE v_cont integer;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.pendencias_importacao
    WHERE codigo_rota='SP-1VTVU005' AND motivo='TRANSFERENCIA'
      AND status='TRATADA' AND observacao='abastecimento VUC'
      AND tratada_em IS NOT NULL) THEN
    RAISE EXCEPTION 'Pendência TRANSFERENCIA antiga não foi tratada automaticamente';
  END IF;
  SELECT count(*) INTO v_cont FROM public.pendencias_importacao
    WHERE codigo_rota IN ('SP-1VTVU005','SP-1VTVU004') AND status='PENDENTE';
  IF v_cont<>0 THEN RAISE EXCEPTION 'Zero pendências ATIVAS de abastecimento esperado'; END IF;
  SELECT count(*) INTO v_cont FROM public.v_chegadas_vuc;
  IF v_cont<>1 THEN RAISE EXCEPTION 'Reaplicação alterou indevidamente chegadas'; END IF;
END
$after_legacy$;

-- SELECT como usuário autenticado com RLS e invoker.
SET ROLE authenticated;
SELECT set_config('sigo.uid','66666666-6666-4666-8666-666666666666',false);
DO $rls_check$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.v_chegadas_vuc;
  IF v_n<>1 THEN
    RAISE EXCEPTION 'RLS/security_invoker não retornou 1 chegada para usuário A: %',v_n;
  END IF;
END
$rls_check$;
RESET ROLE;
