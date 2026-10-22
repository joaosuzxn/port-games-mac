import hashlib
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest import mock
from dataclasses import replace
from pathlib import Path

from prefix import InvalidGame, apply_registry, setup_cd_drive, copy_game, link_saves, relocate_registry
from prefix import PrefixFailed, stop_wine
from recipe import RegistryKey, load_recipe

RECIPE = load_recipe(Path(__file__).parent / "recipes" / "carros.json")


class TestCopyGame(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.game = self.tmp / "game"
        for folder in ("_jvm/bin", "_uninst", "_CommonRedist/DirectX", "steamapps", "bak", "Data/AppStart"):
            (self.game / folder).mkdir(parents=True)
        (self.game / "Cars.exe").write_bytes(b"with steamstub")
        (self.game / "bak" / "Cars.exe").write_bytes(b"no drm")
        (self.game / "THQ Website.url").write_text("x")
        (self.game / "binkw32.dll").write_bytes(b"bink")
        (self.game / "Data" / "Global.pak").write_bytes(b"pak")
        self.recipe = replace(RECIPE, exe_sha1=hashlib.sha1(b"no drm").hexdigest(),
                              required_files=("Data/Global.pak", "binkw32.dll"))
        self.target = self.tmp / "drive_c" / "Games" / "Carros"

    def test_copies_without_excluded(self):
        copy_game(self.game, self.target, self.recipe)
        names = {p.name for p in self.target.iterdir()}
        for excluded in ("_jvm", "_uninst", "_CommonRedist", "steamapps", "bak", "THQ Website.url"):
            self.assertNotIn(excluded, names)
        self.assertEqual((self.target / "Cars.exe").read_bytes(), b"no drm")
        self.assertEqual((self.target / "Data" / "Global.pak").read_bytes(), b"pak")
        self.assertTrue((self.target / "binkw32.dll").exists())

    def test_wrong_hash_does_not_copy(self):
        (self.game / "bak" / "Cars.exe").write_bytes(b"other build")
        with self.assertRaises(InvalidGame):
            copy_game(self.game, self.target, self.recipe)
        self.assertFalse(self.target.exists())

    def test_incomplete_game_does_not_copy(self):
        (self.game / "Data" / "Global.pak").unlink()
        with self.assertRaises(InvalidGame) as ctx:
            copy_game(self.game, self.target, self.recipe)
        self.assertIn("Data/Global.pak", str(ctx.exception))
        self.assertIn("steamcmd", str(ctx.exception))
        self.assertFalse(self.target.exists())

    def test_missing_game(self):
        with self.assertRaises(InvalidGame) as ctx:
            copy_game(self.tmp / "does-not-exist", self.target, self.recipe)
        self.assertIn("steamcmd", str(ctx.exception))
        self.assertFalse(self.target.exists())


class TestPrefix(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.prefix = self.tmp / "prefix"
        (self.prefix / "dosdevices").mkdir(parents=True)
        (self.prefix / "drive_c" / "Games" / "Carros").mkdir(parents=True)
        (self.prefix / "system.reg").write_text("WINE REGISTRY Version 2\n;; All keys relative to \\\\Machine\n\n"
                                                "[Software\\\\Wine\\\\Drives] 1700000000\n#time=1\n\"c:\"=\"hd\"\n\n"
                                                "[System\\\\Other] 1700000000\n\"x\"=dword:00000002\n")
        (self.prefix / "user.reg").write_text("WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n")

    def test_cd_drive(self):
        setup_cd_drive(self.prefix, "Games/Carros", "DISC2")
        link = self.prefix / "dosdevices" / "d:"
        self.assertTrue(link.is_symlink())
        self.assertFalse(os.path.isabs(os.readlink(link)))
        self.assertEqual(link.resolve(), (self.prefix / "drive_c" / "Games" / "Carros").resolve())
        self.assertEqual((self.prefix / "drive_c" / "Games" / "Carros" / ".windows-label").read_text().strip(), "DISC2")

    def test_registry_format(self):
        apply_registry(self.prefix, [
            RegistryKey("system", r"Software\Wine\Drives", {"d:": "cdrom"}),
            RegistryKey("system", r"System\CurrentControlSet\Services\winebus", {"Enable SDL": 1}),
            RegistryKey("user", r"Software\Wine\Explorer", {"Desktop": "Default"}),
        ])
        system = (self.prefix / "system.reg").read_text()
        self.assertIn('"c:"="hd"', system)
        self.assertIn('"d:"="cdrom"', system)
        self.assertIn("[System\\\\CurrentControlSet\\\\Services\\\\winebus]", system)
        self.assertIn('"Enable SDL"=dword:00000001', system)
        self.assertIn('"x"=dword:00000002', system)
        self.assertIn('[Software\\\\Wine\\\\Explorer]', (self.prefix / "user.reg").read_text())
        # the new value goes into the existing section, not into a new one
        section = system.split("[Software\\\\Wine\\\\Drives]")[1].split("\n[")[0]
        self.assertIn('"d:"="cdrom"', section)

    def test_registry_idempotent(self):
        keys = [RegistryKey("system", r"Software\Wine\Drives", {"d:": "cdrom"}),
                RegistryKey("user", r"Software\Wine\Explorer\Desktops", {"Default": "1280x720"})]
        apply_registry(self.prefix, keys)
        apply_registry(self.prefix, keys)
        apply_registry(self.prefix, [RegistryKey("user", r"Software\Wine\Explorer\Desktops", {"Default": "2560x1664"})])
        system = (self.prefix / "system.reg").read_text()
        user = (self.prefix / "user.reg").read_text()
        self.assertEqual(system.count("[Software\\\\Wine\\\\Drives]"), 1)
        self.assertEqual(system.count('"d:"='), 1)
        self.assertEqual(user.count("[Software\\\\Wine\\\\Explorer\\\\Desktops]"), 1)
        self.assertIn('"Default"="2560x1664"', user)
        self.assertNotIn("1280x720", user)


class TestRelocateRegistry(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.old = self.tmp / "build with space ü" / "Carros.app"  # space and a non-ASCII character in the path
        self.new = Path("/Applications/Carros.app")
        self.prefix = self.tmp / "prefix"
        self.prefix.mkdir()
        esc = "Z:" + str(self.old).replace("/", "\\\\")
        self.esc = esc
        (self.prefix / "system.reg").write_text(
            f'[Software\\\\Microsoft\\\\Fonts] 1\n"Marlett"="{esc}\\\\Contents\\\\fonts\\\\marlett.ttf"\n'
            f'"Other"="Z:\\\\Users\\\\x\\\\build with space ü\\\\Carros.app2\\\\a"\n')
        (self.prefix / "user.reg").write_text(
            f'"InstallSource"="{self.old}/Contents/mono"\n"Slash"="Z:{self.old}/x"\n"Without"="C:\\\\windows"\n')

    def test_replaces_the_path_forms(self):
        relocate_registry(self.prefix, self.old, self.new)
        system = (self.prefix / "system.reg").read_text()
        user = (self.prefix / "user.reg").read_text()
        self.assertIn('"Marlett"="Z:\\\\Applications\\\\Carros.app\\\\Contents\\\\fonts\\\\marlett.ttf"', system)
        self.assertNotIn("build with", system.split("\n")[1])
        self.assertIn('"InstallSource"="/Applications/Carros.app/Contents/mono"', user)
        self.assertIn('"Slash"="Z:/Applications/Carros.app/x"', user)
        self.assertIn('"Without"="C:\\\\windows"', user)

    def test_does_not_touch_similar_names(self):
        relocate_registry(self.prefix, self.old, self.new)
        self.assertIn("Carros.app2", (self.prefix / "system.reg").read_text())

    def test_accepts_unresolved_path(self):
        real = self.tmp / "real" / "Carros.app"
        real.mkdir(parents=True)
        link = self.tmp / "shortcut.app"
        link.symlink_to(real)
        (self.prefix / "user.reg").write_text(f'"x"="{real.resolve()}/Contents"\n')
        relocate_registry(self.prefix, link, self.new)
        self.assertEqual((self.prefix / "user.reg").read_text(), '"x"="/Applications/Carros.app/Contents"\n')


class TestSaves(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.prefix = self.tmp / "prefix"
        self.mac_docs = self.tmp / "Documents"
        save = self.mac_docs / "THQ" / "Cars" / "Save"
        save.mkdir(parents=True)
        (save / "slot1").write_text("progress")
        (self.mac_docs / "personal.txt").write_text("not part of the game")
        user = self.prefix / "drive_c" / "users" / "user"
        user.mkdir(parents=True)
        (self.prefix / "drive_c" / "users" / "Public").mkdir()
        os.symlink(self.mac_docs, user / "Documents")  # as Wine creates it by default

    def test_saves_preserved(self):
        link_saves(self.prefix, "THQ", self.mac_docs)
        win_docs = self.prefix / "drive_c" / "users" / "user" / "Documents"
        self.assertFalse(win_docs.is_symlink())
        self.assertTrue((win_docs / "THQ").is_symlink())
        self.assertEqual((win_docs / "THQ" / "Cars" / "Save" / "slot1").read_text(), "progress")
        self.assertFalse((win_docs / "personal.txt").exists())
        link_saves(self.prefix, "THQ", self.mac_docs)  # rebuild
        shutil.rmtree(self.prefix)  # delete the app
        self.assertEqual((self.mac_docs / "THQ" / "Cars" / "Save" / "slot1").read_text(), "progress")
        self.assertTrue((self.mac_docs / "personal.txt").exists())

    def test_creates_saves_folder_if_missing(self):
        shutil.rmtree(self.mac_docs / "THQ")
        link_saves(self.prefix, "THQ", self.mac_docs)
        self.assertTrue((self.mac_docs / "THQ").is_dir())

    def test_user_symlink_outside_deletes_nothing(self):
        external = self.tmp / "external"
        (external / "Documents" / "THQ").mkdir(parents=True)
        (external / "Documents" / "THQ" / "important").write_text("real data")
        (self.prefix / "drive_c" / "users" / "user" / "Documents").unlink()
        (self.prefix / "drive_c" / "users" / "user").rmdir()
        os.symlink(external, self.prefix / "drive_c" / "users" / "user")
        with self.assertRaises(PrefixFailed) as ctx:
            link_saves(self.prefix, "THQ", self.mac_docs)
        self.assertIn("outside the prefix", str(ctx.exception))
        self.assertEqual((external / "Documents" / "THQ" / "important").read_text(), "real data")
        self.assertEqual((self.mac_docs / "THQ" / "Cars" / "Save" / "slot1").read_text(), "progress")

    def test_users_duplicated_by_symlink_are_unique(self):
        os.symlink(self.prefix / "drive_c" / "users" / "user", self.prefix / "drive_c" / "users" / "alias")
        link_saves(self.prefix, "THQ", self.mac_docs)
        self.assertEqual((self.mac_docs / "THQ" / "Cars" / "Save" / "slot1").read_text(), "progress")


class TestStopWine(unittest.TestCase):
    def setUp(self):
        self.app = Path(tempfile.mkdtemp()).resolve() / "Test.app"
        launcher = self.app / "Contents" / "MacOS" / "wineskinlauncher"
        launcher.parent.mkdir(parents=True)
        launcher.write_text("#!/bin/sh\nexit 0\n")
        launcher.chmod(0o755)
        self.procs = []
        self.addCleanup(lambda: [(p.kill(), p.wait()) for p in self.procs])

    def _start(self, argv):
        p = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.procs.append(p)
        time.sleep(0.5)
        return p

    def test_does_not_kill_a_process_that_only_mentions_the_app_in_an_argument(self):
        p = self._start(["sh", "-c", "sleep 30", str(self.app / "Contents" / "anything")])
        stop_wine(self.app, max_time=1)
        self.assertIsNone(p.poll())

    def test_kills_process_executed_from_inside_the_app(self):
        fake = self.app / "Contents" / "SharedSupport" / "wine" / "wineserver"
        fake.parent.mkdir(parents=True)
        fake.symlink_to("/bin/sleep")
        p = self._start([str(fake), "30"])
        stop_wine(self.app, max_time=1)
        self.assertIsNotNone(p.wait(timeout=5))

    def test_without_launcher_does_not_break(self):
        (self.app / "Contents" / "MacOS" / "wineskinlauncher").unlink()
        stop_wine(self.app, max_time=1)

    def test_process_that_resists_sigkill_becomes_an_error(self):
        with mock.patch("prefix._app_processes", return_value=[os.getpid() + 999999]), \
                mock.patch("prefix.os.kill"), mock.patch("prefix.time.sleep"):
            with self.assertRaises(PrefixFailed):
                stop_wine(self.app, max_time=0)


class TestCreatePrefixTimeout(unittest.TestCase):
    def test_stuck_launcher_becomes_an_error(self):
        from prefix import PrefixFailed, create_prefix
        app = Path(tempfile.mkdtemp()) / "Test.app"
        launcher = app / "Contents" / "MacOS" / "wineskinlauncher"
        launcher.parent.mkdir(parents=True)
        launcher.write_text('#!/bin/sh\n[ "$1" = "WSS-wineprefixcreate" ] && sleep 30\nexit 0\n')
        launcher.chmod(0o755)
        with self.assertRaises(PrefixFailed) as ctx:
            create_prefix(app, max_time=1)
        self.assertIn("1", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
