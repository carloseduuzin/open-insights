-- TEMPLATE ONLY. Run as an authorized SQL administrator after Auth user exists.
-- Replace the UUID below with the verified auth.users.id for the intended first administrator.
-- Never use this SQL from a browser or expose privileged credentials.
begin;
insert into public.profiles (id, nome, ativo)
values ('00000000-0000-0000-0000-000000000000', 'Administrador SIGO', true)
on conflict (id) do update set nome = excluded.nome, ativo = true;
insert into public.user_roles (user_id, role)
values ('00000000-0000-0000-0000-000000000000', 'admin')
on conflict (user_id, role) do nothing;
commit;
