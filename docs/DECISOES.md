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

### 2026-11-16 — Etapa 1b: snapshot real do schema `public` (somente estrutura)

- Origem: catálogo do Supabase `sxgziltpoputrzhgpjof`, PostgreSQL 17; levantamento de leitura, sem aplicar nada.
- Baseline gerado em `supabase/migrations/20261116000200_sigo_schema_baseline.sql`. Contém 14 tabelas, 82 constraints, 25 índices no total (5 independentes; 20 criados por constraints), 2 views, 14 funções, 6 triggers sobre tabelas `public`, 33 políticas RLS e ACLs do catálogo para `anon`, `authenticated`, `service_role` e `PUBLIC`. A sequência `nf_eventos_id_seq` nasce da coluna `GENERATED ALWAYS AS IDENTITY`.
- Não é um dump produzido pelo executável `pg_dump`; é uma reconstrução equivalente **dos objetos públicos listados**, a partir de consultas somente leitura ao catálogo. Não contém dados, owners do Supabase, default privileges para objetos futuros nem objetos fora de `public`.
- Cinco migrations anteriores foram preservadas intactas em `supabase/migrations_legacy/` para evitar que `db reset` aplique antes do baseline estruturas contraditórias. O histórico remoto de migrations continua divergente e **não foi reconciliado**.
- PostgreSQL do projeto: 17; CI solicitado: PostgreSQL 15. Grants da permissão `MAINTAIN` (nova no PG17) são condicionais na migration para viabilizar replay PG15 sem alterar as demais ACLs documentadas.

#### Comparação exata com `20261021000500_sigo_sla_hardening.sql`

1. **Função `public.sigo_canhoto_auditoria()`: ausente no banco atual.** A versão `0500` cria essa função para rejeitar recebimento duplicado e gravar `canhoto_recebido_por`/`canhoto_recebido_em` do servidor. Não incluída no baseline, que representa somente o estado existente.
2. **Trigger `prestacao_canhoto_auditoria`: ausente no banco.** A versão `0500` instala um trigger `BEFORE INSERT OR UPDATE` em `public.prestacao_notas` que não aparece no catálogo atual.
3. **Trigger `prestacao_auditoria`: divergente.** No banco atual é `BEFORE UPDATE`; a `0500` o recria como `BEFORE INSERT OR UPDATE`.
4. **Função `public.sigo_prestacao_timestamps()`: divergente.** O banco ainda usa a implementação anterior, que trata `UPDATE` e calcula a marcação `pendencia_fora_sla` conforme o estado de conferência. A `0500` acrescenta lógica para `INSERT`, reforça imutabilidade de campos de auditoria, reavalia a marcação de pendência por diferença de datas no fuso `America/Sao_Paulo` e altera o tratamento de timestamps.
5. **View `public.v_prestacoes_sla`: divergente.** A view real usa `CURRENT_DATE` para as faixas de prazo e busca o limite a partir de `sla_config`; a `0500` usa `(now() AT TIME ZONE 'America/Sao_Paulo')::date` e `p.d0 + 3`, incluindo `coalesce(p.enviada_em, now())` na lógica de pendência. A view real já usa o fuso SP em parte dos cálculos, mas **não em todas as comparações da data atual**.
6. **Permissão da função de canhoto:** o `REVOKE ALL` da `0500` não se aplica ao estado atual, pois a função não existe.

#### Limites de replay e CI

- O dump de `public` depende de objetos fora do schema: `auth.users`, `auth.uid()` e papéis `anon`, `authenticated`, `service_role`. O workflow isolado cria apenas stubs dessas dependências, **não reproduz o Supabase completo**.
- O trigger de criação de perfil `sigo_auth_user_created` está anexado a `auth.users`, portanto é externo ao conjunto de triggers de tabelas `public` e não está incluído em um snapshot limitado a `public`. Sua ausência exige atenção antes de considerar o baseline um substituto integral do ambiente Supabase.
- Snapshot sem dados não inclui a linha de configuração inicial `sla_config(id=true)`; a implantação futura precisa tratar seed/configuração em uma migration separada, se necessário.
- Aplicação ao banco hospedado **expressamente proibida nesta etapa**. Validar em CI antes de merge e depois reconciliar histórico de migrations em etapa controlada.
