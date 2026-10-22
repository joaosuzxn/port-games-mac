"""SPIKE (descartável): instala a ponte lsteamclient num .app montado pelo tools/montar.

Uso: python3 spikes/ponte-steam/instalar_ponte.py <App.app> <appid> <pasta_do_jogo_windows> <exe>
Ex.:  python3 spikes/ponte-steam/instalar_ponte.py build/Spacewar.app 480 'C:\\Games\\Spacewar' SteamworksExample.exe

Layout copiado do Neutron (https://github.com/mont127/Neutron, Apache-2.0):
- lsteamclient.so no lado unix do wine do app; lsteamclient.dll (i386/x86_64) no wine e no prefixo
- Program Files (x86)/Steam: steamclient.dll (forwarder i386), bin64/steamclient.dll e steamclient64.dll
  (forwarder x86_64), steam.exe (stub que finge a Steam rodando)
- SteamAppId/SteamGameId e STEAM_COMPAT_CLIENT_INSTALL_PATH (pasta do steamclient.dylib da Steam do Mac)
Os binários da ponte vêm de ~/Library/Caches/portcarros/fontes (licença Steamworks SDK: nunca no git).
"""
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "tools" / "montar"))
from prefixo import parar_wine  # noqa: E402

FONTES = Path.home() / "Library/Caches/portcarros/fontes"
LSC = FONTES / "wine-build-dual/dlls/lsteamclient"
PEFORWARD = FONTES / "neutron/src/peforward.py"
STEAM_MAC = Path.home() / "Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
AQUI = Path(__file__).resolve().parent


def copiar(de: Path, para: Path) -> None:
    para.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(de, para)
    print(f"  {para}")


def forwarder(bridge: Path, saida: Path) -> None:
    saida.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(PEFORWARD), "gen", str(bridge), "lsteamclient", str(saida)], check=True)
    subprocess.run([sys.executable, str(PEFORWARD), "check", str(bridge), str(saida), "lsteamclient"], check=True)
    print(f"  {saida} (forwarder)")


def main(app: Path, appid: str, pasta_jogo: str, exe: str) -> None:
    app = app.resolve()
    contents = app / "Contents"
    wine_lib = contents / "SharedSupport/wine/lib/wine"
    prefixo = contents / "SharedSupport/prefix"
    steam = prefixo / "drive_c/Program Files (x86)/Steam"
    pe32, pe64, so = LSC / "i386-windows/lsteamclient.dll", LSC / "x86_64-windows/lsteamclient.dll", LSC / "lsteamclient.so"
    for f in (pe32, pe64, so, STEAM_MAC / "steamclient.dylib"):
        if not f.is_file():
            sys.exit(f"faltando: {f}")

    parar_wine(app)
    print("ponte no wine do app:")
    copiar(so, wine_lib / "x86_64-unix/lsteamclient.so")
    subprocess.run(["codesign", "--remove-signature", str(wine_lib / "x86_64-unix/lsteamclient.so")], capture_output=True)
    copiar(pe64, wine_lib / "x86_64-windows/lsteamclient.dll")
    copiar(pe32, wine_lib / "i386-windows/lsteamclient.dll")
    print("ponte no prefixo:")
    copiar(pe64, prefixo / "drive_c/windows/system32/lsteamclient.dll")
    copiar(pe32, prefixo / "drive_c/windows/syswow64/lsteamclient.dll")
    print("Steam falsa:")
    forwarder(pe32, steam / "steamclient.dll")
    forwarder(pe64, steam / "bin64/steamclient.dll")
    copiar(steam / "bin64/steamclient.dll", steam / "steamclient64.dll")
    subprocess.run(["x86_64-w64-mingw32-gcc", "-O2", "-mwindows", "-o", str(steam / "steam.exe"),
                    str(AQUI / "steam_stub.c"), "-ladvapi32", "-luser32"], check=True)
    print(f"  {steam / 'steam.exe'} (stub)")

    bat = prefixo / "drive_c/iniciar.bat"
    bat.write_text(
        "@echo off\r\n"
        'start "" "C:\\Program Files (x86)\\Steam\\steam.exe"\r\n'
        "ping -n 3 127.0.0.1 >nul\r\n"
        f'cd /d "{pasta_jogo}"\r\n'
        f'start "" "{exe}"\r\n',
        encoding="ascii",
    )
    plist = contents / "Info.plist"
    with open(plist, "rb") as f:
        dados = plistlib.load(f)
    dados["Program Name and Path"] = "/iniciar.bat"
    dados["CLI Custom Commands"] = (
        f'export SteamAppId={appid}; export SteamGameId={appid}; '
        f'export STEAM_COMPAT_CLIENT_INSTALL_PATH="{STEAM_MAC}"'
    )
    dados["Debug Mode"] = 1
    dados["WINEDEBUG"] = "-all,+steamclient,+loaddll,err+all"
    with open(plist, "wb") as f:
        plistlib.dump(dados, f)
    print("Info.plist: iniciar.bat + variáveis da Steam; log em Contents/SharedSupport/Logs/LastRunWine.log")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4])
