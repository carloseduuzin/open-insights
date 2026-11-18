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
- Aplicação ao banco hospedado **expressamente proibida nesta etapa**. A validação em CI isolado foi aprovada; o histórico remoto de migrations precisa ser reconciliado em etapa controlada antes de qualquer aplicação no projeto Supabase.

#### Homologação do baseline — 16/11/2026

- Validação informada pelo responsável: execução em PostgreSQL 16 limpo com stub de `auth`, aplicação e reaplicação sem erros, inventário `14 tabelas / 2 views / 6 triggers / 33 políticas / 14 funções` e zero violações de RLS, `SECURITY DEFINER` sem `search_path` e views sem `security_invoker`.
- Confirmação independente em GitHub Actions: workflow `sigo-schema-baseline.yml` executou com sucesso em **PostgreSQL 16 e 17**, rodando aplicação do zero, reaplicação, conferência de inventário e verificações de segurança: https://github.com/carloseduuzin/open-insights/actions/runs/43883902998.
- O workflow mantém `workflow_dispatch`, além de `pull_request` para a branch `feat/sigo-supabase-v1`, limitado aos arquivos `supabase/**`. Não executa migrations no banco hospedado.
- A aprovação do CI demonstra replay com dependências mínimas de `auth`, não equivalência completa com instalações Supabase nem reconciliação do histórico remoto de migrations.

## 2026-11-16 — PR #4 / P0: responsável da prestação é imutável entre operadores

- **Decisão operacional:** `prestacoes.responsavel_id` identifica exclusivamente o usuário que cadastrou o romaneio. O responsável **não é transferido** ao operador que registra o retorno, confere ou envia a prestação à JTI.
- **Problema reproduzido:** A cria via `sigo_criar_prestacao`; B executa `sigo_avancar_prestacao(id, 'RETORNADA')`. A versão anterior da RPC atribuía `responsavel_id = v_usuario`, e o trigger de auditoria do hardening rejeitava com `Identidade e responsável são imutáveis`.
- **Correção no mesmo PR:** `supabase/migrations/20261116000300_sigo_sla_hardening_v2.sql` redefine `public.sigo_avancar_prestacao(uuid,text)` sobre o baseline removendo somente `responsavel_id=v_usuario` da etapa `RETORNADA` e `responsavel_id=coalesce(p.responsavel_id,v_usuario)` da `CONFERIDA`. Permissões, `SECURITY DEFINER`, `SET search_path TO ''`, validação de perfil ativo e demais regras de transição permanecem iguais.
- **Auditoria das etapas:** `conferida_por` registra quem conferiu e `enviada_por` registra quem enviou. O retorno da RPC para a etapa `RETORNADA` continua entregando `p.responsavel_id` no campo `registrado_por` (comportamento anterior preservado). Isso **não identifica o operador que efetuou o retorno**; eventual campo `retornada_por` exige evolução separada, não faz parte deste P0.
- **Teste automatizado no CI PostgreSQL 17:** `auth.uid()` passa a obter o UUID via `NULLIF(current_setting('sigo.uid', true), '')::uuid` no banco descartável, permitindo alternar entre usuários simulados. Perfis A e B possuem role `operacional`. O fluxo verificado é **A cria → B retorna → A confere → B envia**, garantindo o mesmo `responsavel_id` em todas as etapas e conferência/envio auditados pelos operadores corretos.
- **Teste de autorização:** um terceiro perfil ativo sem role tenta criar e avançar uma prestação; ambas as RPCs devem rejeitar com `Usuário sem acesso ativo ao SIGO`, sem gravar a tentativa de cadastro.
- **Escopo:** nenhuma mudança no Supabase hospedado, nenhuma alteração em dados reais e nenhum PR adicional. Esta correção atualiza o PR #4 antes do merge.

## 2026-11-16 — PR #5 — série padrão e transferência VT (revisão do CSV de 307 linhas)

**Origem da decisão:** revisão operacional informada do StopView real de 16/11/2026, com 307 linhas, sobre baseline + migration `0300` + `0400`. Os cinco casos reportados, na rota `SP-1MFV69`, foram: `5603005`, `5604380`, `5605180`, `5606327` e `5607071`. O arquivo original não foi incorporado ao repositório; o CI reproduz esses cinco valores em registros sintéticos isolados.

**P1 — NF sem série:**
- Criar `sla_config.serie_padrao` (`text NOT NULL DEFAULT '7'`, com check de 1 a 3 dígitos) e garantir a linha `sla_config(id=true)` de forma idempotente. A configuração deve ser consultada pelo banco dentro da RPC, não enviada pelo navegador.
- Após normalizar o número da NF, fazer a busca sob lock transacional: **zero** NFs com o número → criar a nota com `serie_padrao`, fixar `romaneio_origem`/`origem_rota_id` na primeira inserção e registrar `SERIE_ASSUMIDA` em `pendencias_importacao`, imediatamente `TRATADA` com `tratada_por` e `tratada_em` (rastreabilidade informativa); **uma** NF com o número → vincular à NF existente, preservando série e origem; **duas ou mais** NFs → não criar outra e registrar `SERIE_AMBIGUA` com `status='PENDENTE'`.
- Os cinco exemplos reais, antes incorretamente classificados `SERIE_AMBIGUA`, devem resultar em NFs `005603005-7`, `005604380-7`, `005605180-7`, `005606327-7` e `005607071-7`, desde que não haja registros prévios com esses números. O CI verifica essa condição a partir de banco vazio. Não há atribuição automática de série caso já exista uma ou mais NFs, exceto vincular à única correspondente.
- `SERIE_ASSUMIDA` é registro de auditoria concluído automaticamente, não pendência operacional bloqueante. A NF permanece sujeita à validação fiscal conforme os procedimentos da operação.

**P2 — rota VT:**
- Reconhecer também o padrão de rota com o sufixo VT imediatamente após o número da saída (exemplo sintético `SP-1VT69`), além de `VT-1`. A identificação de **valor curto `5` em rota VT** ocorre antes das validações de NF, gerando `TRANSFERENCIA`, e nunca `SEM_NF`.
- Valores vazios continuam `SEM_NF`. Valores de 1 a 2 dígitos fora de VT também continuam `SEM_NF`. Transferência não fabrica nota fiscal.

**Cobertura de testes:** `tests/stopview-import.sql` inclui os cinco números da rota `SP-1MFV69`, relatório informativo já tratado, não duplicação após reimportação, VT `5`, duas séries existentes causando `SERIE_AMBIGUA` e o caso de correspondência única `005605465-7`/`5605465`.

**Escopo:** mudanças restritas ao PR #5, na branch `feat/importacao-nf`. Não aplicar migrations no Supabase hospedado; o replay é validado exclusivamente no PostgreSQL descartável do CI. O histórico remoto de migrations ainda requer reconciliação antes de implantação.

## 2026-11-16 — Corrigir VT: abastecimento VUC, não transferência de NF

**Decisão:** rotas `SP-<n>VTVU...` são abastecimentos realizados por VUC, sem movimentação fiscal atribuída à Renovelog. O destino determina se a chegada pertence ao cross próprio. A Renovelog recebe abastecimento exclusivamente em `CROSS-ZL`; códigos VT enviados ao `CROSS-ZS` permanecem registrados, mas não entram no painel de chegadas ZL.

**Alterações da migration `20261116000450_sigo_vt_abastecimento.sql`:**
1. Acrescentar `rotas.tipo_rota` com `ENTREGA | ABASTECIMENTO` e default `ENTREGA`. VT é persistida como `ABASTECIMENTO`; códigos, romaneios e dados brutos originais são preservados.
2. Remover a geração de `TRANSFERENCIA` no novo fluxo da RPC `sigo_importar_stopview`. Toda parada VT fica fora do processamento fiscal: nenhuma NF, execução, vínculo fiscal ou pendência de importação.
3. Preservar o campo original `stop.orders.number` em `paradas.valor_bruto_pedido`, sem atribuir semântica. Ainda **não sabemos o que o valor `5` significa operacionalmente**. A localidade deve vir de `Código da Localidade`, não da sigla VTVU.
4. Adicionar `sla_config.localidade_cross_proprio` (default `CROSS-ZL`). Criar view `v_chegadas_vuc` com `security_invoker=true`, mostrando somente paradas de abastecimento cuja localidade corresponde à configuração.
5. Corrigir pendências históricas `TRANSFERENCIA` para `TRATADA` e observação `abastecimento VUC`, mantendo linha e valor bruto. Quando não há usuário de tratamento, a observação identifica encerramento por migration, sem inventar ator humano. Nenhum dado fiscal histórico é apagado.
6. Em replay parcial, o valor bruto de VT anterior só pode ser recuperado quando existir uma antiga pendência contendo o mesmo valor. **Não reconstruir valores que não estejam mais disponíveis**: um registro legado sem fonte permanece com `valor_bruto_pedido = NULL`.

**Testes:** PostgreSQL 17 isolado, dois usuários ativos `operacional`, `SP-1VTVU005 / CROSS-ZL` gerando exatamente uma linha em `v_chegadas_vuc`; `SP-1VTVU004 / CROSS-ZS` gravada como abastecimento e filtrada da view; zero NF, execução e pendência novas para ambos. A amostra 005 usa dados do export real de 16/11; o 004 usa código e destino da revisão, com ID e romaneio sintéticos claramente identificados em `tests/fixtures/vuc_2026-11-16_regressao.csv`.

**Status de deploy:** alteração **somente no GitHub e CI de PostgreSQL descartável**, não aplicada ao Supabase hospedado. O histórico remoto de migrations continua pendente de reconciliação.
