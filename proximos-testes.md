# Próximos testes

Ideias pesquisadas, mas ainda não aplicadas nem medidas como mudança de desempenho neste projeto. Cada ficha descreve uma hipótese, não um resultado. O teste de retirar o corpo da resposta do log já foi feito no [experimento 28](experimentos.md#28--remover-o-corpo-da-resposta-do-log); ele reduziu o volume de log em 93,02%, sem evidência conclusiva de ganho de vazão.

## 1. Atualizar as visões com `REFRESH ... CONCURRENTLY`

- **Hipótese:** visões atualizadas podem manter os relatórios frescos sem bloquear consultas durante a atualização concorrente.
- **Como testar:** adicionar índices únicos apropriados às visões, produzir alterações controladas de pedidos e itens, executar refresh concorrente e medir tempo de atualização, atraso dos dados, p95 e CPU durante a carga.
- **Requisito e limite:** a API atual é somente leitura. `CONCURRENTLY` exige índice único adequado e ainda calcula a visão inteira; o experimento precisa definir uma frequência de atualização e uma tolerância explícita de defasagem.
- **Fonte:** [PostgreSQL 16 — REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html).

## 2. Medir o custo de criação, armazenamento e atualização das visões

- **Hipótese:** a economia nas leituras compensa o tempo de inicialização, espaço ocupado e custo de refresh das visões materializadas.
- **Como testar:** cronometrar a criação do banco com e sem as visões, medir o espaço de cada uma e executar `REFRESH MATERIALIZED VIEW` com dados equivalentes. Salvar comandos e saídas em `diagnostico/`.
- **Requisito e limite:** recriar o banco sintético em cópias controladas; o resultado de uma atualização isolada não representa por si só a carga de escrita de produção.
- **Fonte:** [PostgreSQL 16 — Materialized Views](https://www.postgresql.org/docs/16/rules-materializedviews.html) e [REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html).

## 3. Paginação por chave (*keyset pagination*) em uma rota nova

- **Hipótese:** um cursor baseado na última chave da página pode manter o custo estável em páginas profundas e evitar a visão de posições usada em `/pedidos`.
- **Como testar:** criar uma rota experimental separada, como `/v2/pedidos`, com cursor por `(criado_em, id)` e comparar páginas iniciais e profundas com a implementação atual, incluindo ordem, duplicação e omissão de linhas ao inserir pedidos entre páginas.
- **Requisito e limite:** paginação por cursor muda a interface e não substitui a rota atual sem autorização para mudar o contrato; não comparar o resultado de uma rota nova como se fosse uma otimização contratualmente equivalente.
- **Fontes:** Markus Winand, [Paging Through Results](https://use-the-index-luke.com/sql/partial-results/fetch-next-page) e [keyset pagination](https://use-the-index-luke.com/no-offset).

## 4. Sensibilidade do tamanho do pool a mais concorrência

- **Hipótese:** o pool de duas conexões escolhido para 20 usuários pode deixar de ser adequado com outra concorrência ou mistura de rotas.
- **Como testar:** em uma matriz exploratória separada, medir `VUS=5, 20, 50, 100` com pool de 1, 2, 3 e 5; registrar vazão, p95, erros, conexões ativas, CPU e memória. Qualquer tamanho escolhido deve passar depois pelo ciclo normal de três medições comparáveis.
- **Requisito e limite:** executar combinações na mesma máquina, sem cargas paralelas; a recomendação de dimensionamento é ponto de partida, não substitui medir a aplicação real.
- **Fonte:** [HikariCP — About Pool Sizing](https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing).

## 5. Localizar a consulta dominante na versão final

- **Hipótese:** depois das mudanças, outra consulta pode dominar o tempo total e apontar o próximo alvo com maior potencial.
- **Como testar:** coletar `pg_stat_statements` numa janela que contenha apenas a carga planejada; ordenar por tempo total, chamadas e tempo médio; salvar saída e planos relevantes. Remover a instrumentação temporária e confirmar limites e contrato antes de uma medição oficial.
- **Requisito e limite:** a instrumentação altera o ambiente e pode adicionar custo. A saída serve para formar uma hipótese; qualquer mudança continua exigindo teste isolado e três medições.
- **Fonte:** [PostgreSQL 16 — pg_stat_statements](https://www.postgresql.org/docs/16/pgstatstatements.html).

## 6. Cache-aside para leituras repetidas

- **Hipótese:** armazenar por pouco tempo respostas de leitura repetidas, especialmente de `/clientes/:id`, pode reduzir consultas ao PostgreSQL.
- **Como testar:** começar por cache local e comparar com cache externo; definir TTL, chaves, política de invalidação e comportamento em cache miss; medir vazão, p95, CPU, memória, taxa de acerto e custo do serviço adicional.
- **Requisito e limite:** os dados de exemplo são estáticos, mas uma aplicação com escrita precisa invalidar ou atualizar as chaves. Um cache externo acrescenta serviço e consumo de recursos que devem aparecer na comparação.
- **Fonte:** [Redis — Cache-aside pattern](https://redis.io/docs/latest/develop/use-cases/cache-aside/) e [guia Node.js](https://redis.io/docs/latest/develop/use-cases/cache-aside/nodejs/).

## 7. PgBouncer com mais de um processo da API

- **Hipótese:** um pooler externo pode compartilhar conexões reais ao PostgreSQL quando há vários processos ou réplicas da API.
- **Como testar:** executar ao menos duas réplicas, adicionar PgBouncer, definir o modo de pool e comparar conexões clientes/servidor, vazão, p95, CPU e memória com o pool interno do `pg` sem PgBouncer.
- **Requisito e limite:** com uma única API e pool pequeno, um serviço extra pode não trazer benefício. Confirmar também compatibilidade de transações e prepared statements para o modo escolhido.
- **Fonte:** [PgBouncer — Configuration](https://www.pgbouncer.org/config.html).

## 8. Rotacionar os logs do Docker

- **Hipótese:** limitar tamanho e quantidade de arquivos de log evita crescimento de disco em execução prolongada.
- **Como testar:** registrar tamanho do log após carga representativa, aplicar `max-size` e `max-file` ao serviço da API, repetir a carga e verificar espaço, retenção de logs, erros e impacto na aplicação.
- **Requisito e limite:** o driver e as opções variam por configuração do Docker. Rotação limita retenção e deve ser dimensionada para preservar o período de diagnóstico necessário.
- **Fontes:** Docker, [JSON File logging driver](https://docs.docker.com/engine/logging/drivers/json-file/) e [Configure logging drivers](https://docs.docker.com/engine/logging/configure/).
