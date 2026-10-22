"""Monta o .app a partir do template do Sikarugir e da engine Wine, configurado pela receita."""
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

from receita import Receita

# Chave do Info.plist do Sikarugir ligada por cada renderizador; wined3d = todas desligadas.
CHAVES_RENDERIZADOR = {"d9vk": "D9VK", "d3dmetal": "D3DMETAL"}


def _extrair(tar_xz: Path, destino: Path) -> Path:
    """Extrai com o tar do sistema (preserva links simbólicos dos frameworks) e devolve a raiz única do arquivo."""
    destino.mkdir(parents=True, exist_ok=True)
    subprocess.run(["tar", "-xJf", str(tar_xz), "-C", str(destino)], check=True)
    raizes = [p for p in destino.iterdir() if not p.name.startswith(".")]
    if len(raizes) != 1:
        raise RuntimeError(f"{tar_xz.name}: esperava uma pasta raiz, achei {[p.name for p in raizes]}")
    return raizes[0]


def configurar_info_plist(plist: Path, receita: Receita) -> None:
    with open(plist, "rb") as f:
        dados = plistlib.load(f)
    dados["CFBundleName"] = receita.nome_app
    dados["CFBundleIdentifier"] = receita.bundle_id
    dados["Program Name and Path"] = f"/Games/{receita.nome_app}/{receita.exe_destino}"
    for chave in ("D9VK", "DXVK", "D3DMETAL"):
        dados[chave] = 0
    if receita.renderizador in CHAVES_RENDERIZADOR:
        dados[CHAVES_RENDERIZADOR[receita.renderizador]] = 1
    dados["Debug Mode"] = 0
    dados["WINEDEBUG"] = "-all"
    dados["Symlinks In User Folder"] = 0
    with open(plist, "wb") as f:
        plistlib.dump(dados, f)


def remover_configuracao(app: Path) -> None:
    """Tira o Configure.app do bundle final. Só depois de criar o prefixo: o launcher lê remakedefaults.reg dele."""
    shutil.rmtree(app / "Contents" / "Configure.app", ignore_errors=True)


def montar_bundle(template: Path, engine_tar: Path, saida: Path, receita: Receita) -> Path:
    saida.mkdir(parents=True, exist_ok=True)
    final = saida / f"{receita.nome_app}.app"
    with tempfile.TemporaryDirectory(dir=saida, prefix=".montando-") as trabalho:
        trabalho = Path(trabalho)
        app = _extrair(template, trabalho / "template")
        contents = app / "Contents"
        wine = _extrair(engine_tar, trabalho / "engine")
        destino_wine = contents / "SharedSupport" / "wine"
        if destino_wine.exists():
            shutil.rmtree(destino_wine)
        wine.rename(destino_wine)
        configurar_info_plist(contents / "Info.plist", receita)

        if final.exists():
            shutil.rmtree(final)
        app.rename(final)
    return final


def substituir_app(novo: Path, final: Path) -> None:
    """Põe `novo` no lugar de `final` por rename (mesmo volume). O app antigo só é apagado depois que o novo está no lugar."""
    velho = None
    if final.exists() or final.is_symlink():
        velho = final.with_name(f".{final.name}.velho")
        shutil.rmtree(velho, ignore_errors=True)
        final.rename(velho)
    try:
        novo.rename(final)
    except BaseException:
        if velho is not None:
            velho.rename(final)
        raise
    if velho is not None:
        shutil.rmtree(velho, ignore_errors=True)
