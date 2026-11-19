# Da varredura de tabelas a 612,73 req/s, sem aumentar os limites

## 1. Resumo

A API de loja era lenta sob carga. As mudanças reduziram consultas repetidas, pré-calcularam dados usados por relatórios e eliminaram o custo de percorrer páginas anteriores em `/pedidos`. Na versão final, com API em 0,5 CPU/256 MB e banco em 1 CPU/512 MB, a mediana foi 612,73 req/s e o p95 foi 70,7 ms. A comparação sequencial confirmou o contrato, mas o baseline teve timeouts e uma inconsistência na vazão reportada; portanto, não calculo um percentual geral confiável de aumento de req/s.

## 2. Contexto e diagnóstico

A API usa Node.js 20, Express e PostgreSQL 16 (100 mil clientes, 20 mil produtos, 500 mil pedidos e 1,5 milhão de itens). A carga (`VUS=20`, `DURACAO=60s`, `SEMENTE=42`) exercita sete rotas. A primeira linha de base ([114000](../resultados/20261106-114000-00-linha-de-base/resumo.txt)) registrou mediana de 2,39 req/s e p95 de 26.801 ms, com o banco em ~100% de 1 CPU ([recursos.txt](../resultados/20261106-114000-00-linha-de-base/recursos.txt)). Esse resultado pertence à sequência inicial dos experimentos. Já na comparação sequencial feita ao final ([experimento 29](../experimentos.md#29--comparação-sequencial-original-e-final)), as três execuções originais tiveram p95 mediano de 33.970 ms; duas tiveram timeout e uma reportou 0,00 req/s apesar de 138 requisições ([224132](../resultados/20261116-224132-29-comparacao-original/resumo.txt)). A versão final atingiu 610,16 a 612,97 req/s e p95 de 70,5 a 71,9 ms ([080825](../resultados/20261117-080825-29-comparacao-final/resumo.txt)). Como são sequências de medição diferentes e a comparação final do original foi instável, não calculo um percentual geral confiável de aumento de vazão.

Coletei `pg_stat_statements` ([09-consultas](../diagnostico/09-consultas-pg-stat-statements.txt)) e planos `EXPLAIN (ANALYZE, BUFFERS)`: loops e varreduras em pedidos do cliente ([03-planos](../diagnostico/03-planos-antes-indices.txt)), ordenação externa de 90 MB em `/pedidos` ([05-planos](../diagnostico/05-planos-status-antes.txt), [28-offset](../diagnostico/28-pedidos-pagina-offset-atual.txt)), agregações caras em relatórios ([07-vendas](../diagnostico/07-vendas-por-dia-antes.txt), [10-custosas](../diagnostico/10-planos-consultas-mais-custosas.txt)), varreduras em e-mail ([14-email](../diagnostico/14-clientes-email-antes.txt)) e busca de produtos ([16-produtos](../diagnostico/16-produtos-busca-antes.txt)), além do corpo inteiro nos logs ([32-log](../diagnostico/32-log-resposta-antes-depois.txt)). Só `/clientes/:id` já usava chave primária ([31-cliente](../diagnostico/31-cliente-por-id-atual.txt)).

Hipótese de causa:
- A API abria conexão por consulta e fazia buscas sequenciais (N+1) na mesma requisição.
- Faltavam índices para filtros por cliente, status, `lower(email)` e `ILIKE`, causando varreduras completas.
- Os relatórios reagregavam até 1,5 milhão de itens a cada chamada em dados estáticos.
- O `OFFSET` em `/pedidos` obrigava o banco a ordenar e descartar milhares de linhas em páginas profundas.

## 3. Estado da arte

### Reduzir consultas e linhas processadas

A documentação do node-postgres recomenda reutilizar conexões com um pool limitado; abrir conexões repetidamente acrescenta o custo do handshake e clientes demais também pressionam o servidor ([node-postgres: pooling](https://node-postgres.com/features/pooling)). Um estudo acadêmico sobre o problema N+1 encontrou que consolidar consultas pode reduzir viagens ao banco preservando o comportamento, mas seus resultados são de aplicações Sequelize e não garantem o mesmo ganho nesta API SQL ([Turcotte, Aldrich e Tip, ASE 2022](https://doi.org/10.1145/3551349.3556911)).

Chen et al. também estudaram antipadrões de desempenho em aplicações ORM e reportaram melhorias de resposta de até 98% (35% em média) ao corrigir os casos analisados. Esse resultado motiva investigar trabalho excessivo no acesso a dados, mas não prevê o ganho desta API: o estudo usa aplicações ORM, enquanto este projeto faz SQL diretamente ([Chen et al., ICSE 2014](https://petertsehsun.github.io/papers/peter_icse2014.pdf)).

### Índices e diagnóstico por planos

O PostgreSQL oferece índices B-tree, GIN, índices em expressões e outras formas de acesso; índices podem acelerar leituras, mas têm custo de espaço e manutenção ([documentação PostgreSQL 16, índices](https://www.postgresql.org/docs/16/indexes.html)). Para busca por trecho, `pg_trgm` permite que índices GIN ou GiST atendam operadores como `LIKE` e `ILIKE` ([documentação `pg_trgm`](https://www.postgresql.org/docs/16/pgtrgm.html)). `EXPLAIN` mostra o plano escolhido e `ANALYZE` inclui tempos e linhas observadas; por isso usei esses planos como diagnóstico, sem confundir uma amostra isolada com medição de carga ([documentação `EXPLAIN`](https://www.postgresql.org/docs/16/sql-explain.html)).

### Pré-computar trabalho repetido

Uma visão materializada armazena os resultados de uma consulta e pode ser atualizada com `REFRESH MATERIALIZED VIEW`; isso troca trabalho de leitura por espaço, criação e atualização dos dados ([documentação de visões materializadas](https://www.postgresql.org/docs/16/rules-materializedviews.html)). As estatísticas de `pg_stat_statements` ajudam a localizar consultas que acumulam planejamento e execução ([documentação `pg_stat_statements`](https://www.postgresql.org/docs/16/pgstatstatements.html)). São fontes técnicas primárias do próprio PostgreSQL; as referências completas estão na seção 8.

## 4. Alternativas consideradas

| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| Aumentar CPU (banco ou API) | Mais recurso reservado | Eleva vazão sob saturação | Compra capacidade sem reduzir trabalho | Baixo |
| Criar índices específicos | Espaço e manutenção em escrita | Busca seletiva lê menos páginas | Pode não ser usado ou custar em escrita | Baixo a médio |
| Reescrever e consolidar consultas | Cuidado no código e contrato | Menos linhas e viagens ao banco | Pode alterar ordem, nulos ou tipos | Médio |
| Pré-calcular resumos e posições | Espaço e atualização | Evita reagregar ou varrer offsets | Defasagem se houver escrita | Médio |

Descartei aumentar a máquina como solução final: o teste temporário com mais CPU elevou a vazão, mas aumentou o recurso reservado sem eliminar o trabalho redundante das consultas. O objetivo do desafio é reduzir o custo computacional dentro do mesmo orçamento de hardware (0,5 CPU na API e 1,0 CPU no banco).

A paginação por chave (*keyset pagination*) também evita descartar muitas linhas em páginas profundas, mas usa um cursor em vez do número de página. Como isso altera os parâmetros e o formato esperado pelo verificador de contrato, ela não pode substituir `/pedidos?status=&pagina=` diretamente; precisaria ser exposta como uma rota separada ([Markus Winand, seek method](https://use-the-index-luke.com/sql/partial-results/fetch-next-page)).

## 5. Solução escolhida e por quê

Mantive mudanças com evidência de ganho e contrato preservado: pool menor, consultas consolidadas, índices de busca, resumos materializados e posições pré-calculadas. A decisão usa três execuções, não apenas um `EXPLAIN`.

Não mantive o índice coberto, a projeção isolada de colunas, o aumento de `work_mem` ou pool de três conexões, pois as medições não justificaram o custo ou mostraram resultado pior/inconclusivo. As visões materializadas são adequadas ao banco sintético e somente leitura deste desafio; uma aplicação com escrita exigiria uma política de atualização e teste de frescor, pois `REFRESH MATERIALIZED VIEW` substitui o conteúdo da visão ([documentação PostgreSQL](https://www.postgresql.org/docs/18/sql-refreshmaterializedview.html)).

## 6. Experimento e resultado

As mudanças foram medidas com `VUS=20`, `DURACAO=60s` e `SEMENTE=42`. A tabela reúne mudanças mantidas, testes sem ganho (revertidos) e a comparação final; a tabela completa das 29 etapas está em [experimentos.md](../experimentos.md).

| Mudança | Hipótese | p95 antes → depois | req/s antes → depois | CPU/memória | Pastas de resultados | Conclusão |
|---|---|---|---|---|---|---|
| [02-pedidos-join](../experimentos.md#02--consulta-única-para-pedidos-do-cliente) | `LEFT JOIN` elimina N+1 da rota | 25.227,2→10.916,1 ms | 2,86→4,21 | DB CPU 99,3→99,4%; RAM máx 479→502,4 MiB | [155548](../resultados/20261106-155548-01-pool/)→[160838](../resultados/20261106-160838-02-pedidos-join/) | p95 rota -62,8%; mantida. |
| [03-indices-cliente](../experimentos.md#03--índices-para-pedidos-do-cliente) | Índices B-tree evitam Seq Scan | 10.916,1→9.058 ms | 4,21→6,25 | DB CPU ~100%; +51 MB disco | [160838](../resultados/20261106-160838-02-pedidos-join/)→[162035](../resultados/20261106-162035-03-indices-pedidos-cliente/) | p95 rota -61,1%; mantida. |
| [08-top-produtos](../experimentos.md#08--pré-computar-os-totais-de-top-produtos) | Visão evita agregar 1,5M itens | 4.395→1.891,2 ms | 13,31→26,17 | DB CPU ~100%; RAM 367,1→213,3 MiB | [120735](../resultados/20261109-120735-08-top-produtos-antes/)→[121509](../resultados/20261109-121509-08-top-produtos-depois/) | Vazão +96,6% (2,3 MB); mantida. |
| [10-pedidos-colunas](../experimentos.md#10--selecionar-somente-colunas-usadas-na-listagem-de-pedidos) | Projetar 4 colunas reduz leitura | 1.409,3→1.539,6 ms | 30,40→27,72 | DB CPU 99,9→96,6% | [144654](../resultados/20261109-144654-10-pedidos-colunas-antes/)→[145210](../resultados/20261109-145210-10-pedidos-colunas-depois/) | Sem ganho (-8,8%); revertida. |
| [14-indice-coberto](../experimentos.md#14--tornar-a-paginação-profunda-de-pedidos-coberta-pelo-índice) | `INCLUDE` acelera offset profundo | 1.190,8→1.193,7 ms | 48,08→46,87 | DB CPU 94,9→95,6%; 21 MB disco | [160330](../resultados/20261109-160330-14-paginacao-antes/)→[160956](../resultados/20261109-160956-14-paginacao-depois/) | Sem ganho (20k fetches); removido. |
| [19-vendas-dia](../experimentos.md#19--pré-computar-as-vendas-agregadas-por-dia) | Visão diária evita reagregação | 714,5→308,7 ms | 62,23→197,63 | DB CPU 73,9→91,4%; API CPU 43,9→22,7% | [162951](../resultados/20261109-162951-18-pool-1/)→[163845](../resultados/20261109-163845-19-vendas-dia-depois/) | Vazão 3,18x (72 kB); mantida. |
| [23-pool-3](../experimentos.md#23--aumentar-o-pool-atual-de-2-para-3) | Pool 2→3 eleva vazão | 202,0→279,9 ms | 288,46→218,43 | DB CPU 100,4→100,2% | [165831](../resultados/20261109-165831-22-pool-2-atual/)→[202604](../resultados/20261109-202604-23-pool-3/) | Vazão -24,3%; revertida. |
| [24-pedidos-posicao](../experimentos.md#24--pré-calcular-a-posição-de-cada-pedido-por-status) | Posição elimina custo do `OFFSET` | 202,0→71,5 ms | 288,46→596,40 | DB CPU 100,4→43,6%; RAM 160,8→172 MiB | [165831](../resultados/20261109-165831-22-pool-2-atual/)→[103545](../resultados/20261110-103545-24-pedidos-posicao-depois/) | Vazão +106,8%; mantida. |
| [26-api-cpu-075](../experimentos.md#26--aumentar-o-limite-de-cpu-da-api-de-05-para-075) | API em 0,75 CPU eleva vazão | 71,5→45,4 ms | 596,40→884,13 | API CPU 50,9→77,0%; DB CPU 43,6→67,5% | [103545](../resultados/20261110-103545-24-pedidos-posicao-depois/)→[111359](../resultados/20261110-111359-26-api-cpu-075/) | Exige +0,25 CPU; revertida. |
| [29-comparacao](../experimentos.md#29--comparação-sequencial-original-e-final) | Final mantém limites e contrato | 33.970→70,7 ms | Instável→612,73 | API CPU 8,3→50,9%; DB CPU 100,1→45,1% | [224132](../resultados/20261116-224132-29-comparacao-original/)→[080825](../resultados/20261117-080825-29-comparacao-final/) | Limites mantidos; banco livre. |

No experimento 29, a API usou mediana de 50,9% de CPU (limite 0,5 CPU) e o banco 45,1% (limite 1,0 CPU), contra 8,3% e 100,1% no original: a API trabalha mais porque atende muito mais vazão, enquanto o banco deixou de saturar. A memória média mediana ficou em 30,0 MiB na API (de 256 MB) e 276,5 MiB no banco (de 512 MB). No isolamento de `/pedidos` ([experimento 25](../experimentos.md#25--isolar-o-efeito-da-otimização-de-pedidos)), o p95 da rota caiu de 26.795,9 para 696,9 ms, mas o p95 geral seguiu em 26.848,2 ms, provando que havia múltiplos gargalos.

## 7. Limites e testes futuros

Os resultados valem para uma única máquina, banco estático de leitura e carga de 20 usuários virtuais. As mudanças interagem entre si, portanto os ganhos de cada etapa não devem ser somados isoladamente. A comparação sequencial do baseline original teve duas rodadas com timeout e uma inconsistência na vazão reportada; por isso a análise de vazão se apoia nas medições incrementais por etapa, e não em um percentual global antes/depois. Não medi carga de escrita nem o custo contínuo de atualização das visões materializadas. Uma carga com escritas frequentes, exigência de frescor imediato ou alta concorrência em múltiplas instâncias da API refutaria o uso de visões estáticas e o pool de duas conexões. As oito fichas para investigar esses cenários estão em [proximos-testes.md](../proximos-testes.md).

## 8. Referências

1. Turcotte, Alexi; Aldrich, Mark W.; Tip, Frank. *Reformulator: Automated Refactoring of the N+1 Problem in Database-Backed Applications*. ASE 2022. [DOI](https://doi.org/10.1145/3551349.3556911). Acesso em 17 nov. 2026.
2. node-postgres. *Pooling*. [Documentação oficial](https://node-postgres.com/features/pooling). Acesso em 17 nov. 2026.
3. PostgreSQL Global Development Group. *PostgreSQL 16: Indexes*. [Documentação](https://www.postgresql.org/docs/16/indexes.html). Acesso em 17 nov. 2026.
4. PostgreSQL Global Development Group. *PostgreSQL 16: `pg_trgm`*. [Documentação](https://www.postgresql.org/docs/16/pgtrgm.html). Acesso em 17 nov. 2026.
5. PostgreSQL Global Development Group. *PostgreSQL 16: `EXPLAIN`*. [Documentação](https://www.postgresql.org/docs/16/sql-explain.html). Acesso em 17 nov. 2026.
6. PostgreSQL Global Development Group. *PostgreSQL 16: Materialized Views*. [Documentação](https://www.postgresql.org/docs/16/rules-materializedviews.html). Acesso em 17 nov. 2026.
7. PostgreSQL Global Development Group. *PostgreSQL 16: `pg_stat_statements`*. [Documentação](https://www.postgresql.org/docs/16/pgstatstatements.html). Acesso em 17 nov. 2026.
8. PostgreSQL Global Development Group. *PostgreSQL 16: `REFRESH MATERIALIZED VIEW`*. [Documentação](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html). Acesso em 17 nov. 2026.
9. Markus Winand. *Paging Through Results* e *We need tool support for keyset pagination*. [Seek method](https://use-the-index-luke.com/sql/partial-results/fetch-next-page), [keyset pagination](https://use-the-index-luke.com/no-offset). Acesso em 17 nov. 2026.
10. Chen, Tse-Hsun; Shang, Weiyi; Jiang, Zhen Ming; Hassan, Ahmed E.; Nasser, Mohamed; Flora, Parminder. *Detecting Performance Anti-patterns for Applications Developed using Object-Relational Mapping*. ICSE 2014. [PDF do artigo](https://petertsehsun.github.io/papers/peter_icse2014.pdf). Acesso em 17 nov. 2026.

## 9. Uso de IA

A IA foi utilizada como ferramenta de apoio na análise, no diagnóstico e na otimização do projeto. Primeiro, executei três rodadas de testes para observar o comportamento da aplicação e registrar os resultados. Depois, fiz uma quarta execução exploratória e usei a IA para analisar os dados disponíveis e apontar possíveis gargalos.

Com base nessas hipóteses, investiguei o código e as consultas SQL para entender como os dados eram buscados e processados. Identifiquei oportunidades de reduzir consultas repetidas e trabalho desnecessário. A partir delas, alterei o código e continuei executando testes para avaliar os efeitos de cada mudança.

Durante o processo, usei o Codex para me ajudar a interpretar os resultados e localizar pontos de maior consumo de CPU e memória. Comparei as medições antes e depois para identificar quais alterações trouxeram melhora, quais tiveram efeitos mistos e quais não justificaram ser mantidas.

A IA ajudou a organizar hipóteses e direcionar a investigação, mas tomei as decisões sobre as alterações com base na minha análise do código, das consultas SQL e dos dados medidos. Conferi os números nos arquivos de resultados. A comparação das visões está registrada em diagnostico/33-equivalencia-visoes-pedidos.txt, e o contrato foi verificado após as mudanças. Também abri e conferi as fontes técnicas citadas.
