"""Receita de um jogo: tudo que é específico dele para montar o .app (o resto do motor não conhece o jogo)."""
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

RENDERIZADORES = ("d9vk", "wined3d", "d3dmetal")
COLMEIAS = ("system", "user")


class ReceitaInvalida(Exception):
    pass


@dataclass(frozen=True)
class ChaveRegistro:
    colmeia: Literal["system", "user"]
    chave: str
    valores: dict  # nome -> str ("..." no .reg) ou int (dword)

    def __hash__(self):
        return hash((self.colmeia, self.chave, tuple(sorted(self.valores.items()))))


@dataclass(frozen=True)
class Receita:
    nome: str
    nome_app: str
    bundle_id: str
    pasta_jogo: str
    exe_origem: str
    exe_destino: str
    sha1_exe: str
    excluir: tuple
    rotulo_cd: str | None
    pasta_saves: str | None
    renderizador: Literal["d9vk", "wined3d", "d3dmetal"]
    registro: tuple
    arquivos_obrigatorios: tuple = ()


def _exigir(dados: dict, campo: str, tipo, opcional: bool = False):
    if campo not in dados:
        if opcional:
            return None
        raise ReceitaInvalida(f"campo obrigatório ausente: {campo}")
    valor = dados[campo]
    if valor is None and opcional:
        return None
    if not isinstance(valor, tipo):
        raise ReceitaInvalida(f"campo {campo} com tipo errado: esperado {tipo.__name__}")
    return valor


def _ler_chave(item: dict) -> ChaveRegistro:
    colmeia = _exigir(item, "colmeia", str)
    if colmeia not in COLMEIAS:
        raise ReceitaInvalida(f"registro.colmeia inválida: {colmeia} (use {', '.join(COLMEIAS)})")
    valores = _exigir(item, "valores", dict)
    for nome, v in valores.items():
        if isinstance(v, bool) or not isinstance(v, (str, int)):
            raise ReceitaInvalida(f"registro.valores.{nome} deve ser texto ou inteiro")
        if isinstance(v, int) and not 0 <= v <= 0xFFFFFFFF:
            raise ReceitaInvalida(f"registro.valores.{nome} fora da faixa de um dword (0 a 4294967295)")
    return ChaveRegistro(colmeia, _exigir(item, "chave", str), dict(valores))


def carregar_receita(caminho: Path) -> Receita:
    try:
        dados = json.loads(Path(caminho).read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise ReceitaInvalida(f"receita não encontrada: {caminho}") from None
    except json.JSONDecodeError as e:
        raise ReceitaInvalida(f"receita com JSON inválido: {caminho}: {e}") from None

    sha1 = _exigir(dados, "sha1_exe", str)
    if not re.fullmatch(r"[0-9a-f]{40}", sha1):
        raise ReceitaInvalida("campo sha1_exe deve ter 40 caracteres hexadecimais minúsculos")
    renderizador = _exigir(dados, "renderizador", str)
    if renderizador not in RENDERIZADORES:
        raise ReceitaInvalida(f"campo renderizador inválido: {renderizador} (use {', '.join(RENDERIZADORES)})")

    obrigatorios = _exigir(dados, "arquivos_obrigatorios", list, opcional=True) or []
    for item in obrigatorios:
        if not isinstance(item, str) or not item or item.startswith("/") or ".." in Path(item).parts:
            raise ReceitaInvalida(f"arquivos_obrigatorios: caminho inválido (use relativo à pasta do jogo): {item!r}")

    return Receita(
        nome=_exigir(dados, "nome", str),
        nome_app=_exigir(dados, "nome_app", str),
        bundle_id=_exigir(dados, "bundle_id", str),
        pasta_jogo=_exigir(dados, "pasta_jogo", str),
        exe_origem=_exigir(dados, "exe_origem", str),
        exe_destino=_exigir(dados, "exe_destino", str),
        sha1_exe=sha1,
        excluir=tuple(_exigir(dados, "excluir", list)),
        rotulo_cd=_exigir(dados, "rotulo_cd", str, opcional=True),
        pasta_saves=_exigir(dados, "pasta_saves", str, opcional=True),
        renderizador=renderizador,
        registro=tuple(_ler_chave(i) for i in _exigir(dados, "registro", list)),
        arquivos_obrigatorios=tuple(obrigatorios),
    )
