import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from artifacts import Artifact, InvalidArtifact, _download, ensure_artifact, load_artifacts, sha256_file


class TestArtifacts(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.cache = self.tmp / "cache"
        self.source = self.tmp / "source"
        self.source.mkdir()
        self.content = b"fake engine"
        (self.source / "engine.tar.xz").write_bytes(self.content)
        self.art = Artifact("engine", "engine.tar.xz", hashlib.sha256(self.content).hexdigest(), None)

    def test_sha256_file(self):
        self.assertEqual(sha256_file(self.source / "engine.tar.xz"), self.art.sha256)

    def test_ensures_from_local_source(self):
        path = ensure_artifact(self.art, self.cache, [self.source])
        self.assertEqual(path, self.cache / "engine.tar.xz")
        self.assertEqual(path.read_bytes(), self.content)

    def test_wrong_hash_refuses(self):
        (self.source / "engine.tar.xz").write_bytes(b"something else")
        with self.assertRaises(InvalidArtifact):
            ensure_artifact(self.art, self.cache, [self.source])
        self.assertFalse((self.cache / "engine.tar.xz").exists())

    def test_already_in_cache_does_not_copy(self):
        ensure_artifact(self.art, self.cache, [self.source])
        (self.source / "engine.tar.xz").unlink()
        self.assertEqual(ensure_artifact(self.art, self.cache, [self.source]), self.cache / "engine.tar.xz")

    def test_corrupted_cache_is_rebuilt(self):
        self.cache.mkdir()
        (self.cache / "engine.tar.xz").write_bytes(b"half done")
        path = ensure_artifact(self.art, self.cache, [self.source])
        self.assertEqual(path.read_bytes(), self.content)

    def test_no_source_no_url(self):
        (self.source / "engine.tar.xz").unlink()
        with self.assertRaises(InvalidArtifact) as ctx:
            ensure_artifact(self.art, self.cache, [self.source])
        self.assertIn(str(self.source), str(ctx.exception))

    def test_loads_project_artifacts(self):
        arts = load_artifacts(Path(__file__).parent / "artifacts.json")
        self.assertEqual(arts["engine"].file, "WS12WineSikarugir11.0_1.tar.xz")
        self.assertEqual(arts["engine"].sha256, "67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e")
        self.assertEqual(arts["template"].file, "Template-1.0.24.tar.xz")
        self.assertTrue(arts["template"].url.startswith("https://github.com/Sikarugir-App/Template/"))


class TestDownload(unittest.TestCase):
    def test_removes_partial_if_the_download_fails(self):
        tmp = Path(tempfile.mkdtemp())

        class Resp:
            def __enter__(self): return self
            def __exit__(self, *a): return False
            def read(self, n=-1): raise ConnectionResetError("dropped")

        target = tmp / "x.tar.xz"
        with mock.patch("artifacts.urllib.request.urlopen", return_value=Resp()):
            with self.assertRaises(OSError):
                _download("https://example.invalid/x", target, "0" * 64)
        self.assertEqual(list(tmp.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
