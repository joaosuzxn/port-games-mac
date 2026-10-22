"""Prefixo Windows dentro do .app: criação pelo launcher, cópia do jogo, drive de CD, registro e saves."""
import hashlib
import os
import re
import shutil
import signal
import subprocess
import time
from pathlib import Path
from typing import Iterable

from receita import ChaveRegistro, Receita

COMANDO_STEAMCMD = (
    'steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$PWD/jogo" '
    '+login <sua-conta> +app_update 331160 validate +quit'
)


class JogoInvalido(Exception):
    pass


class PrefixoFalhou(Exception):
    pass


# --- Wine do bundle -------------------------------------------------------------------

def _launcher(app: Path) -> Path:
    return app / "Contents" / "MacOS" / "wineskinlauncher"


def _processos_do_app(app: Path) -> list[int]:
    saida = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout
    alvo = str(app.resolve())
    return [int(l.split(None, 1)[0]) for l in saida.splitlines() if alvo in l and str(os.getpid()) != l.split(None, 1)[0]]


def parar_wine(app: Path, tempo_max: float = 30.0) -> None:
    """Para o wineserver do app e espera todos os processos dele sumirem (o registro só é gravado no fim)."""
    subprocess.run([str(_launcher(app)), "WSS-wineserverkill"], capture_output=True)
    limite = time.monotonic() + tempo_max
    while _processos_do_app(app):
        if time.monotonic() > limite:
            for pid in _processos_do_app(app):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            time.sleep(1)
            break
        time.sleep(0.5)


def criar_prefixo(app: Path, tempo_max: float = 300.0) -> Path:
    try:
        subprocess.run([str(_launcher(app)), "WSS-wineprefixcreate"], capture_output=True, timeout=tempo_max)
    except subprocess.TimeoutExpired:
        parar_wine(app, tempo_max=10)
        raise PrefixoFalhou(f"o launcher não terminou de criar o prefixo em {tempo_max:g} s (travou em algum diálogo?)") from None
    parar_wine(app)
    prefixo = app / "Contents" / "SharedSupport" / "prefix"
    if not (prefixo / "system.reg").is_file():
        raise PrefixoFalhou(f"o launcher não criou o prefixo em {prefixo}")
    return prefixo


# --- Jogo -------------------------------------------------------------------------------

def _sha1(p: Path) -> str:
    h = hashlib.sha1()
    with open(p, "rb") as f:
        for bloco in iter(lambda: f.read(1 << 20), b""):
            h.update(bloco)
    return h.hexdigest()


def conferir_jogo(origem: Path, receita: Receita) -> None:
    """Levanta JogoInvalido se faltar a pasta, o executável, ou se o executável não for o build esperado."""
    exe = origem / receita.exe_origem
    if not origem.is_dir() or not exe.is_file():
        raise JogoInvalido(
            f"arquivos do jogo não encontrados em {origem} (falta {receita.exe_origem}). "
            f"Baixe com: {COMANDO_STEAMCMD}"
        )
    if _sha1(exe) != receita.sha1_exe:
        raise JogoInvalido(
            f"{exe} não é o build esperado (SHA-1 diferente de {receita.sha1_exe}). "
            f"Baixe de novo com: {COMANDO_STEAMCMD}"
        )


def copiar_jogo(origem: Path, destino: Path, receita: Receita) -> None:
    conferir_jogo(origem, receita)
    exe = origem / receita.exe_origem
    excluir = set(receita.excluir)
    shutil.copytree(origem, destino, ignore=lambda pasta, nomes: excluir & set(nomes) if Path(pasta) == origem else set())
    shutil.copy2(exe, destino / receita.exe_destino)


def configurar_drive_cd(prefixo: Path, alvo_relativo: str, rotulo: str) -> None:
    link = prefixo / "dosdevices" / "d:"
    if link.is_symlink() or link.exists():
        link.unlink()
    os.symlink(f"../drive_c/{alvo_relativo}", link)
    (prefixo / "drive_c" / alvo_relativo / ".windows-label").write_text(rotulo + "\n")


# --- Registro ---------------------------------------------------------------------------

def _escapar(texto: str) -> str:
    return texto.replace("\\", "\\\\").replace('"', '\\"')


def _linha_valor(nome: str, valor) -> str:
    if isinstance(valor, int):
        return f'"{_escapar(nome)}"=dword:{valor:08x}'
    return f'"{_escapar(nome)}"="{_escapar(valor)}"'


def _aplicar_chave(linhas: list[str], chave: ChaveRegistro) -> list[str]:
    cabecalho = "[" + _escapar(chave.chave) + "]"
    inicio = next((i for i, l in enumerate(linhas) if l.lower().startswith(cabecalho.lower())), None)
    if inicio is None:
        novas = ["", f"{cabecalho} {int(time.time())}"] + [_linha_valor(n, v) for n, v in chave.valores.items()]
        return linhas + novas
    fim = next((i for i in range(inicio + 1, len(linhas)) if linhas[i].startswith("[")), len(linhas))
    secao = linhas[inicio + 1:fim]
    for nome, valor in chave.valores.items():
        prefixo_nome = f'"{_escapar(nome)}"='.lower()
        secao = [l for l in secao if not l.lower().startswith(prefixo_nome)]
        while secao and secao[-1] == "":
            secao.pop()
        secao.append(_linha_valor(nome, valor))
    if fim < len(linhas):
        secao.append("")
    return linhas[:inicio + 1] + secao + linhas[fim:]


def aplicar_registro(prefixo: Path, chaves: Iterable[ChaveRegistro]) -> None:
    """Grava as chaves em system.reg/user.reg. O Wine do app precisa estar parado (parar_wine)."""
    for chave in chaves:
        arquivo = prefixo / ("system.reg" if chave.colmeia == "system" else "user.reg")
        linhas = arquivo.read_text(encoding="utf-8").split("\n")
        if linhas and linhas[-1] == "":
            linhas.pop()
        arquivo.write_text("\n".join(_aplicar_chave(linhas, chave)) + "\n", encoding="utf-8")


# --- Saves ------------------------------------------------------------------------------

def ligar_saves(prefixo: Path, pasta: str, documentos_mac: Path) -> None:
    """Liga só Documents/<pasta> do Windows a ~/Documents/<pasta>; o resto de Documents fica isolado no prefixo."""
    alvo = documentos_mac / pasta
    alvo.mkdir(parents=True, exist_ok=True)
    for usuario in (prefixo / "drive_c" / "users").iterdir():
        if usuario.name == "Public" or not usuario.is_dir():
            continue
        docs = usuario / "Documents"
        if docs.is_symlink():
            docs.unlink()
        docs.mkdir(exist_ok=True)
        link = docs / pasta
        if link.is_symlink():
            link.unlink()
        elif link.exists():
            shutil.rmtree(link)
        os.symlink(alvo, link)


# --- Relocação --------------------------------------------------------------------------

def relocar_registro(prefixo: Path, de: Path, para: Path) -> None:
    """Troca o caminho do bundle `de` pelo de `para` em system.reg/user.reg (o Wine grava caminhos absolutos
    de fontes, InstallSource do wine-mono etc.). O Wine do app precisa estar parado (parar_wine)."""
    pares = []
    for origem in dict.fromkeys([str(de), str(de.resolve())]):
        pares.append(("Z:" + origem.replace("/", "\\\\"), "Z:" + str(para).replace("/", "\\\\")))  # forma do .reg: Z:\\Users\\...
        pares.append(("Z:" + origem.replace("/", "\\"), "Z:" + str(para).replace("/", "\\")))
        pares.append((origem, str(para)))  # barras normais (Z:/... ou /...)
    for nome in ("system.reg", "user.reg"):
        arquivo = prefixo / nome
        if not arquivo.is_file():
            continue
        texto = arquivo.read_text(encoding="utf-8")
        for velho, novo in pares:
            texto = re.sub(re.escape(velho) + r"(?![\w-])", lambda _: novo, texto)
        arquivo.write_text(texto, encoding="utf-8")
