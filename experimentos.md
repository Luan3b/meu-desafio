# Experimentos

## 01 — Pool de conexões

- **Hipótese:** reutilizar até 10 conexões com `pg.Pool` deve reduzir a latência e a CPU do banco, evitando abrir e fechar uma conexão PostgreSQL para cada consulta. A resposta da API deve permanecer igual.
- **Fonte da hipótese:** [node-postgres — Pooling](https://node-postgres.com/features/pooling). A documentação explica o custo de handshake por conexão e recomenda pool para aplicações que fazem consultas frequentes. O tamanho 10 é o padrão documentado em [Pool API](https://node-postgres.com/apis/pool); será definido explicitamente neste experimento.
- **Antes:** três execuções de `00-linha-de-base`, com `VUS=20`, `DURACAO=60s` e `SEMENTE=42`: [113816](resultados/20261106-113816-00-linha-de-base/), [114000](resultados/20261106-114000-00-linha-de-base/) e [114143](resultados/20261106-114143-00-linha-de-base/).
- **Depois:** três execuções de `01-pool`, com os mesmos parâmetros: [155042](resultados/20261106-155042-01-pool/), [155548](resultados/20261106-155548-01-pool/) e [155750](resultados/20261106-155750-01-pool/). Todas tiveram `0.00%` de erros e terminaram com “Contrato mantido”. Uma execução interrompida, sem verificação de contrato completa, foi descartada.
- **Status:** aplicada e medida.
- **Conclusão:** as medianas passaram de 2,39 para 2,86 requisições/s (+19,7%) e de 26.801 ms para 25.227,2 ms no p95 geral (-5,9%). A mediana de CPU média do banco caiu de 100,2% para 99,3%, ainda perto do limite. A memória média da API subiu de 35,2 MiB para 38,3 MiB. Na rota `/clientes/:id/pedidos`, o p95 mediano foi de 28.557,3 ms para 30.030,7 ms; o pool, sozinho, não resolveu esse gargalo. A variação de memória do banco entre execuções foi alta, então não concluímos economia de memória.
