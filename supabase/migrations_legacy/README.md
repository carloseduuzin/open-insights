# Migrations legadas do SIGO

Arquivos deslocados em 2026-11-16, na branch `chore/schema-baseline`:

- `20261021000100_sigo_initial.sql`
- `20261021000200_sigo_function_execute_hardening.sql`
- `20261021000400_sigo_operational_core.sql`
- `20261021000500_sigo_sla_hardening.sql`
- `20261116000100_sigo_rpcs_baseline.sql`

Esses arquivos registram a evolução parcial anterior e **não devem ser reaplicados automaticamente** com o novo baseline de schema. Eles foram substituídos no diretório de migrations ativas por `supabase/migrations/20261116000200_sigo_schema_baseline.sql`, que descreve o estado real do schema `public` observado no Supabase. O baseline não incorpora alterações planejadas mas ainda não aplicadas (como parte da `0500`), nem reconcilia o histórico remoto.

**Atenção:** o deslocamento não apaga objetos nem dados do Supabase. Ele altera apenas o replay local de migrations. A ordem de migrations/histórico do banco hospedado permanece divergente: NÃO executar `supabase db push`, `supabase db reset` contra o projeto hospedado ou qualquer automação de deploy de schema até validar dependências e reconciliar o histórico em uma mudança separada.
