-- 02-situacao-e-pessoas.sql — Fotografia atual dos projetos (2026-10-16) e utilização semanal das pessoas

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.projeto_situacao_atual
COMMENT 'Fotografia de hoje (2026-10-16) dos 60 projetos da Vértice Tecnologia: cadastro do PMO e KPIs (PV, EV, AC, SPI, CPI, EAC, estouro previsto, margem projetada, atraso projetado, situação, farol do gerente, farol calculado e melancia).'
AS
WITH kpis_tarefas AS (
  SELECT
    p.projeto_id,
    concat(p.projeto_id, ' · ', p.nome_projeto)             AS projeto,
    p.nome_projeto,
    p.cliente,
    p.segmento,
    p.tipo_projeto,
    p.ferramenta,
    p.gerente_projeto,
    p.valor_contrato,
    p.orcamento_custo                                       AS orcamento,
    p.data_inicio,
    p.data_fim_baseline,
    datediff(p.data_fim_baseline, p.data_inicio)            AS duracao_baseline_dias,
    p.status,
    ROUND(SUM(t.horas * t.pct_concluido) / SUM(t.horas), 2) AS pct_concluido,
    ROUND(
      p.orcamento_custo * SUM(
        t.horas * greatest(
          0.0,
          least(
            1.0,
            datediff(DATE'2026-10-16', t.inicio_baseline)
              / CAST(datediff(t.fim_baseline, t.inicio_baseline) AS DOUBLE)
          )
        )
      ) / SUM(t.horas),
      2
    )                                                       AS pv,
    ROUND(
      p.orcamento_custo * SUM(t.horas * (t.pct_concluido / 100.0)) / SUM(t.horas),
      2
    )                                                       AS ev
  FROM projetos p
  JOIN tarefas t
    ON t.projeto_id = p.projeto_id
  GROUP BY
    p.projeto_id, p.nome_projeto, p.cliente, p.segmento, p.tipo_projeto,
    p.ferramenta, p.gerente_projeto, p.valor_contrato, p.orcamento_custo,
    p.data_inicio, p.data_fim_baseline, p.status
),
custo_hoje AS (
  SELECT
    projeto_id,
    ROUND(SUM(valor), 2) AS ac
  FROM custos
  WHERE data <= DATE'2026-10-16'
  GROUP BY projeto_id
),
ultimo_status AS (
  SELECT
    projeto_id,
    farol AS farol_do_gerente
  FROM (
    SELECT
      projeto_id,
      farol,
      row_number() OVER (PARTITION BY projeto_id ORDER BY data_status DESC) AS rn
    FROM status_semanal
    WHERE data_status <= DATE'2026-10-16'
  )
  WHERE rn = 1
),
base AS (
  SELECT
    kt.*,
    coalesce(ch.ac, CAST(0 AS DECIMAL(14, 2)))                       AS ac,
    ROUND(try_divide(kt.ev, kt.pv), 4)                               AS spi,
    ROUND(try_divide(kt.ev, ch.ac), 4)                               AS cpi,
    ROUND(try_divide(kt.orcamento, try_divide(kt.ev, ch.ac)), 2)     AS eac,
    us.farol_do_gerente
  FROM kpis_tarefas kt
  LEFT JOIN custo_hoje ch
    ON ch.projeto_id = kt.projeto_id
  LEFT JOIN ultimo_status us
    ON us.projeto_id = kt.projeto_id
)
SELECT
  projeto_id,
  projeto,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  ferramenta,
  gerente_projeto,
  valor_contrato,
  orcamento,
  data_inicio,
  data_fim_baseline,
  duracao_baseline_dias,
  status,
  pct_concluido,
  pv,
  ev,
  ac,
  spi,
  cpi,
  eac,
  ROUND(greatest(eac - orcamento, 0.0), 2)                           AS estouro_previsto,
  ROUND(try_divide(valor_contrato - eac, valor_contrato), 4)         AS margem_projetada,
  CAST(
    ROUND(
      greatest(try_divide(duracao_baseline_dias, spi) - duracao_baseline_dias, 0.0)
    ) AS INT
  )                                                                  AS atraso_projetado_dias,
  date_add(
    data_fim_baseline,
    CAST(
      ROUND(
        greatest(try_divide(duracao_baseline_dias, spi) - duracao_baseline_dias, 0.0)
      ) AS INT
    )
  )                                                                  AS termino_projetado,
  CASE
    WHEN status <> 'em_andamento' THEN 'concluído'
    WHEN spi < 0.8 OR cpi < 0.8   THEN 'crítico'
    WHEN spi < 0.9 OR cpi < 0.9   THEN 'atenção'
    ELSE 'ok'
  END                                                                AS situacao,
  farol_do_gerente,
  CASE
    WHEN spi >= 0.95 THEN 'verde'
    WHEN spi >= 0.90 THEN 'amarelo'
    ELSE 'vermelho'
  END                                                                AS farol_calculado,
  (status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9) AS melancia
FROM base;

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.utilizacao_pessoa_semana
COMMENT 'Utilização semanal de cada colaborador por projeto (horas disponíveis, apontadas, ociosas, taxa de utilização, custo ocioso e SPI do projeto na semana).'
AS
SELECT
  a.colaborador_id,
  c.nome,
  c.papel,
  c.senioridade,
  c.custo_hora,
  a.projeto_id,
  a.semana,
  a.horas_disponiveis,
  a.horas_apontadas,
  ROUND(a.horas_disponiveis - a.horas_apontadas, 2)                       AS horas_ociosas,
  ROUND(try_divide(a.horas_apontadas, a.horas_disponiveis), 4)            AS utilizacao,
  ROUND((a.horas_disponiveis - a.horas_apontadas) * c.custo_hora, 2)      AS custo_ocioso,
  f.spi                                                                   AS spi_do_projeto
FROM apontamentos a
JOIN colaboradores c
  ON c.colaborador_id = a.colaborador_id
LEFT JOIN lakehouse_vertice.gold.fato_projeto_semana f
  ON f.projeto_id = a.projeto_id
 AND f.semana = a.semana;
