WITH causas AS (
  SELECT
    projeto_id,
    causa_bloqueio,
    COUNT(*)                        AS semanas_com_causa,
    SUM(coalesce(dias_impacto, 0))  AS dias_causa,
    ROW_NUMBER() OVER (
      PARTITION BY projeto_id
      ORDER BY COUNT(*) DESC, SUM(coalesce(dias_impacto, 0)) DESC, causa_bloqueio
    ) AS rn
  FROM lakehouse_vertice.gold.status_estruturado
  WHERE data_status >= date_sub(DATE'2026-10-16', 90)
    AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
  GROUP BY projeto_id, causa_bloqueio
),
impacto_por_tipo AS (
  SELECT
    projeto_id,
    SUM(CASE WHEN causa_bloqueio = 'falta_sre' THEN coalesce(dias_impacto, 0) ELSE 0 END)    AS dias_falta_sre,
    SUM(CASE WHEN causa_bloqueio = 'rotatividade' THEN coalesce(dias_impacto, 0) ELSE 0 END) AS dias_rotatividade,
    SUM(
      CASE
        WHEN causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado') THEN coalesce(dias_impacto, 0)
        ELSE 0
      END
    ) AS dias_impacto_total_90d
  FROM lakehouse_vertice.gold.status_estruturado
  WHERE data_status >= date_sub(DATE'2026-10-16', 90)
  GROUP BY projeto_id
)
SELECT
  p.projeto_id,
  p.projeto,
  p.nome_projeto,
  p.cliente,
  p.segmento,
  p.gerente_projeto,
  p.situacao,
  p.spi,
  p.cpi,
  p.estouro_previsto,
  p.atraso_projetado_dias,
  p.farol_do_gerente,
  p.farol_calculado,
  p.melancia,
  coalesce(c.causa_bloqueio, 'sem_bloqueio') AS causa_principal_90d,
  coalesce(c.dias_causa, 0)                  AS dias_impacto_causa_90d,
  coalesce(i.dias_falta_sre, 0)              AS dias_falta_sre,
  coalesce(i.dias_rotatividade, 0)           AS dias_rotatividade
FROM lakehouse_vertice.gold.projeto_situacao_atual p
LEFT JOIN causas c
  ON c.projeto_id = p.projeto_id
 AND c.rn = 1
LEFT JOIN impacto_por_tipo i
  ON i.projeto_id = p.projeto_id
WHERE p.status = 'em_andamento'
ORDER BY
  CASE p.situacao
    WHEN 'crítico' THEN 1
    WHEN 'atenção' THEN 2
    ELSE 3
  END,
  p.spi ASC,
  p.cpi ASC
