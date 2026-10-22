"""Third-party artifacts (wrapper template, Wine engine) kept in a cache and checked by SHA-256."""
import hashlib
import json
import shutil
import urllib.request
from dataclasses import dataclass
from pathlib import Path

DEFAULT_CACHE = Path.home() / "Library/Caches/portcarros/artefatos"
DEFAULT_LOCAL_SOURCES = [
    Path.home() / "Library/Application Support/Sikarugir/Engines",
    Path.home() / "Library/Application Support/Sikarugir/Template",
]


class InvalidArtifact(Exception):
    pass


@dataclass(frozen=True)
class Artifact:
    name: str
    file: str
    sha256: str
    url: str | None


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def load_artifacts(path: Path) -> dict[str, Artifact]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return {name: Artifact(name, a["file"], a["sha256"], a.get("url")) for name, a in data.items()}


def _install(source: Path, target: Path, expected: str) -> bool:
    """Copies to a temporary file next to the target and only promotes it if the hash matches."""
    temp = target.with_name(target.name + ".partial")
    shutil.copyfile(source, temp)
    if sha256_file(temp) != expected:
        temp.unlink()
        return False
    temp.replace(target)
    return True


def _download(url: str, target: Path, expected: str) -> bool:
    temp = target.with_name(target.name + ".partial")
    try:
        with urllib.request.urlopen(url) as resp, open(temp, "wb") as f:
            shutil.copyfileobj(resp, f, 1 << 20)
        if sha256_file(temp) != expected:
            return False
        temp.replace(target)
        return True
    finally:
        temp.unlink(missing_ok=True)


def ensure_artifact(a: Artifact, cache: Path, local_sources: list[Path]) -> Path:
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / a.file
    if target.exists():
        if sha256_file(target) == a.sha256:
            return target
        target.unlink()

    searched = []
    for source in local_sources:
        candidate = Path(source) / a.file
        searched.append(str(candidate))
        if candidate.is_file() and _install(candidate, target, a.sha256):
            return target
    if a.url:
        searched.append(a.url)
        if _download(a.url, target, a.sha256):
            return target
    raise InvalidArtifact(
        f"artifact {a.name} ({a.file}) not found with the expected SHA-256. Searched in: " + ", ".join(searched)
    )
