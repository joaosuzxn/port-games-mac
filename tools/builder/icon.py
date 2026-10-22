"""Extracts the icon from the .exe (RT_GROUP_ICON/RT_ICON) and converts it to .icns with sips + iconutil."""
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

RT_ICON = 3
RT_GROUP_ICON = 14
ICONSET_SIZES = (16, 32, 128, 256, 512)


def _resources(data: bytes) -> dict[int, dict[int, bytes]]:
    """{type: {id: bytes}} from the PE resource directory (first language of each id). Empty if there is none."""
    e = struct.unpack_from("<I", data, 0x3C)[0]
    n_sections = struct.unpack_from("<H", data, e + 6)[0]
    opt_size = struct.unpack_from("<H", data, e + 20)[0]
    opt = e + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    directories = opt + (96 if magic == 0x10B else 112)
    if struct.unpack_from("<I", data, directories - 4)[0] <= 2:
        return {}
    rva_rsrc = struct.unpack_from("<I", data, directories + 8 * 2)[0]
    if rva_rsrc == 0:
        return {}
    sections = [struct.unpack_from("<IIII", data, opt + opt_size + 40 * i + 8) for i in range(n_sections)]

    def offset(rva):
        for vs, va, rs, ro in sections:
            if va <= rva < va + max(vs, rs):
                return rva - va + ro
        raise ValueError(f"RVA {rva:#x} outside the sections")

    base = offset(rva_rsrc)

    def entries(o):
        named, ids = struct.unpack_from("<HH", data, o + 12)
        for i in range(named + ids):
            yield struct.unpack_from("<II", data, o + 16 + 8 * i)

    result: dict[int, dict[int, bytes]] = {}
    for rtype, p1 in entries(base):
        if not p1 & 0x80000000:
            continue
        for res_id, p2 in entries(base + (p1 & 0x7FFFFFFF)):
            target = p2
            if target & 0x80000000:  # language level: take the first
                target = next(entries(base + (target & 0x7FFFFFFF)))[1]
            rva, size = struct.unpack_from("<II", data, base + target)
            result.setdefault(rtype, {})[res_id] = data[offset(rva):offset(rva) + size]
    return result


def _ico_of_largest(resources: dict[int, dict[int, bytes]]) -> bytes | None:
    groups = resources.get(RT_GROUP_ICON, {})
    icons = resources.get(RT_ICON, {})
    if not groups or not icons:
        return None
    group = next(iter(groups.values()))
    count = struct.unpack_from("<H", group, 4)[0]
    chosen = None
    for i in range(count):
        w, h, colors, reserved, planes, bits, size, res_id = struct.unpack_from("<BBBBHHIH", group, 6 + 14 * i)
        side = w or 256
        if res_id in icons and (chosen is None or side > chosen[0]):
            chosen = (side, struct.pack("<BBBBHHII", w, h, colors, reserved, planes, bits, len(icons[res_id]), 22), icons[res_id])
    if chosen is None:
        return None
    return struct.pack("<HHH", 0, 1, 1) + chosen[1] + chosen[2]


def extract_icon(exe: Path, target_icns: Path) -> bool:
    try:
        ico = _ico_of_largest(_resources(Path(exe).read_bytes()))
    except (struct.error, ValueError):
        return False
    if ico is None:
        return False
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "icon.ico").write_bytes(ico)
        png = tmp / "icon.png"
        subprocess.run(["sips", "-s", "format", "png", str(tmp / "icon.ico"), "--out", str(png)], check=True, capture_output=True)
        iconset = tmp / "icon.iconset"
        iconset.mkdir()
        for side in ICONSET_SIZES:
            for scale, suffix in ((1, ""), (2, "@2x")):
                output = iconset / f"icon_{side}x{side}{suffix}.png"
                subprocess.run(["sips", "-z", str(side * scale), str(side * scale), str(png), "--out", str(output)],
                               check=True, capture_output=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(tmp / "icon.icns")], check=True, capture_output=True)
        target_icns.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(tmp / "icon.icns", target_icns)
    return True
