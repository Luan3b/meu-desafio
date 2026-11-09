CREATE MATERIALIZED VIEW resumo_pedidos_por_status AS
SELECT status, count(*) AS total
  FROM pedidos
 GROUP BY status;
