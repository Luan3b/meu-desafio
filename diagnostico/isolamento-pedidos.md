# Experimento isolado da rota `/pedidos`

## Objetivo

Medir a aplicação original e depois a mesma aplicação com apenas a otimização de `GET /pedidos?status=&pagina=`. Todas as outras rotas, a camada de conexão e os limites dos containers ficam na versão original.

## Estado original

- Código: commit original com o contrato gravado (`a93c4f9`).
- Ambiente: mesmos limites de CPU e memória; porta local do Postgres ajustada para `5433` para evitar conflito com o serviço local.
- Carga: `VUS=20`, `DURACAO=60s`, `SEMENTE=42`.
- Contrato original: mantido nas 42 respostas antes da referência.

## Referência antes da mudança

Três medições, todas sem erros e com contrato mantido:

- [10:51:38](../resultados/20261110-105138-25-pedidos-isolado-antes/)
- [10:53:33](../resultados/20261110-105333-25-pedidos-isolado-antes/)
- [10:55:21](../resultados/20261110-105521-25-pedidos-isolado-antes/)

Medianas: 2,25 req/s, p95 geral 28.415,7 ms, p95 de `pedidos-por-status` 26.795,9 ms e CPU média do banco 99,3%.

## Variante com apenas `/pedidos` otimizada

Implementação no commit `3e332d9`: alterado somente o handler `/pedidos` e adicionado `banco/03-pedidos-precomputados.sql` com as visões de total e posição usadas por essa rota. As outras rotas e `api/src/db.js` permanecem originais. O contrato passou nas 42 respostas.

Três medições, todas sem erros e com contrato mantido:

- [10:59:35](../resultados/20261110-105935-25-pedidos-isolado-depois/)
- [11:01:28](../resultados/20261110-110128-25-pedidos-isolado-depois/)
- [11:03:21](../resultados/20261110-110321-25-pedidos-isolado-depois/)

Medianas: 2,88 req/s (+28,0%), p95 geral 26.848,2 ms (-5,5%), p95 de `pedidos-por-status` 696,9 ms (-97,4%) e CPU média do banco 100,3% (ante 99,3%).

## Conclusão

`/pedidos` era um gargalo grave: a otimização isolada reduziu seu p95 de 26.795,9 ms para 696,9 ms. Ela aumentou a vazão total em 28%, mas o p95 geral ainda ficou em 26,8 s e a CPU do banco permaneceu saturada, pois as demais rotas continuaram na versão original. Portanto, `/pedidos` era um dos gargalos importantes, mas não explica sozinho a lentidão geral do sistema.
