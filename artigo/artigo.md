# Da varredura de tabelas a 596,40 req/s, sem aumentar os limites

## 1. Resumo

A API de loja respondia lentamente sob uma carga de 20 usuários. Investiguei as consultas e medi cada alteração com o mesmo script. Mantendo API em 0,5 CPU/256 MB e PostgreSQL em 1 CPU/512 MB, a mediana passou de 2,39 para 596,40 requisições por segundo; o p95 geral caiu de 26.801 ms para 71,5 ms. O contrato foi mantido. O maior avanço veio de eliminar trabalho repetido no banco, pré-calcular agregações e substituir a paginação profunda por busca direta da posição.

## 2. Contexto e diagnóstico

A API usa Node.js, Express e PostgreSQL 16, com 100 mil clientes, 20 mil produtos, 500 mil pedidos e 1,5 milhão de itens. A carga fornecida chama sete rotas. Uma execução da linha de base, em [00-linha-de-base](../resultados/20261106-114000-00-linha-de-base/), teve p95 geral de 26.738,9 ms; a mediana de três execuções foi 2,39 req/s e 26.801 ms. O PostgreSQL usou em média cerca de um núcleo.

Usei `EXPLAIN (ANALYZE, BUFFERS)` para observar leituras, ordenações e índices. Os planos mostraram varreduras grandes, agregações repetidas e custo crescente do `OFFSET`. Hipóteses, resultados e pastas estão em [experimentos.md](../experimentos.md).

**Hipóteses de causa:** a aplicação repetia viagens ao banco e agregações em cada chamada; algumas consultas examinavam muitas linhas sem um índice adequado; e `OFFSET` fazia o banco percorrer resultados que não seriam devolvidos. A leitura isolada de `/clientes/:id` já usa a chave primária e não mostrou um alvo claro para nova mudança.

## 3. Estado da arte

### Reduzir consultas e linhas processadas

A documentação do node-postgres recomenda reutilizar conexões com um pool limitado; abrir conexões repetidamente acrescenta o custo do handshake e clientes demais também pressionam o servidor ([node-postgres: pooling](https://node-postgres.com/features/pooling)). Um estudo acadêmico sobre o problema N+1 encontrou que consolidar consultas pode reduzir viagens ao banco preservando o comportamento, mas seus resultados são de aplicações Sequelize e não garantem o mesmo ganho nesta API SQL ([Turcotte, Aldrich e Tip, ASE 2022](https://doi.org/10.1145/3551349.3556911)).

### Índices e diagnóstico por planos

O PostgreSQL oferece índices B-tree, GIN, índices em expressões e outras formas de acesso; índices podem acelerar leituras, mas têm custo de espaço e manutenção ([documentação PostgreSQL 16, índices](https://www.postgresql.org/docs/16/indexes.html)). Para busca por trecho, `pg_trgm` permite que índices GIN ou GiST atendam operadores como `LIKE` e `ILIKE` ([documentação `pg_trgm`](https://www.postgresql.org/docs/16/pgtrgm.html)). `EXPLAIN` mostra o plano escolhido e `ANALYZE` inclui tempos e linhas observadas; por isso usei esses planos como diagnóstico, sem confundir uma amostra isolada com medição de carga ([documentação `EXPLAIN`](https://www.postgresql.org/docs/16/sql-explain.html)).

### Pré-computar trabalho repetido

Uma visão materializada armazena os resultados de uma consulta e pode ser atualizada com `REFRESH MATERIALIZED VIEW`; isso troca trabalho de leitura por espaço, criação e atualização dos dados ([documentação de visões materializadas](https://www.postgresql.org/docs/16/rules-materializedviews.html)). As estatísticas de `pg_stat_statements` ajudam a localizar consultas que acumulam planejamento e execução ([documentação `pg_stat_statements`](https://www.postgresql.org/docs/16/pgstatstatements.html)). São fontes técnicas primárias do próprio PostgreSQL; as referências completas estão na seção 8.

## 4. Alternativas consideradas

| Alternativa | Custo | Desempenho esperado | Risco | Esforço |
|---|---|---|---|---|
| Aumentar CPU do banco ou da API | Mais recurso reservado | Pode elevar vazão quando há saturação | Compra desempenho sem reduzir trabalho; custo maior | Baixo |
| Criar índices para consultas observadas | Espaço e manutenção em escrita | Busca seletiva pode ler menos páginas | Índice pode não ser escolhido ou piorar escrita | Baixo a médio |
| Reescrever consultas e consolidar viagens | Mais cuidado no código e no contrato | Menos linhas, consultas e viagens | Ordenação, nulos e tipos da resposta podem mudar | Médio |
| Pré-calcular resumos e posições | Espaço e atualização/frescor | Evita repetir agregações ou percorrer offsets | Resultado fica desatualizado se houver escrita | Médio |

Descartei aumentar a máquina como solução final: o teste temporário elevou a vazão, mas aumentou o recurso reservado. Os custos e demais tentativas estão no registro de experimentos.

## 5. Solução escolhida e por quê

Mantive mudanças com evidência de ganho e contrato preservado: pool menor, consultas consolidadas, índices de busca, resumos materializados e posições pré-calculadas. A decisão usa três execuções, não apenas um `EXPLAIN`.

Não mantive o índice coberto, a projeção isolada de colunas, o aumento de `work_mem` ou pool de três conexões, pois as medições não justificaram o custo ou mostraram resultado pior/inconclusivo. As visões materializadas são adequadas ao banco sintético e somente leitura deste desafio; uma aplicação com escrita exigiria uma política de atualização e teste de frescor.

## 6. Experimento e resultado

As medições usaram `VUS=20`, `DURACAO=60s` e `SEMENTE=42`. A tabela cobre os 27 experimentos; cada link abre a ficha com hipótese, fonte, pastas de resultados e recursos medidos.

| Mudança (detalhes e pastas) | p95 ms antes→depois | req/s antes→depois | CPU/RAM observadas | Decisão |
|---|---:|---:|---|---|
| [01 Pool](../experimentos.md#01--pool-de-conexões) | 26.801→25.227,2 | 2,39→2,86 | DB CPU 100,2→99,3%; API RAM 35,2→38,3 MiB | Ganho pequeno |
| [02 JOIN cliente-pedidos](../experimentos.md#02--consulta-única-para-pedidos-do-cliente) | 25.227,2→10.916,1 | 2,86→4,21 | DB CPU 99,3→99,4%; pico RAM 479→502,4 MiB | Mantida |
| [03 Índices pedidos/itens](../experimentos.md#03--índices-para-pedidos-do-cliente) | 10.916,1→9.058 | 4,21→6,25 | DB CPU perto de 100%; índices 51 MB | Mantidos |
| [04 Índice status](../experimentos.md#04--índice-para-pedidos-por-status) | 9.058→6.202 | 6,25→10,13 | DB CPU 99,8→99,7%; pico RAM 497,8→478,3 MiB | Parcial |
| [05 Menos coluna](../experimentos.md#05--remover-coluna-não-usada-em-vendas-por-dia) | 6.202→4.003,2 | 10,13→12,87 | API RAM 43,9→32 MiB; DB próximo do limite | Mantida |
| [06 Banco 2 CPU](../experimentos.md#06--diagnóstico-temporário-com-2-cpus-no-banco) | 4.003,2→2.117,8 | 12,87→24,05 | DB CPU 100,3→200,4%; RAM máx. 473,9 MiB | Revertido |
| [07 Diagnóstico SQL](../experimentos.md#07--diagnóstico-de-consultas-com-pg_stat_statements) | Não comparável | 13,36 no diagnóstico | DB CPU 100,7% | Sem mudança |
| [08 Resumo top produtos](../experimentos.md#08--pré-computar-os-totais-de-top-produtos) | 4.395→1.891,2 | 13,31→26,17 | DB CPU 100,0→100,2%; RAM 367,1→213,3 MiB | Mantido |
| [09 Filtro de data](../experimentos.md#09--usar-intervalo-direto-de-timestamp-no-relatório-diário) | 1.698,6→1.407,5 | 27,43→30,88 | DB CPU 100,8→100,3% | Mantido |
| [10 Projeção](../experimentos.md#10--selecionar-somente-colunas-usadas-na-listagem-de-pedidos) | 1.409,3→1.539,6 | 30,40→27,72 | DB CPU 99,9→96,6% | Revertida |
| [11 Índice email](../experimentos.md#11--índice-funcional-para-busca-de-cliente-por-e-mail) | 1.400,8→1.193,8 | 30,28→40,60 | DB CPU 100→99,7%; índice 4.792 kB | Mantido |
| [12 Índice trigram](../experimentos.md#12--índice-trigram-para-busca-de-produtos) | 1.246,7→1.399,4 | 40,14→41,81 | DB CPU 99,1→95,5%; índice 1.144 kB | Misto |
| [13 Resumo contagem](../experimentos.md#13--pré-computar-a-contagem-exata-de-pedidos-por-status) | 1.212,2→1.209,5 | 43,62→46,33 | DB CPU 97,2→94,0%; resumo 16 kB | Ganho modesto |
| [14 Índice coberto](../experimentos.md#14--tornar-a-paginação-profunda-de-pedidos-coberta-pelo-índice) | 1.190,8→1.193,7 | 48,08→46,87 | DB CPU 94,9→95,6%; índice 21 MB | Removido |
| [15 `work_mem`](../experimentos.md#15--avaliar-work_mem-para-a-ordenação-de-páginas-profundas) | Sem carga comparável | — | 64 MB evitou temp numa amostra | Não aplicado |
| [16 Pool 10→5](../experimentos.md#16--reduzir-o-pool-de-conexões-de-10-para-5) | 1.190,8→1.005,5 | 48,08→50,35 | DB CPU 94,9→91,7%; pico RAM 507,3→487,9 MiB | Mantido então |
| [17 Pool 5→2](../experimentos.md#17--reduzir-o-pool-de-conexões-de-5-para-2) | 1.005,5→836,7 | 50,35→55,11 | DB CPU 91,7→83,8%; RAM 367,6→219,4 MiB | Mantido então |
| [18 Pool 2→1](../experimentos.md#18--reduzir-o-pool-de-conexões-de-2-para-1) | 836,7→714,5 | 55,11→62,23 | DB CPU 83,8→73,9%; RAM 219,4→165,1 MiB | Mantido então |
| [19 Resumo diário](../experimentos.md#19--pré-computar-as-vendas-agregadas-por-dia) | 714,5→308,7 | 62,23→197,63 | DB CPU 73,9→91,4%; RAM 165,1→167,5 MiB | Mantido |
| [20 JOIN cliente-pedidos](../experimentos.md#20--buscar-cliente-e-pedidos-em-uma-consulta) | 308,7→299,5 | 197,63→207,91 | DB CPU 91,4→94,7% | Mantido |
| [21 Uma consulta pedidos](../experimentos.md#21--buscar-contagem-e-página-de-pedidos-em-uma-consulta) | 299,5→207,2 | 207,91→274,35 | DB CPU 94,7→87,9% | Mantida |
| [22 Pool 1→2](../experimentos.md#22--reavaliar-tamanho-do-pool-após-reduzir-as-consultas-por-requisição) | 207,2→202,0 | 274,35→288,46 | DB CPU 87,9→100,4% | Misto |
| [23 Pool 2→3](../experimentos.md#23--aumentar-o-pool-atual-de-2-para-3) | 202,0→279,9 | 288,46→218,43 | DB CPU 100,4→100,2% | Rejeitado |
| [24 Posição pedidos](../experimentos.md#24--pré-calcular-a-posição-de-cada-pedido-por-status) | 202→71,5 | 288,46→596,40 | DB CPU 100,4→43,6%; RAM 160,8→172 MiB | Mantida |
| [25 `/pedidos` isolado](../experimentos.md#25--isolar-o-efeito-da-otimização-de-pedidos) | 28.415,7→26.848,2 | 2,25→2,88 | DB CPU 99,3→100,3% | Só rota: p95 -97,4% |
| [26 API 0,5→0,75 CPU](../experimentos.md#26--aumentar-o-limite-de-cpu-da-api-de-05-para-075) | 71,5→45,4 | 596,40→884,13 | API CPU 50,9→77%; DB 43,6→67,5% | Revertida |
| [27 API 0,75→1 CPU](../experimentos.md#27--aumentar-o-limite-de-cpu-da-api-de-075-para-10) | Incompleto | Duas execuções | Configuração padrão restaurada | Sem conclusão |

Na comparação geral, a CPU média da API foi 7,5% na linha de base e 50,9% na versão final; a do banco caiu de 100,2% para 43,6%. A memória média mediana passou de 35,2 para 30,5 MiB na API e de 419,8 para 172,0 MiB no banco. Os limites permaneceram iguais. Os valores vêm das pastas da linha de base e da versão final; as medições completas incluem p99, erros e arquivos de recursos. O teste isolado de `/pedidos` também está registrado em [diagnostico/isolamento-pedidos.md](../diagnostico/isolamento-pedidos.md): isoladamente, reduziu o p95 da rota de 26.795,9 para 696,9 ms, mas não eliminou a lentidão das outras rotas originais.

## 7. Limites e testes futuros

Os resultados cobrem uma máquina, banco estático e 20 usuários. Mudanças interagem, então ganhos incrementais não se somam como contribuições individuais. Não medi escrita nem frescor contínuo das visões; o único isolamento contra o original foi `/pedidos`. Escrita, mais concorrência ou outra consulta dominante poderiam mudar a conclusão; as fichas estão em [proximos-testes.md](../proximos-testes.md).

## 8. Referências

1. Turcotte, Alexi; Aldrich, Mark W.; Tip, Frank. *Reformulator: Automated Refactoring of the N+1 Problem in Database-Backed Applications*. ASE 2022. [DOI](https://doi.org/10.1145/3551349.3556911). Acesso em 16 nov. 2026.
2. node-postgres. *Pooling*. [Documentação oficial](https://node-postgres.com/features/pooling). Acesso em 16 nov. 2026.
3. PostgreSQL Global Development Group. *PostgreSQL 16: Indexes*. [Documentação](https://www.postgresql.org/docs/16/indexes.html). Acesso em 16 nov. 2026.
4. PostgreSQL Global Development Group. *PostgreSQL 16: `pg_trgm`*. [Documentação](https://www.postgresql.org/docs/16/pgtrgm.html). Acesso em 16 nov. 2026.
5. PostgreSQL Global Development Group. *PostgreSQL 16: `EXPLAIN`*. [Documentação](https://www.postgresql.org/docs/16/sql-explain.html). Acesso em 16 nov. 2026.
6. PostgreSQL Global Development Group. *PostgreSQL 16: Materialized Views*. [Documentação](https://www.postgresql.org/docs/16/rules-materializedviews.html). Acesso em 16 nov. 2026.
7. PostgreSQL Global Development Group. *PostgreSQL 16: `pg_stat_statements`*. [Documentação](https://www.postgresql.org/docs/16/pgstatstatements.html). Acesso em 16 nov. 2026.

## 9. Uso de IA

Usei IA para organizar hipóteses, revisar planos e redigir partes deste artigo e dos registros. Conferi os números nos arquivos de `resultados/`, validei os planos salvos e rodei o verificador de contrato; as fontes citadas foram abertas e conferidas.
