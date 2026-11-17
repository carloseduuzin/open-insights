# PR A — reentrega e transferência (em homologação)

Proposta de banco, sem aplicação no Supabase hospedado. A interface será uma etapa posterior à aprovação desta base.

## Regras vigentes

- A bipagem identifica a NF. Recebimento físico, retorno para reentrega e transferência são movimentos distintos.
- A prestação mantém o romaneio fiscal de origem. Transferências preservam origem e registram destino e operador.
- O prazo de reentrega começa no registro do retorno: dois dias interpretados como 48 horas completas. Novas tentativas e transferências não reiniciam esse prazo.
- Após ultrapassar o prazo sem baixa, a NF e a prestação recebem alerta de atraso. O prazo não cria devolução automaticamente.
- Cada falha após uma nova saída confirmada gera uma tentativa no histórico. Não há limite automático de duas tentativas.
- Nova saída exige evidência de importação do GreenMile. Presença em rota não comprova entrega nem recebimento físico do canhoto.
- O mapeamento de status de entrega começa vazio: os exports disponíveis não trazem status de entrega preenchido. Não inventar esse estado.
- Responsabilidades dos oito motivos são uma proposta inicial editável pelo administrador; cada tentativa conserva a responsabilidade registrada na ocasião.

## Validação e limites

Os testes SQL de regras são sintéticos, identificados como tal, executados em PostgreSQL isolado e revertidos. O teste de importação carrega o CSV versionado com duas linhas reais e confere persistência, origem fiscal e replay sem duplicação. Esses testes passaram na execução isolada anterior à última correção de compatibilidade; a revisão atual deve manter todos os checks aprovados. Porém, não há NF coincidente entre essas amostras para comprovar o ciclo completo de reentrega entre dias. Essa evidência continua pendente antes de liberar o fluxo.

Migration nomeada pela CLI na execução isolada: `20261117194733_sigo_reentrega_transferencia.sql`. O deploy transacional em `supabase/deploy/` compara todas as linhas das tabelas existentes antes/depois, sem quantidade fixa. Não usar db push; não executar em produção nesta etapa.

Antes de qualquer implantação: concluir testes, revisar permissões e conciliação, gerar backup atualizado e comprovar recuperação. O backup original de 25 prestações não substitui a proteção dos dados importados posteriormente. As verificações de preservação devem comparar o estado atual completo, sem assumir quantidade fixa de 25.
