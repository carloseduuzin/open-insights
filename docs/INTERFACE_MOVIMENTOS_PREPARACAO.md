# Interface de movimentações — preparação dependente do PR A

Preparada em branch separada, sem publicar no Lovable ou alterar o Supabase em uso. Requer o PR A #14 validado e aprovado antes de abrir o PR B para integração na branch conectada ao Lovable.

- Ao abrir, o modo padrão é receber canhoto. Retorno para reentrega e transferência exigem seleção explícita.
- A leitura identifica a NF. Foi removida a escolha manual de NF faltante e a justificativa genérica no fluxo principal.
- Motivos de retorno são consultados no banco; falha na consulta impede registrar retorno com motivo desconhecido.
- A fila consulta dados persistidos e mostra NF, origem, situação, motivo, motorista, tentativa e prazo do banco. Atualiza a cada minuto enquanto a aba está visível e ao voltar para ela.
- Prazo vencido destaca a prestação atrasada. O alerta depende do prazo registrado no banco; não infere entrega pela presença em rota.
- A fila informa seu limite de 100 registros. Erro de consulta não aparece como ausência de pendências.
- Falha na atualização da lista após uma operação confirmada não é apresentada como falha de gravação, evitando orientar nova bipagem por engano.

Validação automática da branch inclui tipos, lint, testes e compilação. Ainda falta validar o fluxo interativo com autenticação em ambiente de homologação e evidência real da mesma NF em dias diferentes. Não implantar antes de concluir essas verificações e renovar o backup recuperável.
