# SIGO Supabase V1 — Security acceptance matrix

**Status:** checklist for manual/automated validation; no tests executed.

## Required identities
- Anonymous (no JWT)
- Authenticated user without role
- Authenticated user with inactive profile
- Active `operacional`
- Active `admin`

## Expected permissions

| Scenario | Anonymous | No role | Inactive | Operacional | Admin |
| --- | --- | --- | --- | --- | --- |
| SELECT prestadores | Deny | Deny | Deny | Allow | Allow |
| INSERT prestadores | Deny | Deny | Deny | Allow (own created_by/updated_by) | Allow (own created_by/updated_by) |
| UPDATE prestadores | Deny | Deny | Deny | Allow (own updated_by) | Allow (own updated_by) |
| DELETE prestadores | Deny | Deny | Deny | Deny | Allow |
| INSERT/UPDATE/DELETE user_roles from frontend | Deny | Deny | Deny | Deny | Deny |

## Negative tests required
1. Authenticated operational user tries to DELETE a prestador by direct API request.
2. Operational user tries to change `created_by`, `created_at` or `id` during UPDATE; trigger must reject.
3. Authenticated user tries to assign `admin` in `user_roles`.
4. User with no role tries to list prestadores.
5. Inactive admin tries to delete prestador.
6. INSERT with `created_by` belonging to another user must fail.
7. UPDATE with `updated_by` belonging to another user must fail.
8. Anonymous API calls cannot read prestadores or profiles.
9. Verify role/profile queries do not cause recursive RLS errors.
10. Test profile creation trigger for a new Auth user, including missing metadata.
11. Verify delete behavior when future routes, deliveries or payment records reference a prestador.
12. Verify mock data is not seeded into production.

## Release gates
- Test migration in isolated database first.
- Validate policies using real user JWTs, not a privileged service-role connection.
- Run build and lint before PR merge.
- Verify no secrets in commits, logs or frontend bundle.
- Confirm backup and recovery strategy before operational use.
- Review all changes before applying to the live Supabase project.

## Known design boundaries
- This initial migration has no UI integration and does not create the first admin.
- `profiles` administration and bootstrap must use a controlled privileged workflow.
- Database triggers protect creation metadata; business rules around CPF/CNPJ validation and uniqueness require separate approval.
- Permanent deletion is intentionally restricted to admin and must not cascade to business records.
