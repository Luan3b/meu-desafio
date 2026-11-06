CREATE INDEX idx_pedidos_cliente
    ON pedidos (cliente_id, criado_em DESC, id DESC);

CREATE INDEX idx_itens_pedido
    ON itens_pedido (pedido_id, id);
