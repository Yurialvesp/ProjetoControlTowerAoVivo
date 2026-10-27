SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  MAX(custo_hora)                  AS custo_hora,
  MAX(projeto_id)                  AS projeto_atual_id,
  ROUND(AVG(utilizacao) * 100, 1)  AS utilizacao_media_pct,
  ROUND(AVG(horas_ociosas), 2)     AS horas_paradas_semana,
  ROUND(AVG(custo_ocioso), 2)      AS custo_ocioso_semana
FROM lakehouse_vertice.gold.utilizacao_pessoa_semana
WHERE semana > date_sub(DATE'2026-10-16', 84)
GROUP BY colaborador_id, nome, papel, senioridade
HAVING AVG(utilizacao) < 0.20
ORDER BY horas_paradas_semana DESC, custo_ocioso_semana DESC
