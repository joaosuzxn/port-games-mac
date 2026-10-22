import struct
import tempfile
import unittest
from pathlib import Path

from icon import extrair_icone

EXE_REAL = Path(__file__).resolve().parents[2] / "jogo" / "bak" / "Cars.exe"


def pe_minimo_sem_recursos() -> bytes:
    dos = bytearray(0x40)
    dos[0:2] = b"MZ"
    struct.pack_into("<I", dos, 0x3C, 0x40)
    coff = struct.pack("<HHIIIHH", 0x14C, 0, 0, 0, 0, 224, 0x102)
    opcional = bytearray(224)
    struct.pack_into("<H", opcional, 0, 0x10B)
    struct.pack_into("<I", opcional, 92, 16)  # NumberOfRvaAndSizes; diretório de recursos fica zerado
    return bytes(dos) + b"PE\0\0" + coff + bytes(opcional)


class TestIcone(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    @unittest.skipUnless(EXE_REAL.exists(), "jogo/bak/Cars.exe não baixado")
    def test_icone_cars(self):
        destino = self.tmp / "Carros.icns"
        self.assertTrue(extrair_icone(EXE_REAL, destino))
        self.assertGreater(destino.stat().st_size, 1000)
        self.assertEqual(destino.read_bytes()[:4], b"icns")

    def test_icone_sem_recurso(self):
        exe = self.tmp / "vazio.exe"
        exe.write_bytes(pe_minimo_sem_recursos())
        destino = self.tmp / "x.icns"
        self.assertFalse(extrair_icone(exe, destino))
        self.assertFalse(destino.exists())


if __name__ == "__main__":
    unittest.main()
