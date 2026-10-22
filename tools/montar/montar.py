"""Monta o .app de um jogo a partir da receita.

Uso: python3 tools/montar/montar.py carros [--saida build] [--cache DIR] [--jogo DIR] [--instalar]
"""
import argparse
import urllib.error
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from artefatos import CACHE_PADRAO, FONTES_LOCAIS_PADRAO, ArtefatoInvalido, carregar_artefatos, garantir_artefato
from bundle import configurar_info_plist, montar_bundle, remover_configuracao, substituir_app
from icone import extrair_icone
from prefixo import (JogoInvalido, PrefixoFalhou, aplicar_registro, configurar_drive_cd, conferir_jogo, copiar_jogo,
                     criar_prefixo, ligar_saves, parar_wine, relocar_registro)
from receita import ReceitaInvalida, carregar_receita

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]


def _etapa(texto: str) -> None:
    print(f"• {texto}", flush=True)


def _definir_icone(app: Path, icns: Path) -> None:
    plist = app / "Contents" / "Info.plist"
    with open(plist, "rb") as f:
        dados = plistlib.load(f)
    dados["CFBundleIconFile"] = icns.name
    with open(plist, "wb") as f:
        plistlib.dump(dados, f)


DIRETORIO_INSTALACAO_PADRAO = Path("/Applications")


def _bundle_id_de(app: Path) -> str | None:
    try:
        with open(app / "Contents" / "Info.plist", "rb") as f:
            return plistlib.load(f).get("CFBundleIdentifier")
    except (OSError, plistlib.InvalidFileException, ValueError):
        return None


def _conferir_destino(destino: Path, receita) -> None:
    """Só deixa trocar um app que já é deste jogo (mesmo CFBundleIdentifier)."""
    if not (destino.exists() or destino.is_symlink()):
        return
    atual = _bundle_id_de(destino)
    if atual != receita.bundle_id:
        raise PrefixoFalhou(
            f"{destino} já existe e não é o app deste jogo (CFBundleIdentifier {atual!r}, esperado {receita.bundle_id!r}); "
            "não vou apagar. Mova ou remova esse app e rode de novo."
        )


def _prefixo_de(app: Path) -> Path:
    return app / "Contents" / "SharedSupport" / "prefix"


def instalar_app(app: Path, diretorio: Path, receita) -> Path:
    """Copia para `<dir>/.<App>.app.novo`, ajusta os caminhos do registro e troca no fim."""
    destino = diretorio / app.name
    _conferir_destino(destino, receita)
    diretorio.mkdir(parents=True, exist_ok=True)
    novo = diretorio / f".{app.name}.novo"
    shutil.rmtree(novo, ignore_errors=True)
    try:
        shutil.copytree(app, novo, symlinks=True)
        relocar_registro(_prefixo_de(novo), app, destino)
        if destino.exists():
            parar_wine(destino)
        substituir_app(novo, destino)
    finally:
        shutil.rmtree(novo, ignore_errors=True)
    return destino


def montar(receita_nome: str, saida: Path, cache: Path, pasta_jogo: Path | None, instalar: bool,
           diretorio_instalacao: Path = DIRETORIO_INSTALACAO_PADRAO) -> Path:
    receita = carregar_receita(AQUI / "receitas" / f"{receita_nome}.json")
    jogo = pasta_jogo or (RAIZ / receita.pasta_jogo)
    _etapa(f"Conferindo os arquivos do jogo em {jogo}")
    conferir_jogo(jogo, receita)  # antes de tocar em build/
    final = saida / f"{receita.nome_app}.app"
    if instalar:
        _conferir_destino(diretorio_instalacao / final.name, receita)

    _etapa("Conferindo template e engine Wine")
    artefatos = carregar_artefatos(AQUI / "artefatos.json")
    template = garantir_artefato(artefatos["template"], cache, FONTES_LOCAIS_PADRAO)
    engine = garantir_artefato(artefatos["engine"], cache, FONTES_LOCAIS_PADRAO)

    if final.exists():
        parar_wine(final)  # um Wine rodando do app antigo seria sobrescrito/atrapalhado
    saida.mkdir(parents=True, exist_ok=True)
    for abandonado in saida.glob(".montando-*"):
        shutil.rmtree(abandonado, ignore_errors=True)
    trabalho = Path(tempfile.mkdtemp(prefix=".montando-", dir=saida))  # tudo é montado aqui; o app final só muda no fim
    try:
        _etapa(f"Montando {receita.nome_app}.app")
        app = montar_bundle(template, engine, trabalho, receita)
        _etapa("Criando o Windows de dentro do app (prefixo)")
        prefixo = criar_prefixo(app)
        configurar_info_plist(app / "Contents" / "Info.plist", receita)  # o launcher reescreve o identificador ao criar o prefixo

        _etapa("Copiando o jogo")
        destino_jogo = prefixo / "drive_c" / "Games" / receita.nome_app
        copiar_jogo(jogo, destino_jogo, receita)
        if receita.rotulo_cd:
            configurar_drive_cd(prefixo, f"Games/{receita.nome_app}", receita.rotulo_cd)
        aplicar_registro(prefixo, receita.registro)
        if receita.pasta_saves:
            ligar_saves(prefixo, receita.pasta_saves, Path.home() / "Documents")

        _etapa("Ícone e acabamento")
        icns = app / "Contents" / "Resources" / f"{receita.nome_app}.icns"
        if extrair_icone(destino_jogo / receita.exe_destino, icns):
            _definir_icone(app, icns)
        parar_wine(app)
        remover_configuracao(app)
        subprocess.run(["xattr", "-dr", "com.apple.quarantine", str(app)], capture_output=True)
        relocar_registro(prefixo, app, final)  # o Wine gravou o caminho da pasta de trabalho

        substituir_app(app, final)
    finally:
        shutil.rmtree(trabalho, ignore_errors=True)
    app = final

    if instalar:
        _etapa(f"Instalando em {diretorio_instalacao / app.name}")
        app = instalar_app(app, diretorio_instalacao, receita)
    _etapa(f"Pronto: {app}")
    return app


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Monta o .app de um jogo Windows a partir da receita.")
    p.add_argument("receita", help="nome da receita em tools/montar/receitas (ex.: carros)")
    p.add_argument("--saida", type=Path, default=RAIZ / "build")
    p.add_argument("--cache", type=Path, default=CACHE_PADRAO)
    p.add_argument("--jogo", type=Path, default=None, help="pasta com os arquivos do jogo (padrão: a da receita)")
    p.add_argument("--instalar", action="store_true", help="copia o app para /Applications (ou --destino-instalacao)")
    p.add_argument("--destino-instalacao", type=Path, default=DIRETORIO_INSTALACAO_PADRAO,
                   help="pasta onde --instalar põe o app (padrão: /Applications)")
    args = p.parse_args(argv)
    try:
        montar(args.receita, args.saida, args.cache, args.jogo, args.instalar, args.destino_instalacao)
    except (ReceitaInvalida, JogoInvalido, ArtefatoInvalido, PrefixoFalhou) as e:
        print(f"Erro: {e}", file=sys.stderr)
        return 1
    except (OSError, RuntimeError, urllib.error.URLError) as e:
        print(f"Erro: {e}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(f"Erro: comando falhou: {' '.join(map(str, e.cmd))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
