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
from build import main, montar as montar_app
from prefix import PrefixoFalhou
from recipe import carregar_receita


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
        receita = replace(carregar_receita(Path(build.__file__).parent / "recipes" / "carros.json"),
                          sha1_exe=hashlib.sha1(b"build bom").hexdigest())
        with mock.patch("build.carregar_receita", return_value=receita):
            codigo, erro = self._rodar(["carros", "--saida", str(self.saida), "--jogo", str(jogo)])
        self.assertNotEqual(codigo, 0)
        self.assertIn("incompleto", erro)
        self.assertIn("Data/Global.pak", erro)
        self.assertFalse(self.saida.exists() and any(self.saida.iterdir()))

    def test_main_receita_inexistente(self):
        codigo, erro = self._rodar(["pacman", "--saida", str(self.saida)])
        self.assertNotEqual(codigo, 0)
        self.assertIn("pacman", erro)


LAUNCHER = r'''#!/bin/sh
case "$1" in
WSS-wineprefixcreate)
  [ -f "$(dirname "$0")/../falhar" ] && exit 0
  app=$(cd "$(dirname "$0")/../.." && pwd -P)
  esc=$(printf '%s' "$app" | sed 's#/#\\\\#g')
  p="$app/Contents/SharedSupport/prefix"
  mkdir -p "$p/drive_c/users/joao" "$p/dosdevices"
  printf '[Software\\\\Fonts] 1\n"Marlett"="Z:%s\\\\Contents\\\\m.ttf"\n' "$esc" > "$p/system.reg"
  printf '"InstallSource"="%s/Contents/mono"\n' "$app" > "$p/user.reg"
  ;;
esac
exit 0
'''


def _tar(origem: Path, destino: Path, raiz: str):
    subprocess.run(["tar", "-cJf", str(destino), "-C", str(origem), raiz], check=True)


class TestMontarIntegracao(unittest.TestCase):
    """Fluxo completo com template/engine/launcher falsos, em pastas temporárias."""

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

        self.jogo = self.tmp / "jogo"
        (self.jogo / "bak").mkdir(parents=True)
        (self.jogo / "bak" / "Cars.exe").write_bytes(b"build bom")
        (self.jogo / "Data").mkdir()
        (self.jogo / "Data" / "Global.pak").write_bytes(b"pak")
        self.receita = replace(carregar_receita(Path(build.__file__).parent / "recipes" / "carros.json"),
                               sha1_exe=hashlib.sha1(b"build bom").hexdigest(),
                               arquivos_obrigatorios=("Data/Global.pak",), registro=(), pasta_saves=None, rotulo_cd=None)
        self.saida = self.tmp / "build"
        self.cache = self.tmp / "cache"
        self.apps = self.tmp / "Applications"
        self.apps.mkdir()

    def _montar(self, instalar=False):
        fonte = lambda a, cache, fontes: self.template if a.nome == "template" else self.engine
        with mock.patch("build.carregar_receita", return_value=self.receita), \
                mock.patch("build.garantir_artefato", side_effect=fonte), \
                contextlib.redirect_stdout(io.StringIO()):
            return montar_app("carros", self.saida, self.cache, self.jogo, instalar, self.apps)

    def test_monta_e_registro_aponta_para_o_app_final(self):
        app = self._montar()
        self.assertEqual(app, self.saida / "Carros.app")
        reg = (app / "Contents" / "SharedSupport" / "prefix" / "system.reg").read_text()
        self.assertIn("Z:" + str(app).replace("/", "\\\\") + "\\\\Contents", reg)
        self.assertNotIn(".montando", reg)
        self.assertEqual([p.name for p in self.saida.iterdir()], ["Carros.app"])

    def test_falha_no_meio_mantem_o_app_anterior(self):
        app = self._montar()
        (app / "Contents" / "marca").write_text("app bom")
        # o próximo template cria o prefixo vazio: criar_prefixo falha no meio da montagem
        t = self.tmp / "t2" / "T.app" / "Contents"
        (t / "Configure.app").mkdir(parents=True)
        (t / "MacOS").mkdir()
        (t / "SharedSupport").mkdir()
        (t / "falhar").write_text("")
        (t / "MacOS" / "wineskinlauncher").write_text(LAUNCHER)
        os.chmod(t / "MacOS" / "wineskinlauncher", 0o755)
        with open(t / "Info.plist", "wb") as f:
            plistlib.dump({}, f)
        self.template = self.tmp / "T2.tar.xz"
        _tar(self.tmp / "t2", self.template, "T.app")
        with self.assertRaises(PrefixoFalhou):
            self._montar()
        self.assertEqual((app / "Contents" / "marca").read_text(), "app bom")
        self.assertEqual([p.name for p in self.saida.iterdir()], ["Carros.app"])

    def test_limpa_montagens_abandonadas(self):
        velho = self.saida / ".montando-antigo"
        velho.mkdir(parents=True)
        (velho / "lixo").write_text("x")
        self._montar()
        self.assertFalse(velho.exists())

    def test_instalar_relocaliza_e_troca(self):
        self._montar(instalar=True)
        destino = self.apps / "Carros.app"
        reg = (destino / "Contents" / "SharedSupport" / "prefix" / "system.reg").read_text()
        self.assertIn("Z:" + str(destino).replace("/", "\\\\") + "\\\\Contents", reg)
        self.assertNotIn(str(self.saida).replace("/", "\\\\"), reg)
        self.assertEqual([p.name for p in self.apps.iterdir()], ["Carros.app"])
        self._montar(instalar=True)  # reinstalar sobre o mesmo bundle id
        self.assertEqual([p.name for p in self.apps.iterdir()], ["Carros.app"])

    def test_instalar_recusa_destino_com_outro_bundle_id(self):
        outro = self.apps / "Carros.app" / "Contents"
        outro.mkdir(parents=True)
        with open(outro / "Info.plist", "wb") as f:
            plistlib.dump({"CFBundleIdentifier": "com.outra.coisa"}, f)
        (outro / "marca").write_text("intacto")
        with self.assertRaises(PrefixoFalhou) as ctx:
            self._montar(instalar=True)
        self.assertIn("com.outra.coisa", str(ctx.exception))
        self.assertEqual((outro / "marca").read_text(), "intacto")
        self.assertFalse(self.saida.exists() and any(self.saida.iterdir()))


if __name__ == "__main__":
    unittest.main()
