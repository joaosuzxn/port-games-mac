import contextlib
import io
import tempfile
import hashlib
import os
import plistlib
import subprocess
import unittest
from dataclasses import replace
from pathlib import Path
from unittest import mock

import build
from build import main, build_app
from prefix import PrefixFailed
from recipe import load_recipe


class TestMain(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.output = self.tmp / "build"

    def _run(self, argv):
        err = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            code = main(argv)
        return code, err.getvalue()

    def test_main_without_game(self):
        code, err = self._run(["carros", "--output", str(self.output), "--game-dir", str(self.tmp / "nothing")])
        self.assertNotEqual(code, 0)
        self.assertIn("steamcmd", err)
        self.assertFalse(self.output.exists() and any(self.output.iterdir()))

    def test_main_wrong_hash_does_not_build(self):
        game = self.tmp / "game"
        (game / "bak").mkdir(parents=True)
        (game / "bak" / "Cars.exe").write_bytes(b"other build")
        code, err = self._run(["carros", "--output", str(self.output), "--game-dir", str(game)])
        self.assertNotEqual(code, 0)
        self.assertIn("SHA-1", err)
        self.assertFalse(self.output.exists() and any(self.output.iterdir()))

    def test_main_incomplete_game_does_not_build(self):
        game = self.tmp / "game"
        (game / "bak").mkdir(parents=True)
        (game / "bak" / "Cars.exe").write_bytes(b"good build")
        recipe = replace(load_recipe(Path(build.__file__).parent / "recipes" / "carros.json"),
                         exe_sha1=hashlib.sha1(b"good build").hexdigest())
        with mock.patch("build.load_recipe", return_value=recipe):
            code, err = self._run(["carros", "--output", str(self.output), "--game-dir", str(game)])
        self.assertNotEqual(code, 0)
        self.assertIn("incomplete", err)
        self.assertIn("Data/Global.pak", err)
        self.assertFalse(self.output.exists() and any(self.output.iterdir()))

    def test_main_nonexistent_recipe(self):
        code, err = self._run(["pacman", "--output", str(self.output)])
        self.assertNotEqual(code, 0)
        self.assertIn("pacman", err)


LAUNCHER = r'''#!/bin/sh
case "$1" in
WSS-wineprefixcreate)
  [ -f "$(dirname "$0")/../fail" ] && exit 0
  app=$(cd "$(dirname "$0")/../.." && pwd -P)
  esc=$(printf '%s' "$app" | sed 's#/#\\\\#g')
  p="$app/Contents/SharedSupport/prefix"
  mkdir -p "$p/drive_c/users/user" "$p/dosdevices"
  printf '[Software\\\\Fonts] 1\n"Marlett"="Z:%s\\\\Contents\\\\m.ttf"\n' "$esc" > "$p/system.reg"
  printf '"InstallSource"="%s/Contents/mono"\n' "$app" > "$p/user.reg"
  ;;
esac
exit 0
'''


def _tar(source: Path, target: Path, root: str):
    subprocess.run(["tar", "-cJf", str(target), "-C", str(source), root], check=True)


class TestBuildIntegration(unittest.TestCase):
    """Full flow with a fake template/engine/launcher, in temporary folders."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        t = self.tmp / "t" / "T.app" / "Contents"
        (t / "Configure.app" / "Contents").mkdir(parents=True)
        (t / "SharedSupport").mkdir()
        (t / "MacOS").mkdir()
        (t / "MacOS" / "wineskinlauncher").write_text(LAUNCHER)
        os.chmod(t / "MacOS" / "wineskinlauncher", 0o755)
        with open(t / "Info.plist", "wb") as f:
            plistlib.dump({"CFBundleIdentifier": "x"}, f)
        self.template = self.tmp / "T.tar.xz"
        _tar(self.tmp / "t", self.template, "T.app")
        e = self.tmp / "e" / "wswine.bundle" / "bin"
        e.mkdir(parents=True)
        (e / "wine").write_text("#!/bin/sh\n")
        self.engine = self.tmp / "E.tar.xz"
        _tar(self.tmp / "e", self.engine, "wswine.bundle")

        self.game = self.tmp / "game"
        (self.game / "bak").mkdir(parents=True)
        (self.game / "bak" / "Cars.exe").write_bytes(b"good build")
        (self.game / "Data").mkdir()
        (self.game / "Data" / "Global.pak").write_bytes(b"pak")
        self.recipe = replace(load_recipe(Path(build.__file__).parent / "recipes" / "carros.json"),
                              exe_sha1=hashlib.sha1(b"good build").hexdigest(),
                              required_files=("Data/Global.pak",), registry=(), saves_dir=None, cd_label=None)
        self.output = self.tmp / "build"
        self.cache = self.tmp / "cache"
        self.apps = self.tmp / "Applications"
        self.apps.mkdir()

    def _build(self, install=False):
        source = lambda a, cache, local_sources: self.template if a.name == "template" else self.engine
        with mock.patch("build.load_recipe", return_value=self.recipe), \
                mock.patch("build.ensure_artifact", side_effect=source), \
                contextlib.redirect_stdout(io.StringIO()):
            return build_app("carros", self.output, self.cache, self.game, install, self.apps)

    def test_builds_and_registry_points_to_the_final_app(self):
        app = self._build()
        self.assertEqual(app, self.output / "Carros.app")
        reg = (app / "Contents" / "SharedSupport" / "prefix" / "system.reg").read_text()
        self.assertIn("Z:" + str(app).replace("/", "\\\\") + "\\\\Contents", reg)
        self.assertNotIn(".building", reg)
        self.assertEqual([p.name for p in self.output.iterdir()], ["Carros.app"])

    def test_failure_midway_keeps_the_previous_app(self):
        app = self._build()
        (app / "Contents" / "marker").write_text("good app")
        # the next template creates an empty prefix: create_prefix fails midway through the build
        t = self.tmp / "t2" / "T.app" / "Contents"
        (t / "Configure.app").mkdir(parents=True)
        (t / "MacOS").mkdir()
        (t / "SharedSupport").mkdir()
        (t / "fail").write_text("")
        (t / "MacOS" / "wineskinlauncher").write_text(LAUNCHER)
        os.chmod(t / "MacOS" / "wineskinlauncher", 0o755)
        with open(t / "Info.plist", "wb") as f:
            plistlib.dump({}, f)
        self.template = self.tmp / "T2.tar.xz"
        _tar(self.tmp / "t2", self.template, "T.app")
        with self.assertRaises(PrefixFailed):
            self._build()
        self.assertEqual((app / "Contents" / "marker").read_text(), "good app")
        self.assertEqual([p.name for p in self.output.iterdir()], ["Carros.app"])

    def test_cleans_abandoned_builds(self):
        old = self.output / ".building-old"
        old.mkdir(parents=True)
        (old / "junk").write_text("x")
        self._build()
        self.assertFalse(old.exists())

    def test_install_relocates_and_swaps(self):
        self._build(install=True)
        target = self.apps / "Carros.app"
        reg = (target / "Contents" / "SharedSupport" / "prefix" / "system.reg").read_text()
        self.assertIn("Z:" + str(target).replace("/", "\\\\") + "\\\\Contents", reg)
        self.assertNotIn(str(self.output).replace("/", "\\\\"), reg)
        self.assertEqual([p.name for p in self.apps.iterdir()], ["Carros.app"])
        self._build(install=True)  # reinstall over the same bundle id
        self.assertEqual([p.name for p in self.apps.iterdir()], ["Carros.app"])

    def test_install_refuses_target_with_another_bundle_id(self):
        other = self.apps / "Carros.app" / "Contents"
        other.mkdir(parents=True)
        with open(other / "Info.plist", "wb") as f:
            plistlib.dump({"CFBundleIdentifier": "com.other.thing"}, f)
        (other / "marker").write_text("untouched")
        with self.assertRaises(PrefixFailed) as ctx:
            self._build(install=True)
        self.assertIn("com.other.thing", str(ctx.exception))
        self.assertEqual((other / "marker").read_text(), "untouched")
        self.assertFalse(self.output.exists() and any(self.output.iterdir()))


if __name__ == "__main__":
    unittest.main()
