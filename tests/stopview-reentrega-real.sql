\set ON_ERROR_STOP on
-- Fixture tecnica real, 17/11/2026; nenhuma linha de importacao e reconstruida aqui.
BEGIN;
CREATE TEMP TABLE fixture_reentrega (
 "id" text,"Organização" text,"Data da Rota" text,"Código da rota" text,
 "Descrição da rota" text,"stop.orders.number" text,"routeView.route.key" text,"routeView.route.date" text
);
\copy fixture_reentrega FROM 'tests/fixtures/stopview_reentrega_2026-11-17.csv' WITH (FORMAT csv,HEADER true)
DO $regressao$
DECLARE u uuid:=gen_random_uuid(); lote uuid:=gen_random_uuid(); linhas jsonb; r jsonb; rota uuid;
 antes_p bigint; antes_nf bigint;
BEGIN
 SELECT count(*) INTO antes_p FROM public.prestacoes;
 SELECT count(*) INTO antes_nf FROM public.notas_fiscais;
 INSERT INTO auth.users(id,raw_user_meta_data) VALUES(u,'{}');
 INSERT INTO public.profiles(id,nome,ativo) VALUES(u,'Operador de regressao',true);
 INSERT INTO public.user_roles(user_id,role) VALUES(u,'operacional');
 PERFORM set_config('sigo.uid',u::text,true);
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 SELECT jsonb_agg(to_jsonb(f)) INTO linhas FROM fixture_reentrega f;
 r:=public.sigo_importar_stopview(lote,jsonb_build_object('arquivo_nome','stopview_reentrega_2026-11-17.csv','sha256',repeat('a',64),'linhas',linhas));
 IF r->>'status' IS DISTINCT FROM 'IMPORTADO' THEN RAISE EXCEPTION 'Fixture real rejeitada: %',r; END IF;
 SELECT id INTO STRICT rota FROM public.rotas WHERE codigo='SP-GROCERY' AND data_rota='2026-11-17';
 IF NOT EXISTS(SELECT 1 FROM public.rotas WHERE id=rota AND descricao_gm='3,33333E+11' AND romaneio_gm IS NULL AND tipo_romaneio='AUXILIAR')
 THEN RAISE EXCEPTION 'Descricao original perdida ou romaneio fiscal inventado'; END IF;
 IF (SELECT count(*) FROM public.prestacoes)<>antes_p OR (SELECT count(*) FROM public.notas_fiscais)<>antes_nf
 THEN RAISE EXCEPTION 'Reentrega sem origem criou prestacao ou NF artificial'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.pendencias_importacao WHERE importacao_id=lote AND motivo='REENTREGA_SEM_ORIGEM' AND valor_bruto='000000001-7')
 THEN RAISE EXCEPTION 'Origem ausente nao ficou pendente'; END IF;
 r:=public.sigo_importar_stopview(gen_random_uuid(),jsonb_build_object('arquivo_nome','stopview_reentrega_2026-11-17.csv','sha256',repeat('a',64),'linhas',linhas));
 IF r->>'status' IS DISTINCT FROM 'JA_IMPORTADO' THEN RAISE EXCEPTION 'Replay nao idempotente'; END IF;
END; $regressao$;
ROLLBACK;

