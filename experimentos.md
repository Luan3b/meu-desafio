# Experimentos

## 01 — Pool de conexões

- **Hipótese:** reutilizar até 10 conexões com `pg.Pool` deve reduzir a latência e a CPU do banco, evitando abrir e fechar uma conexão PostgreSQL para cada consulta. A resposta da API deve permanecer igual.
- **Fonte da hipótese:** [node-postgres — Pooling](https://node-postgres.com/features/pooling). A documentação explica o custo de handshake por conexão e recomenda pool para aplicações que fazem consultas frequentes. O tamanho 10 é o padrão documentado em [Pool API](https://node-postgres.com/apis/pool); será definido explicitamente neste experimento.
- **Antes:** três execuções de `00-linha-de-base`, com `VUS=20`, `DURACAO=60s` e `SEMENTE=42`: [113816](resultados/20261106-113816-00-linha-de-base/), [114000](resultados/20261106-114000-00-linha-de-base/) e [114143](resultados/20261106-114143-00-linha-de-base/).
- **Depois:** pendente.
- **Status:** mudança em preparação; ainda sem medição posterior.
- **Conclusão:** pendente.
