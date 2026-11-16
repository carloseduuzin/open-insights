# Fixtures reais do StopView — Paradas e Pedidos de 16/11/2026

## Proveniência e campos preservados

- **Paradas:** `StopView - 1794849724851.csv` — 104 linhas, 135 colunas; SHA-256 do arquivo de origem: `a91dfa4673b2183d9a9a6272e327665d77fbbae48dc83fae187b1dd706a45452`.
- **Pedidos:** `StopView - 1794849734118.csv` — 104 linhas, 45 colunas; SHA-256 do arquivo de origem: `e65bb6f4d0f15a15e5e5be177322c0127466f837677a0b36643d12164d8ae173`.
- Há **104 IDs coincidentes** entre esses dois exports. Nos 104 casos, código de rota, data e código de localidade coincidem.
- O arquivo de Pedidos menor fornecido anteriormente (`StopView - 1794848663737.csv`) também continha 104 linhas, mas esta revisão usa como fontes os **dois exports anexados juntos**.
- `stopview_pedidos_2026-11-16_amostra.csv`: 40 registros reais de Pedidos, preservando ID de parada, NF bruta, rota, data, localidade e demais códigos. Nomes de clientes e motoristas foram substituídos por `CLIENTE_NNN` e `MOTORISTA_NN`; SHA-256 da fixture: `55926ede9772a11c89c33ef0a273de7a9867939788a197cfefbafc63a0b101e3`.
- `stopview_paradas_2026-11-16_amostra.csv`: exatamente os **mesmos 40 IDs**, extraídos do export de Paradas, com organização, data, código de rota, **romaneio real** e código de localidade. Sem nome, endereço, telefone nem coordenadas. SHA-256 da fixture: `4836c1309950943ec8f5833667907bf38c42731edae038b81ef5763901d7d1b`.
- Os dois CSVs são carregados pelo teste SQL com `\\copy`, unidos por ID e validados quanto a data, código de rota, localidade e organização.
- **Romaneios fictícios `999000000001` etc. existem apenas no JSON de teste enviado à RPC**, para manter o pedido original. **Não estão substituindo os romaneios reais nas fixtures** e não são dados fiscais JTI.

## Casos reais que os dois exports permitem comprovar

- Na amostra de 40 linhas: 37 NFs explícitas; 2 paradas com pedido/NF vazio (`SEM_NF`); 1 transferência na rota `SP-1VTVU005`, com valor `5`.
- No conjunto completo de 104 linhas: **2** valores vazios, **1** rota VTVU (`SP-1VTVU005`), **nenhuma** ocorrência dos cinco números sem série solicitados nem da NF `005605465`.
- Seis rotas distintas; todos os 104 registros com organização `RENOVELOG-ZL`.

## Cobertura exigida que NÃO existe nestes anexos

- Duas aparições da NF `005605465` para verificar a nota única e os dois vínculos.
- Cinco números sem série: `5603005`, `5604380`, `5605180`, `5606327`, `5607071`, para `SERIE_ASSUMIDA`.
- A rota `SP-1VTVU004` (a outra transferência VTVU).
- A terceira parada com NF vazia.

Por isso, `tests/stopview-fixture-real.sql` **falha intencionalmente no gate final de cobertura**. Os testes funcionais com os 40 registros reais acontecem primeiro; não aprovar o PR até que o usuário disponibilize a parte do export de 16/11 que contém os registros restantes (a revisão anterior citou 307 linhas). Não inventar dados para completar a fixture.
