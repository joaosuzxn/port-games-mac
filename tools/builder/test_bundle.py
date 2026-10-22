import os
import plistlib
import subprocess
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from bundle import build_bundle, remove_configurator, replace_app
from recipe import load_recipe

RECIPE = load_recipe(Path(__file__).parent / "recipes" / "carros.json")

TEMPLATE_PLIST = {
    "CFBundleName": "SikarugirNavyWrapper",
    "CFBundleIdentifier": "com.SikarugirNavyWrapper.Sikarugir",
    "CFBundleIconFile": "Configure.icns",
    "Program Name and Path": "/nothing.exe",
    "D9VK": 1,
    "DXVK": 0,
    "D3DMETAL": 0,
    "Debug Mode": 1,
    "WINEDEBUG": "-plugplay,+loaddll",
    "Symlinks In User Folder": 1,
}


def _tar(source: Path, target: Path, root: str):
    subprocess.run(["tar", "-cJf", str(target), "-C", str(source), root], check=True)


class TestBundle(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        t = self.tmp / "t" / "Template-1.0.24.app" / "Contents"
        (t / "Configure.app" / "Contents").mkdir(parents=True)
        (t / "SharedSupport").mkdir()
        (t / "MacOS").mkdir()
        (t / "MacOS" / "launcher").write_text("#!/bin/sh\n")
        with open(t / "Info.plist", "wb") as f:
            plistlib.dump(TEMPLATE_PLIST, f)
        self.template = self.tmp / "Template-1.0.24.tar.xz"
        _tar(self.tmp / "t", self.template, "Template-1.0.24.app")

        e = self.tmp / "e" / "wswine.bundle" / "bin"
        e.mkdir(parents=True)
        (e / "wine").write_text("#!/bin/sh\n")
        os.chmod(e / "wine", 0o755)
        self.engine = self.tmp / "engine.tar.xz"
        _tar(self.tmp / "e", self.engine, "wswine.bundle")

        self.output = self.tmp / "build with space ü"  # space and a non-ASCII character in the path

    def _build(self, recipe=RECIPE):
        return build_bundle(self.template, self.engine, self.output, recipe)

    def _plist(self, app):
        with open(app / "Contents" / "Info.plist", "rb") as f:
            return plistlib.load(f)

    def test_builds_structure(self):
        app = self._build()
        self.assertEqual(app, self.output / "Carros.app")
        wine = app / "Contents" / "SharedSupport" / "wine" / "bin" / "wine"
        self.assertTrue(wine.is_file())
        self.assertTrue(os.access(wine, os.X_OK))
        # the launcher needs Configure.app (remakedefaults.reg) to create the prefix
        self.assertTrue((app / "Contents" / "Configure.app").exists())

    def test_remove_configurator(self):
        app = self._build()
        remove_configurator(app)
        self.assertFalse((app / "Contents" / "Configure.app").exists())
        remove_configurator(app)  # idempotent

    def test_info_plist(self):
        p = self._plist(self._build(replace(RECIPE, renderer="d9vk")))
        self.assertEqual(p["CFBundleName"], "Carros")
        self.assertEqual(p["CFBundleIdentifier"], "local.portcarros.carros")
        self.assertEqual(p["Program Name and Path"], "/Games/Carros/Cars.exe")
        self.assertEqual((p["D9VK"], p["DXVK"], p["D3DMETAL"]), (1, 0, 0))
        self.assertEqual(p["Debug Mode"], 0)
        self.assertEqual(p["WINEDEBUG"], "-all")
        self.assertEqual(p["Symlinks In User Folder"], 0)

    def test_wined3d_renderer_turns_all_off(self):
        p = self._plist(self._build(replace(RECIPE, renderer="wined3d")))
        self.assertEqual((p["D9VK"], p["DXVK"], p["D3DMETAL"]), (0, 0, 0))

    def test_rebuild_replaces(self):
        app = self._build()
        (app / "Contents" / "junk.txt").write_text("old")
        app2 = self._build()
        self.assertEqual(app2, app)
        self.assertFalse((app / "Contents" / "junk.txt").exists())
        self.assertFalse((app / "Carros.app").exists())
        self.assertEqual(sorted(p.name for p in self.output.iterdir()), ["Carros.app"])

    def test_plist_without_absolute_path(self):
        p = self._plist(self._build())
        for key, value in p.items():
            if isinstance(value, str):
                self.assertNotIn(str(self.output), value, key)


class TestReplaceApp(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.new = self.tmp / "workdir" / "Carros.app"
        (self.new / "Contents").mkdir(parents=True)
        (self.new / "Contents" / "marker").write_text("new")
        self.final = self.tmp / "build" / "Carros.app"
        self.final.parent.mkdir()

    def test_no_previous_app(self):
        replace_app(self.new, self.final)
        self.assertEqual((self.final / "Contents" / "marker").read_text(), "new")
        self.assertFalse(self.new.exists())

    def test_swaps_and_deletes_the_old_one(self):
        (self.final / "Contents").mkdir(parents=True)
        (self.final / "Contents" / "marker").write_text("old")
        replace_app(self.new, self.final)
        self.assertEqual((self.final / "Contents" / "marker").read_text(), "new")
        self.assertEqual([p.name for p in self.final.parent.iterdir()], ["Carros.app"])

    def test_failed_swap_gives_the_old_one_back(self):
        (self.final / "Contents").mkdir(parents=True)
        (self.final / "Contents" / "marker").write_text("old")
        with self.assertRaises(OSError):
            replace_app(self.tmp / "does-not-exist.app", self.final)
        self.assertEqual((self.final / "Contents" / "marker").read_text(), "old")


if __name__ == "__main__":
    unittest.main()
