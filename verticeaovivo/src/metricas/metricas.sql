-- Métricas governadas: os KPIs da Torre, definidos UMA vez.
--
-- Uma metric view guarda a FÓRMULA, não o número. Dashboard, Genie e app pedem
-- MEASURE(spi) e recebem sempre o mesmo cálculo — ninguém mais reescreve SPI
-- num CASE WHEN escondido dentro de um widget.
--
--   gold.mv_projetos   SPI, CPI, EAC, estouro previsto, margem, atraso, melancias (fotografia de hoje)
--
-- ATENÇÃO: o YAML precisa da indentação intacta e NUNCA deve ter ponto-e-vírgula
-- dentro do bloco $$ ... $$, pois a sql_task do job fatia o arquivo em todo ';'.

CREATE OR REPLACE VIEW lakehouse_vertice.gold.mv_projetos
WITH METRICS
LANGUAGE YAML
COMMENT 'KPIs dos projetos em andamento na fotografia de hoje (16/10/2026), sobre as tarefas das 3 ferramentas. Regras de corte: SPI ou CPI < 0,9 atenção, < 0,8 crítico.'
AS $$
version: 1.1
source: lakehouse_vertice.gold.projeto_situacao_atual
filter: status = 'em_andamento'
dimensions:
  - name: projeto_id
    expr: projeto_id
    comment: Código do projeto, como PRJ-011
  - name: projeto
    expr: projeto
    comment: Código e nome do projeto
    synonyms: [nome do projeto]
  - name: cliente
    expr: cliente
    comment: Nome do cliente contratante do projeto
    synonyms: [conta]
  - name: segmento
    expr: segmento
    comment: varejo, financeiro, saude, logistica ou industria
  - name: ferramenta
    expr: ferramenta
    comment: Onde o projeto é gerenciado - excel, clickup ou msproject
  - name: situacao
    expr: situacao
    comment: ok, atenção ou crítico, pela regra de corte de SPI e CPI
  - name: farol_do_gerente
    expr: farol_do_gerente
    comment: Farol publicado pelo gerente no status desta sexta (verde, amarelo, vermelho)
  - name: farol_calculado
    expr: farol_calculado
    comment: Farol pela regra do manual - verde com SPI >= 0,95, amarelo >= 0,90, vermelho abaixo
  - name: gerente_projeto
    expr: gerente_projeto
    comment: Nome do gerente responsável pelo projeto no PMO
    synonyms: [gerente, gestor do projeto]
measures:
  - name: projetos
    expr: COUNT(1)
    comment: Quantidade de projetos em andamento
  - name: carteira
    expr: SUM(valor_contrato)
    comment: Valor de contrato somado, em reais
    synonyms: [valor da carteira, receita contratada]
  - name: spi
    expr: SUM(ev) / SUM(pv)
    comment: Schedule Performance Index = valor agregado / valor planejado. Abaixo de 1 é atraso.
    synonyms: [índice de prazo, desempenho de prazo]
  - name: cpi
    expr: SUM(ev) / SUM(ac)
    comment: Cost Performance Index = valor agregado / custo real. Abaixo de 1 é estouro de custo.
    synonyms: [índice de custo, desempenho de custo]
  - name: eac
    expr: SUM(eac)
    comment: Estimate at Completion = orçamento / CPI. Quanto o projeto vai custar no fim se nada mudar.
    synonyms: [estimativa no término, custo projetado]
  - name: estouro_previsto
    expr: SUM(estouro_previsto)
    comment: EAC menos orçamento, só dos projetos que estouram (projeto abaixo do orçamento não compensa o que estoura)
    synonyms: [estouro de custo, prejuízo previsto, quanto o atraso custa]
  - name: margem_projetada
    expr: (SUM(valor_contrato) - SUM(eac)) / SUM(valor_contrato)
    comment: (valor do contrato - EAC) / valor do contrato, em fração (0,15 = 15%)
    synonyms: [margem da carteira, rentabilidade projetada]
  - name: atraso_projetado_medio_dias
    expr: AVG(atraso_projetado_dias)
    comment: Atraso projetado = duração baseline / SPI - duração baseline, média em dias
    synonyms: [desvio de prazo, atraso previsto]
  - name: projetos_em_risco
    expr: COUNT(1) FILTER (WHERE situacao IN ('atenção', 'crítico'))
    comment: Projetos com SPI ou CPI abaixo de 0,9
    synonyms: [projetos atrasados, projetos com desvio]
  - name: projetos_criticos
    expr: COUNT(1) FILTER (WHERE situacao = 'crítico')
    comment: Projetos com SPI ou CPI abaixo de 0,8
    synonyms: [projetos vermelhos]
  - name: projetos_melancia
    expr: COUNT(1) FILTER (WHERE melancia)
    comment: Projetos com farol verde do gerente e SPI abaixo de 0,9 (verde por fora, vermelho por dentro)
    synonyms: [farol mentiroso, farol errado]
$$;
