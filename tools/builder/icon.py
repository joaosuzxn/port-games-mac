"""Extrai o ícone do .exe (RT_GROUP_ICON/RT_ICON) e converte para .icns com sips + iconutil."""
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

RT_ICON = 3
RT_GROUP_ICON = 14
TAMANHOS_ICONSET = (16, 32, 128, 256, 512)


def _recursos(dados: bytes) -> dict[int, dict[int, bytes]]:
    """{tipo: {id: bytes}} do diretório de recursos do PE (primeiro idioma de cada id). Vazio se não houver."""
    e = struct.unpack_from("<I", dados, 0x3C)[0]
    nsec = struct.unpack_from("<H", dados, e + 6)[0]
    tam_opt = struct.unpack_from("<H", dados, e + 20)[0]
    opt = e + 24
    magic = struct.unpack_from("<H", dados, opt)[0]
    diretorios = opt + (96 if magic == 0x10B else 112)
    if struct.unpack_from("<I", dados, diretorios - 4)[0] <= 2:
        return {}
    rva_rsrc = struct.unpack_from("<I", dados, diretorios + 8 * 2)[0]
    if rva_rsrc == 0:
        return {}
    secoes = [struct.unpack_from("<IIII", dados, opt + tam_opt + 40 * i + 8) for i in range(nsec)]

    def offset(rva):
        for vs, va, rs, ro in secoes:
            if va <= rva < va + max(vs, rs):
                return rva - va + ro
        raise ValueError(f"RVA {rva:#x} fora das seções")

    base = offset(rva_rsrc)

    def entradas(o):
        nomeadas, ids = struct.unpack_from("<HH", dados, o + 12)
        for i in range(nomeadas + ids):
            yield struct.unpack_from("<II", dados, o + 16 + 8 * i)

    resultado: dict[int, dict[int, bytes]] = {}
    for tipo, p1 in entradas(base):
        if not p1 & 0x80000000:
            continue
        for ident, p2 in entradas(base + (p1 & 0x7FFFFFFF)):
            alvo = p2
            if alvo & 0x80000000:  # nível de idioma: pega o primeiro
                alvo = next(entradas(base + (alvo & 0x7FFFFFFF)))[1]
            rva, tam = struct.unpack_from("<II", dados, base + alvo)
            resultado.setdefault(tipo, {})[ident] = dados[offset(rva):offset(rva) + tam]
    return resultado


def _ico_do_maior(recursos: dict[int, dict[int, bytes]]) -> bytes | None:
    grupos = recursos.get(RT_GROUP_ICON, {})
    icones = recursos.get(RT_ICON, {})
    if not grupos or not icones:
        return None
    grupo = next(iter(grupos.values()))
    qtd = struct.unpack_from("<H", grupo, 4)[0]
    escolhido = None
    for i in range(qtd):
        w, h, cores, res, planos, bits, tam, ident = struct.unpack_from("<BBBBHHIH", grupo, 6 + 14 * i)
        lado = w or 256
        if ident in icones and (escolhido is None or lado > escolhido[0]):
            escolhido = (lado, struct.pack("<BBBBHHII", w, h, cores, res, planos, bits, len(icones[ident]), 22), icones[ident])
    if escolhido is None:
        return None
    return struct.pack("<HHH", 0, 1, 1) + escolhido[1] + escolhido[2]


def extrair_icone(exe: Path, destino_icns: Path) -> bool:
    try:
        ico = _ico_do_maior(_recursos(Path(exe).read_bytes()))
    except (struct.error, ValueError):
        return False
    if ico is None:
        return False
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "icone.ico").write_bytes(ico)
        png = tmp / "icone.png"
        subprocess.run(["sips", "-s", "format", "png", str(tmp / "icone.ico"), "--out", str(png)], check=True, capture_output=True)
        iconset = tmp / "icone.iconset"
        iconset.mkdir()
        for lado in TAMANHOS_ICONSET:
            for escala, sufixo in ((1, ""), (2, "@2x")):
                saida = iconset / f"icon_{lado}x{lado}{sufixo}.png"
                subprocess.run(["sips", "-z", str(lado * escala), str(lado * escala), str(png), "--out", str(saida)],
                               check=True, capture_output=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(tmp / "icone.icns")], check=True, capture_output=True)
        destino_icns.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(tmp / "icone.icns", destino_icns)
    return True
