\set ON_ERROR_STOP on
-- Executar somente apos aprovacao, backup atualizado e recuperacao comprovada.
-- NAO executado em producao nesta etapa.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='5min';
CREATE TEMP TABLE sigo_preservacao(tabela text PRIMARY KEY,linhas jsonb) ON COMMIT DROP;
DO $captura$
DECLARE t record;conteudo jsonb;
BEGIN
 FOR t IN SELECT c.relname FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind='r' ORDER BY c.relname LOOP
  EXECUTE format('LOCK TABLE public.%I IN SHARE ROW EXCLUSIVE MODE',t.relname);
  EXECUTE format('SELECT coalesce(jsonb_agg(rowdata ORDER BY rowdata::text),''[]''::jsonb) FROM (SELECT to_jsonb(x) - CASE WHEN %L=''sla_config'' THEN ARRAY[''prazo_reentrega_dias'',''status_gm_entregue''] WHEN %L=''pendencias_importacao'' THEN ARRAY[''nf_id''] ELSE ARRAY[]::text[] END rowdata FROM public.%I x) q',t.relname,t.relname,t.relname) INTO conteudo;
  INSERT INTO sigo_preservacao VALUES(t.relname,conteudo);
 END LOOP;
END; $captura$;
\ir ../migrations/20261117194733_sigo_reentrega_transferencia.sql
DO $confere$
DECLARE t record;conteudo jsonb;
BEGIN
 FOR t IN SELECT * FROM sigo_preservacao ORDER BY tabela LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(rowdata ORDER BY rowdata::text),''[]''::jsonb) FROM (SELECT to_jsonb(x) - CASE WHEN %L=''sla_config'' THEN ARRAY[''prazo_reentrega_dias'',''status_gm_entregue''] WHEN %L=''pendencias_importacao'' THEN ARRAY[''nf_id''] ELSE ARRAY[]::text[] END rowdata FROM public.%I x) q',t.tabela,t.tabela,t.tabela) INTO conteudo;
  IF conteudo IS DISTINCT FROM t.linhas THEN RAISE EXCEPTION 'Preservacao falhou na tabela %; reverter transacao',t.tabela; END IF;
 END LOOP;
END; $confere$;
COMMIT;
