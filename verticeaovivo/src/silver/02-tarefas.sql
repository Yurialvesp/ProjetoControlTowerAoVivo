-- 02-tarefas.sql — As três ferramentas (Excel, ClickUp e MS Project) viram uma tabela só

-- 1. Tarefas do Excel (20 projetos, sem a linha de TOTAL)
CREATE TEMPORARY VIEW tarefas_excel AS
SELECT
  coalesce(p.projeto_id, regexp_extract(e.arquivo, '(PRJ-[0-9]+)', 1)) AS projeto_id,
  'excel'                                                              AS ferramenta,
  CAST(e.id AS STRING)                                                 AS id_na_ferramenta,
  e.fase                                                               AS fase,
  e.tarefa                                                             AS tarefa,
  e.responsavel                                                        AS responsavel,
  CASE
    WHEN e.inicio_previsto LIKE '%/%' THEN to_date(trim(e.inicio_previsto), 'dd/MM/yyyy')
    WHEN trim(e.inicio_previsto) <> '' THEN date_add(DATE'1899-12-30', CAST(trim(e.inicio_previsto) AS INT))
  END                                                                  AS inicio_baseline,
  CASE
    WHEN e.termino_previsto LIKE '%/%' THEN to_date(trim(e.termino_previsto), 'dd/MM/yyyy')
    WHEN trim(e.termino_previsto) <> '' THEN date_add(DATE'1899-12-30', CAST(trim(e.termino_previsto) AS INT))
  END                                                                  AS fim_baseline,
  CASE
    WHEN e.inicio_real LIKE '%/%' THEN to_date(trim(e.inicio_real), 'dd/MM/yyyy')
    WHEN trim(e.inicio_real) <> '' THEN date_add(DATE'1899-12-30', CAST(trim(e.inicio_real) AS INT))
  END                                                                  AS inicio_real,
  CASE
    WHEN e.termino_real LIKE '%/%' THEN to_date(trim(e.termino_real), 'dd/MM/yyyy')
    WHEN trim(e.termino_real) <> '' THEN date_add(DATE'1899-12-30', CAST(trim(e.termino_real) AS INT))
  END                                                                  AS fim_real,
  CASE
    WHEN e.pct_concluido LIKE '%\%%'
      THEN CAST(replace(replace(trim(e.pct_concluido), '%', ''), ',', '.') AS DOUBLE)
    ELSE ROUND(CAST(replace(trim(e.pct_concluido), ',', '.') AS DOUBLE) * 100.0, 2)
  END                                                                  AS pct_como_veio,
  CAST(replace(trim(e.horas_previstas), 'h', '') AS DOUBLE)            AS horas,
  CASE
    WHEN (
      CASE
        WHEN e.pct_concluido LIKE '%\%%'
          THEN CAST(replace(replace(trim(e.pct_concluido), '%', ''), ',', '.') AS DOUBLE)
        ELSE ROUND(CAST(replace(trim(e.pct_concluido), ',', '.') AS DOUBLE) * 100.0, 2)
      END
    ) >= 100 THEN 'concluida'
    WHEN (
      CASE
        WHEN e.pct_concluido LIKE '%\%%'
          THEN CAST(replace(replace(trim(e.pct_concluido), '%', ''), ',', '.') AS DOUBLE)
        ELSE ROUND(CAST(replace(trim(e.pct_concluido), ',', '.') AS DOUBLE) * 100.0, 2)
      END
    ) <= 0 THEN 'a_fazer'
    ELSE 'em_andamento'
  END                                                                  AS status_na_ferramenta
FROM lakehouse_vertice.bronze.excel_tarefas e
LEFT JOIN projetos p
  ON p.ferramenta = 'excel'
 AND p.codigo_ferramenta = e.arquivo
WHERE upper(trim(e.tarefa)) <> 'TOTAL';

-- 2. Tarefas do ClickUp (25 projetos)
CREATE TEMPORARY VIEW tarefas_clickup AS
SELECT
  coalesce(p_cod.projeto_id, p_nome.projeto_id)                             AS projeto_id,
  'clickup'                                                                 AS ferramenta,
  c.id                                                                      AS id_na_ferramenta,
  filter(c.custom_fields, f -> f.name = 'Fase')[0].value                    AS fase,
  c.name                                                                    AS tarefa,
  c.assignees[0].username                                                   AS responsavel,
  to_date(timestamp_millis(CAST(
    filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value AS BIGINT
  )))                                                                       AS inicio_baseline,
  to_date(timestamp_millis(CAST(
    filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value AS BIGINT
  )))                                                                       AS fim_baseline,
  to_date(timestamp_millis(CAST(nullif(trim(c.start_date), '') AS BIGINT))) AS inicio_real,
  to_date(timestamp_millis(CAST(nullif(trim(c.date_done), '')  AS BIGINT))) AS fim_real,
  CAST(
    filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value AS DOUBLE
  )                                                                         AS pct_como_veio,
  CAST(c.time_estimate AS DOUBLE) / 3600000.0                               AS horas,
  CASE
    WHEN lower(trim(c.status.status)) IN ('done', 'closed', 'concluído', 'concluido') THEN 'concluida'
    WHEN lower(trim(c.status.status)) IN ('to do', 'a fazer', 'backlog')              THEN 'a_fazer'
    ELSE 'em_andamento'
  END                                                                       AS status_na_ferramenta
FROM lakehouse_vertice.bronze.clickup_tarefas c
LEFT JOIN projetos p_cod
  ON p_cod.ferramenta = 'clickup'
 AND p_cod.codigo_ferramenta = c.list_id
LEFT JOIN projetos p_nome
  ON p_nome.ferramenta = 'clickup'
 AND p_nome.codigo_ferramenta IS NULL
 AND p_nome.nome_projeto = c.list_name;

-- 3. Tarefas do MS Project (15 projetos, somente tarefas folha Summary = 0)
CREATE TEMPORARY VIEW tarefas_msproject AS
WITH msp_com_fase AS (
  SELECT
    arquivo,
    UID,
    Summary,
    Name,
    Baseline,
    ActualStart,
    ActualFinish,
    PercentComplete,
    Work,
    last_value(CASE WHEN OutlineLevel = 1 THEN Name END, true)
      OVER (PARTITION BY arquivo ORDER BY UID ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS fase
  FROM lakehouse_vertice.bronze.msproject_tarefas
)
SELECT
  p.projeto_id                                               AS projeto_id,
  'msproject'                                                AS ferramenta,
  CAST(m.UID AS STRING)                                      AS id_na_ferramenta,
  m.fase                                                     AS fase,
  m.Name                                                     AS tarefa,
  CAST(NULL AS STRING)                                       AS responsavel,
  to_date(m.Baseline.Start)                                  AS inicio_baseline,
  to_date(m.Baseline.Finish)                                 AS fim_baseline,
  to_date(m.ActualStart)                                     AS inicio_real,
  to_date(m.ActualFinish)                                    AS fim_real,
  CAST(m.PercentComplete AS DOUBLE)                          AS pct_como_veio,
  CAST(regexp_extract(m.Work, 'PT([0-9]+)H', 1) AS DOUBLE)   AS horas,
  CASE
    WHEN m.PercentComplete >= 100 THEN 'concluida'
    WHEN m.PercentComplete <= 0   THEN 'a_fazer'
    ELSE 'em_andamento'
  END                                                        AS status_na_ferramenta
FROM msp_com_fase m
LEFT JOIN projetos p
  ON p.ferramenta = 'msproject'
 AND p.codigo_ferramenta = m.arquivo
WHERE m.Summary = 0;

-- 4. Materialized View unificada
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
  CONSTRAINT achou_o_projeto EXPECT (projeto_id IS NOT NULL)          ON VIOLATION FAIL UPDATE,
  CONSTRAINT pct_valido      EXPECT (pct_concluido BETWEEN 0 AND 100) ON VIOLATION FAIL UPDATE,
  CONSTRAINT horas_positivas EXPECT (horas > 0)                       ON VIOLATION FAIL UPDATE
)
COMMENT 'Cronogramas integrados das 3 ferramentas (Excel, ClickUp e MS Project) em modelo único (4.917 tarefas nos 60 projetos).'
AS
WITH uniao AS (
  SELECT * FROM tarefas_excel
  UNION ALL
  SELECT * FROM tarefas_clickup
  UNION ALL
  SELECT * FROM tarefas_msproject
)
SELECT
  concat(projeto_id, '-', ferramenta, '-', id_na_ferramenta) AS tarefa_id,
  projeto_id,
  ferramenta,
  id_na_ferramenta,
  fase,
  tarefa,
  responsavel,
  inicio_baseline,
  fim_baseline,
  inicio_real,
  fim_real,
  pct_como_veio,
  least(pct_como_veio, 100.0)                                AS pct_concluido,
  (pct_como_veio > 100.0)                                    AS pct_veio_acima_de_100,
  horas,
  status_na_ferramenta
FROM uniao;
