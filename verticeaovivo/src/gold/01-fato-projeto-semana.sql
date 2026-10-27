-- 01-fato-projeto-semana.sql — Evolução semanal (toda sexta-feira) de PV, EV, AC, SPI, CPI e horas por projeto

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.fato_projeto_semana (
  CONSTRAINT pv_nao_negativo  EXPECT (pv >= 0)         ON VIOLATION FAIL UPDATE,
  CONSTRAINT ev_ate_orcamento EXPECT (ev <= orcamento) ON VIOLATION FAIL UPDATE
)
COMMENT 'Evolução semanal por projeto (toda sexta-feira, do início até 2026-10-16): PV, EV, AC acumulados, SPI, CPI, EAC, farol do gerente e horas do timesheet.'
AS
WITH semanas_projeto AS (
  SELECT
    p.projeto_id,
    p.orcamento_custo AS orcamento,
    explode(
      sequence(
        date_add(CAST(date_trunc('WEEK', p.data_inicio) AS DATE), 4),
        DATE'2026-10-16',
        INTERVAL 1 WEEK
      )
    ) AS semana
  FROM projetos p
),
pv_semana AS (
  SELECT
    sp.projeto_id,
    sp.semana,
    sp.orcamento,
    ROUND(
      sp.orcamento * SUM(
        t.horas * greatest(
          0.0,
          least(
            1.0,
            datediff(sp.semana, t.inicio_baseline)
              / CAST(datediff(t.fim_baseline, t.inicio_baseline) AS DOUBLE)
          )
        )
      ) / SUM(t.horas),
      2
    ) AS pv
  FROM semanas_projeto sp
  JOIN tarefas t
    ON t.projeto_id = sp.projeto_id
  GROUP BY sp.projeto_id, sp.semana, sp.orcamento
),
custo_semanal AS (
  SELECT
    projeto_id,
    semana,
    SUM(valor) AS custo_semana
  FROM custos
  GROUP BY projeto_id, semana
),
apont_semanal AS (
  SELECT
    projeto_id,
    semana,
    ROUND(SUM(horas_disponiveis), 2)                   AS horas_disponiveis,
    ROUND(SUM(horas_apontadas), 2)                     AS horas_apontadas,
    ROUND(SUM(horas_disponiveis - horas_apontadas), 2) AS horas_ociosas
  FROM apontamentos
  GROUP BY projeto_id, semana
),
historico AS (
  SELECT
    pv.projeto_id,
    pv.semana,
    pv.orcamento,
    pv.pv,
    coalesce(
      last_value(s.pct_concluido, true) OVER (
        PARTITION BY pv.projeto_id
        ORDER BY pv.semana
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ),
      0
    ) AS pct_concluido,
    last_value(s.farol, true) OVER (
      PARTITION BY pv.projeto_id
      ORDER BY pv.semana
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS farol_do_gerente,
    ROUND(
      coalesce(
        SUM(cs.custo_semana) OVER (
          PARTITION BY pv.projeto_id
          ORDER BY pv.semana
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        0
      ),
      2
    ) AS ac,
    coalesce(ap.horas_disponiveis, 0.0) AS horas_disponiveis,
    coalesce(ap.horas_apontadas, 0.0)   AS horas_apontadas,
    coalesce(ap.horas_ociosas, 0.0)     AS horas_ociosas
  FROM pv_semana pv
  LEFT JOIN status_semanal s
    ON s.projeto_id = pv.projeto_id
   AND s.data_status = pv.semana
  LEFT JOIN custo_semanal cs
    ON cs.projeto_id = pv.projeto_id
   AND cs.semana = pv.semana
  LEFT JOIN apont_semanal ap
    ON ap.projeto_id = pv.projeto_id
   AND ap.semana = pv.semana
)
SELECT
  projeto_id,
  semana,
  orcamento,
  pct_concluido,
  pv,
  ROUND(orcamento * pct_concluido / 100.0, 2)                                      AS ev,
  ac,
  ROUND(try_divide(ROUND(orcamento * pct_concluido / 100.0, 2), pv), 4)            AS spi,
  ROUND(try_divide(ROUND(orcamento * pct_concluido / 100.0, 2), ac), 4)            AS cpi,
  ROUND(
    try_divide(orcamento, try_divide(ROUND(orcamento * pct_concluido / 100.0, 2), ac)),
    2
  )                                                                                AS eac,
  farol_do_gerente,
  horas_disponiveis,
  horas_apontadas,
  horas_ociosas
FROM historico;
