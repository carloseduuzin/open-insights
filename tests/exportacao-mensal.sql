\set ON_ERROR_STOP on
-- Regras sinteticas em banco isolado. Nao sao importacoes GreenMile.
BEGIN;
CREATE TEMP TABLE ids_teste(nome text,id uuid);
DO $seed$
DECLARE u uuid:=gen_random_uuid();op uuid:=gen_random_uuid();
BEGIN
 INSERT INTO auth.users(id,raw_user_meta_data) VALUES(u,'{}'),(op,'{}');
 INSERT INTO public.profiles(id,nome,ativo) VALUES(u,'Admin exportacao teste',true),(op,'Operador exportacao teste',true);
 INSERT INTO public.user_roles(user_id,role) VALUES(u,'admin'),(op,'operacional');
 INSERT INTO ids_teste VALUES('admin',u),('operador',op);
 PERFORM set_config('sigo.uid',u::text,true);
END; $seed$;
ALTER TABLE public.prestacoes DISABLE TRIGGER USER;
INSERT INTO public.prestacoes(romaneio_oficial,d0,status,enviada_em,conferida_em) VALUES
 ('987654329001',current_date-45,'ENVIADA_JTI',now()-interval '40 days',now()-interval '41 days'),
 ('987654329002',current_date-45,'ENVIADA_JTI',now()-interval '40 days',now()-interval '41 days'),
 ('987654329003',current_date-10,'ENVIADA_JTI',now()-interval '5 days',now()-interval '6 days'),
 ('987654329004',current_date-45,'ABERTA',NULL,NULL);
ALTER TABLE public.prestacoes ENABLE TRIGGER USER;
DO $regras$
DECLARE r jsonb;replay jsonb;l uuid;hash text;negado boolean;antes jsonb;depois jsonb;
BEGIN
 SELECT to_jsonb(v) INTO antes FROM public.v_dashboard_prestacoes v;
 r:=public.sigo_preparar_exportacao('sigo-mensal-2026-11-17');l:=(r->>'id')::uuid;hash:=r->>'sha256_dados';
 IF jsonb_array_length(r->'candidatos')<>2 THEN RAISE EXCEPTION 'Candidatos devem ser apenas baixadas antigas'; END IF;
 replay:=public.sigo_preparar_exportacao('sigo-mensal-2026-11-17');
 IF replay<>r OR (SELECT count(*) FROM public.exportacoes_prestacoes)<>1 THEN RAISE EXCEPTION 'Preparacao nao idempotente'; END IF;
 negado:=false;
 BEGIN PERFORM public.sigo_concluir_exportacao(l,hash,'base.xlsx',repeat('a',64),'');EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado OR EXISTS(SELECT 1 FROM public.prestacoes WHERE arquivada_em IS NOT NULL) THEN RAISE EXCEPTION 'Arquivo sem envio permitiu arquivamento'; END IF;
 UPDATE public.prestacoes SET status='CONFIRMADA_JTI' WHERE romaneio_oficial='987654329002';
 r:=public.sigo_concluir_exportacao(l,hash,'C:/teste/base.xlsx',repeat('a',64),'mensagem-ficticia-apenas-teste-isolado');
 IF (r->>'arquivadas')::integer<>1 THEN RAISE EXCEPTION 'Deve arquivar uma e preservar a alterada apos exportar: %',r; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.prestacoes WHERE romaneio_oficial='987654329001' AND arquivada_em IS NOT NULL) THEN RAISE EXCEPTION 'Prestacao antiga nao arquivada'; END IF;
 IF EXISTS(SELECT 1 FROM public.prestacoes WHERE romaneio_oficial IN ('987654329002','987654329003','987654329004') AND arquivada_em IS NOT NULL) THEN RAISE EXCEPTION 'Registro ativo, recente ou alterado foi arquivado'; END IF;
 SELECT to_jsonb(v) INTO depois FROM public.v_dashboard_prestacoes v;
 IF (antes-'arquivadas')<>(depois-'arquivadas') THEN RAISE EXCEPTION 'Dashboard perdeu informacao'; END IF;
 r:=public.sigo_concluir_exportacao(l,hash,'C:/teste/base.xlsx',repeat('a',64),'mensagem-ficticia-apenas-teste-isolado');
 IF r->>'status'<>'JA_CONCLUIDA' OR (SELECT count(*) FROM public.prestacoes)<>4 THEN RAISE EXCEPTION 'Conclusao repetida perdeu ou duplicou dados'; END IF;
 PERFORM set_config('sigo.uid',(SELECT id::text FROM ids_teste WHERE nome='operador'),true);
 negado:=false;
 BEGIN PERFORM public.sigo_preparar_exportacao('sigo-mensal-2026-12-17');EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'Operador nao admin exportou base completa'; END IF;
 IF has_table_privilege('authenticated','public.exportacoes_prestacoes','INSERT') OR has_function_privilege('anon','public.sigo_preparar_exportacao(text)','EXECUTE') THEN RAISE EXCEPTION 'Permissao excessiva na exportacao'; END IF;
END; $regras$;
ROLLBACK;
