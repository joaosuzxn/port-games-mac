import contextlib
import io
import tempfile
import hashlib
import unittest
from dataclasses import replace
from pathlib import Path
from unittest import mock

import montar
from montar import main
from receita import carregar_receita


class TestMain(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.saida = self.tmp / "build"

    def _rodar(self, argv):
        erro = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(erro):
            codigo = main(argv)
        return codigo, erro.getvalue()

    def test_main_sem_jogo(self):
        codigo, erro = self._rodar(["carros", "--saida", str(self.saida), "--jogo", str(self.tmp / "nada")])
        self.assertNotEqual(codigo, 0)
        self.assertIn("steamcmd", erro)
        self.assertFalse(self.saida.exists() and any(self.saida.iterdir()))

    def test_main_hash_errado_nao_monta(self):
        jogo = self.tmp / "jogo"
        (jogo / "bak").mkdir(parents=True)
        (jogo / "bak" / "Cars.exe").write_bytes(b"outro build")
        codigo, erro = self._rodar(["carros", "--saida", str(self.saida), "--jogo", str(jogo)])
        self.assertNotEqual(codigo, 0)
        self.assertIn("SHA-1", erro)
        self.assertFalse(self.saida.exists() and any(self.saida.iterdir()))

    def test_main_jogo_incompleto_nao_monta(self):
        jogo = self.tmp / "jogo"
        (jogo / "bak").mkdir(parents=True)
        (jogo / "bak" / "Cars.exe").write_bytes(b"build bom")
        receita = replace(carregar_receita(Path(montar.__file__).parent / "receitas" / "carros.json"),
                          sha1_exe=hashlib.sha1(b"build bom").hexdigest())
        with mock.patch("montar.carregar_receita", return_value=receita):
            codigo, erro = self._rodar(["carros", "--saida", str(self.saida), "--jogo", str(jogo)])
        self.assertNotEqual(codigo, 0)
        self.assertIn("incompleto", erro)
        self.assertIn("Data/Global.pak", erro)
        self.assertFalse(self.saida.exists() and any(self.saida.iterdir()))

    def test_main_receita_inexistente(self):
        codigo, erro = self._rodar(["pacman", "--saida", str(self.saida)])
        self.assertNotEqual(codigo, 0)
        self.assertIn("pacman", erro)


if __name__ == "__main__":
    unittest.main()
