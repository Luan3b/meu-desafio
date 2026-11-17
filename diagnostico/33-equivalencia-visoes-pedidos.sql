-- Comparacao bidirecional das visoes materializadas com as consultas fonte.
-- Esperado: zero divergencias nas duas secoes.
\echo 'Diferencas: contagem por status (esperado 0)'
WITH esperado AS (
  SELECT status, count(*)::bigint AS total
    FROM pedidos
   GROUP BY status
), diferencas AS (
  (SELECT status, total FROM esperado
   EXCEPT
   SELECT status, total FROM resumo_pedidos_por_status)
  UNION ALL
  (SELECT status, total FROM resumo_pedidos_por_status
   EXCEPT
   SELECT status, total FROM esperado)
)
SELECT count(*) AS diferencas FROM diferencas;

\echo 'Diferencas: posicao por status (esperado 0)'
WITH esperado AS (
  SELECT status,
         row_number() OVER (PARTITION BY status ORDER BY criado_em DESC, id DESC) AS posicao,
         id,
         cliente_id,
         criado_em
    FROM pedidos
), diferencas AS (
  (SELECT status, posicao, id, cliente_id, criado_em FROM esperado
   EXCEPT
   SELECT status, posicao, id, cliente_id, criado_em FROM pedidos_paginados_por_status)
  UNION ALL
  (SELECT status, posicao, id, cliente_id, criado_em FROM pedidos_paginados_por_status
   EXCEPT
   SELECT status, posicao, id, cliente_id, criado_em FROM esperado)
)
SELECT count(*) AS diferencas FROM diferencas;
