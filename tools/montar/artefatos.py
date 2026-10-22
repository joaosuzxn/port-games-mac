"""Artefatos de terceiros (template do wrapper, engine Wine) guardados num cache e conferidos por SHA-256."""
import hashlib
import json
import shutil
import urllib.request
from dataclasses import dataclass
from pathlib import Path

CACHE_PADRAO = Path.home() / "Library/Caches/portcarros/artefatos"
FONTES_LOCAIS_PADRAO = [
    Path.home() / "Library/Application Support/Sikarugir/Engines",
    Path.home() / "Library/Application Support/Sikarugir/Template",
]


class ArtefatoInvalido(Exception):
    pass


@dataclass(frozen=True)
class Artefato:
    nome: str
    arquivo: str
    sha256: str
    url: str | None


def sha256_arquivo(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for bloco in iter(lambda: f.read(1 << 20), b""):
            h.update(bloco)
    return h.hexdigest()


def carregar_artefatos(caminho: Path) -> dict[str, Artefato]:
    dados = json.loads(Path(caminho).read_text(encoding="utf-8"))
    return {nome: Artefato(nome, a["arquivo"], a["sha256"], a.get("url")) for nome, a in dados.items()}


def _instalar(origem: Path, destino: Path, esperado: str) -> bool:
    """Copia para um temporário ao lado do destino e só promove se o hash bater."""
    temp = destino.with_name(destino.name + ".parcial")
    shutil.copyfile(origem, temp)
    if sha256_arquivo(temp) != esperado:
        temp.unlink()
        return False
    temp.replace(destino)
    return True


def _baixar(url: str, destino: Path, esperado: str) -> bool:
    temp = destino.with_name(destino.name + ".parcial")
    with urllib.request.urlopen(url) as resp, open(temp, "wb") as f:
        shutil.copyfileobj(resp, f, 1 << 20)
    if sha256_arquivo(temp) != esperado:
        temp.unlink()
        return False
    temp.replace(destino)
    return True


def garantir_artefato(a: Artefato, cache: Path, fontes_locais: list[Path]) -> Path:
    cache.mkdir(parents=True, exist_ok=True)
    destino = cache / a.arquivo
    if destino.exists():
        if sha256_arquivo(destino) == a.sha256:
            return destino
        destino.unlink()

    procurados = []
    for fonte in fontes_locais:
        candidato = Path(fonte) / a.arquivo
        procurados.append(str(candidato))
        if candidato.is_file() and _instalar(candidato, destino, a.sha256):
            return destino
    if a.url:
        procurados.append(a.url)
        if _baixar(a.url, destino, a.sha256):
            return destino
    raise ArtefatoInvalido(
        f"artefato {a.nome} ({a.arquivo}) não encontrado com o SHA-256 esperado. Procurado em: " + ", ".join(procurados)
    )
