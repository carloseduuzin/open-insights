-- SIGO Etapa 4: backend de bipagem de canhotos.
-- Dependência: baseline 00200, SLA 00300, StopView 00400 e VT 00450.
-- Nunca aplicar no Supabase hospedado sem reconciliar seu histórico remoto.
-- Dados brutos de rotas, paradas e NF permanecem imutáveis; chave_acesso é
-- preenchida UMA vez por bipe de chave válida, por autorização explícita.

CREATE TABLE IF NOT EXISTS public.bipagens (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo_lido text NOT NULL,
  codigo_normalizado text,
  resultado text NOT NULL CHECK (resultado IN (
    'OK','JA_BIPADA','ROTA_DIFERENTE','NAO_ENCONTRADA',
    'PRESTACAO_FECHADA','SEM_PRESTACAO','CODIGO_INVALIDO')),
  nf_id uuid REFERENCES public.notas_fiscais(id),
  prestacao_id uuid REFERENCES public.prestacoes(id),
  rota_execucao_id uuid REFERENCES public.rotas(id),
  usuario_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  dispositivo text,
  bipado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS bipagens_prestacao_em_idx
  ON public.bipagens(prestacao_id, bipado_em DESC);
CREATE INDEX IF NOT EXISTS bipagens_em_idx
  ON public.bipagens(bipado_em DESC);
CREATE INDEX IF NOT EXISTS bipagens_falhas_idx
  ON public.bipagens(resultado) WHERE resultado IN ('NAO_ENCONTRADA','SEM_PRESTACAO');

ALTER TABLE public.bipagens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bipagens FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.bipagens TO authenticated;
DROP POLICY IF EXISTS bipagens_read ON public.bipagens;
CREATE POLICY bipagens_read ON public.bipagens FOR SELECT TO authenticated
  USING ((SELECT public.sigo_is_active()));

CREATE TABLE IF NOT EXISTS public.prestacao_nota_justificativas (
  prestacao_id uuid NOT NULL REFERENCES public.prestacoes(id),
  nf_id uuid NOT NULL REFERENCES public.notas_fiscais(id),
  motivo text NOT NULL CHECK (motivo IN
    ('DEVOLUCAO','REENTREGA_PROGRAMADA','REQUISICAO','RECOLHA','EXTRAVIO','OUTRO')),
  observacao text,
  usuario_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  criado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (prestacao_id,nf_id),
  CONSTRAINT justificativas_observacao_check CHECK (
    motivo NOT IN ('EXTRAVIO','OUTRO') OR NULLIF(btrim(observacao),'') IS NOT NULL)
);
ALTER TABLE public.prestacao_nota_justificativas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.prestacao_nota_justificativas FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.prestacao_nota_justificativas TO authenticated;
DROP POLICY IF EXISTS prestacao_nota_justificativas_read ON public.prestacao_nota_justificativas;
CREATE POLICY prestacao_nota_justificativas_read
  ON public.prestacao_nota_justificativas FOR SELECT TO authenticated
  USING ((SELECT public.sigo_is_active()));

CREATE INDEX IF NOT EXISTS notas_fiscais_numero_serie_idx
  ON public.notas_fiscais(numero,serie);

-- Equivalente estrito a normalizarNF(valor: string) no TypeScript:
-- .trim() APENAS nas extremidades; formato interno nunca é higienizado.
-- 44 dígitos -> chave; de 1 a 9 dígitos + hífen/série 1 a 3
-- -> número com 9 dígitos + série sem zeros; sem hífen -> número-?.
CREATE OR REPLACE FUNCTION public.sigo_normalizar_codigo_canhoto(codigo text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=''
AS $normalize$
DECLARE v text; v_num text; v_serie text;
BEGIN
  IF codigo IS NULL THEN RETURN NULL; END IF;
  v := btrim(codigo,E' \t\n\r\f\v');
  IF v ~ '^[0-9]{44}$' THEN RETURN v; END IF;
  IF v ~ '^[0-9]{1,9}-[0-9]{1,3}$' THEN
    v_num := lpad(split_part(v,'-',1),9,'0');
    v_serie := (split_part(v,'-',2)::integer)::text;
    RETURN v_num||'-'||v_serie;
  END IF;
  IF v ~ '^[0-9]{1,9}$' THEN RETURN lpad(v,9,'0')||'-?'; END IF;
  RETURN NULL;
END;
$normalize$;

-- View agregada da prestação; NF da origem conta mesmo sem prestacao_notas
-- prévia. A NF justificada continua faltante fisicamente até receber canhoto.
CREATE OR REPLACE VIEW public.v_prestacao_progresso
WITH (security_invoker=true) AS
WITH universo AS (
  SELECT p.id prestacao_id,pn.nf_id
  FROM public.prestacoes p JOIN public.prestacao_notas pn ON pn.prestacao_id=p.id
  UNION
  SELECT p.id,nf.id
  FROM public.prestacoes p JOIN public.notas_fiscais nf
    ON nf.romaneio_origem=p.romaneio_oficial
),
agg AS (
  SELECT p.id prestacao_id,
    count(u.nf_id)::int AS total_nfs,
    count(u.nf_id) FILTER (WHERE pn.canhoto_recebido_em IS NOT NULL)::int AS bipados,
    min(pn.canhoto_recebido_em) primeiro_bipe_em,
    max(pn.canhoto_recebido_em) ultimo_bipe_em
  FROM public.prestacoes p
  LEFT JOIN universo u ON u.prestacao_id=p.id
  LEFT JOIN public.prestacao_notas pn
    ON pn.nf_id=u.nf_id AND pn.prestacao_id=p.id
  GROUP BY p.id
)
SELECT p.id AS prestacao_id,p.romaneio_oficial,p.status,
  a.total_nfs,a.bipados,(a.total_nfs-a.bipados) AS faltantes,
  CASE WHEN a.total_nfs=0 THEN 0::numeric
    ELSE round(100.0*a.bipados/a.total_nfs,2) END AS pct_bipado,
  a.primeiro_bipe_em,a.ultimo_bipe_em,
  CASE WHEN p.retornada_em IS NOT NULL AND p.conferida_em IS NOT NULL
    THEN extract(epoch FROM (p.conferida_em-p.retornada_em))/60
    ELSE NULL END AS minutos_retorno_ate_conferencia
FROM public.prestacoes p JOIN agg a ON a.prestacao_id=p.id;

REVOKE ALL ON public.v_prestacao_progresso FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_prestacao_progresso TO authenticated;

-- Somente a RPC pode justificar; perfil ativo + NF pertencente à origem.
CREATE OR REPLACE FUNCTION public.sigo_justificar_faltante(
  p_prestacao_id uuid,p_nf_id uuid,p_motivo text,p_observacao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $justify$
DECLARE v_usuario uuid := (SELECT auth.uid());
  v_rom text; v_nf_rom text; v_recebido timestamptz;
BEGIN
  IF v_usuario IS NULL OR NOT (SELECT public.sigo_is_active()) THEN
    RAISE EXCEPTION 'Usuário sem acesso ativo ao SIGO';
  END IF;
  IF p_motivo NOT IN ('DEVOLUCAO','REENTREGA_PROGRAMADA','REQUISICAO','RECOLHA','EXTRAVIO','OUTRO')
    OR p_motivo IS NULL THEN RAISE EXCEPTION 'Motivo de justificativa inválido'; END IF;
  IF p_motivo IN ('EXTRAVIO','OUTRO') AND NULLIF(btrim(p_observacao),'') IS NULL THEN
    RAISE EXCEPTION 'Observação obrigatória para EXTRAVIO ou OUTRO';
  END IF;
  SELECT romaneio_oficial INTO STRICT v_rom FROM public.prestacoes
    WHERE id=p_prestacao_id AND status IN ('ABERTA','RETORNADA');
  SELECT romaneio_origem INTO STRICT v_nf_rom FROM public.notas_fiscais WHERE id=p_nf_id;
  IF v_nf_rom IS DISTINCT FROM v_rom THEN
    RAISE EXCEPTION 'NF não pertence ao romaneio de origem da prestação';
  END IF;
  SELECT canhoto_recebido_em INTO v_recebido FROM public.prestacao_notas
    WHERE prestacao_id=p_prestacao_id AND nf_id=p_nf_id;
  IF v_recebido IS NOT NULL THEN RAISE EXCEPTION 'NF já possui canhoto recebido'; END IF;
  INSERT INTO public.prestacao_nota_justificativas(
    prestacao_id,nf_id,motivo,observacao,usuario_id)
  VALUES (p_prestacao_id,p_nf_id,p_motivo,NULLIF(btrim(p_observacao),''),v_usuario)
  ON CONFLICT (prestacao_id,nf_id) DO NOTHING;
  RETURN jsonb_build_object('prestacao_id',p_prestacao_id,'nf_id',p_nf_id,
    'motivo',p_motivo,'registrada',true);
END;
$justify$;

CREATE OR REPLACE FUNCTION public.sigo_canhotos_faltantes(p_prestacao_id uuid)
RETURNS TABLE(numero text,serie text,cliente text,status_gm text,tipo_execucao text,justificativa text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $missing$
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT (SELECT public.sigo_is_active()) THEN
    RAISE EXCEPTION 'Usuário sem acesso ativo ao SIGO';
  END IF;
  RETURN QUERY
  WITH ids AS (
    SELECT pn.nf_id FROM public.prestacao_notas pn
      WHERE pn.prestacao_id=p_prestacao_id
    UNION
    SELECT nf.id FROM public.notas_fiscais nf
      JOIN public.prestacoes p ON p.romaneio_oficial=nf.romaneio_origem
      WHERE p.id=p_prestacao_id
  )
  SELECT nf.numero::text,nf.serie,pa.cliente,pa.status_gm,ne.tipo,j.motivo
  FROM ids JOIN public.notas_fiscais nf ON nf.id=ids.nf_id
  LEFT JOIN public.prestacao_notas pn ON pn.nf_id=nf.id AND pn.prestacao_id=p_prestacao_id
  LEFT JOIN LATERAL (
    SELECT p.cliente,p.status_gm FROM public.parada_notas pn2
      JOIN public.paradas p ON p.id=pn2.parada_id
      JOIN public.rotas r ON r.id=p.rota_id
    WHERE pn2.nf_id=nf.id AND r.tipo_rota='ENTREGA'
    ORDER BY p.data_rota DESC NULLS LAST,p.id DESC LIMIT 1
  ) pa ON true
  LEFT JOIN LATERAL (
    SELECT e.tipo FROM public.nf_execucoes e
      JOIN public.rotas r ON r.id=e.rota_id AND r.tipo_rota='ENTREGA'
    WHERE e.nf_id=nf.id
    ORDER BY e.iniciada_em DESC,e.id DESC LIMIT 1
  ) ne ON true
  LEFT JOIN public.prestacao_nota_justificativas j
    ON j.prestacao_id=p_prestacao_id AND j.nf_id=nf.id
  WHERE pn.canhoto_recebido_em IS NULL
  ORDER BY nf.numero,nf.serie;
END;
$missing$;

-- Imutabilidade no próprio banco (inclusive se um futuro grant mudar).
CREATE OR REPLACE FUNCTION public.sigo_guard_bipagens_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path=''
AS $append$
BEGIN RAISE EXCEPTION 'Bipagens são append-only'; END;
$append$;
DROP TRIGGER IF EXISTS bipagens_append_only ON public.bipagens;
CREATE TRIGGER bipagens_append_only BEFORE UPDATE OR DELETE ON public.bipagens
  FOR EACH ROW EXECUTE FUNCTION public.sigo_guard_bipagens_append_only();

CREATE OR REPLACE FUNCTION public.sigo_bipar_canhoto(
  p_codigo text,p_dispositivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $scan$
DECLARE
  v_usuario uuid := (SELECT auth.uid());
  v_norm text := public.sigo_normalizar_codigo_canhoto(p_codigo);
  v_numero text;v_serie text;v_nf public.notas_fiscais%ROWTYPE;
  v_p public.prestacoes%ROWTYPE;
  v_vinculo public.prestacao_notas%ROWTYPE;
  v_exec record;v_origem record;v_usuario_anterior text;
  v_nf_cont integer;v_resultado text;v_detalhe text;
  v_anterior jsonb;v_exec_json jsonb;v_origem_json jsonb;
  v_nf_json jsonb;v_p_json jsonb;v_progresso jsonb;
  v_now timestamptz;v_prestacao_id uuid;v_nf_id uuid;
BEGIN
  IF v_usuario IS NULL OR NOT (SELECT public.sigo_is_active()) THEN
    RAISE EXCEPTION 'Usuário sem acesso ativo ao SIGO';
  END IF;
  v_resultado:='CODIGO_INVALIDO';
  IF v_norm IS NULL THEN
    v_detalhe:='FORMATO_INVALIDO';
    GOTO finalizar;
  END IF;
  IF length(v_norm)=44 THEN
    v_numero:=substr(v_norm,26,9);
    v_serie:=(substr(v_norm,23,3)::integer)::text;
    -- Pelo número/série, não pela chave ainda ausente no StopView.
    SELECT count(*) INTO v_nf_cont FROM public.notas_fiscais
      WHERE numero=v_numero AND serie=v_serie;
    IF v_nf_cont=1 THEN
      SELECT * INTO v_nf FROM public.notas_fiscais
        WHERE numero=v_numero AND serie=v_serie FOR UPDATE;
    ELSIF v_nf_cont>1 THEN
      v_detalhe:='AMBIGUA';
    END IF;
  ELSE
    v_numero:=split_part(v_norm,'-',1);
    v_serie:=split_part(v_norm,'-',2);
    IF v_serie='?' THEN
      SELECT count(*) INTO v_nf_cont FROM public.notas_fiscais WHERE numero=v_numero;
      IF v_nf_cont=1 THEN
        SELECT * INTO v_nf FROM public.notas_fiscais WHERE numero=v_numero FOR UPDATE;
      ELSIF v_nf_cont>1 THEN
        v_detalhe:='AMBIGUA';
      END IF;
    ELSE
      SELECT count(*) INTO v_nf_cont FROM public.notas_fiscais
        WHERE numero=v_numero AND serie=v_serie;
      IF v_nf_cont=1 THEN
        SELECT * INTO v_nf FROM public.notas_fiscais
          WHERE numero=v_numero AND serie=v_serie FOR UPDATE;
      ELSIF v_nf_cont>1 THEN
        v_detalhe:='AMBIGUA';
      END IF;
    END IF;
  END IF;
  v_resultado:='NAO_ENCONTRADA';
  IF v_nf.id IS NULL THEN GOTO finalizar; END IF;
  v_nf_id:=v_nf.id;

  -- NF de abastecimento VUC nunca pode entrar na bipagem.
  IF v_nf.origem_rota_id IS NOT NULL AND EXISTS(
    SELECT 1 FROM public.rotas WHERE id=v_nf.origem_rota_id
      AND tipo_rota='ABASTECIMENTO') THEN
    v_detalhe:='ABASTECIMENTO';v_nf_id:=NULL;
    GOTO finalizar;
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.nf_execucoes e
    JOIN public.rotas r ON r.id=e.rota_id
    WHERE e.nf_id=v_nf.id AND r.tipo_rota='ABASTECIMENTO') THEN
    v_detalhe:='ABASTECIMENTO';v_nf_id:=NULL;
    GOTO finalizar;
  END IF;
  IF length(v_norm)=44 AND v_nf.chave_acesso IS NOT NULL
     AND v_nf.chave_acesso::text<>v_norm THEN
    v_detalhe:='CHAVE_DIVERGENTE';GOTO finalizar;
  END IF;
  SELECT * INTO v_p FROM public.prestacoes
    WHERE romaneio_oficial=v_nf.romaneio_origem FOR UPDATE;
  v_resultado:='SEM_PRESTACAO';
  IF v_p.id IS NULL THEN GOTO finalizar; END IF;
  v_prestacao_id:=v_p.id;
  v_resultado:='PRESTACAO_FECHADA';
  IF v_p.status IN ('ENVIADA_JTI','CONFIRMADA_JTI') THEN GOTO finalizar; END IF;

  -- Campo fiscal opcional que o StopView não possuía na primeira importação.
  -- Gravar uma vez, nunca reescrever ou trocar número/série/romaneio de origem.
  IF length(v_norm)=44 AND v_nf.chave_acesso IS NULL THEN
    UPDATE public.notas_fiscais SET chave_acesso=v_norm WHERE id=v_nf.id
      AND chave_acesso IS NULL;
    v_nf.chave_acesso:=v_norm;
  END IF;

  INSERT INTO public.prestacao_notas(prestacao_id,nf_id)
    VALUES (v_p.id,v_nf.id) ON CONFLICT(nf_id) DO NOTHING;
  SELECT * INTO v_vinculo FROM public.prestacao_notas
    WHERE nf_id=v_nf.id FOR UPDATE;
  IF v_vinculo.prestacao_id IS DISTINCT FROM v_p.id THEN
    v_resultado:='SEM_PRESTACAO';v_detalhe:='VINCULO_DIVERGENTE';GOTO finalizar;
  END IF;
  IF v_vinculo.canhoto_recebido_em IS NOT NULL THEN
    v_resultado:='JA_BIPADA';
    SELECT nome INTO v_usuario_anterior FROM public.profiles
      WHERE id=v_vinculo.canhoto_recebido_por;
    v_anterior:=jsonb_build_object('nome',v_usuario_anterior,
      'usuario_id',v_vinculo.canhoto_recebido_por,'em',v_vinculo.canhoto_recebido_em);
    GOTO finalizar;
  END IF;

  v_now:=clock_timestamp();
  UPDATE public.prestacao_notas
    SET canhoto_recebido_em=v_now,canhoto_recebido_por=v_usuario
    WHERE prestacao_id=v_p.id AND nf_id=v_nf.id;
  INSERT INTO public.nf_eventos(nf_id,tipo,usuario_id)
    VALUES (v_nf.id,'CANHOTO',v_usuario);

  SELECT e.rota_id,r.codigo,r.data_rota INTO v_exec
  FROM public.nf_execucoes e JOIN public.rotas r ON r.id=e.rota_id
  WHERE e.nf_id=v_nf.id AND r.tipo_rota='ENTREGA'
  ORDER BY e.iniciada_em DESC,e.id DESC LIMIT 1;
  IF v_exec.rota_id IS NOT NULL AND v_nf.origem_rota_id IS DISTINCT FROM v_exec.rota_id THEN
    v_resultado:='ROTA_DIFERENTE';
    v_exec_json:=jsonb_build_object('codigo',v_exec.codigo,'data',v_exec.data_rota);
  ELSE v_resultado:='OK'; END IF;

  IF v_p.status='ABERTA' THEN
    PERFORM id FROM public.sigo_avancar_prestacao(v_p.id,'RETORNADA');
    SELECT * INTO v_p FROM public.prestacoes WHERE id=v_p.id;
  END IF;

  <<finalizar>>
  -- Registrar TODA leitura autorizada, inclusive códigos inválidos/sem NF.
  INSERT INTO public.bipagens(
    codigo_lido,codigo_normalizado,resultado,nf_id,prestacao_id,
    rota_execucao_id,usuario_id,dispositivo)
  VALUES(coalesce(p_codigo,''),v_norm,v_resultado,v_nf_id,v_prestacao_id,
    CASE WHEN v_resultado='ROTA_DIFERENTE' THEN v_exec.rota_id ELSE NULL END,
    v_usuario,p_dispositivo);
  IF v_nf_id IS NOT NULL THEN
    v_nf_json:=jsonb_build_object('id',v_nf.id,'numero',v_nf.numero,
      'serie',v_nf.serie,'chave_acesso',v_nf.chave_acesso);
    SELECT r.codigo,r.data_rota INTO v_origem FROM public.rotas r
      WHERE r.id=v_nf.origem_rota_id;
    IF v_origem.codigo IS NOT NULL THEN
      v_origem_json:=jsonb_build_object('codigo',v_origem.codigo,'data',v_origem.data_rota);
    END IF;
  END IF;
  IF v_prestacao_id IS NOT NULL THEN
    SELECT * INTO v_p FROM public.prestacoes WHERE id=v_prestacao_id;
    v_p_json:=jsonb_build_object('id',v_p.id,
      'romaneio_oficial',v_p.romaneio_oficial,'d0',v_p.d0,'status',v_p.status);
    SELECT jsonb_build_object('total',total_nfs,'bipados',bipados,'faltantes',faltantes)
      INTO v_progresso FROM public.v_prestacao_progresso
      WHERE prestacao_id=v_prestacao_id;
  END IF;
  RETURN jsonb_build_object('resultado',v_resultado,'detalhe',v_detalhe,
    'nf',v_nf_json,'prestacao',v_p_json,'rota_origem',v_origem_json,
    'rota_execucao',v_exec_json,'bipada_anteriormente_por',v_anterior,
    'progresso',v_progresso);
END;
$scan$;


-- Hardening: gate de conferência sem alterar outras transições.
CREATE OR REPLACE FUNCTION public.sigo_avancar_prestacao(p_prestacao_id uuid, p_etapa text)
 RETURNS TABLE(id uuid, status text, registrado_em timestamp with time zone, registrado_por uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_usuario uuid := (select auth.uid()); v_faltantes integer;
begin
 if v_usuario is null or not (select public.sigo_is_active()) then
  raise exception 'Usuário sem acesso ativo ao SIGO';
 end if;
 if p_etapa not in ('RETORNADA','CONFERIDA') then
  raise exception 'Etapa não permitida';
 end if;
 if p_etapa='RETORNADA' then
  return query
  update public.prestacoes p
    set status='RETORNADA', retornada_em=clock_timestamp()
  where p.id=p_prestacao_id and p.status='ABERTA' and p.retornada_em is null
  returning p.id,p.status,p.retornada_em,p.responsavel_id;
 else
  -- Conferência requer bipe ou justificativa para toda NF da origem fiscal.
  select count(*) into v_faltantes
  from (
    select pn.nf_id from public.prestacao_notas pn
      where pn.prestacao_id=p_prestacao_id
    union
    select nf.id from public.notas_fiscais nf
      join public.prestacoes p on p.romaneio_oficial=nf.romaneio_origem
      where p.id=p_prestacao_id
  ) todos
  left join public.prestacao_notas pn
    on pn.nf_id=todos.nf_id and pn.prestacao_id=p_prestacao_id
  left join public.prestacao_nota_justificativas j
    on j.nf_id=todos.nf_id and j.prestacao_id=p_prestacao_id
  where pn.canhoto_recebido_em is null and j.nf_id is null;
  if v_faltantes>0 then
    raise exception 'Prestação com % canhoto(s) sem bipagem nem justificativa',v_faltantes;
  end if;
  return query
  update public.prestacoes p
    set status='CONFERIDA', conferida_em=clock_timestamp(), conferida_por=v_usuario
  where p.id=p_prestacao_id and p.status='RETORNADA' and p.conferida_em is null
  returning p.id,p.status,p.conferida_em,p.conferida_por;
 end if;
 if not found then raise exception 'Prestação não encontrada ou etapa anterior não concluída'; end if;
end; $function$;


-- Privilégios explícitos das RPCs (não conceder INSERT direto em tabelas).
REVOKE ALL ON FUNCTION public.sigo_normalizar_codigo_canhoto(text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_normalizar_codigo_canhoto(text) TO authenticated;
REVOKE ALL ON FUNCTION public.sigo_bipar_canhoto(text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_bipar_canhoto(text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.sigo_canhotos_faltantes(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_canhotos_faltantes(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.sigo_justificar_faltante(uuid,uuid,text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_justificar_faltante(uuid,uuid,text,text)
  TO authenticated;
