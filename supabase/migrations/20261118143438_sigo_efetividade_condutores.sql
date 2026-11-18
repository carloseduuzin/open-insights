ALTER TABLE public.sla_config ADD COLUMN status_gm_nao_entregue text[] NOT NULL DEFAULT '{}';
CREATE TABLE public.condutor_frequencias(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),nome_condutor text NOT NULL CHECK(length(btrim(nome_condutor)) BETWEEN 2 AND 160),
 data date NOT NULL,situacao text NOT NULL CHECK(situacao IN ('ESCALADO','PRESENTE','ATRASO','FALTA','FALTA_JUSTIFICADA','FOLGA')),
 minutos_atraso integer NOT NULL DEFAULT 0 CHECK(minutos_atraso BETWEEN 0 AND 1440),observacao text,
 criada_em timestamptz NOT NULL DEFAULT clock_timestamp(),criada_por uuid NOT NULL REFERENCES auth.users(id),
 atualizada_em timestamptz NOT NULL DEFAULT clock_timestamp(),atualizada_por uuid NOT NULL REFERENCES auth.users(id),
 UNIQUE(nome_condutor,data),CHECK((situacao='ATRASO' AND minutos_atraso>0) OR (situacao<>'ATRASO' AND minutos_atraso=0))
);
CREATE INDEX condutor_frequencias_data_idx ON public.condutor_frequencias(data,nome_condutor);
CREATE TABLE public.condutor_frequencia_auditoria(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,frequencia_id uuid NOT NULL REFERENCES public.condutor_frequencias(id),
 anterior jsonb,novo jsonb NOT NULL,usuario_id uuid NOT NULL REFERENCES auth.users(id),ocorrido_em timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX condutor_frequencia_auditoria_freq_idx ON public.condutor_frequencia_auditoria(frequencia_id,ocorrido_em);
REVOKE ALL ON SEQUENCE public.condutor_frequencia_auditoria_id_seq FROM PUBLIC,anon,authenticated;
CREATE INDEX rotas_motorista_periodo_idx ON public.rotas(data_rota,motorista_gm) WHERE tipo_rota='ENTREGA';
CREATE INDEX paradas_efetividade_rota_data_idx ON public.paradas(rota_id,data_rota,id) INCLUDE(status_gm);
ALTER TABLE public.condutor_frequencias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.condutor_frequencia_auditoria ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.condutor_frequencias,public.condutor_frequencia_auditoria FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.condutor_frequencias,public.condutor_frequencia_auditoria TO authenticated;
CREATE POLICY frequencia_admin_read ON public.condutor_frequencias FOR SELECT TO authenticated USING((SELECT public.sigo_is_active()) AND (SELECT public.sigo_has_role('admin')));
CREATE POLICY frequencia_auditoria_admin_read ON public.condutor_frequencia_auditoria FOR SELECT TO authenticated USING((SELECT public.sigo_is_active()) AND (SELECT public.sigo_has_role('admin')));

CREATE FUNCTION public.sigo_registrar_frequencia(p_nome text,p_data date,p_situacao text,p_minutos_atraso integer DEFAULT 0,p_observacao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();nome text:=btrim(p_nome);obs text:=nullif(btrim(p_observacao),'');ant public.condutor_frequencias%ROWTYPE;novo public.condutor_frequencias%ROWTYPE;
 hoje date:=(statement_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 IF NOT public.sigo_has_role('admin') THEN RAISE EXCEPTION 'Controle de condutores exclusivo do administrador'; END IF;
 IF nome IS NULL OR length(nome) NOT BETWEEN 2 AND 160 OR p_data IS NULL OR p_data>hoje+365 OR p_situacao IS NULL OR p_situacao NOT IN ('ESCALADO','PRESENTE','ATRASO','FALTA','FALTA_JUSTIFICADA','FOLGA') THEN RAISE EXCEPTION 'Nome, data ou situacao invalidos'; END IF;
 IF p_data>hoje AND p_situacao NOT IN ('ESCALADO','FOLGA') THEN RAISE EXCEPTION 'Nao confirmar presenca ou falta em data futura'; END IF;
 IF p_minutos_atraso IS NULL OR p_minutos_atraso NOT BETWEEN 0 AND 1440 OR (p_situacao='ATRASO' AND p_minutos_atraso=0) OR (p_situacao<>'ATRASO' AND p_minutos_atraso<>0) THEN RAISE EXCEPTION 'Informe minutos positivos somente para atraso'; END IF;
 IF p_situacao='FALTA_JUSTIFICADA' AND obs IS NULL THEN RAISE EXCEPTION 'Informe a justificativa da ausencia'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(nome||'|'||p_data::text,0));
 SELECT * INTO ant FROM public.condutor_frequencias WHERE nome_condutor=nome AND data=p_data FOR UPDATE;
 IF ant.id IS NOT NULL AND ant.situacao=p_situacao AND ant.minutos_atraso=p_minutos_atraso AND ant.observacao IS NOT DISTINCT FROM obs THEN RETURN jsonb_build_object('registrada',true,'alterada',false,'id',ant.id); END IF;
 IF ant.id IS NOT NULL AND ant.situacao<>'ESCALADO' AND ant.situacao<>p_situacao AND obs IS NULL THEN RAISE EXCEPTION 'Correcao de presenca exige observacao'; END IF;
 INSERT INTO public.condutor_frequencias(nome_condutor,data,situacao,minutos_atraso,observacao,criada_por,atualizada_por)
 VALUES(nome,p_data,p_situacao,p_minutos_atraso,obs,u,u)
 ON CONFLICT(nome_condutor,data) DO UPDATE SET situacao=excluded.situacao,minutos_atraso=excluded.minutos_atraso,observacao=excluded.observacao,atualizada_em=clock_timestamp(),atualizada_por=u RETURNING * INTO novo;
 INSERT INTO public.condutor_frequencia_auditoria(frequencia_id,anterior,novo,usuario_id) VALUES(novo.id,CASE WHEN ant.id IS NULL THEN NULL ELSE to_jsonb(ant) END,to_jsonb(novo),u);
 RETURN jsonb_build_object('registrada',true,'alterada',true,'id',novo.id);
END; $$;

CREATE FUNCTION public.sigo_configurar_resultados_condutores(p_entregues text[],p_nao_entregues text[]) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM sigo_interno.exigir_operador();
 IF NOT public.sigo_has_role('admin') THEN RAISE EXCEPTION 'Controle de condutores exclusivo do administrador'; END IF;
 IF p_entregues IS NULL OR p_nao_entregues IS NULL OR p_entregues&&p_nao_entregues OR array_position(p_entregues,NULL) IS NOT NULL OR array_position(p_nao_entregues,NULL) IS NOT NULL
 OR EXISTS(SELECT 1 FROM unnest(p_entregues||p_nao_entregues) s WHERE nullif(btrim(s),'') IS NULL) THEN RAISE EXCEPTION 'Mapas de resultado invalidos ou sobrepostos'; END IF;
 UPDATE public.sla_config SET status_gm_entregue=p_entregues,status_gm_nao_entregue=p_nao_entregues WHERE id;
END; $$;

CREATE FUNCTION public.sigo_consultar_efetividade(p_inicio date,p_fim date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=sigo_interno.exigir_operador();resultado jsonb;
BEGIN
 IF NOT public.sigo_has_role('admin') THEN RAISE EXCEPTION 'Controle de condutores exclusivo do administrador'; END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>92 THEN RAISE EXCEPTION 'Escolha periodo de ate 93 dias'; END IF;
 WITH nomes AS (
  SELECT DISTINCT btrim(motorista_gm) nome FROM public.rotas WHERE data_rota BETWEEN p_inicio AND p_fim AND tipo_rota='ENTREGA' AND nullif(btrim(motorista_gm),'') IS NOT NULL
  UNION SELECT DISTINCT nome_condutor FROM public.condutor_frequencias WHERE data BETWEEN p_inicio AND p_fim
 ), itens AS (
  SELECT n.nome,
   coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'data',f.data,'situacao',f.situacao,'minutos_atraso',f.minutos_atraso,'observacao',f.observacao) ORDER BY f.data) FROM public.condutor_frequencias f WHERE f.nome_condutor=n.nome AND f.data BETWEEN p_inicio AND p_fim),'[]'::jsonb) frequencias,
   (SELECT count(*) FROM public.rotas r WHERE btrim(r.motorista_gm)=n.nome AND r.data_rota BETWEEN p_inicio AND p_fim AND r.tipo_rota='ENTREGA') rotas,
   e.paradas,e.entregues,e.nao_entregues,e.sem_resultado,
   (SELECT count(*) FROM public.nf_reentregas re WHERE btrim(re.motorista_falha)=n.nome AND (re.registrada_em AT TIME ZONE 'America/Sao_Paulo')::date BETWEEN p_inicio AND p_fim AND re.responsabilidade='CLIENTE') reentregas_cliente,
   (SELECT count(*) FROM public.nf_reentregas re WHERE btrim(re.motorista_falha)=n.nome AND (re.registrada_em AT TIME ZONE 'America/Sao_Paulo')::date BETWEEN p_inicio AND p_fim AND re.responsabilidade='OPERACAO') reentregas_operacao
  FROM nomes n CROSS JOIN LATERAL (
   SELECT count(DISTINCT p.id) paradas,
    count(DISTINCT p.id) FILTER(WHERE p.status_gm=ANY(cfg.status_gm_entregue)) entregues,
    count(DISTINCT p.id) FILTER(WHERE p.status_gm=ANY(cfg.status_gm_nao_entregue)) nao_entregues,
    count(DISTINCT p.id) FILTER(WHERE p.status_gm IS NULL OR NOT (p.status_gm=ANY(cfg.status_gm_entregue||cfg.status_gm_nao_entregue))) sem_resultado
   FROM public.paradas p JOIN public.rotas r ON r.id=p.rota_id CROSS JOIN public.sla_config cfg
   WHERE cfg.id AND btrim(r.motorista_gm)=n.nome AND r.tipo_rota='ENTREGA' AND p.data_rota BETWEEN p_inicio AND p_fim
   AND EXISTS(SELECT 1 FROM public.parada_notas pn WHERE pn.parada_id=p.id)
  ) e
 ) SELECT jsonb_build_object('inicio',p_inicio,'fim',p_fim,'condutores',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.nome),'[]'::jsonb),
 'regras',jsonb_build_object('pontos_presente',10,'pontos_atraso',7,'pontos_falta',0,'minimo_dias_classificar',5,'meta_presenca',95,'meta_entregas',95),
 'entrega_configurada',EXISTS(SELECT 1 FROM public.sla_config WHERE id AND cardinality(status_gm_entregue)>0 AND cardinality(status_gm_nao_entregue)>0)) INTO resultado FROM itens i;
 RETURN resultado;
END; $$;
REVOKE ALL ON FUNCTION public.sigo_registrar_frequencia(text,date,text,integer,text),public.sigo_configurar_resultados_condutores(text[],text[]),public.sigo_consultar_efetividade(date,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_registrar_frequencia(text,date,text,integer,text),public.sigo_configurar_resultados_condutores(text[],text[]),public.sigo_consultar_efetividade(date,date) TO authenticated;
