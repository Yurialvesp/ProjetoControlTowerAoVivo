-- 05-fornecedores.sql — Entregas de fornecedores e consultorias com normalização da CodeForge

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas contratadas de consultorias e fornecedores, com nome normalizado da CodeForge e cálculo de atraso na data de corte (2026-10-16).'
AS
WITH base AS (
  SELECT
    entrega_id,
    projeto_id,
    CASE
      WHEN replace(lower(trim(fornecedor)), ' ', '') LIKE '%codeforge%' THEN 'CodeForge Consultoria Ltda'
      ELSE trim(fornecedor)
    END                                                          AS fornecedor,
    fornecedor                                                   AS fornecedor_como_veio,
    item,
    CAST(valor AS DECIMAL(14, 2))                                AS valor,
    to_date(nullif(trim(data_pedido), ''), 'yyyy-MM-dd')         AS data_pedido,
    to_date(nullif(trim(data_prometida), ''), 'yyyy-MM-dd')      AS data_prometida,
    to_date(nullif(trim(data_entrega), ''), 'yyyy-MM-dd')        AS data_entrega,
    CAST(prazo_contratado_dias AS INT)                           AS prazo_contratado_dias,
    status
  FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  entrega_id,
  projeto_id,
  fornecedor,
  fornecedor_como_veio,
  item,
  valor,
  data_pedido,
  data_prometida,
  data_entrega,
  prazo_contratado_dias,
  datediff(data_prometida, data_pedido)                          AS prazo_prometido_dias,
  datediff(data_entrega, data_pedido)                            AS prazo_real_dias,
  datediff(data_entrega, data_prometida)                         AS dias_de_atraso_na_entrega,
  (data_entrega IS NULL)                                         AS em_aberto,
  (data_entrega IS NULL AND data_prometida < DATE'2026-10-16')   AS em_atraso,
  status
FROM base;
