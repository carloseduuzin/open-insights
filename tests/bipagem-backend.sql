-- SIGO Etapa 4: 11 casos da spec PROMPT_BIPAGEM_SIGO, PostgreSQL 17 isolado.
-- NÃO utiliza dados operacionais nem escreve no Supabase hospedado.
-- Usuários A e B com papel operacional; C com perfil ativo SEM role.
-- A correspondência SQL x TS é feita sobre a MESMA fixture JSON no workflow.
\set ON_ERROR_STOP on

DO $bipe$
DECLARE
  v_a CONSTANT uuid := 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  v_b CONSTANT uuid := 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  v_c CONSTANT uuid := 'cccccccc-3333-4333-8333-cccccccccccc';
  v_origem uuid;v_reentrega uuid;v_vuc uuid;
  v_p uuid;v_pfechada uuid;
  v_nf1 uuid;v_nf2 uuid;v_nf3 uuid;v_nf4 uuid;v_nf5 uuid;
  v_chave text;
  v_res jsonb;v_n integer;v_log bigint;v_status text;v_owner uuid;
  v_bloqueou boolean;
BEGIN
  INSERT INTO auth.users(id,raw_user_meta_data) VALUES
    (v_a,'{}'::jsonb),(v_b,'{}'::jsonb),(v_c,'{}'::jsonb);
  INSERT INTO public.profiles(id,nome,ativo) VALUES
    (v_a,'Operador A',true),(v_b,'Operador B',true),(v_c,'Operador sem role',true);
  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_a,'operacional'),(v_b,'operacional');

  PERFORM set_config('sigo.uid',v_a::text,true);
  -- Regressao: as PRIMEIRAS chamadas, antes de qualquer bipe bem-sucedido,
  -- devem responder sem depender do descritor de um record ainda nao atribuido.
  SELECT count(*) INTO v_log FROM public.bipagens;
  v_res:=public.sigo_bipar_canhoto('9999','regressao-primeira-leitura');
  IF v_res->>'resultado' IS DISTINCT FROM 'NAO_ENCONTRADA' THEN
    RAISE EXCEPTION 'Primeira leitura sem NF retornou resultado incorreto';
  END IF;
  v_res:=public.sigo_bipar_canhoto('invalido','regressao-primeira-leitura');
  IF v_res->>'resultado' IS DISTINCT FROM 'CODIGO_INVALIDO' THEN
    RAISE EXCEPTION 'Codigo invalido antes de qualquer sucesso falhou';
  END IF;
  v_res:=public.sigo_bipar_canhoto(repeat('0',44),'regressao-primeira-leitura');
  IF v_res->>'resultado' IS DISTINCT FROM 'NAO_ENCONTRADA'
    OR (SELECT count(*) FROM public.bipagens) <> v_log+3 THEN
    RAISE EXCEPTION 'Chave sem NF ou auditoria das primeiras leituras incorreta';
  END IF;

  INSERT INTO public.rotas(data_rota,codigo,romaneio_gm,tipo_romaneio,tipo_rota)
    VALUES ('2026-11-16','SP-ORIGEM','601615021154','OFICIAL','ENTREGA')
    RETURNING id INTO v_origem;
  INSERT INTO public.rotas(data_rota,codigo,romaneio_gm,tipo_romaneio,tipo_rota)
    VALUES ('2026-11-16','SP-REENTREGA','601615021155','OFICIAL','ENTREGA')
    RETURNING id INTO v_reentrega;
  INSERT INTO public.rotas(data_rota,codigo,romaneio_gm,tipo_romaneio,tipo_rota)
    VALUES ('2026-11-16','SP-1VTVU005','600000000002','AUXILIAR','ABASTECIMENTO')
    RETURNING id INTO v_vuc;

  INSERT INTO public.prestacoes(romaneio_oficial,d0)
    VALUES('601615021154','2026-11-16') RETURNING id INTO v_p;
  INSERT INTO public.prestacoes(romaneio_oficial,d0)
    VALUES('601615021156','2026-11-16') RETURNING id INTO v_pfechada;

  INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id)
    VALUES ('001234567','7','601615021154',v_origem) RETURNING id INTO v_nf1;
  INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id)
    VALUES ('001234568','7','601615021154',v_origem) RETURNING id INTO v_nf2;
  INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id)
    VALUES ('001234569','7','601615021157',v_origem) RETURNING id INTO v_nf3;
  INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id)
    VALUES ('001234570','7','601615021156',v_origem) RETURNING id INTO v_nf4;
  INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id)
    VALUES ('001234571','7','601615021154',v_origem) RETURNING id INTO v_nf5;
  INSERT INTO public.notas_fiscais(numero,serie) VALUES
    ('001234572','7'),('001234572','8');

  -- 6) A prestação já ENVIADA deve permanecer fechada e sem canhoto.
  UPDATE public.prestacoes SET status='RETORNADA' WHERE id=v_pfechada;
  UPDATE public.prestacoes SET status='CONFERIDA' WHERE id=v_pfechada;
  UPDATE public.prestacoes SET status='ENVIADA_JTI' WHERE id=v_pfechada;

  -- 1) Chave de 44 dígitos localiza NF pelo número+série, preenche chave,
  -- registra canhoto, evento e exatamente UMA leitura.
  v_chave:=repeat('1',22)||'007'||'001234567'||repeat('2',10);
  IF length(v_chave)<>44 THEN RAISE EXCEPTION 'Fixture de chave não tem 44 dígitos'; END IF;
  v_res:=public.sigo_bipar_canhoto(v_chave,'scanner A');
  IF v_res->>'resultado'<>'OK' THEN RAISE EXCEPTION 'Caso 1: chave 44 não OK: %',v_res; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notas_fiscais WHERE id=v_nf1
      AND chave_acesso=v_chave) THEN
    RAISE EXCEPTION 'Caso 1: primeira bipagem não gravou chave na NF importada';
  END IF;
  SELECT count(*) INTO v_n FROM public.prestacao_notas
    WHERE nf_id=v_nf1 AND prestacao_id=v_p AND canhoto_recebido_em IS NOT NULL
      AND canhoto_recebido_por=v_a;
  IF v_n<>1 THEN RAISE EXCEPTION 'Caso 1: canhoto não creditado ao autor do bipe'; END IF;
  SELECT count(*) INTO v_n FROM public.nf_eventos WHERE nf_id=v_nf1 AND tipo='CANHOTO';
  IF v_n<>1 THEN RAISE EXCEPTION 'Caso 1: CANHOTO evento ausente'; END IF;
  SELECT count(*) INTO v_n FROM public.bipagens WHERE codigo_lido=v_chave AND resultado='OK';
  IF v_n<>1 THEN RAISE EXCEPTION 'Caso 1: leitura não foi logada uma vez'; END IF;

  -- 7) Primeiro bipe retorna prestação ABERTA sem trocar responsável.
  SELECT status,responsavel_id INTO v_status,v_owner FROM public.prestacoes WHERE id=v_p;
  IF v_status<>'RETORNADA' OR v_owner IS DISTINCT FROM v_a THEN
    RAISE EXCEPTION 'Caso 7: primeiro bipe deveria retornar mantendo autor';
  END IF;

  -- 2) Mesmo código por usuário B é JA_BIPADA, sem novo evento.
  PERFORM set_config('sigo.uid',v_b::text,true);
  v_res:=public.sigo_bipar_canhoto(v_chave,'scanner B');
  IF v_res->>'resultado'<>'JA_BIPADA'
     OR v_res->'bipada_anteriormente_por'->>'nome'<>'Operador A' THEN
    RAISE EXCEPTION 'Caso 2: replay sem autoria original: %',v_res;
  END IF;
  SELECT count(*) INTO v_n FROM public.nf_eventos WHERE nf_id=v_nf1 AND tipo='CANHOTO';
  IF v_n<>1 THEN RAISE EXCEPTION 'Caso 2: evento duplicado'; END IF;
  SELECT count(*) INTO v_n FROM public.bipagens WHERE codigo_lido=v_chave;
  IF v_n<>2 THEN RAISE EXCEPTION 'Caso 2: devem existir duas leituras imutáveis'; END IF;

  -- 3) NF de R1 entregue por SP-REENTREGA continua creditada à origem.
  INSERT INTO public.nf_execucoes(nf_id,rota_id,tipo,registrada_por)
    VALUES(v_nf2,v_reentrega,'REENTREGA',v_a);
  v_res:=public.sigo_bipar_canhoto('1234568-7','scanner B');
  IF v_res->>'resultado'<>'ROTA_DIFERENTE'
    OR v_res->'rota_execucao'->>'codigo'<>'SP-REENTREGA'
    OR v_res->'prestacao'->>'romaneio_oficial'<>'601615021154' THEN
    RAISE EXCEPTION 'Caso 3: não creditou origem R1: %',v_res;
  END IF;

  -- 4) Número de 4 dígitos válido sintaticamente mas NF inexistente.
  v_res:=public.sigo_bipar_canhoto('9999');
  IF v_res->>'resultado'<>'NAO_ENCONTRADA'
     OR NOT EXISTS(SELECT 1 FROM public.bipagens
       WHERE codigo_lido='9999' AND resultado='NAO_ENCONTRADA') THEN
    RAISE EXCEPTION 'Caso 4: 9999 deveria ser NAO_ENCONTRADA';
  END IF;

  -- 5) NF existente sem prestação cadastrada.
  v_res:=public.sigo_bipar_canhoto('1234569-7');
  IF v_res->>'resultado'<>'SEM_PRESTACAO' THEN
    RAISE EXCEPTION 'Caso 5: sem prestação: %',v_res;
  END IF;

  -- 6) Não receber canhoto de prestação já enviada.
  v_res:=public.sigo_bipar_canhoto('1234570-7');
  IF v_res->>'resultado'<>'PRESTACAO_FECHADA'
    OR EXISTS(SELECT 1 FROM public.prestacao_notas
        WHERE nf_id=v_nf4 AND canhoto_recebido_em IS NOT NULL) THEN
    RAISE EXCEPTION 'Caso 6: prestação fechada recebeu canhoto: %',v_res;
  END IF;

  -- 8) Um faltante exige justificativa antes da conferência.
  PERFORM set_config('sigo.uid',v_a::text,true);
  v_bloqueou:=false;
  BEGIN
    PERFORM id FROM public.sigo_avancar_prestacao(v_p,'CONFERIDA');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Prestação com % canhoto(s) sem bipagem nem justificativa' THEN RAISE; END IF;
    v_bloqueou:=true;
  END;
  IF NOT v_bloqueou THEN RAISE EXCEPTION 'Caso 8: conferiu com faltante'; END IF;
  v_res:=public.sigo_justificar_faltante(v_p,v_nf5,'EXTRAVIO','Produto conferido e sem canhoto');
  IF NOT EXISTS (SELECT 1 FROM public.prestacao_nota_justificativas
      WHERE prestacao_id=v_p AND nf_id=v_nf5
        AND motivo='EXTRAVIO' AND usuario_id=v_a) THEN
    RAISE EXCEPTION 'Caso 8: justificativa não registrada';
  END IF;
  PERFORM id FROM public.sigo_avancar_prestacao(v_p,'CONFERIDA');
  IF NOT EXISTS(SELECT 1 FROM public.prestacoes WHERE id=v_p AND status='CONFERIDA') THEN
    RAISE EXCEPTION 'Caso 8: conferência não liberada após justificativa';
  END IF;
  SELECT count(*) INTO v_n FROM public.sigo_canhotos_faltantes(v_p)
    WHERE nf_id=v_nf5 AND numero='001234571' AND justificativa='EXTRAVIO';
  IF v_n<>1 THEN RAISE EXCEPTION 'Caso 8: faltantes não exibiram justificativa'; END IF;
  -- Contrato da API para UI: nf_id UUID é o PRIMEIRO campo do retorno.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='public.sigo_canhotos_faltantes(uuid)'::regprocedure
      AND pg_get_function_result(p.oid) LIKE 'TABLE(nf_id uuid, numero text,%'
  ) THEN
    RAISE EXCEPTION 'sigo_canhotos_faltantes deve retornar nf_id UUID como primeira coluna';
  END IF;

  -- 9) NF com duas séries não deve chutar série.
  v_res:=public.sigo_bipar_canhoto('1234572');
  IF v_res->>'resultado'<>'NAO_ENCONTRADA'
    OR v_res->>'detalhe'<>'AMBIGUA' THEN
    RAISE EXCEPTION 'Caso 9: série ambígua: %',v_res;
  END IF;

  -- Extra: código inválido gera log imutável.
  v_res:=public.sigo_bipar_canhoto('abc');
  IF v_res->>'resultado'<>'CODIGO_INVALIDO'
    OR NOT EXISTS(SELECT 1 FROM public.bipagens
      WHERE codigo_lido='abc' AND resultado='CODIGO_INVALIDO') THEN
    RAISE EXCEPTION 'Formato inválido não foi auditado';
  END IF;

  -- Um abastecimento nunca pode ser origem fiscal de bipagem.
  INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id)
    VALUES('001234573','7','601615021158',v_vuc);
  v_res:=public.sigo_bipar_canhoto('1234573-7');
  IF v_res->>'resultado'<>'NAO_ENCONTRADA'
    OR v_res->>'detalhe'<>'ABASTECIMENTO' THEN
    RAISE EXCEPTION 'Regra VUC: abastecimento não pode participar: %',v_res;
  END IF;

  -- 11) Perfil ativo sem role não pode usar RPC SECURITY DEFINER.
  PERFORM set_config('sigo.uid',v_c::text,true);
  v_bloqueou:=false;
  BEGIN
    PERFORM public.sigo_bipar_canhoto('1234567-7');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'Usuário sem acesso ativo ao SIGO' THEN RAISE; END IF;
    v_bloqueou:=true;
  END;
  IF NOT v_bloqueou THEN RAISE EXCEPTION 'Caso 11: usuário sem role foi autorizado'; END IF;

  IF has_table_privilege('authenticated','public.bipagens','INSERT')
    OR has_table_privilege('authenticated','public.prestacao_nota_justificativas','INSERT')
    OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.bipagens'::regclass)
    OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.prestacao_nota_justificativas'::regclass)
    OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.v_prestacao_progresso'::regclass
       AND reloptions @> ARRAY['security_invoker=true']) THEN
    RAISE EXCEPTION 'Falha em RLS/grants/security_invoker';
  END IF;

  -- Views e logs continuam legíveis para operadores diferentes.
  PERFORM set_config('sigo.uid',v_b::text,true);
  IF NOT EXISTS(SELECT 1 FROM public.v_prestacao_progresso
      WHERE prestacao_id=v_p AND total_nfs=3 AND bipados=2 AND faltantes=1) THEN
    RAISE EXCEPTION 'Progresso incorreto (esperados total 3/bipados 2/faltante 1)';
  END IF;
END
$bipe$;
