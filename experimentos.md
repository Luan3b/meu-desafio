# Experimentos

## 01 — Pool de conexões

- **Hipótese:** reutilizar até 10 conexões com `pg.Pool` deve reduzir a latência e a CPU do banco, evitando abrir e fechar uma conexão PostgreSQL para cada consulta. A resposta da API deve permanecer igual.
- **Fonte da hipótese:** [node-postgres — Pooling](https://node-postgres.com/features/pooling). A documentação explica o custo de handshake por conexão e recomenda pool para aplicações que fazem consultas frequentes. O tamanho 10 é o padrão documentado em [Pool API](https://node-postgres.com/apis/pool); será definido explicitamente neste experimento.
- **Antes:** três execuções de `00-linha-de-base`, com `VUS=20`, `DURACAO=60s` e `SEMENTE=42`: [113816](resultados/20261106-113816-00-linha-de-base/), [114000](resultados/20261106-114000-00-linha-de-base/) e [114143](resultados/20261106-114143-00-linha-de-base/).
- **Depois:** três execuções de `01-pool`, com os mesmos parâmetros: [155042](resultados/20261106-155042-01-pool/), [155548](resultados/20261106-155548-01-pool/) e [155750](resultados/20261106-155750-01-pool/). Todas tiveram `0.00%` de erros e terminaram com “Contrato mantido”. Uma execução interrompida, sem verificação de contrato completa, foi descartada.
- **Status:** aplicada e medida.
- **Conclusão:** as medianas passaram de 2,39 para 2,86 requisições/s (+19,7%) e de 26.801 ms para 25.227,2 ms no p95 geral (-5,9%). A mediana de CPU média do banco caiu de 100,2% para 99,3%, ainda perto do limite. A memória média da API subiu de 35,2 MiB para 38,3 MiB. Na rota `/clientes/:id/pedidos`, o p95 mediano foi de 28.557,3 ms para 30.030,7 ms; o pool, sozinho, não resolveu esse gargalo. A variação de memória do banco entre execuções foi alta, então não concluímos economia de memória.

## 02 — Consulta única para pedidos do cliente

- **Hipótese:** substituir as consultas sequenciais de pedidos, itens e produtos por uma consulta com `LEFT JOIN` deve reduzir as viagens entre API e banco e o p95 de `/clientes/:id/pedidos`, sem mudar status, campos, valores ou ordem da resposta.
- **Fonte da hipótese:** [Turcotte, Aldrich e Tip, “reformulator: Automated Refactoring of the N+1 Problem in Database-Backed Applications”, ASE 2022](https://doi.org/10.1145/3551349.3556911). O estudo descreve consultas dentro de loops como N+1 e avalia refatorações que reduzem o número de consultas; os autores também recomendam verificar o comportamento após a transformação. O estudo usa Sequelize, enquanto esta API usa SQL direto, portanto é uma justificativa para testar, não uma previsão do ganho.
- **Antes:** três execuções da versão com pool: [155042](resultados/20261106-155042-01-pool/), [155548](resultados/20261106-155548-01-pool/) e [155750](resultados/20261106-155750-01-pool/). Na rota `/clientes/:id/pedidos`, o p95 mediano foi 30.030,7 ms.
- **Depois:** três execuções de `02-pedidos-join`, com os mesmos parâmetros: [160657](resultados/20261106-160657-02-pedidos-join/), [160838](resultados/20261106-160838-02-pedidos-join/) e [161023](resultados/20261106-161023-02-pedidos-join/). Todas tiveram `0.00%` de erros e terminaram com “Contrato mantido”.
- **Status:** aplicada e medida.
- **Conclusão:** comparada à versão com pool, a mediana subiu de 2,86 para 4,21 requisições/s (+47,2%). O p95 geral caiu de 25.227,2 ms para 10.916,1 ms (-56,7%), e o p95 de `/clientes/:id/pedidos` caiu de 30.030,7 ms para 11.155,5 ms (-62,8%). A CPU média do banco permaneceu praticamente igual (99,3% para 99,4%), enquanto a memória máxima mediana do banco subiu de 479,0 MiB para 502,4 MiB, perto do limite de 512 MiB. A mudança acelerou a API nesta carga, mas não reduziu a saturação de CPU e elevou o pico de memória observado; esse custo precisa ser acompanhado nos próximos experimentos.

## 03 — Índices para pedidos do cliente

- **Hipótese:** índices B-tree em `pedidos(cliente_id, criado_em DESC, id DESC)` e `itens_pedido(pedido_id, id)` devem evitar as leituras sequenciais observadas no plano da rota com JOIN, reduzindo o p95 de `/clientes/:id/pedidos` e a carga do banco. O custo é espaço em disco e manutenção dos índices.
- **Evidência anterior:** [planos e índices antes do teste](diagnostico/03-planos-antes-indices.txt). A consulta JOIN fez leitura sequencial de 500 mil pedidos e 1,5 milhão de itens, com tempo de execução de 4.706 ms para o cliente analisado; só as quatro chaves primárias apareciam em `\\di`.
- **Fonte da hipótese:** [documentação PostgreSQL 16 — índices](https://www.postgresql.org/docs/16/indexes.html) explica o benefício e o custo geral de índices; [índices multicoluna](https://www.postgresql.org/docs/16/indexes-multicolumn.html) explica a utilidade de colocar primeiro a coluna filtrada (`cliente_id` ou `pedido_id`) e depois as colunas de ordenação.
- **Antes:** três execuções de `02-pedidos-join`: [160657](resultados/20261106-160657-02-pedidos-join/), [160838](resultados/20261106-160838-02-pedidos-join/) e [161023](resultados/20261106-161023-02-pedidos-join/). O p95 mediano da rota foi 11.155,5 ms.
- **Depois:** pendente.
- **Status:** mudança em preparação; ainda sem medição posterior.
- **Conclusão:** pendente.
