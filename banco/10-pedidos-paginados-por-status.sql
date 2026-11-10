CREATE MATERIALIZED VIEW pedidos_paginados_por_status AS
SELECT status,
       row_number() OVER (PARTITION BY status ORDER BY criado_em DESC, id DESC) AS posicao,
       id,
       cliente_id,
       criado_em
  FROM pedidos;

CREATE UNIQUE INDEX idx_pedidos_paginados_status_posicao
    ON pedidos_paginados_por_status (status, posicao);

DROP INDEX idx_pedidos_status;
