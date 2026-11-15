# Próximos testes

Este arquivo registra ideias pesquisadas que não foram aplicadas na versão entregue. Elas não têm resultados de desempenho neste projeto. O objetivo é mostrar como poderiam ser avaliadas e que recursos adicionais seriam necessários.

## 1. Identificar consultas dominantes na versão otimizada

- **Origem:** a documentação do PostgreSQL descreve `pg_stat_statements` como extensão para acompanhar estatísticas de planejamento e execução das consultas; o projeto já usou essa extensão como diagnóstico na versão inicial ([experimento 07](experimentos.md#07--diagnóstico-de-consultas-com-pg_stat_statements)).
- **Hipótese:** repetir o levantamento na versão final pode revelar uma consulta que passou a dominar depois das otimizações feitas.
- **Como testar:** habilitar a extensão apenas no ambiente de diagnóstico, zerar suas estatísticas, executar a carga padrão sem misturar aquecimento e verificação de contrato na janela analisada, salvar a saída e comparar tempo total, chamadas e tempo médio por consulta. Depois, remover a instrumentação e confirmar que os limites padrão foram restaurados.
- **Custo e requisito:** exige reiniciar/reconfigurar temporariamente o PostgreSQL e consome recursos de instrumentação. O resultado serve para escolher uma hipótese, não como medição final de desempenho. Uma mudança só seria aceita após o ciclo normal de contrato e três medições.
- **Fonte:** [PostgreSQL 16 — `pg_stat_statements`](https://www.postgresql.org/docs/16/pgstatstatements.html).

## 2. Medir custo de atualização das visões materializadas

- **Origem:** a documentação explica que uma visão materializada persiste os resultados e precisa ser atualizada com `REFRESH MATERIALIZED VIEW` ([PostgreSQL 16 — Materialized Views](https://www.postgresql.org/docs/16/rules-materializedviews.html)). O ganho de leitura observado neste desafio depende de dados estáticos e da inicialização do banco.
- **Hipótese:** em um sistema que recebe pedidos e itens continuamente, o tempo de atualização e a defasagem dos resumos podem superar a economia obtida nas leituras.
- **Como testar:** criar um cenário separado com uma taxa definida de inserções/alterações, medir latência e vazão de escrita, duração da atualização, atraso até o resumo refletir a mudança e latência de leitura durante a atualização. Comparar atualização completa com estratégias incrementais, mantendo o mesmo conjunto de dados e carga.
- **Custo e requisito:** o teste fornecido é somente de leitura; seria necessário um gerador de escrita separado, dados com alterações controladas e uma regra explícita de frescor. Não alterar `carga/` para encaixar esse cenário no benchmark existente.
- **Fontes:** [PostgreSQL 16 — Materialized Views](https://www.postgresql.org/docs/16/rules-materializedviews.html); [PostgreSQL 16 — `REFRESH MATERIALIZED VIEW`](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html).

## 3. Quantificar o custo dos índices sob escrita

- **Origem:** índices aceleram buscas que conseguem utilizá-los, mas ocupam armazenamento e precisam acompanhar alterações nas tabelas. O índice trigram e os índices B-tree foram avaliados aqui com carga de leitura.
- **Hipótese:** sob inserções e atualizações frequentes, o custo de manter índices — especialmente o GIN de `pg_trgm` — pode reduzir a vazão de escrita e mudar quais índices valem a pena.
- **Como testar:** medir uma carga de escrita representativa com o conjunto atual de índices; repetir em cópia equivalente sem um índice por vez; comparar vazão de escrita, latências de leitura, espaço em disco e tempo de recuperação. A remoção só seria considerada se as consultas correspondentes continuassem dentro de uma meta definida.
- **Custo e requisito:** requer carga de escrita e uma cópia descartável do banco. O benchmark atual não escreve e não permite concluir sobre esse custo.
- **Fontes:** [PostgreSQL 16 — Índices](https://www.postgresql.org/docs/16/indexes.html); [PostgreSQL 16 — `pg_trgm`](https://www.postgresql.org/docs/16/pgtrgm.html).

## 4. Explorar capacidade em níveis de concorrência diferentes

- **Origem:** as comparações principais usam `VUS=20`, conforme o teste fornecido. Os resultados descrevem esse cenário e não determinam o ponto de saturação para outras quantidades de usuários.
- **Hipótese:** o pool de duas conexões e as consultas consolidadas podem ter outro ponto de equilíbrio com concorrência ou mistura de rotas diferentes.
- **Como testar:** em uma experiência exploratória separada, variar a concorrência em degraus e registrar vazão, p95, erros, CPU, memória e conexões ativas. Não comparar diretamente esses resultados com os números oficiais a 20 usuários; para qualquer mudança escolhida, repetir antes/depois com os mesmos parâmetros.
- **Custo e requisito:** mais tempo de execução e uma definição de perfil de tráfego real. Os resultados atuais não provam comportamento sob concorrência diferente.

## Evidência usada para encerrar a rodada atual

Os diagnósticos [top produtos](diagnostico/30-top-produtos-atual.txt) e [cliente por ID](diagnostico/31-cliente-por-id-atual.txt) não indicaram uma nova mudança óbvia naquelas consultas. Isso não prova que não exista outro gargalo: uma próxima rodada deve começar com atribuição de tempo por consulta na versão otimizada, sem presumir de antemão qual rota precisa mudar.
