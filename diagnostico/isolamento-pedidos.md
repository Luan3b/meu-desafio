# Experimento isolado da rota `/pedidos`

## Objetivo

Medir a aplicação original e depois a mesma aplicação com apenas a otimização de `GET /pedidos?status=&pagina=`. Todas as outras rotas, a camada de conexão e os limites dos containers ficam na versão original.

## Estado original

- Código: commit original com o contrato gravado (`a93c4f9`).
- Ambiente: mesmos limites de CPU e memória; porta local do Postgres ajustada para `5433` para evitar conflito com o serviço local.
- Carga: `VUS=20`, `DURACAO=60s`, `SEMENTE=42`.
- Contrato original: mantido nas 42 respostas antes da referência.

## Referência antes da mudança

Medições pendentes.

## Variante com apenas `/pedidos` otimizada

Medições pendentes.
