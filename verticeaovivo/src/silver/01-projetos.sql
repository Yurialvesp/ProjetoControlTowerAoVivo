-- 01-projetos.sql — Cadastro do PMO (de-para da integração com as 3 ferramentas)
CREATE OR REFRESH MATERIALIZED VIEW projetos (
  CONSTRAINT data_inicio_valida EXPECT (data_inicio IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT ferramenta_valida  EXPECT (ferramenta IN ('excel', 'clickup', 'msproject')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro dos 60 projetos do PMO (de-para de integração com Excel, ClickUp e MS Project), com datas e valores tipados.'
AS
SELECT
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  CASE
    WHEN lower(trim(ferramenta)) LIKE '%excel%' OR lower(trim(ferramenta)) LIKE '%planilha%' THEN 'excel'
    WHEN lower(trim(ferramenta)) LIKE '%clickup%'                                            THEN 'clickup'
    WHEN lower(trim(ferramenta)) LIKE '%project%'                                            THEN 'msproject'
  END                                                                                        AS ferramenta,
  ferramenta                                                                                 AS ferramenta_como_veio,
  nullif(trim(codigo_ferramenta), '')                                                        AS codigo_ferramenta,
  CAST(valor_contrato AS DECIMAL(14, 2))                                                     AS valor_contrato,
  CAST(orcamento_custo AS DECIMAL(14, 2))                                                    AS orcamento_custo,
  coalesce(
    try_to_date(trim(data_inicio), 'yyyy-MM-dd'),
    try_to_date(trim(data_inicio), 'dd/MM/yyyy')
  )                                                                                          AS data_inicio,
  coalesce(
    try_to_date(trim(data_fim_baseline), 'yyyy-MM-dd'),
    try_to_date(trim(data_fim_baseline), 'dd/MM/yyyy')
  )                                                                                          AS data_fim_baseline,
  lower(trim(status))                                                                        AS status,
  gerente_projeto
FROM lakehouse_vertice.bronze.projetos;
