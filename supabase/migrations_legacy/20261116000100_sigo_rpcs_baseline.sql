-- SIGO: baseline de RPCs existentes, 2026-11-16.
-- DDL de pg_get_functiondef sem mudanca de logica, somente terminador SQL e ACL explicita.
-- NAO aplicado ao Supabase; publicar somente via revisao de PR.

-- Captured verbatim using pg_get_functiondef: public.sigo_avancar_prestacao(uuid,text)
CREATE OR REPLACE FUNCTION public.sigo_avancar_prestacao(p_prestacao_id uuid, p_etapa text)
 RETURNS TABLE(id uuid, status text, registrado_em timestamp with time zone, registrado_por uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_usuario uuid := (select auth.uid());
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
    set status='RETORNADA', retornada_em=clock_timestamp(), responsavel_id=v_usuario
  where p.id=p_prestacao_id and p.status='ABERTA' and p.retornada_em is null
  returning p.id,p.status,p.retornada_em,p.responsavel_id;
 else
  return query
  update public.prestacoes p
    set status='CONFERIDA', conferida_em=clock_timestamp(), conferida_por=v_usuario,
        responsavel_id=coalesce(p.responsavel_id,v_usuario)
  where p.id=p_prestacao_id and p.status='RETORNADA' and p.conferida_em is null
  returning p.id,p.status,p.conferida_em,p.conferida_por;
 end if;
 if not found then raise exception 'Prestação não encontrada ou etapa anterior não concluída'; end if;
end; $function$;
REVOKE ALL ON FUNCTION public.sigo_avancar_prestacao(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_avancar_prestacao(uuid,text) TO authenticated;

-- Captured verbatim using pg_get_functiondef: public.sigo_criar_prestacao(text,date)
CREATE OR REPLACE FUNCTION public.sigo_criar_prestacao(p_romaneio text, p_d0 date)
 RETURNS TABLE(id uuid, romaneio_oficial text, d0 date, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := (select auth.uid());
begin
 if v_user is null or not (select public.sigo_is_active()) then
  raise exception 'Usuário sem acesso ativo ao SIGO';
 end if;
 if p_romaneio is null or p_romaneio !~ '^[0-9]{12}$' or p_romaneio ~ '^(.)\1{11}$' or p_romaneio like '6000000000%' then
  raise exception 'Informe um romaneio oficial válido com 12 dígitos (não auxiliar)';
 end if;
 if p_d0 is null or p_d0 > (now() at time zone 'America/Sao_Paulo')::date then
  raise exception 'A data D0 não pode estar no futuro';
 end if;
 return query
 insert into public.prestacoes as p (romaneio_oficial,d0,status,responsavel_id)
 values (p_romaneio,p_d0,'ABERTA',v_user)
 returning p.id,p.romaneio_oficial,p.d0,p.status;
exception when unique_violation then
 raise exception 'Esse romaneio já está cadastrado no SIGO';
end; $function$;
REVOKE ALL ON FUNCTION public.sigo_criar_prestacao(text,date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_criar_prestacao(text,date) TO authenticated;

-- Captured verbatim using pg_get_functiondef: public.sigo_enviar_prestacao_jti(uuid)
CREATE OR REPLACE FUNCTION public.sigo_enviar_prestacao_jti(p_prestacao_id uuid)
 RETURNS TABLE(id uuid, romaneio_oficial text, enviada_em timestamp with time zone, enviada_por uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_usuario uuid := (select auth.uid());
begin
  if v_usuario is null or not (select public.sigo_is_active()) then
    raise exception 'Acesso não autorizado ao SIGO';
  end if;
  return query
  update public.prestacoes p
  set status = 'ENVIADA_JTI',
      enviada_em = clock_timestamp(),
      enviada_por = v_usuario
  where p.id = p_prestacao_id
    and p.status = 'CONFERIDA'
    and p.enviada_em is null
  returning p.id, p.romaneio_oficial, p.enviada_em, p.enviada_por;
  if not found then
    raise exception 'Prestação não encontrada ou não está conferida e disponível para envio';
  end if;
end;
$function$;
REVOKE ALL ON FUNCTION public.sigo_enviar_prestacao_jti(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_enviar_prestacao_jti(uuid) TO authenticated;

-- Captured verbatim using pg_get_functiondef: public.sigo_importar_prestacoes_gm(jsonb)
CREATE OR REPLACE FUNCTION public.sigo_importar_prestacoes_gm(p_itens jsonb)
 RETURNS TABLE(inseridos integer, existentes integer, total integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_item jsonb; v_rom text; v_d0 date; v_count int := 0;
 v_novos int := 0; v_anteriores int := 0; v_existente date;
begin
 if (select auth.uid()) is null or not (select public.sigo_is_active()) then
   raise exception 'Acesso não autorizado ao SIGO';
 end if;
 if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens)=0 or jsonb_array_length(p_itens)>200 then
   raise exception 'Lote inválido (1 a 200 romaneios)';
 end if;
 if (select count(*) from jsonb_array_elements(p_itens) x where (x->>'romaneio') is null or (x->>'d0') is null or jsonb_typeof(x) <> 'object') > 0 then
   raise exception 'Dados obrigatórios ausentes';
 end if;
 if (select count(*) from jsonb_array_elements(p_itens)) <> (select count(distinct x->>'romaneio') from jsonb_array_elements(p_itens) x) then
   raise exception 'Romaneio repetido dentro do mesmo lote';
 end if;
 for v_item in select * from jsonb_array_elements(p_itens) loop
   v_rom := v_item->>'romaneio';
   if v_rom !~ '^[0-9]{12}$' or v_rom ~ '^(.)\1{11}$' or v_rom like '6000000000%' then
     raise exception 'Romaneio não oficial ou inválido';
   end if;
   if (v_item->>'d0') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'D0 inválido'; end if;
   v_d0 := (v_item->>'d0')::date;
   if v_d0 > (now() at time zone 'America/Sao_Paulo')::date then
     raise exception 'A rota é futura. Aguarde D0 para abrir a prestação';
   end if;
   select p.d0 into v_existente from public.prestacoes p where p.romaneio_oficial=v_rom;
   if found then
      if v_existente <> v_d0 then raise exception 'Romaneio já existe com D0 diferente'; end if;
      v_anteriores := v_anteriores + 1;
   else
      insert into public.prestacoes(romaneio_oficial,d0,status,responsavel_id)
      values(v_rom,v_d0,'ABERTA',(select auth.uid()))
      on conflict(romaneio_oficial) do nothing;
      if found then v_novos:=v_novos+1; else v_anteriores:=v_anteriores+1; end if;
   end if;
   v_count:=v_count+1;
 end loop;
 return query select v_novos,v_anteriores,v_count;
end;
$function$;
REVOKE ALL ON FUNCTION public.sigo_importar_prestacoes_gm(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_importar_prestacoes_gm(jsonb) TO authenticated;

-- Captured verbatim using pg_get_functiondef: public.sigo_registrar_ocorrencia(jsonb)
CREATE OR REPLACE FUNCTION public.sigo_registrar_ocorrencia(p_dados jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
 if v_uid is null or not (select public.sigo_is_active()) then raise exception 'Acesso não autorizado'; end if;
 if jsonb_typeof(p_dados) is distinct from 'object' then raise exception 'Dados inválidos'; end if;
 if length(trim(coalesce(p_dados->>'codigo_cliente','')))=0 or length(trim(coalesce(p_dados->>'cliente','')))=0 or
    length(trim(coalesce(p_dados->>'nf','')))=0 or length(trim(coalesce(p_dados->>'codigo_rota','')))=0 or
    length(trim(coalesce(p_dados->>'detalhe','')))<10 then raise exception 'Preencha cliente, código, NF, rota e descrição com pelo menos 10 caracteres'; end if;
 if (p_dados->>'data_rota')::date > (now() at time zone 'America/Sao_Paulo')::date then raise exception 'Data futura não permitida'; end if;
 insert into public.ocorrencias_roteirizacao(
  criado_por,data_rota,codigo_cliente,cliente,nf,codigo_rota,romaneio,condutor,vendedor,tipo,saida,
  sequencia_planejada,sequencia_executada,horario_restricao,detalhe,impacto,acao_imediata,area_correcao,responsavel_tratativa
 ) values(
  v_uid,(p_dados->>'data_rota')::date,trim(p_dados->>'codigo_cliente'),trim(p_dados->>'cliente'),
  trim(p_dados->>'nf'),trim(p_dados->>'codigo_rota'),nullif(trim(p_dados->>'romaneio'),''),
  nullif(trim(p_dados->>'condutor'),''),nullif(trim(p_dados->>'vendedor'),''),
  p_dados->>'tipo',p_dados->>'saida',
  nullif(p_dados->>'sequencia_planejada','')::integer,
  nullif(p_dados->>'sequencia_executada','')::integer,
  nullif(trim(p_dados->>'horario_restricao'),''),
  trim(p_dados->>'detalhe'),p_dados->>'impacto',
  nullif(trim(p_dados->>'acao_imediata'),''),p_dados->>'area_correcao',
  nullif(trim(p_dados->>'responsavel_tratativa'),'')
 ) returning id into v_id;
 return v_id;
end;
$function$;
REVOKE ALL ON FUNCTION public.sigo_registrar_ocorrencia(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_registrar_ocorrencia(jsonb) TO authenticated;

-- Captured verbatim using pg_get_functiondef: public.sigo_tratar_ocorrencia(uuid,text,text,text)
CREATE OR REPLACE FUNCTION public.sigo_tratar_ocorrencia(p_id uuid, p_status text, p_retorno text, p_responsavel text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := (select auth.uid());
begin
 if v_uid is null or not (select public.sigo_is_active()) then raise exception 'Acesso não autorizado'; end if;
 if p_status not in ('ABERTA','ENVIADA_GESTAO','EM_TRATATIVA','CORRIGIDA','SEM_CORRECAO') then raise exception 'Status inválido'; end if;
 if p_status in ('CORRIGIDA','SEM_CORRECAO') and length(trim(coalesce(p_retorno,'')))<8 then raise exception 'Informe o retorno da tratativa'; end if;
 update public.ocorrencias_roteirizacao
 set status=p_status,retorno_gestao=nullif(trim(p_retorno),''),
     responsavel_tratativa=nullif(trim(p_responsavel),''),
     atualizado_em=now(),atualizado_por=v_uid,
     resolvido_em=case when p_status in ('CORRIGIDA','SEM_CORRECAO') then now() else null end
 where id=p_id;
 return found;
end; $function$;
REVOKE ALL ON FUNCTION public.sigo_tratar_ocorrencia(uuid,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sigo_tratar_ocorrencia(uuid,text,text,text) TO authenticated;
