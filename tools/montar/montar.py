"""Monta o .app de um jogo a partir da receita.

Uso: python3 tools/montar/montar.py carros [--saida build] [--cache DIR] [--jogo DIR] [--instalar]
"""
import argparse
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

from artefatos import CACHE_PADRAO, FONTES_LOCAIS_PADRAO, ArtefatoInvalido, carregar_artefatos, garantir_artefato
from bundle import configurar_info_plist, montar_bundle, remover_configuracao
from icone import extrair_icone
from prefixo import (JogoInvalido, PrefixoFalhou, aplicar_registro, configurar_drive_cd, conferir_jogo, copiar_jogo,
                     criar_prefixo, ligar_saves, parar_wine)
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


def montar(receita_nome: str, saida: Path, cache: Path, pasta_jogo: Path | None, instalar: bool) -> Path:
    receita = carregar_receita(AQUI / "receitas" / f"{receita_nome}.json")
    jogo = pasta_jogo or (RAIZ / receita.pasta_jogo)
    _etapa(f"Conferindo os arquivos do jogo em {jogo}")
    conferir_jogo(jogo, receita)  # antes de tocar em build/

    _etapa("Conferindo template e engine Wine")
    artefatos = carregar_artefatos(AQUI / "artefatos.json")
    template = garantir_artefato(artefatos["template"], cache, FONTES_LOCAIS_PADRAO)
    engine = garantir_artefato(artefatos["engine"], cache, FONTES_LOCAIS_PADRAO)

    _etapa(f"Montando {receita.nome_app}.app")
    app = montar_bundle(template, engine, saida, receita)
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

    if instalar:
        destino = Path("/Applications") / app.name
        _etapa(f"Instalando em {destino}")
        if destino.exists():
            shutil.rmtree(destino)
        shutil.copytree(app, destino, symlinks=True)
        app = destino
    _etapa(f"Pronto: {app}")
    return app


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Monta o .app de um jogo Windows a partir da receita.")
    p.add_argument("receita", help="nome da receita em tools/montar/receitas (ex.: carros)")
    p.add_argument("--saida", type=Path, default=RAIZ / "build")
    p.add_argument("--cache", type=Path, default=CACHE_PADRAO)
    p.add_argument("--jogo", type=Path, default=None, help="pasta com os arquivos do jogo (padrão: a da receita)")
    p.add_argument("--instalar", action="store_true", help="copia o app para /Applications")
    args = p.parse_args(argv)
    try:
        montar(args.receita, args.saida, args.cache, args.jogo, args.instalar)
    except (ReceitaInvalida, JogoInvalido, ArtefatoInvalido, PrefixoFalhou) as e:
        print(f"Erro: {e}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(f"Erro: comando falhou: {' '.join(map(str, e.cmd))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
