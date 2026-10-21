-- SIGO V1 - initial schema and access controls
-- Initial schema for the empty SIGO development database; review before applying to production.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null default '',
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'operacional')),
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table if not exists public.prestadores (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(btrim(nome)) between 3 and 100),
  documento text not null check (char_length(btrim(documento)) between 11 and 20),
  veiculo text not null check (veiculo in ('Moto', 'Fiorino', 'VUC')),
  placa text not null check (char_length(btrim(placa)) between 7 and 8),
  base text not null check (char_length(btrim(base)) > 0),
  disponibilidade text not null default 'Disponível'
    check (disponibilidade in ('Disponível', 'Em rota', 'Indisponível')),
  status text not null default 'Ativo'
    check (status in ('Ativo', 'Pendente', 'Inativo')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null
);

create index if not exists prestadores_base_idx on public.prestadores(base);
create index if not exists prestadores_status_idx on public.prestadores(status);

create or replace function public.sigo_has_role(requested_role text)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles ur
    join public.profiles p on p.id = ur.user_id
    where ur.user_id = (select auth.uid())
      and ur.role = requested_role
      and p.ativo = true
  );
$$;

create or replace function public.sigo_is_active()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
    where p.id = (select auth.uid()) and p.ativo = true
      and ur.role in ('admin', 'operacional')
  );
$$;

revoke all on function public.sigo_has_role(text) from public;
revoke all on function public.sigo_is_active() from public;
grant execute on function public.sigo_has_role(text) to authenticated;
grant execute on function public.sigo_is_active() to authenticated;

create or replace function public.sigo_set_updated_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
for each row execute function public.sigo_set_updated_at();
-- Prevent clients from changing creation metadata or record identity.
-- Database-generated updated_at is maintained by the trigger above.
create or replace function public.sigo_guard_prestador_update()
returns trigger language plpgsql set search_path = ''
as $
begin
  if new.id is distinct from old.id
    or new.created_at is distinct from old.created_at
    or new.created_by is distinct from old.created_by then
    raise exception 'Campos de criação e identidade não podem ser alterados';
  end if;
  return new;
end;
$;
create trigger prestadores_guard_update before update on public.prestadores
for each row execute function public.sigo_guard_prestador_update();
create trigger prestadores_updated_at before update on public.prestadores
for each row execute function public.sigo_set_updated_at();

-- A new Auth user gets a profile, but NEVER receives a role automatically.
create or replace function public.sigo_handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles(id, nome)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nome', ''));
  return new;
end;
$$;
create trigger sigo_auth_user_created after insert on auth.users
for each row execute function public.sigo_handle_new_user();

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.prestadores enable row level security;

revoke all on public.profiles, public.user_roles, public.prestadores from anon;
grant select on public.profiles, public.user_roles, public.prestadores to authenticated;
grant insert, update, delete on public.prestadores to authenticated;
-- Profile changes require the admin-only UPDATE policy below.
grant update on public.profiles to authenticated;

create policy profiles_read on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select public.sigo_has_role('admin')));
create policy profiles_admin_update on public.profiles for update to authenticated
using ((select public.sigo_has_role('admin')))
with check ((select public.sigo_has_role('admin')));

create policy roles_read on public.user_roles for select to authenticated
using (user_id = (select auth.uid()) or (select public.sigo_has_role('admin')));
-- Role changes deliberately have no client INSERT/UPDATE/DELETE policies or grants.

create policy prestadores_read on public.prestadores for select to authenticated
using ((select public.sigo_is_active()));
create policy prestadores_insert on public.prestadores for insert to authenticated
with check ((select public.sigo_is_active()) and created_by = (select auth.uid())
  and updated_by = (select auth.uid()));
create policy prestadores_update on public.prestadores for update to authenticated
using ((select public.sigo_is_active()))
with check ((select public.sigo_is_active()) and updated_by = (select auth.uid()));
create policy prestadores_delete on public.prestadores for delete to authenticated
using ((select public.sigo_has_role('admin')));

-- Initial admin provisioning is intentionally excluded: use a controlled,
-- authenticated administrative procedure after verifying the user's UUID.
-- Before applying: test UPDATE immutability, role bootstrap and delete dependencies.
