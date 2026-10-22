import struct
import tempfile
import unittest
from pathlib import Path

from icon import extract_icon

REAL_EXE = Path(__file__).resolve().parents[2] / "jogo" / "bak" / "Cars.exe"


def minimal_pe_without_resources() -> bytes:
    dos = bytearray(0x40)
    dos[0:2] = b"MZ"
    struct.pack_into("<I", dos, 0x3C, 0x40)
    coff = struct.pack("<HHIIIHH", 0x14C, 0, 0, 0, 0, 224, 0x102)
    optional = bytearray(224)
    struct.pack_into("<H", optional, 0, 0x10B)
    struct.pack_into("<I", optional, 92, 16)  # NumberOfRvaAndSizes; the resource directory is left zeroed
    return bytes(dos) + b"PE\0\0" + coff + bytes(optional)


class TestIcon(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    @unittest.skipUnless(REAL_EXE.exists(), "jogo/bak/Cars.exe not downloaded")
    def test_cars_icon(self):
        target = self.tmp / "Carros.icns"
        self.assertTrue(extract_icon(REAL_EXE, target))
        self.assertGreater(target.stat().st_size, 1000)
        self.assertEqual(target.read_bytes()[:4], b"icns")

    def test_icon_without_resource(self):
        exe = self.tmp / "empty.exe"
        exe.write_bytes(minimal_pe_without_resources())
        target = self.tmp / "x.icns"
        self.assertFalse(extract_icon(exe, target))
        self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
