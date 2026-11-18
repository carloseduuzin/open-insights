\set ON_ERROR_STOP on
-- Carrega amostra versionada real; nao altera os campos tecnicos.
BEGIN;
CREATE TEMP TABLE gm_real("id" text,"Organização" text,"Data da Rota" text,"Código da rota" text,"Descrição da rota" text,"stop.orders.number" text,"routeView.route.key" text,"routeView.route.date" text);
\copy gm_real FROM 'tests/fixtures/stopview_2026-11-16_17_tecnica.csv' WITH (FORMAT csv,HEADER true)
DO $real$
DECLARE u uuid:=gen_random_uuid();linha jsonb;payload jsonb;r jsonb;i uuid;n uuid;rom text;
BEGIN
 INSERT INTO auth.users(id,raw_user_meta_data) VALUES(u,'{}');
 INSERT INTO public.profiles(id,nome,ativo) VALUES(u,'Operador teste fixture real',true);
 INSERT INTO public.user_roles(user_id,role) VALUES(u,'operacional');
 PERFORM set_config('sigo.uid',u::text,true);
 FOR linha IN SELECT to_jsonb(t) FROM gm_real t ORDER BY "Data da Rota" LOOP
  i:=gen_random_uuid();
  -- SHA identifica o recorte JSON efetivamente enviado, nao o export completo.
  payload:=jsonb_build_object('arquivo_nome','stopview_2026-11-16_17_tecnica.csv','sha256',encode(sha256(convert_to(linha::text,'UTF8')),'hex'),'linhas',jsonb_build_array(linha));
  r:=public.sigo_importar_stopview(i,payload);
  IF r->>'status'<>'IMPORTADO' THEN RAISE EXCEPTION 'Fixture real nao importada: %',r; END IF;
  SELECT id,romaneio_origem INTO STRICT n,rom FROM public.notas_fiscais WHERE numero=split_part(linha->>'stop.orders.number','-',1) AND serie=split_part(linha->>'stop.orders.number','-',2);
  IF rom IS DISTINCT FROM linha->>'Descrição da rota' THEN RAISE EXCEPTION 'Origem real alterada'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nf_execucoes WHERE nf_id=n AND encerrada_em IS NULL) THEN RAISE EXCEPTION 'Execucao nao persistida'; END IF;
  r:=public.sigo_importar_stopview(gen_random_uuid(),payload);
  IF r->>'status'<>'JA_IMPORTADO' THEN RAISE EXCEPTION 'Reimportacao criou duplicidade: %',r; END IF;
 END LOOP;
 IF (SELECT count(*) FROM gm_real)<>2 THEN RAISE EXCEPTION 'Amostra tecnica inesperada'; END IF;
END; $real$;
ROLLBACK;
