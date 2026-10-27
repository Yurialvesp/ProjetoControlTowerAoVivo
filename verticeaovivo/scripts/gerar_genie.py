#!/usr/bin/env python3
"""Gera o Genie Agent do Projeto Farol como JSON versionado (serialized_space v2).

Uso:  python scripts/gerar_genie.py [--profile DEFAULT]

Escreve resources/farol.geniespace.json, que o bundle publica no deploy
(resources/genie.genie_space.yml).
Verifica automaticamente se lakehouse_vertice.gold.score_estouro_30d existe no workspace:
sem ela, não inclui a tabela nem cita o score nas instruções ou exemplos.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess

SAIDA = pathlib.Path(__file__).resolve().parents[1] / "resources" / "farol.geniespace.json"
G = "lakehouse_vertice.gold"
S = "lakehouse_vertice.silver"


def ident(prefixo: str, n: int) -> str:
    return f"{prefixo}{n:0{32 - len(prefixo)}d}"  # 32 caracteres hex, únicos e ordenados


def tem_score_estouro(profile: str) -> bool:
    try:
        r = subprocess.run(
            ["databricks", "tables", "exists", f"{G}.score_estouro_30d", "--profile", profile, "-o", "json"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=20,
        )
        if r.returncode != 0:
            return False
        dados = json.loads(r.stdout or "{}")
        return bool(dados.get("table_exists", False))
    except Exception:
        return False


PERGUNTAS = [
    "Quais projetos estão atrasados, e de quais clientes?",
    "Quanto esse atraso vai me custar?",
    "Tenho gente parada enquanto outro projeto pede gente?",
    "O que vai dar errado no próximo mês, e o que eu faço agora?",
]


def montar(com_score: bool) -> dict:
    instrucoes = [
        "Você é o analista da Torre de Controle (Projeto Farol) da Vértice Tecnologia, empresa de tecnologia com 520 pessoas e 60 projetos de clientes (varejo, financeiro, saúde, logística, indústria). Quem pergunta é o dono da empresa ou alguém da diretoria. Responda em português, com números em reais (R$) e índices com 2 casas.",
        "HOJE é 16/10/2026 (sexta-feira). Nunca use current_date(). 'Últimos 90 dias' = data >= DATE'2026-07-18'; 'últimas 12 semanas' = semana > DATE'2026-07-24'; 'últimas 8 semanas' = semana > DATE'2026-08-21'; 'próximo mês' = de 16/10/2026 a 15/11/2026.",
        "Definições: SPI = EV / PV (abaixo de 1 é atraso). CPI = EV / AC (abaixo de 1 é estouro de custo). EAC = orçamento / CPI. Estouro previsto = EAC - orçamento, só quando positivo. Regras de corte: SPI ou CPI < 0,9 = atenção; < 0,8 = crítico. 'Atrasado' = situação atenção ou crítico.",
        "Para SPI, CPI, EAC, estouro, margem, atraso projetado e contagem de projetos em risco HOJE, use a metric view mv_projetos com MEASURE(), ou a tabela projeto_situacao_atual filtrando status = 'em_andamento'. Projetos concluídos nunca entram em contagens de risco nem no estouro previsto.",
        "Para evolução no tempo use fato_projeto_semana. PV, EV e AC em fato_projeto_semana são ACUMULADOS até a semana: nunca some semanas diferentes do mesmo projeto.",
        "Farol: farol_do_gerente é o que o gerente publicou; farol_calculado segue a regra do manual (verde com SPI >= 0,95, amarelo >= 0,90, vermelho abaixo). 'Melancia' = farol do gerente verde com SPI < 0,9 (coluna melancia em projeto_situacao_atual).",
        "'Por que o projeto X atrasou?': use status_estruturado (causa_bloqueio, bloqueio, quem_destrava, dias_impacto), contando as causas dos últimos 90 dias e ignorando 'sem_bloqueio' e 'nao_reportado'. Mostre também o SPI de projeto_situacao_atual. Se a causa for falta_sre, procure SREs com utilização abaixo de 20% em outros projetos (utilizacao_pessoa_semana, papel = 'sre').",
        "Gente parada: utilizacao_pessoa_semana (utilizacao, horas_ociosas, custo_ocioso, papel). Utilização baixa = abaixo de 20% nas últimas 12 semanas. Agrupe por pessoa e projeto e calcule SUM(horas_apontadas) / SUM(horas_disponiveis).",
    ]

    if com_score:
        instrucoes.extend(
            [
                "O que vai dar errado no próximo mês: (1) o modelo de estouro em 30 dias, gold.score_estouro_30d (prob_estouro_30d de 0 a 1, ranking, faixa_risco alto/medio/baixo e principais_fatores em português), na data_referencia mais recente. Projeto que já está abaixo de 0,9 hoje tem prob 1,0: a pergunta sobre o futuro interessa mais pelos projetos com situacao = 'ok' e faixa alto ou medio (os que a regra de corte ainda não vê); (2) entregas de consultoria em atraso (silver.entregas_fornecedor com em_atraso = true); (3) o change freeze de varejo começa em 01/11/2026 e trava deploy até 10/01/2027 nos projetos de e-commerce (tipo_projeto com e-commerce, checkout ou marketplace) ainda em andamento. Junte os três quando a pergunta for sobre o futuro, e mostre o motivo (principais_fatores) do modelo.",
                "Probabilidade de estouro, risco em 30 dias, 'qual projeto vai estourar': gold.score_estouro_30d, com join em projeto_situacao_atual por projeto_id para nome, cliente e situação. Mostre a probabilidade em %.",
            ]
        )
    else:
        instrucoes.append(
            "O que vai dar errado no próximo mês: (1) entregas de consultoria em atraso (silver.entregas_fornecedor com em_atraso = true); (2) o change freeze de varejo começa em 01/11/2026 e trava deploy até 10/01/2027 nos projetos de e-commerce (tipo_projeto com e-commerce, checkout ou marketplace) ainda em andamento. Junte os dois quando a pergunta for sobre o próximo mês ou futuro."
        )

    instrucoes.extend(
        [
            "Fornecedores: silver.entregas_fornecedor (o nome já está normalizado; prazo_real_dias / prazo_prometido_dias = fator de atraso; em_atraso = prometida antes de hoje e não entregue). Agrupe por fornecedor.",
            "Quando perguntarem por projeto, responda com projeto_id (ex.: PRJ-011), o nome e o cliente.",
            "Rankings de projeto (maior estouro, pior SPI, maior atraso): use a tabela projeto_situacao_atual com WHERE status = 'em_andamento', ORDER BY e LIMIT. A metric view mv_projetos serve para totais da carteira, não para ranking.",
            "Pergunta no singular ('qual fornecedor', 'qual projeto') pede UMA linha: ORDER BY ... LIMIT 1. Change freeze: todo projeto de e-commerce, checkout ou marketplace em andamento é afetado, sem filtrar por data de término (o freeze trava deploy, inclusive de correção).",
            "Quando perguntarem QUAIS CLIENTES, devolva cada cliente uma vez só (SELECT DISTINCT cliente ou GROUP BY cliente), com a quantidade de projetos dele na situação perguntada.",
        ]
    )

    if com_score:
        sql_proximo_mes = (
            f"SELECT 'risco de estouro em 30 dias (modelo)' AS risco, s.projeto_id, p.projeto, "
            f"concat(CAST(ROUND(s.prob_estouro_30d * 100) AS INT), '% de chance: ', s.principais_fatores) AS detalhe, "
            f"'olhar agora, antes de cruzar 0,9' AS o_que_fazer "
            f"FROM {G}.score_estouro_30d s JOIN {G}.projeto_situacao_atual p ON p.projeto_id = s.projeto_id "
            f"WHERE s.data_referencia = (SELECT MAX(data_referencia) FROM {G}.score_estouro_30d) "
            f"AND p.situacao = 'ok' AND s.faixa_risco IN ('alto', 'medio') "
            f"UNION ALL "
            f"SELECT 'entrega de fornecedor atrasada' AS risco, e.projeto_id, p.projeto, "
            f"concat(e.fornecedor, ': ', e.item, ' (', CAST(datediff(DATE'2026-10-16', e.data_prometida) AS STRING), ' dias de atraso)') AS detalhe, "
            f"'cobrar o fornecedor e aplicar a multa do contrato' AS o_que_fazer "
            f"FROM {S}.entregas_fornecedor e JOIN {G}.projeto_situacao_atual p ON p.projeto_id = e.projeto_id WHERE e.em_atraso "
            f"UNION ALL "
            f"SELECT 'change freeze da Black Friday', projeto_id, projeto, "
            f"'deploy em produção travado de 01/11/2026 a 10/01/2027', "
            f"'antecipar o que der para subir até 31/10' "
            f"FROM {G}.projeto_situacao_atual WHERE status = 'em_andamento' "
            f"AND (lower(tipo_projeto) LIKE '%commerce%' OR lower(tipo_projeto) LIKE '%checkout%' OR lower(tipo_projeto) LIKE '%marketplace%')"
        )
    else:
        sql_proximo_mes = (
            f"SELECT 'entrega de fornecedor atrasada' AS risco, e.projeto_id, p.projeto, "
            f"concat(e.fornecedor, ': ', e.item, ' (', CAST(datediff(DATE'2026-10-16', e.data_prometida) AS STRING), ' dias de atraso)') AS detalhe, "
            f"'cobrar o fornecedor e aplicar a multa do contrato' AS o_que_fazer "
            f"FROM {S}.entregas_fornecedor e JOIN {G}.projeto_situacao_atual p ON p.projeto_id = e.projeto_id WHERE e.em_atraso "
            f"UNION ALL "
            f"SELECT 'change freeze da Black Friday' AS risco, projeto_id, projeto, "
            f"'deploy em produção travado de 01/11/2026 a 10/01/2027' AS detalhe, "
            f"'antecipar o que der para subir até 31/10' AS o_que_fazer "
            f"FROM {G}.projeto_situacao_atual WHERE status = 'em_andamento' "
            f"AND (lower(tipo_projeto) LIKE '%commerce%' OR lower(tipo_projeto) LIKE '%checkout%' OR lower(tipo_projeto) LIKE '%marketplace%')"
        )

    exemplos = [
        (
            "Quais projetos estão atrasados, e de quais clientes?",
            f"SELECT projeto_id, nome_projeto, cliente, ferramenta, situacao, ROUND(spi, 2) AS spi, ROUND(cpi, 2) AS cpi, atraso_projetado_dias "
            f"FROM {G}.projeto_situacao_atual WHERE status = 'em_andamento' AND situacao IN ('crítico', 'atenção') ORDER BY least(spi, cpi)",
        ),
        (
            "Quanto esse atraso vai me custar?",
            f"SELECT MEASURE(estouro_previsto) AS estouro_previsto, MEASURE(projetos_em_risco) AS projetos_em_risco, "
            f"MEASURE(margem_projetada) AS margem_projetada FROM {G}.mv_projetos",
        ),
        (
            "Tenho gente parada enquanto outro projeto pede gente?",
            f"SELECT u.colaborador_id, u.nome, u.papel, u.projeto_id, p.projeto, ROUND(SUM(u.horas_apontadas) / SUM(u.horas_disponiveis), 3) AS utilizacao, "
            f"SUM(u.horas_ociosas) AS horas_ociosas, SUM(u.custo_ocioso) AS custo_ocioso "
            f"FROM {G}.utilizacao_pessoa_semana u JOIN {G}.projeto_situacao_atual p ON p.projeto_id = u.projeto_id "
            f"WHERE u.semana > DATE'2026-07-24' "
            f"GROUP BY ALL HAVING SUM(u.horas_apontadas) / SUM(u.horas_disponiveis) < 0.2 ORDER BY utilizacao",
        ),
        (
            "Por que o projeto PRJ-011 atrasou?",
            f"SELECT s.causa_bloqueio, COUNT(*) AS semanas, SUM(coalesce(s.dias_impacto, 0)) AS dias_de_impacto, MAX(p.spi) AS spi_do_projeto "
            f"FROM {G}.status_estruturado s JOIN {G}.projeto_situacao_atual p ON p.projeto_id = s.projeto_id "
            f"WHERE s.projeto_id = 'PRJ-011' AND s.data_status >= DATE'2026-07-18' AND s.causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado') "
            f"GROUP BY s.causa_bloqueio ORDER BY semanas DESC",
        ),
        (
            "Qual fornecedor mais atrasa?",
            f"SELECT fornecedor, COUNT(*) AS entregas, ROUND(AVG(prazo_real_dias / prazo_prometido_dias), 2) AS fator_atraso, "
            f"COUNT_IF(em_atraso) AS em_atraso_hoje FROM {S}.entregas_fornecedor GROUP BY fornecedor ORDER BY fator_atraso DESC LIMIT 1",
        ),
        (
            "Quais projetos ficam travados pelo change freeze da Black Friday?",
            f"SELECT projeto_id, nome_projeto, cliente, tipo_projeto, ROUND(spi, 2) AS spi FROM {G}.projeto_situacao_atual "
            f"WHERE status = 'em_andamento' AND (lower(tipo_projeto) LIKE '%commerce%' OR lower(tipo_projeto) LIKE '%checkout%' "
            f"OR lower(tipo_projeto) LIKE '%marketplace%') ORDER BY spi",
        ),
        (
            "O que vai dar errado no próximo mês, e o que eu faço agora?",
            sql_proximo_mes,
        ),
        (
            "Quais clientes têm projetos críticos?",
            f"SELECT cliente, COUNT(*) AS projetos_criticos FROM {G}.projeto_situacao_atual "
            f"WHERE status = 'em_andamento' AND situacao = 'crítico' GROUP BY cliente ORDER BY projetos_criticos DESC",
        ),
        (
            "Qual projeto tem o maior estouro previsto?",
            f"SELECT projeto_id, nome_projeto, cliente, estouro_previsto FROM {G}.projeto_situacao_atual "
            f"WHERE status = 'em_andamento' ORDER BY estouro_previsto DESC LIMIT 1",
        ),
        (
            "Quais projetos estão com farol verde mas estão atrasados?",
            f"SELECT projeto_id, nome_projeto, cliente, ROUND(spi, 2) AS spi, farol_do_gerente, farol_calculado "
            f"FROM {G}.projeto_situacao_atual WHERE melancia ORDER BY spi",
        ),
    ]

    if com_score:
        exemplos.append(
            (
                "Qual a chance de o PRJ-024 estourar no próximo mês?",
                f"SELECT s.projeto_id, p.projeto, p.cliente, p.situacao, ROUND(s.prob_estouro_30d, 2) AS prob_estouro_30d, s.faixa_risco, "
                f"s.principais_fatores FROM {G}.score_estouro_30d s JOIN {G}.projeto_situacao_atual p ON p.projeto_id = s.projeto_id "
                f"WHERE s.projeto_id = 'PRJ-024' AND s.data_referencia = (SELECT MAX(data_referencia) FROM {G}.score_estouro_30d)",
            )
        )

    tabelas = [
        f"{G}.fato_projeto_semana",
        f"{G}.projeto_situacao_atual",
        f"{G}.status_estruturado",
        f"{G}.utilizacao_pessoa_semana",
        f"{S}.entregas_fornecedor",
    ]
    if com_score:
        tabelas.append(f"{G}.score_estouro_30d")

    metricas = [f"{G}.mv_projetos"]

    return {
        "version": 2,
        "config": {
            "sample_questions": [{"id": ident("b1", i), "question": [q]} for i, q in enumerate(PERGUNTAS, 1)]
        },
        "data_sources": {
            "tables": [{"identifier": t} for t in sorted(tabelas)],
            "metric_views": [{"identifier": m} for m in sorted(metricas)],
        },
        "instructions": {
            "text_instructions": [{"id": ident("c1", 1), "content": [l + "\n" for l in instrucoes]}],
            "example_question_sqls": [
                {"id": ident("d1", i), "question": [q], "sql": [s]} for i, (q, s) in enumerate(exemplos, 1)
            ],
        },
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default="DEFAULT", help="Profile do Databricks CLI")
    args = ap.parse_args()

    com_score = tem_score_estouro(args.profile)
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    SAIDA.write_text(json.dumps(montar(com_score), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"ok: {SAIDA} (score_estouro_30d={com_score})")


if __name__ == "__main__":
    main()
