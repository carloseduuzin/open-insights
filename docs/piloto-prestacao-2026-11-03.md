# SIGO — Roteiro de piloto de Prestação de Contas | 03/11/2026

## Estado de liberação
**Piloto assistido e reversível por processo, não substituição do GreenMile.** Autorização operacional depende de conferência visual no Lovable e de confirmar o arquivo e a data D0. Não publicar nem importar dados de produção no escuro.

## Preparação
1. Entrar com usuário ativo no Lovable sincronizado à branch `feat/sigo-supabase-v1`.
2. Verificar a aba **Prestação de Contas** (sem demonstração) e a aba **Importação GreenMile**.
3. Continuar o controle oficial existente em paralelo durante o piloto.
4. Não testar botões reais com documentos de cliente sem ter ocorrido retorno/conferência/envio.

## Conferir importação 03/11/2026
- Exports fornecidos previamente: 397 paradas + 397 linhas de pedidos; 24 rotas distintas; 23 romaneios oficiais candidatos e 1 romaneio auxiliar `600000000002`.
- A aba Importação deve mostrar a prévia dos romaneios **antes** da confirmação.
- Conferir códigos, romaneios e D0; a NF curta `5` já identificada na auditoria deve ser investigada no GreenMile separadamente.
- Somente abrir prestação em data D0 ou posterior, após confirmar que a carga é da operação RENOVELOG-ZL e os romaneios são fiscais oficiais. Não importar se houver erro de conciliação, data ou divergência.
- A importação cria APENAS filas de prestação; não grava notas, paradas ou rotas completas.

## Fluxo da prestação
1. **ABERTA**: romaneio entra na fila com D0.
2. **RETORNADA**: registrar quando os documentos físicos voltarem à base.
3. **CONFERIDA**: registrar após verificação de canhotos/documentos e pendências.
4. **ENVIADA_JTI**: confirmar apenas após envio real. Dá baixa no SIGO, tira do SLA ativo e mantém histórico, usuário e horário.
5. **CONFIRMADA_JTI**: estado opcional posterior; não é necessário para sair da fila.

D+3: data D0 + 3 dias corridos; D+2 alerta, D+3 urgente, D+4 crítico. Meta interna 48 horas.

## Proteções verificadas
- RPCs do Supabase para cadastro em lote, retorno, conferência e envio; somente usuários autenticados ativos.
- Importação em lote idempotente: não reabre romaneio já baixado.
- Teste transacional sintético de lote, reimportação e baixa executado sem deixar registros.
- GitHub CI da integração aprovado em 41551857033.

## Suspender o piloto e usar controle anterior se:
- Lovable não sincronizou ou exibe erro de acesso/rede.
- Contagem de romaneios não corresponde à prévia conferida, especialmente auxiliares.
- Qualquer baixa apareça sem ação deliberada ou falhe em registrar data/usuário.
- Status, prazo D0/D+3 ou fila não atualizarem após clicar.
- Houver divergência de dado fiscal ou canhoto com GreenMile.

## Pendências antes de ampliar
- Homologar manualmente no Lovable o fluxo real com um documento autorizado e a conferência física.
- Automatizar auditoria de canhotos/NFs e histórico de eventos detalhado, caso requerido.
- Não considerar o SIGO uma confirmação automática de recebimento da JTI.
