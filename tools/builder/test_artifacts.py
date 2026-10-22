import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from artifacts import Artefato, ArtefatoInvalido, _baixar, carregar_artefatos, garantir_artefato, sha256_arquivo


class TestArtefatos(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.cache = self.tmp / "cache"
        self.fonte = self.tmp / "fonte"
        self.fonte.mkdir()
        self.conteudo = b"engine falsa"
        (self.fonte / "engine.tar.xz").write_bytes(self.conteudo)
        self.art = Artefato("engine", "engine.tar.xz", hashlib.sha256(self.conteudo).hexdigest(), None)

    def test_sha256_arquivo(self):
        self.assertEqual(sha256_arquivo(self.fonte / "engine.tar.xz"), self.art.sha256)

    def test_garante_de_fonte_local(self):
        caminho = garantir_artefato(self.art, self.cache, [self.fonte])
        self.assertEqual(caminho, self.cache / "engine.tar.xz")
        self.assertEqual(caminho.read_bytes(), self.conteudo)

    def test_hash_errado_recusa(self):
        (self.fonte / "engine.tar.xz").write_bytes(b"outra coisa")
        with self.assertRaises(ArtefatoInvalido):
            garantir_artefato(self.art, self.cache, [self.fonte])
        self.assertFalse((self.cache / "engine.tar.xz").exists())

    def test_ja_no_cache_nao_copia(self):
        garantir_artefato(self.art, self.cache, [self.fonte])
        (self.fonte / "engine.tar.xz").unlink()
        self.assertEqual(garantir_artefato(self.art, self.cache, [self.fonte]), self.cache / "engine.tar.xz")

    def test_cache_corrompido_e_refeito(self):
        self.cache.mkdir()
        (self.cache / "engine.tar.xz").write_bytes(b"pela metade")
        caminho = garantir_artefato(self.art, self.cache, [self.fonte])
        self.assertEqual(caminho.read_bytes(), self.conteudo)

    def test_sem_fonte_sem_url(self):
        (self.fonte / "engine.tar.xz").unlink()
        with self.assertRaises(ArtefatoInvalido) as ctx:
            garantir_artefato(self.art, self.cache, [self.fonte])
        self.assertIn(str(self.fonte), str(ctx.exception))

    def test_carrega_artefatos_do_projeto(self):
        arts = carregar_artefatos(Path(__file__).parent / "artifacts.json")
        self.assertEqual(arts["engine"].arquivo, "WS12WineSikarugir11.0_1.tar.xz")
        self.assertEqual(arts["engine"].sha256, "67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e")
        self.assertEqual(arts["template"].arquivo, "Template-1.0.24.tar.xz")
        self.assertTrue(arts["template"].url.startswith("https://github.com/Sikarugir-App/Template/"))


class TestBaixar(unittest.TestCase):
    def test_apaga_parcial_se_o_download_falha(self):
        tmp = Path(tempfile.mkdtemp())

        class Resp:
            def __enter__(self): return self
            def __exit__(self, *a): return False
            def read(self, n=-1): raise ConnectionResetError("caiu")

        destino = tmp / "x.tar.xz"
        with mock.patch("artifacts.urllib.request.urlopen", return_value=Resp()):
            with self.assertRaises(OSError):
                _baixar("https://exemplo.invalid/x", destino, "0" * 64)
        self.assertEqual(list(tmp.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
