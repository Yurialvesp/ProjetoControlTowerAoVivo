-- 04-pessoas.sql — Colaboradores deduplicados e apontamentos de timesheet

CREATE OR REFRESH MATERIALIZED VIEW colaboradores
COMMENT 'Cadastro único dos 520 colaboradores da Vértice Tecnologia (deduplicado mantendo o papel em minúsculas).'
AS
WITH numerados AS (
  SELECT
    colaborador_id,
    nome,
    papel,
    senioridade,
    CAST(custo_hora AS DECIMAL(10, 2))                         AS custo_hora,
    to_date(nullif(trim(data_admissao), ''), 'yyyy-MM-dd')     AS data_admissao,
    to_date(nullif(trim(data_desligamento), ''), 'yyyy-MM-dd') AS data_desligamento,
    row_number() OVER (
      PARTITION BY colaborador_id
      ORDER BY CASE WHEN papel = lower(papel) THEN 0 ELSE 1 END
    )                                                          AS rn
  FROM lakehouse_vertice.bronze.colaboradores
)
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  custo_hora,
  data_admissao,
  data_desligamento
FROM numerados
WHERE rn = 1;

CREATE OR REFRESH MATERIALIZED VIEW apontamentos
COMMENT 'Apontamentos semanais de timesheet por colaborador e projeto, referenciados pela sexta-feira da semana.'
AS
SELECT
  colaborador_id,
  projeto_id,
  to_date(trim(semana_inicio), 'yyyy-MM-dd')              AS semana_inicio,
  date_add(to_date(trim(semana_inicio), 'yyyy-MM-dd'), 4) AS semana,
  CAST(horas_disponiveis AS DOUBLE)                       AS horas_disponiveis,
  CAST(horas_apontadas AS DOUBLE)                         AS horas_apontadas
FROM lakehouse_vertice.bronze.apontamentos;
