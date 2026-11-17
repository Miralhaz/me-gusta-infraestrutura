#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MeGusta - analisar-jtl.py

Le o JTL (CSV) gerado pelo JMeter e imprime estatisticas por amostra:
contagem, erros, percentis de latencia e vazao.

Uso:
    python3 analisar-jtl.py resultados.jtl
    python3 analisar-jtl.py resultados.jtl --formato markdown
    python3 analisar-jtl.py resultados.jtl --formato json
    python3 analisar-jtl.py resultados.jtl --max-erro-pct 1 --max-p95-ms 3000

Saida:
    texto      tabela legivel no terminal (padrao)
    markdown   tabela pronta para colar no relatorio
    json       objeto com todas as metricas (para automacao)

Codigos de saida:
    0  metricas dentro dos limites
    2  algum limite violado (erro %, p95 ou vazao)
    1  erro de leitura/argumentos

Os limites sao verificados no consolidado e em cada amostra com pelo menos
--min-amostras amostras (padrao 20). Isso evita reprovar a sonda /health, que
roda em baixa frequencia de proposito.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Iterable


@dataclass
class Metricas:
    label: str
    total: int = 0
    erros: int = 0
    latencias: list[int] = field(default_factory=list)
    codigos: Counter = field(default_factory=Counter)
    inicio_ms: int | None = None
    fim_ms: int | None = None

    def adicionar(self, elapsed: int, sucesso: bool, codigo: str, ts: int) -> None:
        self.total += 1
        if not sucesso:
            self.erros += 1
        self.latencias.append(elapsed)
        self.codigos[codigo] += 1
        fim = ts + elapsed
        if self.inicio_ms is None or ts < self.inicio_ms:
            self.inicio_ms = ts
        if self.fim_ms is None or fim > self.fim_ms:
            self.fim_ms = fim

    def resumo(self, janela_s: float | None = None) -> dict:
        lat = sorted(self.latencias)
        if janela_s is None:
            janela_s = 0.0
            if self.inicio_ms is not None and self.fim_ms is not None:
                janela_s = max((self.fim_ms - self.inicio_ms) / 1000.0, 0.001)

        return {
            "amostra": self.label,
            "total": self.total,
            "erros": self.erros,
            "erro_pct": round(100.0 * self.erros / self.total, 3) if self.total else 0.0,
            "media_ms": round(sum(lat) / len(lat), 2) if lat else 0.0,
            "p50_ms": percentil(lat, 50),
            "p90_ms": percentil(lat, 90),
            "p95_ms": percentil(lat, 95),
            "p99_ms": percentil(lat, 99),
            "min_ms": lat[0] if lat else 0,
            "max_ms": lat[-1] if lat else 0,
            "vazao_s": round(self.total / janela_s, 3) if self.total else 0.0,
            "codigos": dict(sorted(rotular_codigos(self.codigos).items())),
        }


def rotulo_codigo(codigo: str) -> str:
    """Encurta codigos nao HTTP para a tabela nao ficar ilegivel."""
    if re.fullmatch(r"\d{3}", codigo):
        return codigo
    if "HttpHostConnectException" in codigo:
        return "ERR:conexao"
    if "SocketTimeoutException" in codigo:
        return "ERR:timeout"
    if "UnknownHostException" in codigo:
        return "ERR:dns"
    if "SSL" in codigo or "Handshake" in codigo:
        return "ERR:tls"
    if codigo.startswith("Non HTTP"):
        return "ERR:outro"
    return codigo[:24]


def rotular_codigos(codigos: Counter) -> Counter:
    agregados: Counter = Counter()
    for codigo, quantidade in codigos.items():
        agregados[rotulo_codigo(codigo)] += quantidade
    return agregados


def percentil(ordenados: Iterable[int], p: float) -> float:
    """Percentil por posto mais proximo (nearest-rank)."""
    valores = list(ordenados)
    if not valores:
        return 0.0
    k = max(0, math.ceil(p / 100.0 * len(valores)) - 1)
    return float(valores[k])


def ler_jtl(caminho: Path) -> list[Metricas]:
    por_label: dict[str, Metricas] = {}

    with caminho.open("r", encoding="utf-8-sig", newline="") as fh:
        leitor = csv.DictReader(fh)
        if not leitor.fieldnames:
            raise ValueError("JTL vazio ou sem cabecalho")

        colunas = set(leitor.fieldnames or [])
        if not {"timeStamp", "elapsed", "label"}.issubset(colunas):
            raise ValueError(
                "JTL nao parece ser CSV do JMeter (faltam timeStamp/elapsed/label). "
                f"Colunas encontradas: {sorted(colunas)}"
            )

        for linha in leitor:
            try:
                ts = int(linha["timeStamp"])
                elapsed = int(float(linha["elapsed"]))
            except (TypeError, ValueError):
                continue

            label = (linha.get("label") or "sem-label").strip() or "sem-label"
            codigo = (linha.get("responseCode") or "").strip()

            sucesso_raw = (linha.get("success") or "").strip().lower()
            if sucesso_raw in {"true", "false"}:
                sucesso = sucesso_raw == "true"
            else:
                try:
                    sucesso = int(codigo) < 400
                except ValueError:
                    sucesso = False

            metrica = por_label.setdefault(label, Metricas(label))
            metrica.adicionar(elapsed, sucesso, codigo or "?", ts)

    if not por_label:
        raise ValueError("nenhuma amostra valida encontrada no JTL")

    return list(por_label.values())


def consolidar(metricas: list[Metricas]) -> Metricas:
    total = Metricas("TOTAL (todas as amostras)")
    for m in metricas:
        total.total += m.total
        total.erros += m.erros
        total.latencias.extend(m.latencias)
        total.codigos.update(m.codigos)
        if m.inicio_ms is not None and (total.inicio_ms is None or m.inicio_ms < total.inicio_ms):
            total.inicio_ms = m.inicio_ms
        if m.fim_ms is not None and (total.fim_ms is None or m.fim_ms > total.fim_ms):
            total.fim_ms = m.fim_ms
    return total


def formatar_texto(resumos: list[dict]) -> str:
    cabecalho = (
        f"{'Amostra':<38} {'#':>6} {'Err':>5} {'%Err':>7} "
        f"{'Media':>9} {'p50':>8} {'p90':>8} {'p95':>8} {'p99':>8} "
        f"{'Min':>8} {'Max':>8} {'Req/s':>8}  Codigos"
    )
    linhas = [cabecalho, "-" * len(cabecalho)]
    for r in resumos:
        codigos = ",".join(f"{c}:{n}" for c, n in r["codigos"].items())
        linhas.append(
            f"{r['amostra'][:38]:<38} {r['total']:>6} {r['erros']:>5} {r['erro_pct']:>7.2f} "
            f"{r['media_ms']:>9.1f} {r['p50_ms']:>8.0f} {r['p90_ms']:>8.0f} "
            f"{r['p95_ms']:>8.0f} {r['p99_ms']:>8.0f} "
            f"{r['min_ms']:>8} {r['max_ms']:>8} {r['vazao_s']:>8.2f}  {codigos}"
        )
    return "\n".join(linhas)


def formatar_markdown(resumos: list[dict]) -> str:
    linhas = [
        "| Amostra | # | Erros | % Erros | Média (ms) | p50 | p90 | p95 | p99 | Mín | Máx | Req/s | Códigos |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for r in resumos:
        codigos = ", ".join(f"{c}:{n}" for c, n in r["codigos"].items())
        linhas.append(
            f"| {r['amostra']} | {r['total']} | {r['erros']} | {r['erro_pct']:.2f}% | "
            f"{r['media_ms']:.1f} | {r['p50_ms']:.0f} | {r['p90_ms']:.0f} | "
            f"{r['p95_ms']:.0f} | {r['p99_ms']:.0f} | {r['min_ms']} | {r['max_ms']} | "
            f"{r['vazao_s']:.2f} | {codigos} |"
        )
    return "\n".join(linhas)


def avaliar(resumos: list[dict], args: argparse.Namespace) -> list[str]:
    falhas: list[str] = []
    for r in resumos:
        # O consolidado sempre entra; amostras individuais so com volume minimo.
        if not r["amostra"].startswith("TOTAL") and r["total"] < args.min_amostras:
            continue
        if args.max_erro_pct is not None and r["erro_pct"] > args.max_erro_pct:
            falhas.append(
                f"{r['amostra']}: erro {r['erro_pct']:.2f}% > {args.max_erro_pct:.2f}%"
            )
        if args.max_p95_ms is not None and r["p95_ms"] > args.max_p95_ms:
            falhas.append(
                f"{r['amostra']}: p95 {r['p95_ms']:.0f} ms > {args.max_p95_ms:.0f} ms"
            )
        if args.min_vazao is not None and r["vazao_s"] < args.min_vazao:
            falhas.append(
                f"{r['amostra']}: vazao {r['vazao_s']:.2f} req/s < {args.min_vazao:.2f} req/s"
            )
    return falhas


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Analisa o JTL do JMeter e resume latencia, erros e vazao."
    )
    parser.add_argument("jtl", help="arquivo .jtl (CSV) gerado pelo JMeter")
    parser.add_argument(
        "--formato", choices=("texto", "markdown", "json"), default="texto",
        help="formato de saida (padrao: texto)",
    )
    parser.add_argument("--max-erro-pct", type=float, default=None,
                        help="reprova se %% de erro passar deste valor")
    parser.add_argument("--max-p95-ms", type=float, default=None,
                        help="reprova se p95 passar deste valor (ms)")
    parser.add_argument("--min-vazao", type=float, default=None,
                        help="reprova se a vazao ficar abaixo deste valor (req/s)")
    parser.add_argument("--min-amostras", type=int, default=20,
                        help="minimo de amostras para avaliar uma linha (padrao: 20)")
    args = parser.parse_args(argv)

    caminho = Path(args.jtl)
    if not caminho.is_file():
        print(f"ERRO: JTL nao encontrado: {caminho}", file=sys.stderr)
        return 1

    try:
        metricas = ler_jtl(caminho)
    except (OSError, ValueError) as exc:
        print(f"ERRO ao ler {caminho}: {exc}", file=sys.stderr)
        return 1

    # Ordena pelo inicio da amostra para manter uma leitura previsivel.
    metricas.sort(key=lambda m: m.inicio_ms or 0)
    total = consolidar(metricas)

    # Vazao sempre sobre a janela global do teste: a janela de uma amostra
    # isolada (ex.: 1 sonda /health) produziria req/s sem significado.
    janela_global = None
    if total.inicio_ms is not None and total.fim_ms is not None:
        janela_global = max((total.fim_ms - total.inicio_ms) / 1000.0, 0.001)
    resumos = [m.resumo(janela_global) for m in metricas] + [total.resumo(janela_global)]

    if args.formato == "json":
        print(json.dumps({
            "arquivo": str(caminho),
            "gerado_em": datetime.now().isoformat(timespec="seconds"),
            "amostras": resumos,
        }, ensure_ascii=False, indent=2))
    elif args.formato == "markdown":
        print(formatar_markdown(resumos))
    else:
        print(f"JTL: {caminho.resolve()}")
        print(formatar_texto(resumos))

    falhas = avaliar(resumos, args)
    if falhas:
        print("\nLIMITES VIOLADOS:", file=sys.stderr)
        for f in falhas:
            print(f"  - {f}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
