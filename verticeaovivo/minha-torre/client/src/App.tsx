import { useEffect, useMemo, useState } from 'react';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  GenieChat,
  Input,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  useAnalyticsQuery,
} from '@databricks/appkit-ui/react';

interface ScoreLinha {
  projeto_id: string;
  prob_estouro: number;
  faixa_risco: string;
}

interface ScoreEstouroResponse {
  disponivel: boolean;
  linhas: ScoreLinha[];
}

const formatMoeda = (valor: unknown): string => {
  const num = Number(valor);
  if (!Number.isFinite(num)) return 'R$ 0,00';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(num);
};

const formatMoedaCompacta = (valor: unknown): string => {
  const num = Number(valor);
  if (!Number.isFinite(num)) return 'R$ 0,00';
  if (Math.abs(num) >= 1_000_000) {
    const mi = num / 1_000_000;
    return `R$ ${mi.toLocaleString('pt-BR', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })} mi`;
  }
  return formatMoeda(num);
};

const formatIndice = (valor: unknown): string => {
  const num = Number(valor);
  if (!Number.isFinite(num)) return '0,00';
  return num.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
};

const formatNumero = (valor: unknown, casas = 1): string => {
  const num = Number(valor);
  if (!Number.isFinite(num)) return '0';
  return num.toLocaleString('pt-BR', {
    minimumFractionDigits: casas,
    maximumFractionDigits: casas,
  });
};

const LABELS_CAUSA: Record<string, string> = {
  falta_sre: 'Falta de SRE',
  rotatividade: 'Rotatividade',
  mudanca_escopo: 'Mudança de escopo',
  bug_retrabalho: 'Bugs / retrabalho',
  dependencia_fornecedor: 'Dependência de fornecedor',
  aprovacao_cliente: 'Aprovação do cliente',
  change_freeze: 'Change freeze',
  sem_bloqueio: 'Sem bloqueio',
  nao_reportado: 'Não reportado',
};

const formatCausa = (causa: string): string => LABELS_CAUSA[causa] ?? causa;

function parseScoreResponse(raw: unknown): ScoreEstouroResponse {
  if (!raw || typeof raw !== 'object') {
    return { disponivel: false, linhas: [] };
  }
  const obj = raw as Record<string, unknown>;
  const disponivel = Boolean(obj.disponivel);
  const rawLinhas = Array.isArray(obj.linhas) ? obj.linhas : [];
  const linhas: ScoreLinha[] = rawLinhas.map((item) => {
    const row = (item && typeof item === 'object' ? item : {}) as Record<string, unknown>;
    const probBruta = row.prob_estouro ?? row.probabilidade ?? row.score ?? 0;
    const projetoId =
      typeof row.projeto_id === 'string' || typeof row.projeto_id === 'number'
        ? String(row.projeto_id)
        : '';
    const faixaRisco =
      typeof row.faixa_risco === 'string' || typeof row.faixa_risco === 'number'
        ? String(row.faixa_risco)
        : '';
    return {
      projeto_id: projetoId,
      prob_estouro: Number(probBruta),
      faixa_risco: faixaRisco,
    };
  });
  return { disponivel, linhas };
}

function SituacaoBadge({ situacao }: { situacao: string }) {
  if (situacao === 'crítico') {
    return (
      <Badge variant="destructive" className="font-semibold">
        Crítico
      </Badge>
    );
  }
  if (situacao === 'atenção') {
    return (
      <Badge
        variant="outline"
        className="bg-warning/20 text-foreground border-warning font-semibold"
      >
        Atenção
      </Badge>
    );
  }
  return (
    <Badge
      variant="outline"
      className="bg-success/15 text-foreground border-success/40 font-medium"
    >
      OK
    </Badge>
  );
}

type AbaAtiva = 'risco' | 'simulador' | 'perguntar';

export default function App() {
  const [aba, setAba] = useState<AbaAtiva>('risco');
  const emptyParams = useMemo(() => ({}), []);

  const kpisQuery = useAnalyticsQuery('kpis', emptyParams);
  const projetosQuery = useAnalyticsQuery('projetos_risco', emptyParams);
  const pessoasQuery = useAnalyticsQuery('pessoas_ociosas', emptyParams);

  const [scoreState, setScoreState] = useState<ScoreEstouroResponse>({
    disponivel: false,
    linhas: [],
  });
  const [scoreLoading, setScoreLoading] = useState<boolean>(true);

  useEffect(() => {
    let ativo = true;
    fetch('/api/score-estouro')
      .then((r) => r.json())
      .then((json: unknown) => {
        if (!ativo) return;
        setScoreState(parseScoreResponse(json));
        setScoreLoading(false);
      })
      .catch(() => {
        if (!ativo) return;
        setScoreState({ disponivel: false, linhas: [] });
        setScoreLoading(false);
      });
    return () => {
      ativo = false;
    };
  }, []);

  const scorePorProjeto = useMemo(() => {
    const mapa = new Map<string, ScoreLinha>();
    for (const item of scoreState.linhas) {
      if (item.projeto_id) {
        mapa.set(item.projeto_id, item);
      }
    }
    return mapa;
  }, [scoreState.linhas]);

  const altoRisco30d = useMemo(() => {
    if (!scoreState.disponivel) return null;
    return scoreState.linhas.filter(
      (l) => l.faixa_risco.trim().toLowerCase() === 'alto',
    ).length;
  }, [scoreState]);

  // Estado do Simulador
  const pessoasOciosas = useMemo(() => pessoasQuery.data ?? [], [pessoasQuery.data]);
  const [colaboradorSelecionadoId, setColaboradorSelecionadoId] = useState<string>('');
  const [projetoDestinoId, setProjetoDestinoId] = useState<string>('');
  const [horasOnboarding, setHorasOnboarding] = useState<number>(40);

  const pessoaSelecionada = useMemo(() => {
    if (!pessoasOciosas.length) return null;
    return (
      pessoasOciosas.find((p) => p.colaborador_id === colaboradorSelecionadoId) ??
      pessoasOciosas[0]
    );
  }, [pessoasOciosas, colaboradorSelecionadoId]);

  const projetosDestinoOrdenados = useMemo(() => {
    const todos = projetosQuery.data ?? [];
    const emRisco = todos.filter(
      (p) => p.situacao === 'atenção' || p.situacao === 'crítico',
    );
    const ehSre = pessoaSelecionada?.papel?.toLowerCase() === 'sre';

    return [...emRisco].sort((a, b) => {
      if (ehSre) {
        const diffSre = Number(b.dias_falta_sre) - Number(a.dias_falta_sre);
        if (diffSre !== 0) return diffSre;
      } else {
        const diffRot = Number(b.dias_rotatividade) - Number(a.dias_rotatividade);
        if (diffRot !== 0) return diffRot;
      }
      const pesoA = a.situacao === 'crítico' ? 0 : 1;
      const pesoB = b.situacao === 'crítico' ? 0 : 1;
      if (pesoA !== pesoB) return pesoA - pesoB;
      return Number(a.spi) - Number(b.spi);
    });
  }, [projetosQuery.data, pessoaSelecionada]);

  const projetoDestinoSelecionado = useMemo(() => {
    if (!projetosDestinoOrdenados.length) return null;
    return (
      projetosDestinoOrdenados.find((p) => p.projeto_id === projetoDestinoId) ??
      projetosDestinoOrdenados[0]
    );
  }, [projetosDestinoOrdenados, projetoDestinoId]);

  const simulacao = useMemo(() => {
    if (!pessoaSelecionada || !projetoDestinoSelecionado) return null;

    const horasParadasSemana = Number(pessoaSelecionada.horas_paradas_semana);
    const custoOciosoSemana = Number(pessoaSelecionada.custo_ocioso_semana);
    const custoHora = Number(pessoaSelecionada.custo_hora);
    const ehSre = pessoaSelecionada.papel.toLowerCase() === 'sre';

    const diasFaltaSre = Number(projetoDestinoSelecionado.dias_falta_sre);
    const diasRotatividade = Number(projetoDestinoSelecionado.dias_rotatividade);
    const diasCausaPrincipal = Number(
      projetoDestinoSelecionado.dias_impacto_causa_90d,
    );

    let diasImpactoCausa90d = diasCausaPrincipal;
    let causaConsiderada = projetoDestinoSelecionado.causa_principal_90d;

    if (ehSre && diasFaltaSre > 0) {
      diasImpactoCausa90d = diasFaltaSre;
      causaConsiderada = 'falta_sre';
    } else if (!ehSre && diasRotatividade > 0) {
      diasImpactoCausa90d = diasRotatividade;
      causaConsiderada = 'rotatividade';
    }

    const horasMes = horasParadasSemana * 4;
    const ociosidadeEvitada = custoOciosoSemana * 4;
    const diasRecuperados = (diasImpactoCausa90d / 90) * 30;
    const horasOnb = Number.isFinite(horasOnboarding) && horasOnboarding >= 0 ? horasOnboarding : 0;
    const custoMobilizacao = horasOnb * custoHora;
    const saldo = ociosidadeEvitada - custoMobilizacao;

    return {
      horasParadasSemana,
      custoOciosoSemana,
      custoHora,
      horasMes,
      ociosidadeEvitada,
      diasImpactoCausa90d,
      causaConsiderada,
      diasRecuperados,
      horasOnb,
      custoMobilizacao,
      saldo,
    };
  }, [pessoaSelecionada, projetoDestinoSelecionado, horasOnboarding]);

  const kpiRow = kpisQuery.data?.[0];

  return (
    <div className="min-h-screen bg-background text-foreground flex flex-col">
      <header className="border-b bg-card px-4 md:px-6 py-3 flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <h1 className="text-xl font-bold tracking-tight text-foreground">
            Projeto Farol
          </h1>
          <span className="text-xs text-muted-foreground hidden sm:inline">
            Vértice Tecnologia · Fotografia em 16/10/2026
          </span>
        </div>

        <nav className="flex items-center gap-2" aria-label="Menu principal">
          <Button
            variant={aba === 'risco' ? 'default' : 'ghost'}
            size="sm"
            onClick={() => setAba('risco')}
          >
            Projetos em risco
          </Button>
          <Button
            variant={aba === 'simulador' ? 'default' : 'ghost'}
            size="sm"
            onClick={() => setAba('simulador')}
          >
            Simulador
          </Button>
          <Button
            variant={aba === 'perguntar' ? 'default' : 'ghost'}
            size="sm"
            onClick={() => setAba('perguntar')}
          >
            Perguntar
          </Button>
        </nav>
      </header>

      <main className="flex-1 p-4 md:p-6 max-w-7xl w-full mx-auto space-y-6">
        {aba === 'risco' ? (
          <section className="space-y-6" aria-label="Projetos em risco">
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm font-medium text-muted-foreground">
                    Projetos em risco
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {kpisQuery.loading ? (
                    <Skeleton className="h-8 w-24" />
                  ) : kpisQuery.error ? (
                    <p className="text-sm text-destructive">{kpisQuery.error}</p>
                  ) : (
                    <>
                      <div className="text-2xl font-bold text-destructive">
                        {Number(kpiRow?.projetos_em_risco ?? 0)}
                      </div>
                      <p className="text-xs text-muted-foreground mt-1">
                        {Number(kpiRow?.projetos_criticos ?? 0)} críticos ·{' '}
                        {Number(kpiRow?.melancias ?? 0)} melancias 🍉 (de{' '}
                        {Number(kpiRow?.projetos_andamento ?? 0)} ativos)
                      </p>
                    </>
                  )}
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm font-medium text-muted-foreground">
                    Estouro previsto
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {kpisQuery.loading ? (
                    <Skeleton className="h-8 w-32" />
                  ) : kpisQuery.error ? (
                    <p className="text-sm text-destructive">{kpisQuery.error}</p>
                  ) : (
                    <>
                      <div className="text-2xl font-bold text-foreground">
                        {formatMoedaCompacta(kpiRow?.estouro_previsto ?? 0)}
                      </div>
                      <p className="text-xs text-muted-foreground mt-1">
                        {formatMoeda(kpiRow?.estouro_previsto ?? 0)} (EAC − orçamento)
                      </p>
                    </>
                  )}
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm font-medium text-muted-foreground">
                    Carteira
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {kpisQuery.loading ? (
                    <Skeleton className="h-8 w-32" />
                  ) : kpisQuery.error ? (
                    <p className="text-sm text-destructive">{kpisQuery.error}</p>
                  ) : (
                    <>
                      <div className="text-2xl font-bold text-foreground">
                        {formatMoedaCompacta(kpiRow?.carteira ?? 0)}
                      </div>
                      <p className="text-xs text-muted-foreground mt-1">
                        {formatMoeda(kpiRow?.carteira ?? 0)} em andamento
                      </p>
                    </>
                  )}
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm font-medium text-muted-foreground">
                    Alto risco em 30 dias
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {scoreLoading ? (
                    <Skeleton className="h-8 w-16" />
                  ) : (
                    <>
                      <div className="text-2xl font-bold text-foreground">
                        {altoRisco30d !== null ? altoRisco30d : '—'}
                      </div>
                      <p className="text-xs text-muted-foreground mt-1">
                        {scoreState.disponivel
                          ? "Projetos com faixa_risco = 'alto' (gold.score_estouro_30d)"
                          : 'Modelo preditivo (gold.score_estouro_30d) ainda não publicado'}
                      </p>
                    </>
                  )}
                </CardContent>
              </Card>
            </div>

            <Card>
              <CardHeader>
                <CardTitle className="text-base font-semibold">
                  Projetos em andamento (do pior para o melhor)
                </CardTitle>
              </CardHeader>
              <CardContent>
                {projetosQuery.loading ? (
                  <div className="space-y-2">
                    <Skeleton className="h-8 w-full" />
                    <Skeleton className="h-8 w-full" />
                    <Skeleton className="h-8 w-full" />
                  </div>
                ) : projetosQuery.error ? (
                  <div className="p-4 rounded-md bg-destructive/10 text-destructive text-sm">
                    Erro ao carregar projetos: {projetosQuery.error}
                  </div>
                ) : !projetosQuery.data?.length ? (
                  <div className="text-sm text-muted-foreground py-6 text-center">
                    Nenhum projeto em andamento encontrado.
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Projeto</TableHead>
                          <TableHead>Situação</TableHead>
                          <TableHead className="text-right">SPI</TableHead>
                          <TableHead className="text-right">CPI</TableHead>
                          <TableHead className="text-right">Estouro previsto</TableHead>
                          <TableHead className="text-right">Atraso (dias)</TableHead>
                          <TableHead>Farol (Gerente × Calc.)</TableHead>
                          <TableHead>Causa 90d &amp; Impacto</TableHead>
                          <TableHead className="text-right">P(estouro)</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {projetosQuery.data.map((row) => {
                          const scoreItem = scorePorProjeto.get(row.projeto_id);
                          const ehMelancia = Boolean(row.melancia);
                          const diasSre = Number(row.dias_falta_sre);
                          const diasRot = Number(row.dias_rotatividade);

                          return (
                            <TableRow key={row.projeto_id}>
                              <TableCell>
                                <div className="font-medium text-foreground">
                                  {row.projeto}
                                </div>
                                <div className="text-xs text-muted-foreground">
                                  {row.cliente} · Ger.: {row.gerente_projeto}
                                </div>
                              </TableCell>
                              <TableCell>
                                <SituacaoBadge situacao={row.situacao} />
                              </TableCell>
                              <TableCell className="text-right font-mono">
                                {formatIndice(row.spi)}
                              </TableCell>
                              <TableCell className="text-right font-mono">
                                {formatIndice(row.cpi)}
                              </TableCell>
                              <TableCell className="text-right font-mono">
                                {formatMoeda(row.estouro_previsto)}
                              </TableCell>
                              <TableCell className="text-right font-mono">
                                {Number(row.atraso_projetado_dias)}d
                              </TableCell>
                              <TableCell>
                                <span className="text-sm">
                                  {row.farol_do_gerente}
                                  {ehMelancia ? ' 🍉' : ''} × {row.farol_calculado}
                                </span>
                              </TableCell>
                              <TableCell>
                                <div className="text-sm">
                                  {formatCausa(row.causa_principal_90d)}
                                </div>
                                {(diasSre > 0 || diasRot > 0) && (
                                  <div className="text-xs text-muted-foreground">
                                    {diasSre > 0 ? `Falta SRE: ${diasSre}d` : ''}
                                    {diasSre > 0 && diasRot > 0 ? ' · ' : ''}
                                    {diasRot > 0 ? `Rotatividade: ${diasRot}d` : ''}
                                  </div>
                                )}
                              </TableCell>
                              <TableCell className="text-right font-mono">
                                {scoreState.disponivel && scoreItem
                                  ? `${formatNumero(
                                      Number(scoreItem.prob_estouro) <= 1
                                        ? Number(scoreItem.prob_estouro) * 100
                                        : Number(scoreItem.prob_estouro),
                                      1,
                                    )}%`
                                  : '—'}
                              </TableCell>
                            </TableRow>
                          );
                        })}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </CardContent>
            </Card>
          </section>
        ) : aba === 'simulador' ? (
          <section className="space-y-6" aria-label="Simulador de realocação">
            <Card>
              <CardHeader>
                <CardTitle className="text-base font-semibold">
                  Simulador de Realocação de Pessoas Ociosas
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-6">
                {pessoasQuery.loading || projetosQuery.loading ? (
                  <div className="space-y-3">
                    <Skeleton className="h-10 w-full" />
                    <Skeleton className="h-10 w-full" />
                  </div>
                ) : pessoasQuery.error || projetosQuery.error ? (
                  <div className="p-4 rounded-md bg-destructive/10 text-destructive text-sm">
                    Erro ao carregar dados do simulador:{' '}
                    {pessoasQuery.error ?? projetosQuery.error}
                  </div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="select-pessoa">
                        Pessoa ociosa (&lt; 20% nas últimas 12 semanas)
                      </Label>
                      <Select
                        value={pessoaSelecionada?.colaborador_id ?? ''}
                        onValueChange={(val) => setColaboradorSelecionadoId(val)}
                      >
                        <SelectTrigger id="select-pessoa">
                          <SelectValue placeholder="Selecione uma pessoa" />
                        </SelectTrigger>
                        <SelectContent>
                          {pessoasOciosas.map((p) => (
                            <SelectItem key={p.colaborador_id} value={p.colaborador_id}>
                              {p.colaborador_id} · {p.nome} ({p.papel.toUpperCase()} ·{' '}
                              {formatNumero(p.utilizacao_media_pct, 1)}% uso no{' '}
                              {p.projeto_atual_id})
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="select-projeto">
                        Projeto destino (atenção ou crítico)
                      </Label>
                      <Select
                        value={projetoDestinoSelecionado?.projeto_id ?? ''}
                        onValueChange={(val) => setProjetoDestinoId(val)}
                      >
                        <SelectTrigger id="select-projeto">
                          <SelectValue placeholder="Selecione o projeto destino" />
                        </SelectTrigger>
                        <SelectContent>
                          {projetosDestinoOrdenados.map((proj) => (
                            <SelectItem key={proj.projeto_id} value={proj.projeto_id}>
                              {proj.projeto_id} · {proj.nome_projeto} ({proj.situacao} ·
                              SPI {formatIndice(proj.spi)}
                              {Number(proj.dias_falta_sre) > 0
                                ? ` · Falta SRE: ${Number(proj.dias_falta_sre)}d`
                                : ''}
                              )
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="input-onboarding">
                        Horas de onboarding (mobilização)
                      </Label>
                      <Input
                        id="input-onboarding"
                        type="number"
                        min={0}
                        step={1}
                        value={horasOnboarding}
                        onChange={(e) => setHorasOnboarding(Number(e.target.value))}
                      />
                    </div>
                  </div>
                )}

                {simulacao && pessoaSelecionada && projetoDestinoSelecionado && (
                  <>
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 pt-2">
                      <Card>
                        <CardHeader className="pb-2">
                          <CardTitle className="text-xs font-medium text-muted-foreground">
                            Horas no mês (× 4 semanas)
                          </CardTitle>
                        </CardHeader>
                        <CardContent>
                          <div className="text-xl font-bold text-foreground">
                            {formatNumero(simulacao.horasMes, 2)} h
                          </div>
                          <p className="text-xs text-muted-foreground mt-1">
                            {formatNumero(simulacao.horasParadasSemana, 2)} h/sem × 4
                          </p>
                        </CardContent>
                      </Card>

                      <Card>
                        <CardHeader className="pb-2">
                          <CardTitle className="text-xs font-medium text-muted-foreground">
                            Ociosidade que deixa de ser paga
                          </CardTitle>
                        </CardHeader>
                        <CardContent>
                          <div className="text-xl font-bold text-foreground">
                            {formatMoeda(simulacao.ociosidadeEvitada)}
                          </div>
                          <p className="text-xs text-muted-foreground mt-1">
                            {formatMoeda(simulacao.custoOciosoSemana)}/sem × 4
                          </p>
                        </CardContent>
                      </Card>

                      <Card>
                        <CardHeader className="pb-2">
                          <CardTitle className="text-xs font-medium text-muted-foreground">
                            Dias de cronograma recuperados
                          </CardTitle>
                        </CardHeader>
                        <CardContent>
                          <div className="text-xl font-bold text-foreground">
                            {formatNumero(simulacao.diasRecuperados, 1)} dias
                          </div>
                          <p className="text-xs text-muted-foreground mt-1">
                            {Number(simulacao.diasImpactoCausa90d)}d (
                            {formatCausa(simulacao.causaConsiderada)}) ÷ 90 × 30
                          </p>
                        </CardContent>
                      </Card>

                      <Card>
                        <CardHeader className="pb-2">
                          <CardTitle className="text-xs font-medium text-muted-foreground">
                            Custo de mobilização
                          </CardTitle>
                        </CardHeader>
                        <CardContent>
                          <div className="text-xl font-bold text-foreground">
                            {formatMoeda(simulacao.custoMobilizacao)}
                          </div>
                          <p className="text-xs text-muted-foreground mt-1">
                            {simulacao.horasOnb} h × {formatMoeda(simulacao.custoHora)}/h
                          </p>
                        </CardContent>
                      </Card>

                      <Card>
                        <CardHeader className="pb-2">
                          <CardTitle className="text-xs font-medium text-muted-foreground">
                            Saldo no 1º mês
                          </CardTitle>
                        </CardHeader>
                        <CardContent>
                          <div
                            className={`text-xl font-bold ${
                              simulacao.saldo >= 0 ? 'text-foreground' : 'text-destructive'
                            }`}
                          >
                            {formatMoeda(simulacao.saldo)}
                          </div>
                          <p className="text-xs text-muted-foreground mt-1">
                            Ociosidade evitada − mobilização
                          </p>
                        </CardContent>
                      </Card>
                    </div>

                    <details className="rounded-md border bg-muted/40 p-4 text-sm">
                      <summary className="cursor-pointer font-medium text-foreground">
                        Como a conta é feita (memória de cálculo)
                      </summary>
                      <div className="mt-3 space-y-2 text-muted-foreground">
                        <p>
                          <strong>1. Horas disponíveis no mês:</strong>{' '}
                          {pessoaSelecionada.nome} ({pessoaSelecionada.papel.toUpperCase()}
                          , atualmente em {pessoaSelecionada.projeto_atual_id}) teve em
                          média{' '}
                          <strong>
                            {formatNumero(simulacao.horasParadasSemana, 2)} horas paradas
                            por semana
                          </strong>{' '}
                          nas últimas 12 semanas. Em 4 semanas: {formatNumero(simulacao.horasParadasSemana, 2)} × 4 ={' '}
                          <strong>{formatNumero(simulacao.horasMes, 2)} horas</strong>.
                        </p>
                        <p>
                          <strong>2. Ociosidade que deixa de ser paga:</strong> custo
                          ocioso médio semanal de{' '}
                          <strong>{formatMoeda(simulacao.custoOciosoSemana)}</strong> × 4
                          semanas ={' '}
                          <strong>{formatMoeda(simulacao.ociosidadeEvitada)}</strong>{' '}
                          (custo/hora de {formatMoeda(simulacao.custoHora)}).
                        </p>
                        <p>
                          <strong>3. Dias de cronograma recuperados em 30 dias:</strong> o
                          projeto destino{' '}
                          <strong>{projetoDestinoSelecionado.projeto}</strong> acumulou{' '}
                          <strong>{Number(simulacao.diasImpactoCausa90d)} dias</strong> de
                          impacto por{' '}
                          <strong>{formatCausa(simulacao.causaConsiderada)}</strong> nos
                          últimos 90 dias. Projetando para 30 dias:{' '}
                          {Number(simulacao.diasImpactoCausa90d)} ÷ 90 × 30 ={' '}
                          <strong>
                            {formatNumero(simulacao.diasRecuperados, 1)} dias recuperados
                          </strong>
                          .
                        </p>
                        <p>
                          <strong>4. Mobilização (onboarding):</strong>{' '}
                          {simulacao.horasOnb} horas de rampa ×{' '}
                          {formatMoeda(simulacao.custoHora)}/h ={' '}
                          <strong>{formatMoeda(simulacao.custoMobilizacao)}</strong>.
                        </p>
                        <p>
                          <strong>5. Saldo líquido no 1º mês:</strong>{' '}
                          {formatMoeda(simulacao.ociosidadeEvitada)} −{' '}
                          {formatMoeda(simulacao.custoMobilizacao)} ={' '}
                          <strong>{formatMoeda(simulacao.saldo)}</strong>.
                        </p>
                      </div>
                    </details>
                  </>
                )}
              </CardContent>
            </Card>
          </section>
        ) : (
          <section className="space-y-6 max-w-4xl mx-auto" aria-label="Perguntar ao Genie">
            <div>
              <h2 className="text-2xl font-bold text-foreground">Perguntar</h2>
              <p className="text-sm text-muted-foreground mt-1">
                Genie &ldquo;Farol · Diretoria&rdquo;: projetos em atraso, custo do estouro, pessoas
                ociosas, causa do atraso nos status semanais e riscos do próximo mês. Experimente:{' '}
                <i>&ldquo;Por que o PRJ-011 atrasou?&rdquo;</i>
              </p>
            </div>
            <div className="h-[min(640px,72vh)] border rounded-lg overflow-hidden bg-card">
              <GenieChat alias="default" />
            </div>
          </section>
        )}
      </main>
    </div>
  );
}
