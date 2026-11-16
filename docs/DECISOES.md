# Decisões — SIGO

## 2026-11-16 — Baseline das RPCs existentes

**Fonte:** Supabase `sxgziltpoputrzhgpjof` (introspecção somente leitura de `pg_proc`, `pg_get_functiondef` e histórico de migrations); repositório `carloseduuzin/open-insights`, branch `feat/sigo-supabase-v1`.

**Decisão:** registrar em `supabase/migrations/20261116000100_sigo_rpcs_baseline.sql` as 6 funções SQL que existem no banco, mas não nas migrations do repositório. As definições foram copiadas de `pg_get_functiondef`, com apenas o terminador SQL e comandos explícitos de privilégio. Nenhum SQL foi aplicado no banco.

### Histórico de migrations aplicado no banco (9)

- `20261021042900_sigo_initial`
- `20261021042917_sigo_function_execute_hardening`
- `20261021052920_sigo_operational_core`
- `20261102233111_sigo_prestacao_envio_jti_controlado`
- `20261102233707_sigo_prestacao_retorno_conferencia`
- `20261102233743_sigo_prestacao_restrict_direct_mutations`
- `20261102233812_sigo_prestacao_manual_create_controlled`
- `20261103001421_sigo_importar_prestacoes_gm_approved_batch`
- `20261106020500_sigo_impactos_comercial_roteirizacao_v1`

### Arquivos de migration da branch-base (4)

- `20261021000100_sigo_initial.sql`
- `20261021000200_sigo_function_execute_hardening.sql`
- `20261021000400_sigo_operational_core.sql`
- `20261021000500_sigo_sla_hardening.sql`

### Migration deste PR (não aplicada)

- `20261116000100_sigo_rpcs_baseline.sql` — baseline das seis RPCs presentes no banco, ainda ausentes dos arquivos SQL versionados.

### Cobertura das funções `public.sigo_*`

- 14 funções no Supabase; 9 funções já definidas em migrations; 6 funções adicionais recuperadas:
  - `public.sigo_avancar_prestacao(uuid,text)`
  - `public.sigo_criar_prestacao(text,date)`
  - `public.sigo_enviar_prestacao_jti(uuid)`
  - `public.sigo_importar_prestacoes_gm(jsonb)`
  - `public.sigo_registrar_ocorrencia(jsonb)`
  - `public.sigo_tratar_ocorrencia(uuid,text,text,text)`
- `SECURITY DEFINER`: todas as funções examinadas já usam `SET search_path TO ''`; definições preservadas.
- ACLs observadas das seis: `authenticated` tem `EXECUTE`, `anon` não. Este baseline declara `REVOKE ALL FROM PUBLIC, anon, authenticated` e `GRANT EXECUTE TO authenticated`, sem alterar o banco.

### Divergências a tratar separadamente

1. As três migrations iniciais do banco têm timestamps diferentes dos arquivos correspondentes no GitHub: equivalência por nome não comprova DDL idêntico.
2. Seis registros de migration no histórico do banco não possuem arquivos SQL correspondentes nesta branch: `sigo_prestacao_envio_jti_controlado`, `sigo_prestacao_retorno_conferencia`, `sigo_prestacao_restrict_direct_mutations`, `sigo_prestacao_manual_create_controlled`, `sigo_importar_prestacoes_gm_approved_batch` e `sigo_impactos_comercial_roteirizacao_v1`.
3. O arquivo `20261021000500_sigo_sla_hardening.sql` está no GitHub, mas não no histórico de migrations do banco. Sua função `sigo_canhoto_auditoria` não foi localizada no banco atual.
4. As RPCs de ocorrências dependem da tabela de ocorrências, cuja migration de criação não está no repositório. Recuperar esta dependência antes de testar `db reset` com todas as migrations.
5. O corpo atual de `sigo_prestacao_timestamps` no banco não deve ser confundido com a versão no arquivo de hardening ausente do histórico. Nenhuma reconciliação de código, schema, triggers ou dados foi realizada aqui.
6. Não executar esta migration nem reconciliar o histórico na base ativa sem revisão, homologação em ambiente isolado e autorização em etapa posterior.
