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

Medições pendentes.
