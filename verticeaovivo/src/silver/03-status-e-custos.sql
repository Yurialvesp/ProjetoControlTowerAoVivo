-- 03-status-e-custos.sql — Histórico de status semanal e lançamentos de custos reais

CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
  CONSTRAINT farol_valido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Histórico de status semanal reportado pelos gerentes toda sexta-feira, com flag de status vazio.'
AS
SELECT
  projeto_id,
  to_date(trim(data_status), 'yyyy-MM-dd') AS data_status,
  gerente,
  lower(trim(farol))                       AS farol,
  CAST(trim(pct_concluido) AS INT)         AS pct_concluido,
  texto_status,
  (
    texto_status IS NULL
    OR lower(trim(texto_status)) IN ('', 'n/a', 'ver ata da reunião', 'ver ata da reuniao')
  )                                        AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal;

CREATE OR REFRESH MATERIALIZED VIEW custos (
  CONSTRAINT valor_nao_nulo EXPECT (valor IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Lançamentos de custos reais por projeto, com recuperação de vírgula decimal, flag de estorno e sexta-feira da semana.'
AS
SELECT
  lancamento_id,
  projeto_id,
  to_date(trim(data), 'yyyy-MM-dd')                                                  AS data,
  date_add(CAST(date_trunc('WEEK', to_date(trim(data), 'yyyy-MM-dd')) AS DATE), 4)   AS semana,
  categoria,
  descricao,
  CAST(replace(trim(valor), ',', '.') AS DECIMAL(14, 2))                             AS valor,
  (valor LIKE '%,%')                                                                 AS valor_veio_com_virgula,
  (CAST(replace(trim(valor), ',', '.') AS DECIMAL(14, 2)) < 0)                       AS estorno,
  centro_custo
FROM lakehouse_vertice.bronze.custos;
