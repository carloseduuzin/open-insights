-- Retirada da listagem operacional; metadados e relacionamentos permanecem para o dashboard e auditoria.
ALTER TABLE public.prestacoes ADD COLUMN arquivada_em timestamptz;
ALTER TABLE public.prestacoes ADD COLUMN arquivada_lote uuid;
CREATE TABLE public.exportacoes_prestacoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),chave text UNIQUE NOT NULL,
 criada_em timestamptz NOT NULL DEFAULT clock_timestamp(),criada_por uuid NOT NULL REFERENCES auth.users(id),
 status text NOT NULL DEFAULT 'PREPARADA' CHECK(status IN ('PREPARADA','CONCLUIDA')),
 dados jsonb NOT NULL,sha256_dados text NOT NULL CHECK(sha256_dados ~ '^[0-9a-f]{64}$'),
 candidatos uuid[] NOT NULL DEFAULT '{}',arquivo_caminho text,arquivo_sha256 text,
 email_destino text,email_mensagem_id text,concluida_em timestamptz,arquivadas integer NOT NULL DEFAULT 0,
 CHECK(status<>'CONCLUIDA' OR (arquivo_caminho IS NOT NULL AND arquivo_sha256 ~ '^[0-9a-f]{64}$' AND email_destino='monitoramento@renovelog.com.br' AND length(email_mensagem_id)>0 AND concluida_em IS NOT NULL))
);
ALTER TABLE public.prestacoes ADD CONSTRAINT prestacoes_arquivo_lote_fk FOREIGN KEY(arquivada_lote) REFERENCES public.exportacoes_prestacoes(id);
ALTER TABLE public.prestacoes ADD CONSTRAINT prestacoes_arquivo_coerente CHECK((arquivada_em IS NULL)=(arquivada_lote IS NULL));
CREATE INDEX prestacoes_operacionais_d0_idx ON public.prestacoes(d0,id) WHERE arquivada_em IS NULL;
ALTER TABLE public.exportacoes_prestacoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.exportacoes_prestacoes FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.exportacoes_prestacoes TO authenticated;
CREATE POLICY exportacoes_admin_read ON public.exportacoes_prestacoes FOR SELECT TO authenticated USING((SELECT public.sigo_is_active()) AND (SELECT public.sigo_has_role('admin')));

CREATE VIEW public.v_dashboard_prestacoes WITH(security_invoker=true) AS
SELECT count(*) FILTER(WHERE status NOT IN ('ENVIADA_JTI','CONFIRMADA_JTI'))::integer pendentes,
 count(*) FILTER(WHERE status NOT IN ('ENVIADA_JTI','CONFIRMADA_JTI') AND (statement_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-d0>=4)::integer criticas,
 count(*) FILTER(WHERE status NOT IN ('ENVIADA_JTI','CONFIRMADA_JTI') AND (statement_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-d0=3)::integer urgentes,
 count(*) FILTER(WHERE status NOT IN ('ENVIADA_JTI','CONFIRMADA_JTI') AND (statement_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-d0=2)::integer alertas,
 count(*) FILTER(WHERE status IN ('ENVIADA_JTI','CONFIRMADA_JTI'))::integer baixadas,
 count(*) FILTER(WHERE arquivada_em IS NOT NULL)::integer arquivadas
FROM public.prestacoes;
REVOKE ALL ON public.v_dashboard_prestacoes FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.v_dashboard_prestacoes TO authenticated;

CREATE FUNCTION public.sigo_preparar_exportacao(p_chave text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();l public.exportacoes_prestacoes%ROWTYPE;conteudo jsonb;ids uuid[];agora timestamptz:=clock_timestamp();
BEGIN
 IF NOT public.sigo_has_role('admin') THEN RAISE EXCEPTION 'Exportacao exclusiva do administrador'; END IF;
 IF p_chave IS NULL OR p_chave !~ '^sigo-mensal-[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'Chave de exportacao invalida'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_chave,0));
 SELECT * INTO l FROM public.exportacoes_prestacoes WHERE chave=p_chave;
 IF l.id IS NOT NULL THEN RETURN jsonb_build_object('id',l.id,'status',l.status,'sha256_dados',l.sha256_dados,'dados',l.dados,'candidatos',l.candidatos,'email_mensagem_id',l.email_mensagem_id); END IF;
 SELECT coalesce(array_agg(p.id ORDER BY p.id),'{}') INTO ids FROM public.prestacoes p
 WHERE p.arquivada_em IS NULL AND p.status IN ('ENVIADA_JTI','CONFIRMADA_JTI')
 AND coalesce(p.confirmada_em,p.enviada_em)<=agora-interval '30 days'
 AND NOT EXISTS(SELECT 1 FROM public.nf_reentregas r WHERE r.prestacao_origem_id=p.id AND r.status IN ('AGUARDANDO','EM_ROTA','DEVOLUCAO_PENDENTE'));
 SELECT jsonb_build_object('extraido_em',agora,'corte_arquivamento',agora-interval '30 days',
 'prestacoes',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.prestacoes p),'[]'::jsonb),
 'notas_fiscais',coalesce((SELECT jsonb_agg(to_jsonb(n) ORDER BY n.id) FROM public.notas_fiscais n WHERE EXISTS(SELECT 1 FROM public.prestacao_notas pn WHERE pn.nf_id=n.id)),'[]'::jsonb),
 'prestacao_notas',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.prestacao_id,p.nf_id) FROM public.prestacao_notas p),'[]'::jsonb),
 'reentregas',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM public.nf_reentregas r),'[]'::jsonb),
 'transferencias',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.nf_transferencias t),'[]'::jsonb),
 'bipagens',coalesce((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.bipagens b),'[]'::jsonb),
 'justificativas',coalesce((SELECT jsonb_agg(to_jsonb(j) ORDER BY j.prestacao_id,j.nf_id) FROM public.prestacao_nota_justificativas j),'[]'::jsonb),
 'eventos_nf',coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id) FROM public.nf_eventos e),'[]'::jsonb),
 'execucoes',coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id) FROM public.nf_execucoes e),'[]'::jsonb),
 'rotas',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM public.rotas r),'[]'::jsonb),
 'paradas',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.paradas p),'[]'::jsonb),
 'parada_notas',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.parada_id,p.nf_id) FROM public.parada_notas p),'[]'::jsonb),
 'responsaveis',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'nome',p.nome) ORDER BY p.id) FROM public.profiles p),'[]'::jsonb)) INTO conteudo;
 INSERT INTO public.exportacoes_prestacoes(chave,criada_por,dados,sha256_dados,candidatos)
 VALUES(p_chave,u,conteudo,encode(sha256(convert_to(conteudo::text,'UTF8')),'hex'),ids) RETURNING * INTO l;
 RETURN jsonb_build_object('id',l.id,'status',l.status,'sha256_dados',l.sha256_dados,'dados',l.dados,'candidatos',l.candidatos);
END; $$;

CREATE FUNCTION public.sigo_concluir_exportacao(p_lote uuid,p_sha256_dados text,p_arquivo_caminho text,p_arquivo_sha256 text,p_email_mensagem_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();l public.exportacoes_prestacoes%ROWTYPE;quantidade integer;
BEGIN
 IF NOT public.sigo_has_role('admin') THEN RAISE EXCEPTION 'Exportacao exclusiva do administrador'; END IF;
 SELECT * INTO STRICT l FROM public.exportacoes_prestacoes WHERE id=p_lote FOR UPDATE;
 IF l.status='CONCLUIDA' THEN RETURN jsonb_build_object('status','JA_CONCLUIDA','arquivadas',l.arquivadas); END IF;
 IF p_sha256_dados IS DISTINCT FROM l.sha256_dados OR p_arquivo_sha256 IS NULL OR p_arquivo_sha256 !~ '^[0-9a-f]{64}$'
 OR nullif(btrim(p_arquivo_caminho),'') IS NULL OR p_arquivo_caminho !~* '\.xlsx$' OR nullif(btrim(p_email_mensagem_id),'') IS NULL THEN RAISE EXCEPTION 'Arquivo validado e comprovante de envio obrigatorios'; END IF;
 UPDATE public.prestacoes p SET arquivada_em=clock_timestamp(),arquivada_lote=l.id
 WHERE p.id=ANY(l.candidatos) AND p.arquivada_em IS NULL AND p.status IN ('ENVIADA_JTI','CONFIRMADA_JTI')
 AND coalesce(p.confirmada_em,p.enviada_em)<=(l.dados->>'corte_arquivamento')::timestamptz
 AND EXISTS(SELECT 1 FROM jsonb_array_elements(l.dados->'prestacoes') s WHERE s->>'id'=p.id::text AND (s-'arquivada_em'-'arquivada_lote')=(to_jsonb(p)-'arquivada_em'-'arquivada_lote'))
 AND NOT EXISTS(SELECT 1 FROM public.nf_reentregas r WHERE r.prestacao_origem_id=p.id AND r.status IN ('AGUARDANDO','EM_ROTA','DEVOLUCAO_PENDENTE'));
 GET DIAGNOSTICS quantidade=ROW_COUNT;
 UPDATE public.exportacoes_prestacoes SET status='CONCLUIDA',arquivo_caminho=p_arquivo_caminho,arquivo_sha256=p_arquivo_sha256,
 email_destino='monitoramento@renovelog.com.br',email_mensagem_id=p_email_mensagem_id,concluida_em=clock_timestamp(),arquivadas=quantidade WHERE id=l.id;
 RETURN jsonb_build_object('status','CONCLUIDA','arquivadas',quantidade,'candidatos',cardinality(l.candidatos));
END; $$;
REVOKE ALL ON FUNCTION public.sigo_preparar_exportacao(text),public.sigo_concluir_exportacao(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_preparar_exportacao(text),public.sigo_concluir_exportacao(uuid,text,text,text,text) TO authenticated;
