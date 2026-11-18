-- Corrige saidas antecipadas antes de carregar rota: campos escalares iniciam NULL.
-- Versao gerada pelo Supabase na aplicacao do hotfix validado com ROLLBACK.
CREATE OR REPLACE FUNCTION public.sigo_bipar_canhoto(p_codigo text, p_dispositivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_usuario uuid := (SELECT auth.uid());
  v_norm text := public.sigo_normalizar_codigo_canhoto(p_codigo);
  v_numero text;v_serie text;v_nf public.notas_fiscais%ROWTYPE;
  v_p public.prestacoes%ROWTYPE;
  v_vinculo public.prestacao_notas%ROWTYPE;
  v_exec_rota_id uuid;v_exec_codigo text;v_exec_data date;
  v_origem_codigo text;v_origem_data date;v_usuario_anterior text;
  v_nf_cont integer;v_resultado text;v_detalhe text;
  v_anterior jsonb;v_exec_json jsonb;v_origem_json jsonb;
  v_nf_json jsonb;v_p_json jsonb;v_progresso jsonb;
  v_now timestamptz;v_prestacao_id uuid;v_nf_id uuid;
BEGIN
  IF v_usuario IS NULL OR NOT (SELECT public.sigo_is_active()) THEN
    RAISE EXCEPTION 'Usuário sem acesso ativo ao SIGO';
  END IF;
  <<processar>>
  BEGIN
  v_resultado:='CODIGO_INVALIDO';
  IF v_norm IS NULL THEN
    v_detalhe:='FORMATO_INVALIDO';
    EXIT processar;
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
  IF v_nf.id IS NULL THEN EXIT processar; END IF;
  v_nf_id:=v_nf.id;

  -- NF de abastecimento VUC nunca pode entrar na bipagem.
  IF v_nf.origem_rota_id IS NOT NULL AND EXISTS(
    SELECT 1 FROM public.rotas WHERE id=v_nf.origem_rota_id
      AND tipo_rota='ABASTECIMENTO') THEN
    v_detalhe:='ABASTECIMENTO';v_nf_id:=NULL;
    EXIT processar;
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.nf_execucoes e
    JOIN public.rotas r ON r.id=e.rota_id
    WHERE e.nf_id=v_nf.id AND r.tipo_rota='ABASTECIMENTO') THEN
    v_detalhe:='ABASTECIMENTO';v_nf_id:=NULL;
    EXIT processar;
  END IF;
  IF length(v_norm)=44 AND v_nf.chave_acesso IS NOT NULL
     AND v_nf.chave_acesso::text<>v_norm THEN
    v_detalhe:='CHAVE_DIVERGENTE';EXIT processar;
  END IF;
  SELECT * INTO v_p FROM public.prestacoes
    WHERE romaneio_oficial=v_nf.romaneio_origem FOR UPDATE;
  v_resultado:='SEM_PRESTACAO';
  IF v_p.id IS NULL THEN EXIT processar; END IF;
  v_prestacao_id:=v_p.id;
  v_resultado:='PRESTACAO_FECHADA';
  IF v_p.status IN ('ENVIADA_JTI','CONFIRMADA_JTI') THEN EXIT processar; END IF;

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
    v_resultado:='SEM_PRESTACAO';v_detalhe:='VINCULO_DIVERGENTE';EXIT processar;
  END IF;
  IF v_vinculo.canhoto_recebido_em IS NOT NULL THEN
    v_resultado:='JA_BIPADA';
    SELECT nome INTO v_usuario_anterior FROM public.profiles
      WHERE id=v_vinculo.canhoto_recebido_por;
    v_anterior:=jsonb_build_object('nome',v_usuario_anterior,
      'usuario_id',v_vinculo.canhoto_recebido_por,'em',v_vinculo.canhoto_recebido_em);
    EXIT processar;
  END IF;

  v_now:=clock_timestamp();
  UPDATE public.prestacao_notas
    SET canhoto_recebido_em=v_now,canhoto_recebido_por=v_usuario
    WHERE prestacao_id=v_p.id AND nf_id=v_nf.id;
  INSERT INTO public.nf_eventos(nf_id,tipo,usuario_id)
    VALUES (v_nf.id,'CANHOTO',v_usuario);

  SELECT e.rota_id,r.codigo,r.data_rota INTO v_exec_rota_id,v_exec_codigo,v_exec_data
  FROM public.nf_execucoes e JOIN public.rotas r ON r.id=e.rota_id
  WHERE e.nf_id=v_nf.id AND r.tipo_rota='ENTREGA'
  ORDER BY e.iniciada_em DESC,e.id DESC LIMIT 1;
  IF v_exec_rota_id IS NOT NULL AND v_nf.origem_rota_id IS DISTINCT FROM v_exec_rota_id THEN
    v_resultado:='ROTA_DIFERENTE';
    v_exec_json:=jsonb_build_object('codigo',v_exec_codigo,'data',v_exec_data);
  ELSE v_resultado:='OK'; END IF;

  IF v_p.status='ABERTA' THEN
    PERFORM id FROM public.sigo_avancar_prestacao(v_p.id,'RETORNADA');
    SELECT * INTO v_p FROM public.prestacoes WHERE id=v_p.id;
  END IF;

  END processar;
  -- Registrar TODA leitura autorizada, inclusive códigos inválidos/sem NF.
  INSERT INTO public.bipagens(
    codigo_lido,codigo_normalizado,resultado,nf_id,prestacao_id,
    rota_execucao_id,usuario_id,dispositivo)
  VALUES(coalesce(p_codigo,''),v_norm,v_resultado,v_nf_id,v_prestacao_id,
    CASE WHEN v_resultado='ROTA_DIFERENTE' THEN v_exec_rota_id ELSE NULL END,
    v_usuario,p_dispositivo);
  IF v_nf_id IS NOT NULL THEN
    v_nf_json:=jsonb_build_object('id',v_nf.id,'numero',v_nf.numero,
      'serie',v_nf.serie,'chave_acesso',v_nf.chave_acesso);
    SELECT r.codigo,r.data_rota INTO v_origem_codigo,v_origem_data FROM public.rotas r
      WHERE r.id=v_nf.origem_rota_id;
    IF v_origem_codigo IS NOT NULL THEN
      v_origem_json:=jsonb_build_object('codigo',v_origem_codigo,'data',v_origem_data);
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
$function$;
