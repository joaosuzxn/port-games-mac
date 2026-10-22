"""Windows prefix inside the .app: creation by the launcher, game copy, CD drive, registry and saves."""
import hashlib
import os
import re
import shutil
import signal
import subprocess
import time
from pathlib import Path
from typing import Iterable

from recipe import Recipe, RegistryKey

STEAMCMD_COMMAND = (
    'steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$PWD/jogo" '
    '+login <your-account> +app_update 331160 validate +quit'
)


class InvalidGame(Exception):
    pass


class PrefixFailed(Exception):
    pass


# --- Wine in the bundle ---------------------------------------------------------------

def _launcher(app: Path) -> Path:
    return app / "Contents" / "MacOS" / "wineskinlauncher"


def _app_processes(app: Path) -> list[int]:
    """PIDs of processes whose EXECUTABLE is inside the bundle (the command starts with the app path).
    Anything that merely mentions the app in an argument does not count."""
    output = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout
    target = str(app.resolve()) + "/"
    mine = str(os.getpid())
    pids = []
    for line in output.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0] != mine and parts[1].startswith(target):
            pids.append(int(parts[0]))
    return pids


def stop_wine(app: Path, max_time: float = 30.0) -> None:
    """Stops the app's wineserver and waits for all of its processes to go away (the registry is only written at the end).
    The Windows processes (C:\\...) go down together with the wineserver (WSS-wineserverkill)."""
    try:
        subprocess.run([str(_launcher(app)), "WSS-wineserverkill"], capture_output=True)
    except OSError:
        pass  # app without a launcher: it is still worth looking for processes
    deadline = time.monotonic() + max_time
    while _app_processes(app):
        if time.monotonic() > deadline:
            for pid in _app_processes(app):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            time.sleep(1)
            remaining = _app_processes(app)
            if remaining:
                raise PrefixFailed(f"could not stop the app's Wine processes (PIDs {remaining})")
            break
        time.sleep(0.5)


def create_prefix(app: Path, max_time: float = 300.0) -> Path:
    try:
        subprocess.run([str(_launcher(app)), "WSS-wineprefixcreate"], capture_output=True, timeout=max_time)
    except subprocess.TimeoutExpired:
        stop_wine(app, max_time=10)
        raise PrefixFailed(f"the launcher did not finish creating the prefix within {max_time:g} s (stuck on a dialog?)") from None
    stop_wine(app)
    prefix = app / "Contents" / "SharedSupport" / "prefix"
    if not (prefix / "system.reg").is_file():
        raise PrefixFailed(f"the launcher did not create the prefix at {prefix}")
    return prefix


# --- Game -------------------------------------------------------------------------------

def _sha1(p: Path) -> str:
    h = hashlib.sha1()
    with open(p, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def check_game(source: Path, recipe: Recipe) -> None:
    """Raises InvalidGame if the folder or the executable is missing, or if the executable is not the expected build."""
    exe = source / recipe.exe_source
    if not source.is_dir() or not exe.is_file():
        raise InvalidGame(
            f"game files not found in {source} ({recipe.exe_source} is missing). "
            f"Download with: {STEAMCMD_COMMAND}"
        )
    if _sha1(exe) != recipe.exe_sha1:
        raise InvalidGame(
            f"{exe} is not the expected build (SHA-1 differs from {recipe.exe_sha1}). "
            f"Download again with: {STEAMCMD_COMMAND}"
        )
    missing = [f for f in recipe.required_files if not (source / f).is_file()]
    if missing:
        raise InvalidGame(
            f"incomplete game in {source} (missing: {', '.join(missing)}). "
            f"Download/validate with: {STEAMCMD_COMMAND}"
        )


def copy_game(source: Path, target: Path, recipe: Recipe) -> None:
    check_game(source, recipe)
    exe = source / recipe.exe_source
    exclude = set(recipe.exclude)
    shutil.copytree(source, target, ignore=lambda folder, names: exclude & set(names) if Path(folder) == source else set())
    shutil.copy2(exe, target / recipe.exe_target)


def setup_cd_drive(prefix: Path, relative_target: str, label: str) -> None:
    link = prefix / "dosdevices" / "d:"
    if link.is_symlink() or link.exists():
        link.unlink()
    os.symlink(f"../drive_c/{relative_target}", link)
    (prefix / "drive_c" / relative_target / ".windows-label").write_text(label + "\n")


# --- Registry ---------------------------------------------------------------------------

def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def _value_line(name: str, value) -> str:
    if isinstance(value, int):
        return f'"{_escape(name)}"=dword:{value:08x}'
    return f'"{_escape(name)}"="{_escape(value)}"'


def _apply_key(lines: list[str], key: RegistryKey) -> list[str]:
    header = "[" + _escape(key.key) + "]"
    start = next((i for i, l in enumerate(lines) if l.lower().startswith(header.lower())), None)
    if start is None:
        new_lines = ["", f"{header} {int(time.time())}"] + [_value_line(n, v) for n, v in key.values.items()]
        return lines + new_lines
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    section = lines[start + 1:end]
    for name, value in key.values.items():
        name_prefix = f'"{_escape(name)}"='.lower()
        section = [l for l in section if not l.lower().startswith(name_prefix)]
        while section and section[-1] == "":
            section.pop()
        section.append(_value_line(name, value))
    if end < len(lines):
        section.append("")
    return lines[:start + 1] + section + lines[end:]


def apply_registry(prefix: Path, keys: Iterable[RegistryKey]) -> None:
    """Writes the keys into system.reg/user.reg. The app's Wine must be stopped (stop_wine)."""
    for key in keys:
        file = prefix / ("system.reg" if key.hive == "system" else "user.reg")
        lines = file.read_text(encoding="utf-8").split("\n")
        if lines and lines[-1] == "":
            lines.pop()
        file.write_text("\n".join(_apply_key(lines, key)) + "\n", encoding="utf-8")


# --- Saves ------------------------------------------------------------------------------

def _is_within(path: Path, parent: Path) -> bool:
    return path == parent or parent in path.parents


def link_saves(prefix: Path, folder: str, mac_documents: Path) -> None:
    """Links only Windows Documents/<folder> to ~/Documents/<folder>; the rest of Documents stays isolated in the prefix.
    Never deletes anything that resolves outside the prefix, nor the saves folder itself."""
    target = mac_documents / folder
    target.mkdir(parents=True, exist_ok=True)
    root = prefix.resolve()
    seen = set()
    for user in sorted((prefix / "drive_c" / "users").iterdir()):
        if user.name == "Public" or not user.is_dir():
            continue
        real = user.resolve()
        if not _is_within(real, root):
            raise PrefixFailed(f"the user folder {user} points outside the prefix ({real}); nothing was deleted")
        if real in seen:
            continue
        seen.add(real)
        docs = user / "Documents"
        if docs.is_symlink():
            docs.unlink()  # only the link, never the target
        docs.mkdir(exist_ok=True)
        link = docs / folder
        if link.is_symlink():
            link.unlink()
        elif link.exists():
            resolved = link.resolve()
            if not _is_within(resolved, root) or resolved == target.resolve():
                raise PrefixFailed(f"{link} resolves to {resolved}, outside the prefix or equal to the saves folder; nothing was deleted")
            shutil.rmtree(link)
        os.symlink(target, link)


# --- Relocation -------------------------------------------------------------------------

def relocate_registry(prefix: Path, old: Path, new: Path) -> None:
    """Replaces the bundle path `old` with `new` in system.reg/user.reg (Wine records absolute paths
    for fonts, the wine-mono InstallSource etc.). The app's Wine must be stopped (stop_wine)."""
    pairs = []
    for variant in dict.fromkeys([str(old), str(old.resolve())]):
        pairs.append(("Z:" + variant.replace("/", "\\\\"), "Z:" + str(new).replace("/", "\\\\")))  # .reg form: Z:\\Users\\...
        pairs.append(("Z:" + variant.replace("/", "\\"), "Z:" + str(new).replace("/", "\\")))
        pairs.append((variant, str(new)))  # forward slashes (Z:/... or /...)
    for name in ("system.reg", "user.reg"):
        file = prefix / name
        if not file.is_file():
            continue
        text = file.read_text(encoding="utf-8")
        for old_text, new_text in pairs:
            text = re.sub(re.escape(old_text) + r"(?![\w-])", lambda _: new_text, text)
        file.write_text(text, encoding="utf-8")
