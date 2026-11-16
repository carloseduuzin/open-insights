-- SIGO SLA hardening v2: reaplica incrementalmente a migration legacy 0500
-- sobre o snapshot public de 20261116000200, sem alterar registros existentes.
-- O único DML é o seed idempotente da configuração SLA, quando ausente.
-- NÃO aplicar no banco hospedado neste PR; validar apenas no CI isolado.

insert into public.sla_config (id) values (true) on conflict (id) do nothing;

-- P0: responsável original permanece imutável; executores são auditados nas respectivas etapas.
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
    set status='RETORNADA', retornada_em=clock_timestamp()
  where p.id=p_prestacao_id and p.status='ABERTA' and p.retornada_em is null
  returning p.id,p.status,p.retornada_em,p.responsavel_id;
 else
  return query
  update public.prestacoes p
    set status='CONFERIDA', conferida_em=clock_timestamp(), conferida_por=v_usuario
  where p.id=p_prestacao_id and p.status='RETORNADA' and p.conferida_em is null
  returning p.id,p.status,p.conferida_em,p.conferida_por;
 end if;
 if not found then raise exception 'Prestação não encontrada ou etapa anterior não concluída'; end if;
end; $function$;

-- Hardening: timestamp ownership and immutable SLA breach history (corpo original 0500).
create or replace function public.sigo_prestacao_timestamps() returns trigger language plpgsql set search_path='' as $$
declare dias_pendencia integer;
begin
 if tg_op='INSERT' then
  new.responsavel_id := auth.uid();
  if new.responsavel_id is null then raise exception 'Sessão obrigatória'; end if;
  new.status := 'ABERTA';
  new.retornada_em := null; new.conferida_em := null; new.conferida_por := null;
  new.enviada_em := null; new.enviada_por := null; new.confirmada_em := null; new.confirmada_por := null;
  new.pendencia_fora_sla := false;
  return new;
 end if;
 if new.responsavel_id is distinct from old.responsavel_id or new.d0 is distinct from old.d0 or new.romaneio_oficial is distinct from old.romaneio_oficial then
  raise exception 'Identidade e responsável são imutáveis';
 end if;
 new.retornada_em := old.retornada_em;
 new.conferida_em := old.conferida_em;
 new.conferida_por := old.conferida_por;
 new.enviada_em := old.enviada_em;
 new.enviada_por := old.enviada_por;
 new.confirmada_em := old.confirmada_em;
 new.confirmada_por := old.confirmada_por;
 if new.status is distinct from old.status then
  if (old.status,new.status) not in (('ABERTA','RETORNADA'),('RETORNADA','CONFERIDA'),('CONFERIDA','ENVIADA_JTI'),('ENVIADA_JTI','CONFIRMADA_JTI')) then raise exception 'Transição inválida'; end if;
  if new.status='RETORNADA' then new.retornada_em:=now(); end if;
  if new.status='CONFERIDA' then new.conferida_em:=now(); new.conferida_por:=auth.uid(); end if;
  if new.status='ENVIADA_JTI' then new.enviada_em:=now(); new.enviada_por:=auth.uid(); end if;
  if new.status='CONFIRMADA_JTI' then new.confirmada_em:=now(); new.confirmada_por:=auth.uid(); end if;
 end if;
 dias_pendencia := case when old.conferida_em is null then 0 else
 ((coalesce(new.enviada_em,now()) at time zone 'America/Sao_Paulo')::date -
 (old.conferida_em at time zone 'America/Sao_Paulo')::date) end;
 new.pendencia_fora_sla := old.pendencia_fora_sla or (old.conferida_em is not null and dias_pendencia >= 4);
 return new;
end; $$;
drop trigger if exists prestacao_auditoria on public.prestacoes;
create trigger prestacao_auditoria before insert or update on public.prestacoes for each row execute function public.sigo_prestacao_timestamps();
create or replace view public.v_prestacoes_sla with (security_invoker=true) as
select p.id,p.romaneio_oficial,p.d0,p.status,p.responsavel_id,p.conferida_em,p.enviada_em,p.pendencia_fora_sla,
 p.d0 + 3 as vence_em,
 case when p.enviada_em is not null and (p.enviada_em at time zone 'America/Sao_Paulo')::date > p.d0+3 then 'VENCIDO'
 when p.enviada_em is not null then 'ENVIADO'
 when (now() at time zone 'America/Sao_Paulo')::date>p.d0+3 then 'VENCIDO'
 when (now() at time zone 'America/Sao_Paulo')::date=p.d0+3 then 'URGENTE'
 when (now() at time zone 'America/Sao_Paulo')::date=p.d0+2 then 'ATENCAO'
 else 'NO_PRAZO' end as faixa_envio,
 case when p.conferida_em is null then 'NAO_INICIADA'
 when p.pendencia_fora_sla or (coalesce(p.enviada_em,now()) at time zone 'America/Sao_Paulo')::date >= (p.conferida_em at time zone 'America/Sao_Paulo')::date+4 then 'CRITICO'
 when p.enviada_em is not null then 'RESOLVIDA'
 when (now() at time zone 'America/Sao_Paulo')::date >= (p.conferida_em at time zone 'America/Sao_Paulo')::date+3 then 'URGENTE'
 when (now() at time zone 'America/Sao_Paulo')::date >= (p.conferida_em at time zone 'America/Sao_Paulo')::date+2 then 'ATENCAO'
 else 'NO_PRAZO' end as faixa_pendencia
from public.prestacoes p;
create or replace function public.sigo_canhoto_auditoria() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then
  new.canhoto_recebido_em := null; new.canhoto_recebido_por := null;
 elsif new.canhoto_recebido_em is distinct from old.canhoto_recebido_em or new.canhoto_recebido_por is distinct from old.canhoto_recebido_por then
  if old.canhoto_recebido_em is not null then raise exception 'Canhoto já recebido'; end if;
  if new.canhoto_recebido_em is null then raise exception 'Confirmação de recebimento obrigatória'; end if;
  new.canhoto_recebido_em := now(); new.canhoto_recebido_por := auth.uid();
 end if;
 return new;
end; $$;
drop trigger if exists prestacao_canhoto_auditoria on public.prestacao_notas;
create trigger prestacao_canhoto_auditoria before insert or update on public.prestacao_notas for each row execute function public.sigo_canhoto_auditoria();
revoke all on function public.sigo_canhoto_auditoria() from public,anon,authenticated;
