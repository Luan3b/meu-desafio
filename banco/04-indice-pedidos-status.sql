CREATE INDEX idx_pedidos_status
    ON pedidos (status, criado_em DESC, id DESC);
