import json
import tempfile
import unittest
from pathlib import Path

from receita import ChaveRegistro, ReceitaInvalida, carregar_receita

RECEITAS = Path(__file__).parent / "receitas"


class TestReceitaCarros(unittest.TestCase):
    def setUp(self):
        self.r = carregar_receita(RECEITAS / "carros.json")

    def test_carrega_carros(self):
        r = self.r
        self.assertEqual(r.nome, "carros")
        self.assertEqual(r.nome_app, "Carros")
        self.assertEqual(r.bundle_id, "local.portcarros.carros")
        self.assertEqual(r.pasta_jogo, "jogo")
        self.assertEqual(r.exe_origem, "bak/Cars.exe")
        self.assertEqual(r.exe_destino, "Cars.exe")
        self.assertEqual(r.sha1_exe, "a175e49a8cd3aa67ffd71b7cf1a8d0c90b527902")
        self.assertEqual(r.rotulo_cd, "DISC2")
        self.assertEqual(r.pasta_saves, "THQ")
        self.assertEqual(r.renderizador, "d9vk")
        for item in ("_jvm", "_uninst", "_CommonRedist", "steamapps", "THQ Website.url", "Cars.exe", "bak"):
            self.assertIn(item, r.excluir)

    def test_registro_carros(self):
        self.assertIn(ChaveRegistro("system", r"Software\Wine\Drives", {"d:": "cdrom"}), self.r.registro)
        # tela cheia: emulação de troca de resolução, sem área de trabalho virtual (ADR 0002)
        self.assertIn(ChaveRegistro("user", r"Software\Wine\X11 Driver", {"EmulateModeset": "y"}), self.r.registro)
        self.assertFalse(any(c.chave.startswith(r"Software\Wine\Explorer") for c in self.r.registro))


class TestReceitaInvalida(unittest.TestCase):
    def _gravar(self, alterar):
        dados = json.loads((RECEITAS / "carros.json").read_text(encoding="utf-8"))
        alterar(dados)
        tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        json.dump(dados, tmp)
        tmp.close()
        self.addCleanup(Path(tmp.name).unlink)
        return Path(tmp.name)

    def test_campo_faltando(self):
        caminho = self._gravar(lambda d: d.pop("sha1_exe"))
        with self.assertRaises(ReceitaInvalida) as ctx:
            carregar_receita(caminho)
        self.assertIn("sha1_exe", str(ctx.exception))

    def test_renderizador_invalido(self):
        caminho = self._gravar(lambda d: d.update(renderizador="vulkan"))
        with self.assertRaises(ReceitaInvalida):
            carregar_receita(caminho)

    def test_sha1_malformado(self):
        caminho = self._gravar(lambda d: d.update(sha1_exe="abc123"))
        with self.assertRaises(ReceitaInvalida):
            carregar_receita(caminho)


if __name__ == "__main__":
    unittest.main()
