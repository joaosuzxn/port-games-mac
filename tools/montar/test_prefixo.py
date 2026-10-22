import hashlib
import os
import shutil
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from prefixo import JogoInvalido, aplicar_registro, configurar_drive_cd, copiar_jogo, ligar_saves
from receita import ChaveRegistro, carregar_receita

RECEITA = carregar_receita(Path(__file__).parent / "receitas" / "carros.json")


class TestCopiarJogo(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.jogo = self.tmp / "jogo"
        for pasta in ("_jvm/bin", "_uninst", "_CommonRedist/DirectX", "steamapps", "bak", "Data/AppStart"):
            (self.jogo / pasta).mkdir(parents=True)
        (self.jogo / "Cars.exe").write_bytes(b"com steamstub")
        (self.jogo / "bak" / "Cars.exe").write_bytes(b"sem drm")
        (self.jogo / "THQ Website.url").write_text("x")
        (self.jogo / "binkw32.dll").write_bytes(b"bink")
        (self.jogo / "Data" / "Global.pak").write_bytes(b"pak")
        self.receita = replace(RECEITA, sha1_exe=hashlib.sha1(b"sem drm").hexdigest())
        self.destino = self.tmp / "drive_c" / "Games" / "Carros"

    def test_copia_sem_excluidos(self):
        copiar_jogo(self.jogo, self.destino, self.receita)
        nomes = {p.name for p in self.destino.iterdir()}
        for excluido in ("_jvm", "_uninst", "_CommonRedist", "steamapps", "bak", "THQ Website.url"):
            self.assertNotIn(excluido, nomes)
        self.assertEqual((self.destino / "Cars.exe").read_bytes(), b"sem drm")
        self.assertEqual((self.destino / "Data" / "Global.pak").read_bytes(), b"pak")
        self.assertTrue((self.destino / "binkw32.dll").exists())

    def test_hash_errado_nao_copia(self):
        (self.jogo / "bak" / "Cars.exe").write_bytes(b"outro build")
        with self.assertRaises(JogoInvalido):
            copiar_jogo(self.jogo, self.destino, self.receita)
        self.assertFalse(self.destino.exists())

    def test_jogo_ausente(self):
        with self.assertRaises(JogoInvalido) as ctx:
            copiar_jogo(self.tmp / "nao-existe", self.destino, self.receita)
        self.assertIn("steamcmd", str(ctx.exception))
        self.assertFalse(self.destino.exists())


class TestPrefixo(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.prefixo = self.tmp / "prefix"
        (self.prefixo / "dosdevices").mkdir(parents=True)
        (self.prefixo / "drive_c" / "Games" / "Carros").mkdir(parents=True)
        (self.prefixo / "system.reg").write_text("WINE REGISTRY Version 2\n;; All keys relative to \\\\Machine\n\n"
                                                 "[Software\\\\Wine\\\\Drives] 1700000000\n#time=1\n\"c:\"=\"hd\"\n\n"
                                                 "[System\\\\Outra] 1700000000\n\"x\"=dword:00000002\n")
        (self.prefixo / "user.reg").write_text("WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n")

    def test_drive_cd(self):
        configurar_drive_cd(self.prefixo, "Games/Carros", "DISC2")
        link = self.prefixo / "dosdevices" / "d:"
        self.assertTrue(link.is_symlink())
        self.assertFalse(os.path.isabs(os.readlink(link)))
        self.assertEqual(link.resolve(), (self.prefixo / "drive_c" / "Games" / "Carros").resolve())
        self.assertEqual((self.prefixo / "drive_c" / "Games" / "Carros" / ".windows-label").read_text().strip(), "DISC2")

    def test_registro_formato(self):
        aplicar_registro(self.prefixo, [
            ChaveRegistro("system", r"Software\Wine\Drives", {"d:": "cdrom"}),
            ChaveRegistro("system", r"System\CurrentControlSet\Services\winebus", {"Enable SDL": 1}),
            ChaveRegistro("user", r"Software\Wine\Explorer", {"Desktop": "Default"}),
        ])
        sistema = (self.prefixo / "system.reg").read_text()
        self.assertIn('"c:"="hd"', sistema)
        self.assertIn('"d:"="cdrom"', sistema)
        self.assertIn("[System\\\\CurrentControlSet\\\\Services\\\\winebus]", sistema)
        self.assertIn('"Enable SDL"=dword:00000001', sistema)
        self.assertIn('"x"=dword:00000002', sistema)
        self.assertIn('[Software\\\\Wine\\\\Explorer]', (self.prefixo / "user.reg").read_text())
        # o valor novo entra na seção existente, não numa seção nova
        secao = sistema.split("[Software\\\\Wine\\\\Drives]")[1].split("\n[")[0]
        self.assertIn('"d:"="cdrom"', secao)

    def test_registro_idempotente(self):
        chaves = [ChaveRegistro("system", r"Software\Wine\Drives", {"d:": "cdrom"}),
                  ChaveRegistro("user", r"Software\Wine\Explorer\Desktops", {"Default": "1280x720"})]
        aplicar_registro(self.prefixo, chaves)
        aplicar_registro(self.prefixo, chaves)
        aplicar_registro(self.prefixo, [ChaveRegistro("user", r"Software\Wine\Explorer\Desktops", {"Default": "2560x1664"})])
        sistema = (self.prefixo / "system.reg").read_text()
        usuario = (self.prefixo / "user.reg").read_text()
        self.assertEqual(sistema.count("[Software\\\\Wine\\\\Drives]"), 1)
        self.assertEqual(sistema.count('"d:"='), 1)
        self.assertEqual(usuario.count("[Software\\\\Wine\\\\Explorer\\\\Desktops]"), 1)
        self.assertIn('"Default"="2560x1664"', usuario)
        self.assertNotIn("1280x720", usuario)


class TestSaves(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.prefixo = self.tmp / "prefix"
        self.docs_mac = self.tmp / "Documents"
        save = self.docs_mac / "THQ" / "Cars" / "Save"
        save.mkdir(parents=True)
        (save / "slot1").write_text("progresso")
        (self.docs_mac / "pessoal.txt").write_text("não é do jogo")
        usuario = self.prefixo / "drive_c" / "users" / "joao"
        usuario.mkdir(parents=True)
        (self.prefixo / "drive_c" / "users" / "Public").mkdir()
        os.symlink(self.docs_mac, usuario / "Documents")  # como o Wine cria por padrão

    def test_saves_preservados(self):
        ligar_saves(self.prefixo, "THQ", self.docs_mac)
        docs_win = self.prefixo / "drive_c" / "users" / "joao" / "Documents"
        self.assertFalse(docs_win.is_symlink())
        self.assertTrue((docs_win / "THQ").is_symlink())
        self.assertEqual((docs_win / "THQ" / "Cars" / "Save" / "slot1").read_text(), "progresso")
        self.assertFalse((docs_win / "pessoal.txt").exists())
        ligar_saves(self.prefixo, "THQ", self.docs_mac)  # remontar
        shutil.rmtree(self.prefixo)  # apagar o app
        self.assertEqual((self.docs_mac / "THQ" / "Cars" / "Save" / "slot1").read_text(), "progresso")
        self.assertTrue((self.docs_mac / "pessoal.txt").exists())

    def test_cria_pasta_de_saves_se_nao_existe(self):
        shutil.rmtree(self.docs_mac / "THQ")
        ligar_saves(self.prefixo, "THQ", self.docs_mac)
        self.assertTrue((self.docs_mac / "THQ").is_dir())


if __name__ == "__main__":
    unittest.main()


class TestCriarPrefixoTempo(unittest.TestCase):
    def test_launcher_travado_vira_erro(self):
        from prefixo import PrefixoFalhou, criar_prefixo
        app = Path(tempfile.mkdtemp()) / "Teste.app"
        launcher = app / "Contents" / "MacOS" / "wineskinlauncher"
        launcher.parent.mkdir(parents=True)
        launcher.write_text('#!/bin/sh\n[ "$1" = "WSS-wineprefixcreate" ] && sleep 30\nexit 0\n')
        launcher.chmod(0o755)
        with self.assertRaises(PrefixoFalhou) as ctx:
            criar_prefixo(app, tempo_max=1)
        self.assertIn("1", str(ctx.exception))
