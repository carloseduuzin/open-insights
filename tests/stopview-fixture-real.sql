-- Fixture de Pedidos: amostra REAL de 40 linhas do export StopView 2026-11-16,
-- arquivo original "StopView - 1794848663737.csv" com 104 linhas de Pedidos.
-- Driver e cliente foram anonimizados; IDs, códigos de rota e NF vieram do export.
--
-- IMPORTANTE: O CSV Pedidos NÃO contém romaneio nem a exportação Paradas.
-- Exclusivamente neste teste, criamos o equivalente de Paradas no JSON enviado
-- à RPC, associando cada código de rota a um romaneio FICTÍCIO 99900000000N
-- (12 dígitos, sem repetir 12 dígitos iguais); são TESTE, não dados da JTI.
-- Os campos Código da rota, id, stop.orders.number e data permanecem do CSV.
--
-- Esta amostra é PARCIAL: NÃO inclui a NF 005605465, os cinco números
-- 5603005/5604380/5605180/5606327/5607071, SP-1VTVU004 ou a 3ª parada
-- vazia. O bloco final exige a cobertura solicitada e falha explicitamente
-- até que se substitua a fixture por uma amostra do export completo (307 linhas).
\set ON_ERROR_STOP on

CREATE TEMP TABLE stopview_pedidos_fixture (
  id text,
  codigo_localidade text,
  codigo_rota text,
  data_rota text,
  cliente_anonimizado text,
  motorista_anonimizado text,
  valor_bruto text,
  organizacao_id text,
  equipamento_organizacao_id text,
  principal text
);

\copy stopview_pedidos_fixture FROM 'tests/fixtures/stopview_pedidos_2026-11-16_amostra.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

DO $fixture$
DECLARE
  v_usuario uuid := '55555555-5555-4555-8555-555555555555';
  v_linhas jsonb;
  v_resultado jsonb;
  v_count integer;
  v_duplicata integer;
  v_sem_serie integer;
  v_vt integer;
  v_sem_nf integer;
BEGIN
  SELECT count(*) INTO v_count FROM stopview_pedidos_fixture;
  IF v_count <> 40 THEN
    RAISE EXCEPTION 'Fixture 2026-11-16: esperado 40 linhas reais, obtido %',v_count;
  END IF;
  IF EXISTS (SELECT 1 FROM stopview_pedidos_fixture WHERE
      data_rota <> '2026-11-16' OR id !~ '^[0-9]+$'
      OR codigo_rota IS NULL OR valor_bruto IS NULL) THEN
    RAISE EXCEPTION 'Fixture real: coluna técnica inválida';
  END IF;

  INSERT INTO auth.users(id,raw_user_meta_data)
    VALUES (v_usuario,'{}'::jsonb);
  INSERT INTO public.profiles(id,nome,ativo)
    VALUES (v_usuario,'Operador fixture',true);
  INSERT INTO public.user_roles(user_id,role)
    VALUES (v_usuario,'operacional');
  PERFORM set_config('sigo.uid', v_usuario::text, true);

  -- SIMULAÇÃO EXCLUSIVA DO CSV DE PARADAS, não presente no arquivo de Pedidos.
  -- Mapeia rotas de maneira determinística a romaneios de teste 999000000001...
  WITH rotas_ficticias AS (
    SELECT codigo_rota,
           '999' || lpad(row_number() OVER (ORDER BY codigo_rota)::text,9,'0')
             AS romaneio_ficticio
    FROM (SELECT DISTINCT codigo_rota FROM stopview_pedidos_fixture) AS r
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', f.id,
      'Código da rota', f.codigo_rota,
      'Descrição da rota', r.romaneio_ficticio,
      'Data da Rota', f.data_rota,
      'stop.orders.number', f.valor_bruto,
      'routeView.route.key', f.codigo_rota,
      'routeView.route.date', f.data_rota,
      'Código da Localidade', f.codigo_localidade,
      'Cliente', f.cliente_anonimizado,
      'Motorista', f.motorista_anonimizado
    ) ORDER BY f.id
  )
  INTO v_linhas
  FROM stopview_pedidos_fixture f
  JOIN rotas_ficticias r USING (codigo_rota);

  IF jsonb_array_length(v_linhas) <> 40 THEN
    RAISE EXCEPTION 'Fixture: perda de linhas ao criar Paradas sintéticas';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_linhas) AS l
    WHERE (l->>'Descrição da rota') !~ '^999[0-9]{9}$'
  ) THEN
    RAISE EXCEPTION 'Romaneio fictício deve iniciar com 999 e conter 12 dígitos';
  END IF;

  v_resultado := public.sigo_importar_stopview(
    '55555555-5555-4555-8555-555555555556',
    jsonb_build_object(
      'arquivo_nome', 'stopview_pedidos_2026-11-16_amostra.csv [ROMANEIOS 999 SINTETICOS]',
      'sha256', repeat('7',64),
      'linhas',v_linhas
    )
  );

  IF v_resultado->>'status' <> 'IMPORTADO'
    OR (v_resultado->>'linhas')::integer <> 40
    OR (v_resultado->>'notas_novas')::integer <> 37
    OR (v_resultado->>'pendencias_novas')::integer <> 3 THEN
    RAISE EXCEPTION 'Falha no lote real de 40 linhas: %',v_resultado;
  END IF;

  SELECT count(*) INTO v_count FROM public.pendencias_importacao
    WHERE importacao_id = '55555555-5555-4555-8555-555555555556'::uuid
      AND motivo='SEM_NF';
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Fixture real: duas paradas vazias devem ser SEM_NF; obtido %',v_count;
  END IF;

  SELECT count(*) INTO v_count FROM public.pendencias_importacao
    WHERE importacao_id = '55555555-5555-4555-8555-555555555556'::uuid
      AND codigo_rota='SP-1VTVU005' AND motivo='TRANSFERENCIA'
      AND valor_bruto='5';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Fixture real: VTVU005 valor 5 deve ser TRANSFERENCIA; obtido %',v_count;
  END IF;

  SELECT count(*) INTO v_count FROM public.notas_fiscais
    WHERE romaneio_origem LIKE '999%';
  IF v_count <> 37 THEN
    RAISE EXCEPTION 'Fixture real: esperadas 37 NFs com romaneio fictício 999, obtido %',v_count;
  END IF;

  v_resultado := public.sigo_importar_stopview(
    '55555555-5555-4555-8555-555555555557',
    jsonb_build_object(
      'arquivo_nome','mesmos bytes, outro nome.csv',
      'sha256',repeat('7',64),
      'linhas',v_linhas
    )
  );
  IF v_resultado->>'status' <> 'JA_IMPORTADO' THEN
    RAISE EXCEPTION 'Fixture real: reimportação não foi idempotente: %',v_resultado;
  END IF;

  -- Gate de cobertura OBRIGATÓRIO: a amostra fornecida tem somente 104
  -- linhas na origem, portanto não satisfaz a fixture pedida (307 linhas).
  SELECT count(*) INTO v_duplicata FROM stopview_pedidos_fixture
    WHERE lpad(split_part(valor_bruto,'-',1),9,'0')='005605465';
  SELECT count(*) INTO v_sem_serie FROM stopview_pedidos_fixture
    WHERE valor_bruto IN ('5603005','5604380','5605180','5606327','5607071');
  SELECT count(*) INTO v_vt FROM stopview_pedidos_fixture
    WHERE codigo_rota IN ('SP-1VTVU004','SP-1VTVU005') AND valor_bruto='5';
  SELECT count(*) INTO v_sem_nf FROM stopview_pedidos_fixture
    WHERE btrim(coalesce(valor_bruto,''))='';

  IF v_duplicata <> 2 OR v_sem_serie <> 5 OR v_vt <> 2 OR v_sem_nf <> 3 THEN
    RAISE EXCEPTION
      'COBERTURA_INCOMPLETA: fixture 104 linhas de origem não contém casos obrigatórios (duplicata 005605465 %/2, série assumida %/5, VT %/2, vazios %/3). Fornecer export completo de 307 linhas.',
      v_duplicata, v_sem_serie, v_vt, v_sem_nf;
  END IF;
END
$fixture$;
