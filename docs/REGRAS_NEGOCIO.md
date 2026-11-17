# Regras de Negócio — SIGO / Renovelog ZL

## Abastecimento VUC e rotas VTVU (16/11/2026)

**Decisão operacional:** códigos de rota `SP-<n>VTVU...` representam **abastecimento do cross por VUC**, não transferência de notas fiscais. A regra de classificação contempla também outros códigos VT já reconhecidos pela importação, para manter a retrocompatibilidade. O campo de classificação é `rotas.tipo_rota`, com valores `ENTREGA` (padrão) e `ABASTECIMENTO`.

O código de rota indica o tipo de operação, **não a localidade de destino**. A destinação deve vir exclusivamente do campo **`Código da Localidade`** do StopView, persistido em `paradas.codigo_localidade`. O cross próprio é configurado em `sla_config.localidade_cross_proprio` (padrão `CROSS-ZL`).

- **`SP-1VTVU005` → `CROSS-ZL`:** abastecimento registrado e exibido em `v_chegadas_vuc`.
- **`SP-1VTVU004` → `CROSS-ZS`:** abastecimento registrado, porém **não** exibido na view das chegadas do cross próprio.
- **Nenhuma parada de abastecimento** gera `notas_fiscais`, `parada_notas`, `nf_execucoes`, `prestacoes` nem `pendencias_importacao` por si só. Seu valor de pedido bruto é preservado em `paradas.valor_bruto_pedido`.
- A view `public.v_chegadas_vuc` expõe **data, código da rota, motorista, localidade de destino e `valor_bruto_pedido`**, filtrando exclusivamente `localidade_cross_proprio`. Usa `security_invoker=true`, os grants de SELECT e as políticas RLS existentes nas tabelas de origem.
- **`valor_bruto_pedido` não tem significado de negócio confirmado.** O exemplo real é `5`. Não interpretar como quantidade de volumes, NFs, caixas, notas ou valor monetário até receber validação operacional.
- Pendências antigas com motivo `TRANSFERENCIA` permanecem no histórico (sem exclusão), mas passam a `TRATADA` com observação **`abastecimento VUC`** e data de tratamento. O motivo deixa de ser gerado por novos imports; os demais motivos de importação mantêm suas regras.
- A configuração `localidade_cross_proprio` é ajustável, mas sua mudança deve ser tratada como decisão operacional, não derivada do nome de rota.

### Fonte e segurança dos testes

A linha de `SP-1VTVU005 / CROSS-ZL` em `tests/fixtures/vuc_2026-11-16_regressao.csv` foi extraída dos StopViews de 16/11/2026 (ID `11617893`, romaneio `600000000002`, valor bruto `5`). Para `SP-1VTVU004 / CROSS-ZS`, **código e localidade** foram informados na revisão operacional, mas o ID `99000004` e o romaneio `999000000004` são **sintéticos somente no teste**. Nunca apresentar o cenário como linha extraída do export.

A migration incremental `20261116000450_sigo_vt_abastecimento.sql` preserva os valores brutos e não deve ser executada no banco hospedado sem reconciliação separada do histórico de migrations.
