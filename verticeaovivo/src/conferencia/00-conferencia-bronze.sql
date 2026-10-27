-- Conferência da camada bronze antes de rodar o pipeline medalhão (seed 42).
-- bronze.feriados fica de fora porque acumula uma captura a cada execução.
WITH contagens AS (
  SELECT 'projetos'            AS tabela, 60    AS esperado, (SELECT COUNT(*) FROM lakehouse_vertice.bronze.projetos)            AS obtido
  UNION ALL SELECT 'status_semanal',      3911,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.status_semanal)
  UNION ALL SELECT 'excel_tarefas',       1663,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.excel_tarefas)
  UNION ALL SELECT 'clickup_tarefas',     2119,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.clickup_tarefas)
  UNION ALL SELECT 'msproject_tarefas',   1260,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.msproject_tarefas)
  UNION ALL SELECT 'colaboradores',       523,               (SELECT COUNT(*) FROM lakehouse_vertice.bronze.colaboradores)
  UNION ALL SELECT 'apontamentos',        30883,             (SELECT COUNT(*) FROM lakehouse_vertice.bronze.apontamentos)
  UNION ALL SELECT 'custos',              23640,             (SELECT COUNT(*) FROM lakehouse_vertice.bronze.custos)
  UNION ALL SELECT 'entregas_fornecedor', 640,               (SELECT COUNT(*) FROM lakehouse_vertice.bronze.entregas_fornecedor)
)
SELECT
  tabela,
  esperado,
  obtido,
  CASE
    WHEN obtido = esperado THEN 'OK'
    ELSE raise_error(
      concat(
        'Divergência na tabela lakehouse_vertice.bronze.', tabela,
        ': esperado = ', CAST(esperado AS STRING),
        ', obtido = ', CAST(obtido AS STRING),
        '. Verifique a saída da tarefa de ingestão do data lake (IngestaoAWS).'
      )
    )
  END AS validacao
FROM contagens
ORDER BY esperado DESC;
