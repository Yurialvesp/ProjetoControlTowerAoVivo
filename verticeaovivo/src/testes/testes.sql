-- 10 testes de qualidade (Silver + Gold). Qualquer falha interrompe o job com raise_error().
WITH testes AS (
  -- 1. Os 60 projetos têm cronograma na silver.tarefas
  SELECT
    1 AS n,
    'os 60 projetos têm cronograma na silver.tarefas' AS teste,
    (SELECT COUNT(DISTINCT projeto_id) = 60 FROM lakehouse_vertice.silver.tarefas) AS passou

  -- 2. Cada projeto veio de UMA ferramenta, a do cadastro do PMO
  UNION ALL
  SELECT
    2,
    'cada projeto veio de UMA ferramenta, a do cadastro do PMO',
    (
      SELECT COUNT(*) = 60
      FROM (
        SELECT t.projeto_id
        FROM lakehouse_vertice.silver.tarefas t
        JOIN lakehouse_vertice.silver.projetos p ON p.projeto_id = t.projeto_id
        GROUP BY t.projeto_id
        HAVING COUNT(DISTINCT t.ferramenta) = 1
           AND MAX(t.ferramenta) = MAX(p.ferramenta)
      )
    )

  -- 3. As horas do Excel na silver = a soma das linhas de TOTAL das planilhas
  UNION ALL
  SELECT
    3,
    'as horas do Excel na silver = a soma das linhas de TOTAL das planilhas',
    (
      SELECT ROUND(
        (SELECT SUM(horas) FROM lakehouse_vertice.silver.tarefas WHERE ferramenta = 'excel')
        - (SELECT SUM(CAST(replace(trim(horas_previstas), 'h', '') AS DOUBLE))
           FROM lakehouse_vertice.bronze.excel_tarefas
           WHERE upper(trim(tarefa)) = 'TOTAL'),
        2
      ) = 0
    )

  -- 4. Uma linha por pessoa na silver
  UNION ALL
  SELECT
    4,
    'uma linha por pessoa na silver',
    (
      SELECT COUNT(*) = COUNT(DISTINCT colaborador_id) AND COUNT(*) = 520
      FROM lakehouse_vertice.silver.colaboradores
    )

  -- 5. A CodeForge virou um fornecedor só
  UNION ALL
  SELECT
    5,
    'a CodeForge virou um fornecedor só',
    (
      SELECT COUNT(DISTINCT fornecedor) = 1
      FROM lakehouse_vertice.silver.entregas_fornecedor
      WHERE replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'
    )

  -- 6. A limpeza não mudou o custo total (bronze com replace = silver)
  UNION ALL
  SELECT
    6,
    'a limpeza não mudou o custo total (bronze com replace = silver)',
    (
      SELECT ROUND(
        (SELECT SUM(CAST(replace(trim(valor), ',', '.') AS DECIMAL(14, 2))) FROM lakehouse_vertice.bronze.custos)
        - (SELECT SUM(valor) FROM lakehouse_vertice.silver.custos),
        2
      ) = 0
    )

  -- 7. Os 60 projetos têm fotografia de hoje
  UNION ALL
  SELECT
    7,
    'os 60 projetos têm fotografia de hoje',
    (
      SELECT COUNT(*) = 60 AND COUNT(DISTINCT projeto_id) = 60
      FROM lakehouse_vertice.gold.projeto_situacao_atual
    )

  -- 8. Todo projeto em andamento tem SPI e CPI
  UNION ALL
  SELECT
    8,
    'todo projeto em andamento tem SPI e CPI',
    (
      SELECT COUNT_IF(spi IS NULL OR cpi IS NULL) = 0
      FROM lakehouse_vertice.gold.projeto_situacao_atual
      WHERE status = 'em_andamento'
    )

  -- 9. O EV de hoje do status semanal bate com o das ferramentas (diferença < 1%)
  UNION ALL
  SELECT
    9,
    'o EV de hoje do status semanal bate com o das ferramentas (diferença < 1%)',
    (
      SELECT ABS(ev_fato - ev_ferramentas) / ev_ferramentas < 0.01
      FROM (
        SELECT
          (SELECT SUM(ev) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16') AS ev_fato,
          (SELECT SUM(ev) FROM lakehouse_vertice.gold.projeto_situacao_atual) AS ev_ferramentas
      )
    )

  -- 10. AC de hoje no fato = soma dos lançamentos até hoje
  UNION ALL
  SELECT
    10,
    'AC de hoje no fato = soma dos lançamentos até hoje',
    (
      SELECT ROUND(
        (SELECT SUM(ac) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16')
        - (SELECT SUM(valor) FROM lakehouse_vertice.silver.custos WHERE data <= DATE'2026-10-16'),
        2
      ) = 0
    )
)
SELECT
  n,
  teste,
  CASE
    WHEN passou THEN 'OK'
    ELSE raise_error(concat('Falha no teste ', CAST(n AS STRING), ': ', teste))
  END AS resultado
FROM testes
ORDER BY n;
