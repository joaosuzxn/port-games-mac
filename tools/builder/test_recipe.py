import json
import tempfile
import unittest
from pathlib import Path

from recipe import InvalidRecipe, RegistryKey, load_recipe

RECIPES = Path(__file__).parent / "recipes"


class TestRecipeCarros(unittest.TestCase):
    def setUp(self):
        self.r = load_recipe(RECIPES / "carros.json")

    def test_loads_carros(self):
        r = self.r
        self.assertEqual(r.name, "carros")
        self.assertEqual(r.app_name, "Carros")
        self.assertEqual(r.bundle_id, "local.portcarros.carros")
        self.assertEqual(r.game_dir, "jogo")
        self.assertEqual(r.exe_source, "bak/Cars.exe")
        self.assertEqual(r.exe_target, "Cars.exe")
        self.assertEqual(r.exe_sha1, "a175e49a8cd3aa67ffd71b7cf1a8d0c90b527902")
        self.assertEqual(r.cd_label, "DISC2")
        self.assertEqual(r.saves_dir, "THQ")
        self.assertEqual(r.renderer, "wined3d")  # ADR 0003: stable 30 FPS (the game's cap)
        for item in ("Data/Global.pak", "Data/UI.pak", "Data/misc.pak", "Data/Audio.pak", "Data/Scenes.pak",
                     "Data/Act.pak", "Data/Res.pak", "binkw32.dll"):
            self.assertIn(item, r.required_files)
        for item in ("_jvm", "_uninst", "_CommonRedist", "steamapps", "THQ Website.url", "Cars.exe", "bak"):
            self.assertIn(item, r.exclude)

    def test_carros_registry(self):
        self.assertIn(RegistryKey("system", r"Software\Wine\Drives", {"d:": "cdrom"}), self.r.registry)
        # fullscreen: resolution-change emulation, no virtual desktop (ADR 0002)
        self.assertIn(RegistryKey("user", r"Software\Wine\X11 Driver", {"EmulateModeset": "y"}), self.r.registry)
        self.assertFalse(any(c.key.startswith(r"Software\Wine\Explorer") for c in self.r.registry))
        # controllers (ControlSet001: CurrentControlSet is a link in system.reg): Wine's SDL backend, Xbox layout for any controller recognized by SDL
        self.assertIn(RegistryKey("system", r"System\ControlSet001\Services\winebus",
                                  {"Enable SDL": 1, "Map Controllers": 1}), self.r.registry)
        # game video: 1600x1200 (index 14), 4x MSAA, effects on — measured at a stable 30 FPS
        self.assertIn(RegistryKey("user", r"Software\THQ\Cars\Settings\Display",
                                  {"Resolution": 14, "MultiSampleType": 4, "FullscreenEffects": 1}), self.r.registry)


class TestInvalidRecipe(unittest.TestCase):
    def _write(self, change):
        data = json.loads((RECIPES / "carros.json").read_text(encoding="utf-8"))
        change(data)
        tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        json.dump(data, tmp)
        tmp.close()
        self.addCleanup(Path(tmp.name).unlink)
        return Path(tmp.name)

    def test_missing_field(self):
        path = self._write(lambda d: d.pop("exe_sha1"))
        with self.assertRaises(InvalidRecipe) as ctx:
            load_recipe(path)
        self.assertIn("exe_sha1", str(ctx.exception))

    def test_invalid_renderer(self):
        path = self._write(lambda d: d.update(renderer="vulkan"))
        with self.assertRaises(InvalidRecipe):
            load_recipe(path)

    def test_malformed_sha1(self):
        path = self._write(lambda d: d.update(exe_sha1="abc123"))
        with self.assertRaises(InvalidRecipe):
            load_recipe(path)

    def test_required_files_optional(self):
        r = load_recipe(self._write(lambda d: d.pop("required_files")))
        self.assertEqual(r.required_files, ())

    def test_required_files_cannot_leave_the_folder(self):
        for bad in ("../x", "/etc/passwd"):
            path = self._write(lambda d: d.update(required_files=[bad]))
            with self.assertRaises(InvalidRecipe):
                load_recipe(path)

    def test_dword_out_of_range(self):
        for bad in (-1, 0x1_0000_0000):
            path = self._write(lambda d: d["registry"].append(
                {"hive": "user", "key": "A", "values": {"x": bad}}))
            with self.assertRaises(InvalidRecipe):
                load_recipe(path)


if __name__ == "__main__":
    unittest.main()
