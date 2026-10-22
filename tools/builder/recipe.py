"""Recipe for one game: everything specific to it for building the .app (the rest of the engine does not know the game)."""
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

RENDERERS = ("d9vk", "wined3d", "d3dmetal")
HIVES = ("system", "user")


class InvalidRecipe(Exception):
    pass


@dataclass(frozen=True)
class RegistryKey:
    hive: Literal["system", "user"]
    key: str
    values: dict  # name -> str ("..." in the .reg) or int (dword)

    def __hash__(self):
        return hash((self.hive, self.key, tuple(sorted(self.values.items()))))


@dataclass(frozen=True)
class Recipe:
    name: str
    app_name: str
    bundle_id: str
    game_dir: str
    exe_source: str
    exe_target: str
    exe_sha1: str
    exclude: tuple
    cd_label: str | None
    saves_dir: str | None
    renderer: Literal["d9vk", "wined3d", "d3dmetal"]
    registry: tuple
    required_files: tuple = ()


def _require(data: dict, field: str, expected_type, optional: bool = False):
    if field not in data:
        if optional:
            return None
        raise InvalidRecipe(f"required field missing: {field}")
    value = data[field]
    if value is None and optional:
        return None
    if not isinstance(value, expected_type):
        raise InvalidRecipe(f"field {field} has the wrong type: expected {expected_type.__name__}")
    return value


def _read_key(item: dict) -> RegistryKey:
    hive = _require(item, "hive", str)
    if hive not in HIVES:
        raise InvalidRecipe(f"invalid registry.hive: {hive} (use {', '.join(HIVES)})")
    values = _require(item, "values", dict)
    for name, v in values.items():
        if isinstance(v, bool) or not isinstance(v, (str, int)):
            raise InvalidRecipe(f"registry.values.{name} must be a string or an integer")
        if isinstance(v, int) and not 0 <= v <= 0xFFFFFFFF:
            raise InvalidRecipe(f"registry.values.{name} is outside the dword range (0 to 4294967295)")
    return RegistryKey(hive, _require(item, "key", str), dict(values))


def load_recipe(path: Path) -> Recipe:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise InvalidRecipe(f"recipe not found: {path}") from None
    except json.JSONDecodeError as e:
        raise InvalidRecipe(f"recipe has invalid JSON: {path}: {e}") from None

    sha1 = _require(data, "exe_sha1", str)
    if not re.fullmatch(r"[0-9a-f]{40}", sha1):
        raise InvalidRecipe("field exe_sha1 must have 40 lowercase hexadecimal characters")
    renderer = _require(data, "renderer", str)
    if renderer not in RENDERERS:
        raise InvalidRecipe(f"invalid renderer field: {renderer} (use {', '.join(RENDERERS)})")

    required = _require(data, "required_files", list, optional=True) or []
    for item in required:
        if not isinstance(item, str) or not item or item.startswith("/") or ".." in Path(item).parts:
            raise InvalidRecipe(f"required_files: invalid path (use a path relative to the game folder): {item!r}")

    return Recipe(
        name=_require(data, "name", str),
        app_name=_require(data, "app_name", str),
        bundle_id=_require(data, "bundle_id", str),
        game_dir=_require(data, "game_dir", str),
        exe_source=_require(data, "exe_source", str),
        exe_target=_require(data, "exe_target", str),
        exe_sha1=sha1,
        exclude=tuple(_require(data, "exclude", list)),
        cd_label=_require(data, "cd_label", str, optional=True),
        saves_dir=_require(data, "saves_dir", str, optional=True),
        renderer=renderer,
        registry=tuple(_read_key(i) for i in _require(data, "registry", list)),
        required_files=tuple(required),
    )
