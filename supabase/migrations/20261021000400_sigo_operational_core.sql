-- SIGO: fundação operacional para importações GreenMile e rastreio fiscal.
create table if not exists public.sla_config (
 id boolean primary key default true check (id),
 limite_dias integer not null default 3 check (limite_dias=3),
 tipo_contagem text not null default 'corridos' check (tipo_contagem='corridos'),
 meta_horas integer not null default 48 check (meta_horas=48)
);
insert into public.sla_config(id) values (true) on conflict do nothing;
create table if not exists public.gm_importacoes (
 id uuid primary key default gen_random_uuid(),
 tipo text not null check(tipo in ('ROUTEVIEW','STOPVIEW_PARADAS','STOPVIEW_PEDIDOS')),
 arquivo_nome text not null,
 sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
 registros integer not null default 0 check(registros>=0),
 criado_por uuid not null default auth.uid() references auth.users(id),
 criado_em timestamptz not null default now(),
 unique(tipo,sha256)
);
create table if not exists public.rotas (
 id uuid primary key default gen_random_uuid(),
 data_rota date not null,
 codigo text not null,
 romaneio_gm text check (romaneio_gm is null or romaneio_gm ~ '^[0-9]{12}$'),
 tipo_romaneio text not null default 'A_CLASSIFICAR' check(tipo_romaneio in ('OFICIAL','AUXILIAR','A_CLASSIFICAR')),
 motorista_gm text,
 veiculo text,
 saida smallint check(saida between 1 and 9),
 km_planejado numeric(12,3),
 km_realizado numeric(12,3),
 gm_status text,
 importacao_id uuid references public.gm_importacoes(id),
 atualizado_em timestamptz not null default now(),
 unique(data_rota,codigo)
);
create table if not exists public.paradas (
 id bigint primary key,
 rota_id uuid references public.rotas(id),
 data_rota date,
 codigo_rota text,
 codigo_localidade text,
 cliente text,
 status_gm text,
 importacao_id uuid references public.gm_importacoes(id),
 atualizado_em timestamptz not null default now()
);
create table if not exists public.notas_fiscais (
 id uuid primary key default gen_random_uuid(),
 numero char(9) not null check(numero ~ '^[0-9]{9}$'),
 serie text not null check(serie ~ '^[0-9]{1,3}$'),
 chave_acesso char(44) unique check(chave_acesso is null or chave_acesso ~ '^[0-9]{44}$'),
 emitente_documento text,
 romaneio_origem text check(romaneio_origem is null or romaneio_origem ~ '^[0-9]{12}$'),
 origem_rota_id uuid references public.rotas(id),
 origem_confirmada boolean not null default false,
 primeira_carga_em timestamptz not null default now(),
 unique(emitente_documento,numero,serie)
);
create table if not exists public.parada_notas (
 parada_id bigint not null references public.paradas(id),
 nf_id uuid not null references public.notas_fiscais(id),
 importacao_id uuid references public.gm_importacoes(id),
 primary key(parada_id,nf_id)
);
create table if not exists public.nf_execucoes (
 id uuid primary key default gen_random_uuid(),
 nf_id uuid not null references public.notas_fiscais(id),
 rota_id uuid not null references public.rotas(id),
 tipo text not null check(tipo in ('CARGA','TRANSFERENCIA','REENTREGA','APOIO')),
 iniciada_em timestamptz not null default now(),
 encerrada_em timestamptz,
 registrada_por uuid not null default auth.uid() references auth.users(id),
 check(encerrada_em is null or encerrada_em>=iniciada_em)
);
create unique index if not exists nf_uma_execucao_aberta_idx on public.nf_execucoes(nf_id) where encerrada_em is null;
create table if not exists public.nf_eventos (
 id bigint generated always as identity primary key,
 nf_id uuid not null references public.notas_fiscais(id),
 tipo text not null check(tipo in ('CARGA_GM','SAIDA','TRANSFERENCIA','RETORNO','CANHOTO','DEVOLUCAO','ORIGEM_VINCULADA')),
 motivo text check(motivo is null or motivo in ('APOIO','REENTREGA','REBALANCEAMENTO','RECUSA','DEVOLUCAO','OUTRO_PADRONIZADO')),
 rota_destino_id uuid references public.rotas(id),
 usuario_id uuid not null default auth.uid() references auth.users(id),
 ocorrido_em timestamptz not null default now()
);
create table if not exists public.prestacoes (
 id uuid primary key default gen_random_uuid(),
 romaneio_oficial text not null unique check(romaneio_oficial ~ '^[0-9]{12}$'),
 d0 date not null,
 status text not null default 'ABERTA' check(status in ('ABERTA','RETORNADA','CONFERIDA','ENVIADA_JTI','CONFIRMADA_JTI')),
 responsavel_id uuid not null default auth.uid() references auth.users(id),
 retornada_em timestamptz,
 conferida_em timestamptz,
 conferida_por uuid references auth.users(id),
 enviada_em timestamptz,
 enviada_por uuid references auth.users(id),
 confirmada_em timestamptz,
 confirmada_por uuid references auth.users(id),
 pendencia_fora_sla boolean not null default false
);
create table if not exists public.prestacao_notas (
 prestacao_id uuid not null references public.prestacoes(id),
 nf_id uuid not null unique references public.notas_fiscais(id),
 canhoto_recebido_em timestamptz,
 canhoto_recebido_por uuid references auth.users(id),
 primary key(prestacao_id,nf_id)
);
create or replace function public.sigo_guard_nf_origem() returns trigger language plpgsql set search_path='' as $$
begin
 if new.romaneio_origem is distinct from old.romaneio_origem
 or new.origem_rota_id is distinct from old.origem_rota_id
 or new.numero is distinct from old.numero
 or new.serie is distinct from old.serie then
  raise exception 'Origem e identidade fiscal são imutáveis; correções exigem procedimento auditado';
 end if;
 return new;
end; $$;
create trigger nf_origem_imutavel before update on public.notas_fiscais for each row execute function public.sigo_guard_nf_origem();
create or replace function public.sigo_guard_eventos() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Eventos são append-only'; end; $$;
create trigger nf_eventos_append_only before update or delete on public.nf_eventos for each row execute function public.sigo_guard_eventos();
create or replace function public.sigo_prestacao_timestamps() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if new.responsavel_id is distinct from old.responsavel_id or new.d0 is distinct from old.d0 or new.romaneio_oficial is distinct from old.romaneio_oficial then
   raise exception 'Identidade da prestação e responsável não podem ser alterados';
  end if;
  if new.status is distinct from old.status then
   if (old.status,new.status) not in (('ABERTA','RETORNADA'),('RETORNADA','CONFERIDA'),('CONFERIDA','ENVIADA_JTI'),('ENVIADA_JTI','CONFIRMADA_JTI')) then
    raise exception 'Transição de prestação inválida';
   end if;
   if new.status='RETORNADA' then new.retornada_em:=now(); end if;
   if new.status='CONFERIDA' then new.conferida_em:=now(); new.conferida_por:=auth.uid(); end if;
   if new.status='ENVIADA_JTI' then new.enviada_em:=now(); new.enviada_por:=auth.uid(); end if;
   if new.status='CONFIRMADA_JTI' then new.confirmada_em:=now(); new.confirmada_por:=auth.uid(); end if;
  end if;
  new.pendencia_fora_sla:=old.pendencia_fora_sla or (old.conferida_em is not null and now() >= old.conferida_em + interval '4 days' and old.status not in ('ENVIADA_JTI','CONFIRMADA_JTI'));
 end if;
 return new;
end; $$;
create trigger prestacao_auditoria before update on public.prestacoes for each row execute function public.sigo_prestacao_timestamps();
create or replace view public.v_prestacoes_sla with (security_invoker=true) as
select p.id,p.romaneio_oficial,p.d0,p.status,p.responsavel_id,p.conferida_em,p.enviada_em,p.pendencia_fora_sla,
 p.d0 + (select limite_dias from public.sla_config where id=true) as vence_em,
 case when p.enviada_em is not null and (p.enviada_em at time zone 'America/Sao_Paulo')::date > p.d0+3 then 'VENCIDO'
 when p.enviada_em is not null then 'ENVIADO'
 when current_date>p.d0+3 then 'VENCIDO'
 when current_date=p.d0+3 then 'URGENTE'
 when current_date=p.d0+2 then 'ATENCAO'
 else 'NO_PRAZO' end as faixa_envio,
 case when p.conferida_em is null then 'NAO_INICIADA'
 when p.pendencia_fora_sla or (p.enviada_em is null and current_date >= (p.conferida_em at time zone 'America/Sao_Paulo')::date+4) then 'CRITICO'
 when p.enviada_em is not null then 'RESOLVIDA'
 when current_date >= (p.conferida_em at time zone 'America/Sao_Paulo')::date+3 then 'URGENTE'
 when current_date >= (p.conferida_em at time zone 'America/Sao_Paulo')::date+2 then 'ATENCAO'
 else 'NO_PRAZO' end as faixa_pendencia
from public.prestacoes p;
create or replace view public.v_alerta_fim_semana with (security_invoker=true) as
select * from public.v_prestacoes_sla where status not in ('ENVIADA_JTI','CONFIRMADA_JTI')
and extract(isodow from (now() at time zone 'America/Sao_Paulo')) in (4,5)
and extract(isodow from vence_em) in (6,7)
and vence_em >= (now() at time zone 'America/Sao_Paulo')::date
and vence_em <= (now() at time zone 'America/Sao_Paulo')::date+3;
do $$ declare t text; begin
 foreach t in array array['sla_config','gm_importacoes','rotas','paradas','notas_fiscais','parada_notas','nf_execucoes','nf_eventos','prestacoes','prestacao_notas'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy sigo_read on public.%I for select to authenticated using ((select public.sigo_is_active()))',t);
 end loop;
end $$;
create policy sigo_import_insert on public.gm_importacoes for insert to authenticated with check ((select public.sigo_is_active()) and criado_por=auth.uid());
create policy sigo_rotas_insert on public.rotas for insert to authenticated with check ((select public.sigo_is_active()));
create policy sigo_rotas_update on public.rotas for update to authenticated using ((select public.sigo_is_active())) with check ((select public.sigo_is_active()));
create policy sigo_paradas_insert on public.paradas for insert to authenticated with check ((select public.sigo_is_active()));
create policy sigo_paradas_update on public.paradas for update to authenticated using ((select public.sigo_is_active())) with check ((select public.sigo_is_active()));
create policy sigo_nf_insert on public.notas_fiscais for insert to authenticated with check ((select public.sigo_is_active()));
create policy sigo_nf_update on public.notas_fiscais for update to authenticated using ((select public.sigo_is_active())) with check ((select public.sigo_is_active()));
create policy sigo_parada_nf_insert on public.parada_notas for insert to authenticated with check ((select public.sigo_is_active()));
create policy sigo_exec_insert on public.nf_execucoes for insert to authenticated with check ((select public.sigo_is_active()) and registrada_por=auth.uid());
create policy sigo_exec_update on public.nf_execucoes for update to authenticated using ((select public.sigo_is_active())) with check ((select public.sigo_is_active()));
create policy sigo_event_insert on public.nf_eventos for insert to authenticated with check ((select public.sigo_is_active()) and usuario_id=auth.uid());
create policy sigo_prest_insert on public.prestacoes for insert to authenticated with check ((select public.sigo_is_active()) and responsavel_id=auth.uid());
create policy sigo_prest_update on public.prestacoes for update to authenticated using ((select public.sigo_is_active())) with check ((select public.sigo_is_active()));
create policy sigo_prest_nf_insert on public.prestacao_notas for insert to authenticated with check ((select public.sigo_is_active()));
create policy sigo_prest_nf_update on public.prestacao_notas for update to authenticated using ((select public.sigo_is_active())) with check ((select public.sigo_is_active()));
revoke all on function public.sigo_guard_nf_origem() from public,anon,authenticated;
revoke all on function public.sigo_guard_eventos() from public,anon,authenticated;
revoke all on function public.sigo_prestacao_timestamps() from public,anon,authenticated;
