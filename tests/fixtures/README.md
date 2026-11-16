# Fixture real do StopView — Pedidos, 16/11/2026

## Origem e tratamento

- Arquivo fornecido pelo usuário: `StopView - 1794848663737.csv`.
- Data das rotas no arquivo: `2026-11-16`.
- Arquivo de origem inspecionado: **104 linhas** de Pedidos e 10 colunas. SHA-256 da origem: `66ecb1d631beeda6d34ede8bd11e6f1bf730de15fcd3c36285677b4a72b21a7f`.
- Esta amostra contém **40 linhas extraídas literalmente do arquivo** quanto aos IDs de parada, códigos de rota, datas, códigos de localidade, números de pedidos/NFs e dados estruturais.
- As únicas colunas alteradas para anonimização são `Descrição da Localidade` e `routeView.primaryDriver.name`, substituídas por pseudônimos estáveis `CLIENTE_NNN` e `MOTORISTA_NN`; não inferimos identidades.
- SHA-256 da amostra versionada: `55926ede9772a11c89c33ef0a273de7a9867939788a197cfefbafc63a0b101e3`.
- O CSV é de **Pedidos**: não possui romaneio. Em `tests/stopview-fixture-real.sql`, a parte de Paradas é gerada **somente para o teste**, usando romaneios fictícios explicitamente marcados `999000000001` etc. Esses números **não são IDs reais** do GreenMile/JTI.

## Cobertura presente nesta fonte

- 37 entradas com NF e série explícita.
- 2 paradas com número de NF vazio → `SEM_NF`.
- 1 parada com valor `5` na rota `SP-1VTVU005` → `TRANSFERENCIA`.
- 6 códigos de rota distintos e 40 IDs de parada distintos.

## Cobertura solicitada, mas ausente do arquivo fornecido

- NF `005605465` com seus dois vínculos.
- Cinco números sem série: `5603005`, `5604380`, `5605180`, `5606327`, `5607071`.
- A rota `SP-1VTVU004` e uma segunda transferência VTVU.
- A terceira parada com NF vazia.

O teste de cobertura intencionalmente **falha** se esses exemplos não estiverem na fixture. Não completar valores ausentes com linhas inventadas. Obter um export de Pedidos mais completo (a revisão anterior citou 307 linhas) e substituir a amostra por até aproximadamente 40 linhas que contenham todos os casos, preservando dados técnicos e a anonimização.
