-- Estruturação incremental do texto livre do status semanal (regra + palavra-chave + IA v2.0).

CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado (
  projeto_id       STRING    COMMENT 'Código identificador do projeto (ex.: PRJ-011)',
  data_status      DATE      COMMENT 'Data de publicação do status semanal (sexta-feira)',
  farol            STRING    COMMENT 'Farol reportado pelo gerente (verde, amarelo ou vermelho)',
  causa_bloqueio   STRING    COMMENT 'Categoria padronizada do bloqueio (falta_sre, change_freeze, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio ou nao_reportado)',
  bloqueio         STRING    COMMENT 'Resumo do bloqueio extraído pela IA nos status recentes com bloqueio',
  quem_destrava    STRING    COMMENT 'Área, papel ou responsável por destravar o bloqueio segundo a IA',
  dias_impacto     DOUBLE    COMMENT 'Impacto estimado em dias corridos (ex.: 1 semana = 7)',
  metodo           STRING    COMMENT 'Método de classificação aplicado: regra, ia ou palavra_chave',
  texto_status     STRING    COMMENT 'Texto original completo publicado pelo gerente no status semanal',
  _classificado_em TIMESTAMP COMMENT 'Data e hora em que o registro foi classificado e inserido na gold'
)
COMMENT 'Status semanais estruturados com causa de bloqueio, resumo do bloqueio, quem destrava e dias de impacto (combinando regras, palavras-chave no histórico e IA nos últimos 90 dias).';

MERGE INTO lakehouse_vertice.gold.status_estruturado AS destino
USING (
  WITH novos AS (
    SELECT
      s.projeto_id,
      s.data_status,
      s.farol,
      s.texto_status,
      s.status_vazio,
      CASE
        WHEN s.status_vazio
          OR lower(s.texto_status) LIKE '%bloqueios: nenhum%'
          OR lower(s.texto_status) LIKE '%sem bloqueios%'
          OR lower(s.texto_status) LIKE '%nada relevante%'
          THEN 'regra'
        WHEN s.data_status >= DATE'2026-07-18'
          THEN 'ia'
        ELSE 'palavra_chave'
      END AS metodo,
      CASE
        WHEN lower(s.texto_status) RLIKE 'impacto estimado[^0-9]*1 semana' THEN 7.0
        WHEN lower(s.texto_status) RLIKE 'impacto estimado[^0-9]*([0-9]+)\\s*dia'
          THEN CAST(regexp_extract(lower(s.texto_status), 'impacto estimado[^0-9]*([0-9]+)\\s*dia', 1) AS DOUBLE)
      END AS dias_regex
    FROM lakehouse_vertice.silver.status_semanal s
    LEFT ANTI JOIN lakehouse_vertice.gold.status_estruturado g
      ON g.projeto_id = s.projeto_id
     AND g.data_status = s.data_status
  ),
  ramo_regra AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      CASE
        WHEN status_vazio THEN 'nao_reportado'
        ELSE 'sem_bloqueio'
      END                  AS causa_bloqueio,
      CAST(NULL AS STRING) AS bloqueio,
      CAST(NULL AS STRING) AS quem_destrava,
      CAST(NULL AS DOUBLE) AS dias_impacto,
      metodo,
      texto_status
    FROM novos
    WHERE metodo = 'regra'
  ),
  ramo_palavra_chave AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      CASE
        WHEN lower(texto_status) RLIKE 'freeze|congelamento|janela de deploy'                    THEN 'change_freeze'
        WHEN lower(texto_status) RLIKE 'sre|infraestrutura|ambiente de homologa[çc][ãa]o'        THEN 'falta_sre'
        WHEN lower(texto_status) RLIKE 'forge|consultoria|fornecedor'                            THEN 'dependencia_fornecedor'
        WHEN lower(texto_status) RLIKE 'sa[íi]da de|rotatividade|onboarding'                     THEN 'rotatividade'
        WHEN lower(texto_status) RLIKE 'escopo|change request|regra de neg[óo]cio'               THEN 'mudanca_escopo'
        WHEN lower(texto_status) RLIKE 'bugs|regress[ãa]o|refazendo'                             THEN 'bug_retrabalho'
        WHEN lower(texto_status) RLIKE 'aprova[çc][ãa]o do cliente|homologa[çc][ãa]o do cliente' THEN 'aprovacao_cliente'
        ELSE 'sem_bloqueio'
      END                  AS causa_bloqueio,
      CAST(NULL AS STRING) AS bloqueio,
      CAST(NULL AS STRING) AS quem_destrava,
      dias_regex           AS dias_impacto,
      metodo,
      texto_status
    FROM novos
    WHERE metodo = 'palavra_chave'
  ),
  ia_bruto AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      metodo,
      texto_status,
      dias_regex,
      ai_classify(
        texto_status,
        '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
        map('version', '2.0')
      ) AS clf,
      ai_extract(
        texto_status,
        '{"bloqueio":{"type":"string"},"quem_destrava":{"type":"string"},"dias_impacto":{"type":"number","description":"1 semana = 7"}}',
        map('version', '2.0')
      ) AS ext
    FROM novos
    WHERE metodo = 'ia'
  ),
  ramo_ia AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      clf:response[0]::STRING                                 AS causa_bloqueio,
      ext:response:bloqueio::STRING                           AS bloqueio,
      ext:response:quem_destrava::STRING                      AS quem_destrava,
      coalesce(ext:response:dias_impacto::DOUBLE, dias_regex) AS dias_impacto,
      metodo,
      texto_status
    FROM ia_bruto
  )
  SELECT *, current_timestamp() AS _classificado_em FROM ramo_regra
  UNION ALL
  SELECT *, current_timestamp() AS _classificado_em FROM ramo_palavra_chave
  UNION ALL
  SELECT *, current_timestamp() AS _classificado_em FROM ramo_ia
) AS origem
ON destino.projeto_id = origem.projeto_id
AND destino.data_status = origem.data_status
WHEN NOT MATCHED THEN INSERT (
  projeto_id,
  data_status,
  farol,
  causa_bloqueio,
  bloqueio,
  quem_destrava,
  dias_impacto,
  metodo,
  texto_status,
  _classificado_em
) VALUES (
  origem.projeto_id,
  origem.data_status,
  origem.farol,
  origem.causa_bloqueio,
  origem.bloqueio,
  origem.quem_destrava,
  origem.dias_impacto,
  origem.metodo,
  origem.texto_status,
  origem._classificado_em
);

SELECT
  metodo,
  causa_bloqueio,
  COUNT(*) AS qtd_status,
  SUM(coalesce(dias_impacto, 0)) AS total_dias_impacto
FROM lakehouse_vertice.gold.status_estruturado
GROUP BY metodo, causa_bloqueio
ORDER BY metodo, qtd_status DESC;
