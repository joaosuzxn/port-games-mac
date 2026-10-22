"""Builds a game's .app from its recipe.

Usage: python3 tools/builder/build.py carros [--output build] [--cache DIR] [--game-dir DIR] [--install] [--install-dir DIR]
"""
import argparse
import urllib.error
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from artifacts import DEFAULT_CACHE, DEFAULT_LOCAL_SOURCES, InvalidArtifact, ensure_artifact, load_artifacts
from bundle import build_bundle, configure_info_plist, remove_configurator, replace_app
from icon import extract_icon
from prefix import (InvalidGame, PrefixFailed, apply_registry, check_game, copy_game, create_prefix, link_saves,
                    relocate_registry, setup_cd_drive, stop_wine)
from recipe import InvalidRecipe, load_recipe

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def _step(text: str) -> None:
    print(f"• {text}", flush=True)


def _set_icon(app: Path, icns: Path) -> None:
    plist = app / "Contents" / "Info.plist"
    with open(plist, "rb") as f:
        data = plistlib.load(f)
    data["CFBundleIconFile"] = icns.name
    with open(plist, "wb") as f:
        plistlib.dump(data, f)


DEFAULT_INSTALL_DIR = Path("/Applications")


def _bundle_id_of(app: Path) -> str | None:
    try:
        with open(app / "Contents" / "Info.plist", "rb") as f:
            return plistlib.load(f).get("CFBundleIdentifier")
    except (OSError, plistlib.InvalidFileException, ValueError):
        return None


def _check_target(target: Path, recipe) -> None:
    """Only lets an app that already belongs to this game (same CFBundleIdentifier) be replaced."""
    if not (target.exists() or target.is_symlink()):
        return
    current = _bundle_id_of(target)
    if current != recipe.bundle_id:
        raise PrefixFailed(
            f"{target} already exists and is not this game's app (CFBundleIdentifier {current!r}, expected {recipe.bundle_id!r}); "
            "I will not delete it. Move or remove that app and run again."
        )


def _prefix_of(app: Path) -> Path:
    return app / "Contents" / "SharedSupport" / "prefix"


def install_app(app: Path, directory: Path, recipe) -> Path:
    """Copies to `<dir>/.<App>.app.new`, adjusts the registry paths and swaps at the end."""
    target = directory / app.name
    _check_target(target, recipe)
    directory.mkdir(parents=True, exist_ok=True)
    new = directory / f".{app.name}.new"
    shutil.rmtree(new, ignore_errors=True)
    try:
        shutil.copytree(app, new, symlinks=True)
        relocate_registry(_prefix_of(new), app, target)
        if target.exists():
            stop_wine(target)
        replace_app(new, target)
    finally:
        shutil.rmtree(new, ignore_errors=True)
    return target


def build_app(recipe_name: str, output: Path, cache: Path, game_dir: Path | None, install: bool,
              install_dir: Path = DEFAULT_INSTALL_DIR) -> Path:
    recipe = load_recipe(HERE / "recipes" / f"{recipe_name}.json")
    game = game_dir or (ROOT / recipe.game_dir)
    _step(f"Checking the game files in {game}")
    check_game(game, recipe)  # before touching build/
    final = output / f"{recipe.app_name}.app"
    if install:
        _check_target(install_dir / final.name, recipe)

    _step("Checking template and Wine engine")
    artifacts = load_artifacts(HERE / "artifacts.json")
    template = ensure_artifact(artifacts["template"], cache, DEFAULT_LOCAL_SOURCES)
    engine = ensure_artifact(artifacts["engine"], cache, DEFAULT_LOCAL_SOURCES)

    if final.exists():
        stop_wine(final)  # a Wine running from the old app would be overwritten/disturbed
    output.mkdir(parents=True, exist_ok=True)
    for abandoned in output.glob(".building-*"):
        shutil.rmtree(abandoned, ignore_errors=True)
    workdir = Path(tempfile.mkdtemp(prefix=".building-", dir=output))  # everything is built here; the final app only changes at the end
    try:
        _step(f"Building {recipe.app_name}.app")
        app = build_bundle(template, engine, workdir, recipe)
        _step("Creating the Windows inside the app (prefix)")
        prefix = create_prefix(app)
        configure_info_plist(app / "Contents" / "Info.plist", recipe)  # the launcher rewrites the identifier when creating the prefix

        _step("Copying the game")
        game_target = prefix / "drive_c" / "Games" / recipe.app_name
        copy_game(game, game_target, recipe)
        if recipe.cd_label:
            setup_cd_drive(prefix, f"Games/{recipe.app_name}", recipe.cd_label)
        apply_registry(prefix, recipe.registry)
        if recipe.saves_dir:
            link_saves(prefix, recipe.saves_dir, Path.home() / "Documents")

        _step("Icon and finishing touches")
        icns = app / "Contents" / "Resources" / f"{recipe.app_name}.icns"
        if extract_icon(game_target / recipe.exe_target, icns):
            _set_icon(app, icns)
        stop_wine(app)
        remove_configurator(app)
        subprocess.run(["xattr", "-dr", "com.apple.quarantine", str(app)], capture_output=True)
        relocate_registry(prefix, app, final)  # Wine recorded the path of the work folder

        replace_app(app, final)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
    app = final

    if install:
        _step(f"Installing in {install_dir / app.name}")
        app = install_app(app, install_dir, recipe)
    _step(f"Done: {app}")
    return app


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Builds the .app of a Windows game from its recipe.")
    p.add_argument("recipe", help="name of the recipe in tools/builder/recipes (e.g. carros)")
    p.add_argument("--output", type=Path, default=ROOT / "build")
    p.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    p.add_argument("--game-dir", type=Path, default=None, help="folder with the game files (default: the recipe's)")
    p.add_argument("--install", action="store_true", help="copies the app to /Applications (or --install-dir)")
    p.add_argument("--install-dir", type=Path, default=DEFAULT_INSTALL_DIR,
                   help="folder where --install puts the app (default: /Applications)")
    args = p.parse_args(argv)
    try:
        build_app(args.recipe, args.output, args.cache, args.game_dir, args.install, args.install_dir)
    except (InvalidRecipe, InvalidGame, InvalidArtifact, PrefixFailed) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except (OSError, RuntimeError, urllib.error.URLError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(f"Error: command failed: {' '.join(map(str, e.cmd))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
