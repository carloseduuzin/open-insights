-- Restrict function execution in exposed public schema.
revoke execute on function public.sigo_has_role(text) from anon;
revoke execute on function public.sigo_is_active() from anon;
revoke all on function public.sigo_handle_new_user() from public, anon, authenticated;
revoke all on function public.sigo_guard_prestador_update() from public, anon, authenticated;
revoke all on function public.sigo_set_updated_at() from public, anon, authenticated;
