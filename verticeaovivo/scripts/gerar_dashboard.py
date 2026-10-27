#!/usr/bin/env python3
"""Gera o dashboard AI/BI (Lakeview GRID_V1) da Torre de Controle em resources/dashboard-portfolio.lvdash.json.

Três páginas:
  1. Portfólio    — KPIs da carteira em andamento (SUM/SUM), estouro por projeto, dispersão SPI × CPI,
                    evolução semanal de SPI/CPI e tabela comparando farol do gerente × farol calculado (melancia).
  2. Pessoas      — Top 15 pessoas por custo da hora parada (12 semanas), causas de bloqueio por projeto (90 dias)
                    e tabela de utilização por pessoa e projeto.
  3. Fornecedores — Resumo por fornecedor (grafias, prazo real ÷ prometido, % no prazo, em atraso) e entregas atrasadas.
"""
from __future__ import annotations

import json
import pathlib

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "resources" / "dashboard-portfolio.lvdash.json"

# ---------------------------------------------------------------------------
# Queries SQL dos datasets (nomes puros na gold; nome completo na silver)
# ---------------------------------------------------------------------------

SQL_KPIS_PORTFOLIO = """SELECT
  ROUND(SUM(valor_contrato), 2) AS carteira,
  ROUND(SUM(ev) / SUM(pv), 2) AS spi,
  ROUND(SUM(ev) / SUM(ac), 2) AS cpi,
  ROUND(SUM(estouro_previsto), 2) AS estouro_previsto,
  COUNT_IF(situacao IN ('atenção', 'crítico')) AS projetos_em_risco,
  COUNT_IF(situacao = 'crítico') AS projetos_criticos,
  COUNT_IF(melancia) AS melancias
FROM projeto_situacao_atual
WHERE status = 'em_andamento'"""

SQL_PROJETOS_ANDAMENTO = """SELECT
  projeto_id,
  projeto,
  cliente,
  segmento,
  ferramenta,
  gerente_projeto,
  valor_contrato,
  orcamento,
  ROUND(spi, 2) AS spi,
  ROUND(cpi, 2) AS cpi,
  estouro_previsto,
  margem_projetada,
  atraso_projetado_dias,
  situacao,
  farol_do_gerente,
  farol_calculado,
  CASE WHEN melancia THEN 'Sim' ELSE 'Não' END AS melancia
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
ORDER BY estouro_previsto DESC, spi ASC"""

SQL_EVOLUCAO_SEMANAL = """SELECT
  semana,
  ROUND(SUM(ev) / SUM(pv), 3) AS spi,
  ROUND(SUM(ev) / SUM(ac), 3) AS cpi
FROM fato_projeto_semana
WHERE semana >= DATE'2025-03-07'
GROUP BY semana
ORDER BY semana"""

SQL_TOP15_OCIOSAS = """SELECT
  concat(colaborador_id, ' · ', nome, ' (', papel, ')') AS pessoa,
  colaborador_id,
  nome,
  papel,
  senioridade,
  projeto_id,
  ROUND(SUM(horas_disponiveis), 1) AS horas_disponiveis,
  ROUND(SUM(horas_apontadas), 1) AS horas_apontadas,
  ROUND(SUM(horas_ociosas), 1) AS horas_ociosas,
  ROUND(SUM(horas_apontadas) / SUM(horas_disponiveis), 4) AS utilizacao,
  ROUND(SUM(custo_ocioso), 2) AS custo_ocioso
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY colaborador_id, nome, papel, senioridade, projeto_id
ORDER BY custo_ocioso DESC
LIMIT 15"""

SQL_UTILIZACAO_PESSOAS = """SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  projeto_id,
  ROUND(SUM(horas_disponiveis), 1) AS horas_disponiveis,
  ROUND(SUM(horas_apontadas), 1) AS horas_apontadas,
  ROUND(SUM(horas_ociosas), 1) AS horas_ociosas,
  ROUND(SUM(horas_apontadas) / SUM(horas_disponiveis), 4) AS utilizacao,
  ROUND(SUM(custo_ocioso), 2) AS custo_ocioso,
  ROUND(AVG(spi_do_projeto), 2) AS spi_do_projeto
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY colaborador_id, nome, papel, senioridade, projeto_id
ORDER BY utilizacao ASC, custo_ocioso DESC"""

SQL_BLOQUEIOS_PROJETO = """SELECT
  projeto_id,
  causa_bloqueio,
  COUNT(*) AS semanas_com_bloqueio,
  ROUND(SUM(coalesce(dias_impacto, 0)), 0) AS dias_impacto
FROM status_estruturado
WHERE data_status >= DATE'2026-07-18'
  AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
GROUP BY projeto_id, causa_bloqueio
ORDER BY semanas_com_bloqueio DESC"""

SQL_FORNECEDORES = """SELECT
  fornecedor,
  COUNT(DISTINCT fornecedor_como_veio) AS grafias_no_cadastro,
  COUNT(*) AS entregas,
  ROUND(AVG(prazo_real_dias / prazo_prometido_dias), 2) AS prazo_real_div_prometido,
  ROUND(
    AVG(
      CASE
        WHEN data_entrega IS NOT NULL AND data_entrega <= data_prometida THEN 1.0
        WHEN data_entrega IS NOT NULL THEN 0.0
      END
    ),
    4
  ) AS pct_no_prazo,
  COUNT_IF(em_atraso) AS em_atraso_hoje,
  ROUND(SUM(valor), 2) AS valor_total
FROM lakehouse_vertice.silver.entregas_fornecedor
GROUP BY fornecedor
ORDER BY em_atraso_hoje DESC, prazo_real_div_prometido DESC"""

SQL_ENTREGAS_ATRASADAS = """SELECT
  entrega_id,
  projeto_id,
  fornecedor,
  fornecedor_como_veio,
  item,
  valor,
  data_pedido,
  data_prometida,
  prazo_prometido_dias,
  datediff(DATE'2026-10-16', data_prometida) AS dias_em_atraso
FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE em_atraso
ORDER BY dias_em_atraso DESC"""


# ---------------------------------------------------------------------------
# Helpers de construção de datasets e widgets Lakeview
# ---------------------------------------------------------------------------

def dataset(nome: str, titulo: str, sql: str) -> dict:
    linhas = sql.split("\n")
    return {
        "name": nome,
        "displayName": titulo,
        "queryLines": [linha + "\n" for linha in linhas],
    }


def texto(nome: str, linhas_md: list[str], pos: tuple[int, int, int, int]) -> dict:
    x, y, w, h = pos
    return {
        "widget": {
            "name": nome,
            "multilineTextboxSpec": {"lines": linhas_md},
        },
        "position": {"x": x, "y": y, "width": w, "height": h},
    }


def widget(
    nome: str,
    ds_name: str,
    campos: list[tuple[str, str]],
    spec: dict,
    pos: tuple[int, int, int, int],
    desagregado: bool = True,
) -> dict:
    x, y, w, h = pos
    return {
        "widget": {
            "name": nome,
            "queries": [
                {
                    "name": "main_query",
                    "query": {
                        "datasetName": ds_name,
                        "fields": [{"name": n, "expression": e} for n, e in campos],
                        "disaggregated": desagregado,
                    },
                }
            ],
            "spec": spec,
        },
        "position": {"x": x, "y": y, "width": w, "height": h},
    }


BRL_COMPACT = {
    "type": "number-currency",
    "currencyCode": "BRL",
    "abbreviation": "compact",
    "decimalPlaces": {"type": "max", "places": 2},
}

BRL_INTEIRO = {
    "type": "number-currency",
    "currencyCode": "BRL",
    "decimalPlaces": {"type": "max", "places": 0},
}

DECIMAL_2 = {
    "type": "number-plain",
    "decimalPlaces": {"type": "max", "places": 2},
}

INTEIRO = {
    "type": "number-plain",
    "decimalPlaces": {"type": "max", "places": 0},
}

PCT_1 = {
    "type": "number-percent",
    "decimalPlaces": {"type": "max", "places": 1},
}

COR_SITUACAO = {
    "type": "categorical",
    "mappings": [
        {"value": "crítico", "color": "#FF5F46"},
        {"value": "atenção", "color": "#F6C344"},
        {"value": "ok", "color": "#22C2F4"},
    ],
}


def kpi(nome: str, campo: str, titulo: str, fmt: dict, pos: tuple[int, int, int, int]) -> dict:
    return widget(
        nome=nome,
        ds_name="ds_kpis_portfolio",
        campos=[(campo, f"`{campo}`")],
        spec={
            "version": 2,
            "widgetType": "counter",
            "encodings": {
                "value": {
                    "fieldName": campo,
                    "displayName": titulo,
                    "format": fmt,
                }
            },
            "frame": {"showTitle": True, "title": titulo},
        },
        pos=pos,
        desagregado=True,
    )


def montar_pagina_portfolio() -> dict:
    layout = [
        texto(
            "hdr-portfolio",
            [
                "## Portfólio · Quais projetos estão atrasados, de quais clientes, e quanto esse atraso vai me custar?\n",
                "\n",
                "Fotografia de **16/10/2026** dos 41 projetos em andamento (Excel, ClickUp e MS Project unificados na camada Gold).",
            ],
            (0, 0, 12, 2),
        ),
        # Linha 1 de KPIs (4 × width 3 = 12)
        kpi("kpi-carteira", "carteira", "Carteira em andamento", BRL_COMPACT, (0, 2, 3, 3)),
        kpi("kpi-spi", "spi", "SPI da carteira (SUM EV / SUM PV)", DECIMAL_2, (3, 2, 3, 3)),
        kpi("kpi-cpi", "cpi", "CPI da carteira (SUM EV / SUM AC)", DECIMAL_2, (6, 2, 3, 3)),
        kpi("kpi-estouro", "estouro_previsto", "Estouro previsto total", BRL_COMPACT, (9, 2, 3, 3)),
        # Linha 2 de KPIs (3 × width 4 = 12)
        kpi("kpi-em-risco", "projetos_em_risco", "Projetos em risco (atenção + crítico)", INTEIRO, (0, 5, 4, 3)),
        kpi("kpi-criticos", "projetos_criticos", "Projetos críticos (SPI ou CPI < 0,8)", INTEIRO, (4, 5, 4, 3)),
        kpi("kpi-melancias", "melancias", "Melancias (farol verde e SPI < 0,9)", INTEIRO, (8, 5, 4, 3)),
        # Gráficos lado a lado (2 × width 6 = 12)
        widget(
            "bar-estouro-projeto",
            "ds_projetos_andamento",
            [
                ("projeto", "`projeto`"),
                ("estouro_previsto", "`estouro_previsto`"),
                ("situacao", "`situacao`"),
            ],
            {
                "version": 3,
                "widgetType": "bar",
                "encodings": {
                    "y": {
                        "fieldName": "projeto",
                        "displayName": "Projeto",
                        "scale": {"type": "categorical", "sort": {"by": "x-reversed"}},
                    },
                    "x": {
                        "fieldName": "estouro_previsto",
                        "displayName": "Estouro previsto (R$)",
                        "scale": {"type": "quantitative"},
                        "format": BRL_COMPACT,
                    },
                    "color": {
                        "fieldName": "situacao",
                        "displayName": "Situação",
                        "scale": COR_SITUACAO,
                    },
                },
                "frame": {
                    "showTitle": True,
                    "title": "Estouro previsto por projeto em andamento (colorido por situação)",
                },
            },
            (0, 8, 6, 7),
            desagregado=True,
        ),
        widget(
            "scatter-spi-cpi",
            "ds_projetos_andamento",
            [
                ("spi", "`spi`"),
                ("cpi", "`cpi`"),
                ("situacao", "`situacao`"),
                ("projeto", "`projeto`"),
            ],
            {
                "version": 3,
                "widgetType": "scatter",
                "encodings": {
                    "x": {
                        "fieldName": "spi",
                        "displayName": "SPI (Prazo)",
                        "scale": {"type": "quantitative"},
                    },
                    "y": {
                        "fieldName": "cpi",
                        "displayName": "CPI (Custo)",
                        "scale": {"type": "quantitative"},
                    },
                    "color": {
                        "fieldName": "situacao",
                        "displayName": "Situação",
                        "scale": COR_SITUACAO,
                    },
                    "label": {"fieldName": "projeto", "show": False},
                },
                "frame": {
                    "showTitle": True,
                    "title": "Dispersão SPI × CPI (um ponto por projeto em andamento)",
                },
            },
            (6, 8, 6, 7),
            desagregado=True,
        ),
        # Linha temporal SPI e CPI semanais (width 12)
        widget(
            "line-spi-cpi-semanal",
            "ds_evolucao_semanal",
            [
                ("semana", "`semana`"),
                ("spi", "`spi`"),
                ("cpi", "`cpi`"),
            ],
            {
                "version": 3,
                "widgetType": "line",
                "encodings": {
                    "x": {
                        "fieldName": "semana",
                        "displayName": "Semana (sexta-feira)",
                        "scale": {"type": "temporal"},
                    },
                    "y": {
                        "scale": {"type": "quantitative"},
                        "fields": [
                            {"fieldName": "spi", "displayName": "SPI da carteira (SUM EV / SUM PV)"},
                            {"fieldName": "cpi", "displayName": "CPI da carteira (SUM EV / SUM AC)"},
                        ],
                    },
                },
                "frame": {
                    "showTitle": True,
                    "title": "Evolução semanal de SPI e CPI da carteira (a partir de 07/03/2025)",
                },
            },
            (0, 15, 12, 6),
            desagregado=True,
        ),
        # Tabela de projetos em andamento (width 12)
        widget(
            "tabela-projetos-andamento",
            "ds_projetos_andamento",
            [
                (c, f"`{c}`")
                for c in (
                    "projeto",
                    "cliente",
                    "segmento",
                    "ferramenta",
                    "gerente_projeto",
                    "spi",
                    "cpi",
                    "situacao",
                    "farol_do_gerente",
                    "farol_calculado",
                    "melancia",
                    "estouro_previsto",
                    "margem_projetada",
                    "atraso_projetado_dias",
                )
            ],
            {
                "version": 2,
                "widgetType": "table",
                "encodings": {
                    "columns": [
                        {"fieldName": "projeto", "displayName": "Projeto"},
                        {"fieldName": "cliente", "displayName": "Cliente"},
                        {"fieldName": "segmento", "displayName": "Segmento"},
                        {"fieldName": "ferramenta", "displayName": "Ferramenta"},
                        {"fieldName": "gerente_projeto", "displayName": "Gerente"},
                        {"fieldName": "spi", "displayName": "SPI"},
                        {"fieldName": "cpi", "displayName": "CPI"},
                        {"fieldName": "situacao", "displayName": "Situação"},
                        {"fieldName": "farol_do_gerente", "displayName": "Farol do gerente"},
                        {"fieldName": "farol_calculado", "displayName": "Farol calculado"},
                        {"fieldName": "melancia", "displayName": "Melancia"},
                        {"fieldName": "estouro_previsto", "displayName": "Estouro previsto", "format": BRL_INTEIRO},
                        {"fieldName": "margem_projetada", "displayName": "Margem projetada", "format": PCT_1},
                        {"fieldName": "atraso_projetado_dias", "displayName": "Atraso projetado (dias)"},
                    ]
                },
                "frame": {
                    "showTitle": True,
                    "title": "Projetos em andamento (farol do gerente ao lado do farol pelo número e melancia)",
                },
            },
            (0, 21, 12, 8),
            desagregado=True,
        ),
    ]
    return {
        "name": "portfolio",
        "displayName": "Portfólio",
        "pageType": "PAGE_TYPE_CANVAS",
        "layoutVersion": "GRID_V1",
        "layout": layout,
    }


def montar_pagina_pessoas() -> dict:
    layout = [
        texto(
            "hdr-pessoas",
            [
                "## Pessoas · Tenho gente parada enquanto outro projeto pede gente?\n",
                "\n",
                "Cruzamento da ociosidade do timesheet nas últimas 12 semanas (`semana > 2026-07-24`) com as causas de bloqueio extraídas pela IA nos últimos 90 dias.",
            ],
            (0, 0, 12, 2),
        ),
        widget(
            "bar-top15-custo-ocioso",
            "ds_top15_ociosas",
            [
                ("pessoa", "`pessoa`"),
                ("custo_ocioso", "`custo_ocioso`"),
                ("papel", "`papel`"),
            ],
            {
                "version": 3,
                "widgetType": "bar",
                "encodings": {
                    "y": {
                        "fieldName": "pessoa",
                        "displayName": "Colaborador",
                        "scale": {"type": "categorical", "sort": {"by": "x-reversed"}},
                    },
                    "x": {
                        "fieldName": "custo_ocioso",
                        "displayName": "Custo da hora parada (R$)",
                        "scale": {"type": "quantitative"},
                        "format": BRL_INTEIRO,
                    },
                    "color": {
                        "fieldName": "papel",
                        "displayName": "Papel",
                        "scale": {"type": "categorical"},
                    },
                },
                "frame": {
                    "showTitle": True,
                    "title": "Top 15 pessoas por custo da hora parada (últimas 12 semanas)",
                },
            },
            (0, 2, 6, 7),
            desagregado=True,
        ),
        widget(
            "bar-bloqueios-projeto",
            "ds_bloqueios_projeto",
            [
                ("projeto_id", "`projeto_id`"),
                ("semanas_com_bloqueio", "`semanas_com_bloqueio`"),
                ("causa_bloqueio", "`causa_bloqueio`"),
            ],
            {
                "version": 3,
                "widgetType": "bar",
                "encodings": {
                    "x": {
                        "fieldName": "projeto_id",
                        "displayName": "Projeto",
                        "scale": {"type": "categorical"},
                    },
                    "y": {
                        "fieldName": "semanas_com_bloqueio",
                        "displayName": "Semanas com bloqueio",
                        "scale": {"type": "quantitative"},
                    },
                    "color": {
                        "fieldName": "causa_bloqueio",
                        "displayName": "Causa do bloqueio",
                        "scale": {"type": "categorical"},
                    },
                },
                "frame": {
                    "showTitle": True,
                    "title": "Causas de bloqueio por projeto (últimos 90 dias, estruturado com IA)",
                },
            },
            (6, 2, 6, 7),
            desagregado=True,
        ),
        widget(
            "tabela-utilizacao-pessoas",
            "ds_utilizacao_pessoas",
            [
                (c, f"`{c}`")
                for c in (
                    "colaborador_id",
                    "nome",
                    "papel",
                    "senioridade",
                    "projeto_id",
                    "horas_disponiveis",
                    "horas_apontadas",
                    "horas_ociosas",
                    "utilizacao",
                    "custo_ocioso",
                    "spi_do_projeto",
                )
            ],
            {
                "version": 2,
                "widgetType": "table",
                "encodings": {
                    "columns": [
                        {"fieldName": "colaborador_id", "displayName": "ID"},
                        {"fieldName": "nome", "displayName": "Colaborador"},
                        {"fieldName": "papel", "displayName": "Papel"},
                        {"fieldName": "senioridade", "displayName": "Senioridade"},
                        {"fieldName": "projeto_id", "displayName": "Projeto"},
                        {"fieldName": "horas_disponiveis", "displayName": "Horas disponíveis"},
                        {"fieldName": "horas_apontadas", "displayName": "Horas apontadas"},
                        {"fieldName": "horas_ociosas", "displayName": "Horas ociosas"},
                        {"fieldName": "utilizacao", "displayName": "Utilização", "format": PCT_1},
                        {"fieldName": "custo_ocioso", "displayName": "Custo ocioso", "format": BRL_INTEIRO},
                        {"fieldName": "spi_do_projeto", "displayName": "SPI médio do projeto"},
                    ]
                },
                "frame": {
                    "showTitle": True,
                    "title": "Utilização por pessoa e projeto nas últimas 12 semanas (da mais parada à mais ocupada)",
                },
            },
            (0, 9, 12, 8),
            desagregado=True,
        ),
    ]
    return {
        "name": "pessoas",
        "displayName": "Pessoas",
        "pageType": "PAGE_TYPE_CANVAS",
        "layoutVersion": "GRID_V1",
        "layout": layout,
    }


def montar_pagina_fornecedores() -> dict:
    layout = [
        texto(
            "hdr-fornecedores",
            [
                "## Fornecedores · O que vai dar errado no próximo mês? Quais consultorias atrasam as entregas?\n",
                "\n",
                "Análise direta sobre `lakehouse_vertice.silver.entregas_fornecedor`, com as 4 grafias da CodeForge unificadas.",
            ],
            (0, 0, 12, 2),
        ),
        widget(
            "tabela-fornecedores-resumo",
            "ds_fornecedores",
            [
                (c, f"`{c}`")
                for c in (
                    "fornecedor",
                    "grafias_no_cadastro",
                    "entregas",
                    "prazo_real_div_prometido",
                    "pct_no_prazo",
                    "em_atraso_hoje",
                    "valor_total",
                )
            ],
            {
                "version": 2,
                "widgetType": "table",
                "encodings": {
                    "columns": [
                        {"fieldName": "fornecedor", "displayName": "Fornecedor"},
                        {"fieldName": "grafias_no_cadastro", "displayName": "Grafias no cadastro"},
                        {"fieldName": "entregas", "displayName": "Entregas"},
                        {"fieldName": "prazo_real_div_prometido", "displayName": "Prazo real ÷ prometido"},
                        {"fieldName": "pct_no_prazo", "displayName": "% no prazo", "format": PCT_1},
                        {"fieldName": "em_atraso_hoje", "displayName": "Em atraso hoje"},
                        {"fieldName": "valor_total", "displayName": "Valor total contratado", "format": BRL_INTEIRO},
                    ]
                },
                "frame": {
                    "showTitle": True,
                    "title": "Desempenho por fornecedor (grafias no cadastro, entregas, prazo real ÷ prometido, % no prazo e em atraso)",
                },
            },
            (0, 2, 12, 5),
            desagregado=True,
        ),
        widget(
            "tabela-entregas-atrasadas",
            "ds_entregas_atrasadas",
            [
                (c, f"`{c}`")
                for c in (
                    "entrega_id",
                    "projeto_id",
                    "fornecedor",
                    "fornecedor_como_veio",
                    "item",
                    "valor",
                    "data_pedido",
                    "data_prometida",
                    "prazo_prometido_dias",
                    "dias_em_atraso",
                )
            ],
            {
                "version": 2,
                "widgetType": "table",
                "encodings": {
                    "columns": [
                        {"fieldName": "entrega_id", "displayName": "Entrega"},
                        {"fieldName": "projeto_id", "displayName": "Projeto"},
                        {"fieldName": "fornecedor", "displayName": "Fornecedor (normalizado)"},
                        {"fieldName": "fornecedor_como_veio", "displayName": "Grafia original"},
                        {"fieldName": "item", "displayName": "Item contratado"},
                        {"fieldName": "valor", "displayName": "Valor", "format": BRL_INTEIRO},
                        {"fieldName": "data_pedido", "displayName": "Data do pedido"},
                        {"fieldName": "data_prometida", "displayName": "Data prometida"},
                        {"fieldName": "prazo_prometido_dias", "displayName": "Prazo prometido (dias)"},
                        {"fieldName": "dias_em_atraso", "displayName": "Dias em atraso hoje"},
                    ]
                },
                "frame": {
                    "showTitle": True,
                    "title": "Entregas de fornecedor em atraso hoje (16/10/2026)",
                },
            },
            (0, 7, 12, 6),
            desagregado=True,
        ),
    ]
    return {
        "name": "fornecedores",
        "displayName": "Fornecedores",
        "pageType": "PAGE_TYPE_CANVAS",
        "layoutVersion": "GRID_V1",
        "layout": layout,
    }


def montar_dashboard() -> dict:
    return {
        "datasets": [
            dataset("ds_kpis_portfolio", "KPIs da carteira em andamento", SQL_KPIS_PORTFOLIO),
            dataset("ds_projetos_andamento", "Projetos em andamento", SQL_PROJETOS_ANDAMENTO),
            dataset("ds_evolucao_semanal", "Evolução semanal SPI e CPI", SQL_EVOLUCAO_SEMANAL),
            dataset("ds_top15_ociosas", "Top 15 pessoas por custo ocioso (12 semanas)", SQL_TOP15_OCIOSAS),
            dataset("ds_utilizacao_pessoas", "Utilização por pessoa e projeto (12 semanas)", SQL_UTILIZACAO_PESSOAS),
            dataset("ds_bloqueios_projeto", "Causas de bloqueio por projeto (90 dias)", SQL_BLOQUEIOS_PROJETO),
            dataset("ds_fornecedores", "Resumo por fornecedor", SQL_FORNECEDORES),
            dataset("ds_entregas_atrasadas", "Entregas em atraso hoje", SQL_ENTREGAS_ATRASADAS),
        ],
        "pages": [
            montar_pagina_portfolio(),
            montar_pagina_pessoas(),
            montar_pagina_fornecedores(),
        ],
        "uiSettings": {
            "theme": {
                "canvasBackgroundColor": {"light": "#F5F6FC", "dark": "#14141A"},
                "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1E1E24"},
                "fontColor": {"light": "#14141A", "dark": "#F5F6FC"},
                "selectionColor": {"light": "#0059DB", "dark": "#22C2F4"},
                "visualizationColors": [
                    "#0059DB",
                    "#22C2F4",
                    "#F6C344",
                    "#FF5F46",
                    "#9B6BDB",
                    "#3ECF8E",
                    "#6E7180",
                ],
                "widgetHeaderAlignment": "LEFT",
                "widgetCornerRadius": 12,
            }
        },
    }


def main() -> None:
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    painel = montar_dashboard()
    SAIDA.write_text(json.dumps(painel, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"ok: {SAIDA.relative_to(RAIZ)} ({len(painel['datasets'])} datasets, {len(painel['pages'])} páginas)")


if __name__ == "__main__":
    main()
