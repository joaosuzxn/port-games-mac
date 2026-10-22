import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from montar import main


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

    def test_main_receita_inexistente(self):
        codigo, erro = self._rodar(["pacman", "--saida", str(self.saida)])
        self.assertNotEqual(codigo, 0)
        self.assertIn("pacman", erro)


if __name__ == "__main__":
    unittest.main()
