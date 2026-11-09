CREATE MATERIALIZED VIEW resumo_top_produtos AS
SELECT pr.id AS produto_id,
       pr.nome,
       pr.categoria,
       sum(i.quantidade) AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
  FROM itens_pedido i
  JOIN pedidos p ON p.id = i.pedido_id
  JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado'
 GROUP BY pr.id, pr.nome, pr.categoria;

CREATE INDEX idx_resumo_top_produtos_ordem
    ON resumo_top_produtos (receita_centavos DESC, produto_id);
