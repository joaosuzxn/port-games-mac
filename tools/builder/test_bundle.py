import os
import plistlib
import subprocess
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from bundle import montar_bundle, remover_configuracao, substituir_app
from recipe import carregar_receita

RECEITA = carregar_receita(Path(__file__).parent / "recipes" / "carros.json")

PLIST_TEMPLATE = {
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


def _tar(origem: Path, destino: Path, raiz: str):
    subprocess.run(["tar", "-cJf", str(destino), "-C", str(origem), raiz], check=True)


class TestBundle(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        t = self.tmp / "t" / "Template-1.0.24.app" / "Contents"
        (t / "Configure.app" / "Contents").mkdir(parents=True)
        (t / "SharedSupport").mkdir()
        (t / "MacOS").mkdir()
        (t / "MacOS" / "launcher").write_text("#!/bin/sh\n")
        with open(t / "Info.plist", "wb") as f:
            plistlib.dump(PLIST_TEMPLATE, f)
        self.template = self.tmp / "Template-1.0.24.tar.xz"
        _tar(self.tmp / "t", self.template, "Template-1.0.24.app")

        e = self.tmp / "e" / "wswine.bundle" / "bin"
        e.mkdir(parents=True)
        (e / "wine").write_text("#!/bin/sh\n")
        os.chmod(e / "wine", 0o755)
        self.engine = self.tmp / "engine.tar.xz"
        _tar(self.tmp / "e", self.engine, "wswine.bundle")

        self.saida = self.tmp / "build com espaço"

    def _montar(self, receita=RECEITA):
        return montar_bundle(self.template, self.engine, self.saida, receita)

    def _plist(self, app):
        with open(app / "Contents" / "Info.plist", "rb") as f:
            return plistlib.load(f)

    def test_monta_estrutura(self):
        app = self._montar()
        self.assertEqual(app, self.saida / "Carros.app")
        wine = app / "Contents" / "SharedSupport" / "wine" / "bin" / "wine"
        self.assertTrue(wine.is_file())
        self.assertTrue(os.access(wine, os.X_OK))
        # o launcher precisa do Configure.app (remakedefaults.reg) para criar o prefixo
        self.assertTrue((app / "Contents" / "Configure.app").exists())

    def test_remover_configuracao(self):
        app = self._montar()
        remover_configuracao(app)
        self.assertFalse((app / "Contents" / "Configure.app").exists())
        remover_configuracao(app)  # idempotente

    def test_info_plist(self):
        p = self._plist(self._montar(replace(RECEITA, renderizador="d9vk")))
        self.assertEqual(p["CFBundleName"], "Carros")
        self.assertEqual(p["CFBundleIdentifier"], "local.portcarros.carros")
        self.assertEqual(p["Program Name and Path"], "/Games/Carros/Cars.exe")
        self.assertEqual((p["D9VK"], p["DXVK"], p["D3DMETAL"]), (1, 0, 0))
        self.assertEqual(p["Debug Mode"], 0)
        self.assertEqual(p["WINEDEBUG"], "-all")
        self.assertEqual(p["Symlinks In User Folder"], 0)

    def test_renderizador_wined3d_desliga_todos(self):
        p = self._plist(self._montar(replace(RECEITA, renderizador="wined3d")))
        self.assertEqual((p["D9VK"], p["DXVK"], p["D3DMETAL"]), (0, 0, 0))

    def test_remontar_substitui(self):
        app = self._montar()
        (app / "Contents" / "lixo.txt").write_text("velho")
        app2 = self._montar()
        self.assertEqual(app2, app)
        self.assertFalse((app / "Contents" / "lixo.txt").exists())
        self.assertFalse((app / "Carros.app").exists())
        self.assertEqual(sorted(p.name for p in self.saida.iterdir()), ["Carros.app"])

    def test_plist_sem_caminho_absoluto(self):
        p = self._plist(self._montar())
        for chave, valor in p.items():
            if isinstance(valor, str):
                self.assertNotIn(str(self.saida), valor, chave)


class TestSubstituirApp(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.novo = self.tmp / "trabalho" / "Carros.app"
        (self.novo / "Contents").mkdir(parents=True)
        (self.novo / "Contents" / "marca").write_text("novo")
        self.final = self.tmp / "build" / "Carros.app"
        self.final.parent.mkdir()

    def test_sem_app_anterior(self):
        substituir_app(self.novo, self.final)
        self.assertEqual((self.final / "Contents" / "marca").read_text(), "novo")
        self.assertFalse(self.novo.exists())

    def test_troca_e_apaga_o_velho(self):
        (self.final / "Contents").mkdir(parents=True)
        (self.final / "Contents" / "marca").write_text("velho")
        substituir_app(self.novo, self.final)
        self.assertEqual((self.final / "Contents" / "marca").read_text(), "novo")
        self.assertEqual([p.name for p in self.final.parent.iterdir()], ["Carros.app"])

    def test_falha_na_troca_devolve_o_velho(self):
        (self.final / "Contents").mkdir(parents=True)
        (self.final / "Contents" / "marca").write_text("velho")
        with self.assertRaises(OSError):
            substituir_app(self.tmp / "nao-existe.app", self.final)
        self.assertEqual((self.final / "Contents" / "marca").read_text(), "velho")


if __name__ == "__main__":
    unittest.main()
