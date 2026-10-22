"""Builds the .app from the Sikarugir template and the Wine engine, configured by the recipe."""
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

from recipe import Recipe

# Sikarugir Info.plist key turned on by each renderer; wined3d = all of them off.
RENDERER_PLIST_KEYS = {"d9vk": "D9VK", "d3dmetal": "D3DMETAL"}


def _extract(tar_xz: Path, target: Path) -> Path:
    """Extracts with the system tar (preserves the frameworks' symbolic links) and returns the archive's single root."""
    target.mkdir(parents=True, exist_ok=True)
    subprocess.run(["tar", "-xJf", str(tar_xz), "-C", str(target)], check=True)
    roots = [p for p in target.iterdir() if not p.name.startswith(".")]
    if len(roots) != 1:
        raise RuntimeError(f"{tar_xz.name}: expected a single root folder, found {[p.name for p in roots]}")
    return roots[0]


def configure_info_plist(plist: Path, recipe: Recipe) -> None:
    with open(plist, "rb") as f:
        data = plistlib.load(f)
    data["CFBundleName"] = recipe.app_name
    data["CFBundleIdentifier"] = recipe.bundle_id
    data["Program Name and Path"] = f"/Games/{recipe.app_name}/{recipe.exe_target}"
    for key in ("D9VK", "DXVK", "D3DMETAL"):
        data[key] = 0
    if recipe.renderer in RENDERER_PLIST_KEYS:
        data[RENDERER_PLIST_KEYS[recipe.renderer]] = 1
    data["Debug Mode"] = 0
    data["WINEDEBUG"] = "-all"
    data["Symlinks In User Folder"] = 0
    with open(plist, "wb") as f:
        plistlib.dump(data, f)


def remove_configurator(app: Path) -> None:
    """Removes Configure.app from the final bundle. Only after creating the prefix: the launcher reads its remakedefaults.reg."""
    shutil.rmtree(app / "Contents" / "Configure.app", ignore_errors=True)


def build_bundle(template: Path, engine_tar: Path, output: Path, recipe: Recipe) -> Path:
    output.mkdir(parents=True, exist_ok=True)
    final = output / f"{recipe.app_name}.app"
    with tempfile.TemporaryDirectory(dir=output, prefix=".building-") as workdir:
        workdir = Path(workdir)
        app = _extract(template, workdir / "template")
        contents = app / "Contents"
        wine = _extract(engine_tar, workdir / "engine")
        wine_target = contents / "SharedSupport" / "wine"
        if wine_target.exists():
            shutil.rmtree(wine_target)
        wine.rename(wine_target)
        configure_info_plist(contents / "Info.plist", recipe)

        if final.exists():
            shutil.rmtree(final)
        app.rename(final)
    return final


def replace_app(new: Path, final: Path) -> None:
    """Puts `new` in place of `final` by rename (same volume). The old app is only deleted after the new one is in place."""
    old = None
    if final.exists() or final.is_symlink():
        old = final.with_name(f".{final.name}.old")
        shutil.rmtree(old, ignore_errors=True)
        final.rename(old)
    try:
        new.rename(final)
    except BaseException:
        if old is not None:
            old.rename(final)
        raise
    if old is not None:
        shutil.rmtree(old, ignore_errors=True)
