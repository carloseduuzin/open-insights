# SIGO / Supabase V1 — implementation checklist

Status: **work in progress; no database migrations applied**.

## Approved decisions
- External Supabase project `sigo-renovelog-dev`.
- Roles: `admin` and `operacional`.
- Both roles can read/create/update prestadores. Only admin can permanently delete.
- No automatic role assignment at signup.
- GitHub `main` is protected by workflow: all changes on `feat/sigo-supabase-v1`.

## Important checks before applying migration
1. Review SQL with Supabase SQL advisor and test on an isolated development database.
2. Confirm no existing tables/triggers with these names.
3. Verify user creation and initial admin bootstrap; never grant admin from the browser.
4. Test RLS with anon, unassigned, inactive, operational, and admin users.
5. Prevent spoofing immutable audit fields (`created_by`, `created_at`) on UPDATE.
6. Validate permanent deletion against future route/payment foreign keys.
7. Validate CPF/CNPJ handling and privacy requirements before real data.
8. Keep mock prestadores out of production.
9. Review SSR/TanStack Start session management before integrating auth.
10. Run lint/build and check login/logout/recovery and CRUD regression.

## Public frontend configuration (not credentials)
```env
VITE_SUPABASE_URL=https://sxgziltpoputrzhgpjof.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

Use local env or hosting secrets/settings; do not commit a real key. Never put `service_role` or `sb_secret_*` in frontend variables.

## Staged delivery
1. Schema and RLS review
2. SDK configuration and SSR-safe session integration
3. Login, reset password, protected routes
4. Prestadores data service and CRUD
5. RLS negative tests, QA, PR review

No database changes should be made until the migration is reviewed and the user authorizes application.
