<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

## Testes de importação GreenMile — fonte real obrigatória

- **Todo novo teste de importação deve utilizar uma fixture extraída de um export real do GreenMile**, com referência à data, ao tipo de relatório (StopView/RouteView), às colunas originais e à procedência.
- Preserve os campos necessários para conferir códigos de rota, IDs de parada e valores originais de NF. Remova ou anonimiza dados pessoais e dados comerciais sensíveis antes de versionar uma amostra no GitHub; **não altere nem invente valores técnicos** usados pelas regras testadas.
- As fixtures devem ficar em `tests/fixtures/`; o teste SQL/automatizado precisa **carregar o arquivo versionado**, em vez de reconstruir manualmente as linhas do export em `VALUES` ou JSON.
- **Se o export real não estiver acessível, não fabrique uma fixture nem descreva dados simulados como reais.** Registre o bloqueio no PR e mantenha qualquer teste sintético explicitamente identificado como provisório, sem apresentá-lo como homologação com dados reais.
- Para o PR #5, os números de NF e códigos de rota informados na revisão são comprovados pelo relato operacional; os demais campos das fixtures sintéticas existentes **não** foram extraídos do arquivo original de 16/11/2026. A substituição por `tests/fixtures/stopview_2026-11-16_amostra.csv` está pendente de acesso ao CSV fonte.
