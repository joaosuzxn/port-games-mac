"""SPIKE (disposable): installs the lsteamclient bridge into an .app built by tools/builder.

Usage: python3 spikes/steam-bridge/install_bridge.py <App.app> <appid> <windows_game_dir> <exe>
E.g.:  python3 spikes/steam-bridge/install_bridge.py build/Spacewar.app 480 'C:\\Games\\Spacewar' SteamworksExample.exe

Layout copied from Neutron (https://github.com/mont127/Neutron, Apache-2.0):
- lsteamclient.so on the unix side of the app's wine; lsteamclient.dll (i386/x86_64) in the wine and in the prefix
- Program Files (x86)/Steam: steamclient.dll (i386 forwarder), bin64/steamclient.dll and steamclient64.dll
  (x86_64 forwarder), steam.exe (stub that pretends Steam is running)
- SteamAppId/SteamGameId and STEAM_COMPAT_CLIENT_INSTALL_PATH (folder of the Mac Steam's steamclient.dylib)
The bridge binaries come from ~/Library/Caches/portcarros/fontes (Steamworks SDK license: never in git).
"""
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "builder"))
from prefix import stop_wine  # noqa: E402

SOURCES = Path.home() / "Library/Caches/portcarros/fontes"
LSC = SOURCES / "wine-build-dual/dlls/lsteamclient"
PEFORWARD = SOURCES / "neutron/src/peforward.py"
STEAM_MAC = Path.home() / "Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
HERE = Path(__file__).resolve().parent


def copy(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    print(f"  {target}")


def forwarder(bridge: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(PEFORWARD), "gen", str(bridge), "lsteamclient", str(output)], check=True)
    subprocess.run([sys.executable, str(PEFORWARD), "check", str(bridge), str(output), "lsteamclient"], check=True)
    print(f"  {output} (forwarder)")


def main(app: Path, appid: str, game_dir: str, exe: str) -> None:
    app = app.resolve()
    contents = app / "Contents"
    wine_lib = contents / "SharedSupport/wine/lib/wine"
    prefix = contents / "SharedSupport/prefix"
    steam = prefix / "drive_c/Program Files (x86)/Steam"
    pe32, pe64, so = LSC / "i386-windows/lsteamclient.dll", LSC / "x86_64-windows/lsteamclient.dll", LSC / "lsteamclient.so"
    for f in (pe32, pe64, so, STEAM_MAC / "steamclient.dylib"):
        if not f.is_file():
            sys.exit(f"missing: {f}")

    stop_wine(app)
    print("bridge in the app's wine:")
    copy(so, wine_lib / "x86_64-unix/lsteamclient.so")
    subprocess.run(["codesign", "--remove-signature", str(wine_lib / "x86_64-unix/lsteamclient.so")], capture_output=True)
    copy(pe64, wine_lib / "x86_64-windows/lsteamclient.dll")
    copy(pe32, wine_lib / "i386-windows/lsteamclient.dll")
    print("bridge in the prefix:")
    copy(pe64, prefix / "drive_c/windows/system32/lsteamclient.dll")
    copy(pe32, prefix / "drive_c/windows/syswow64/lsteamclient.dll")
    print("fake Steam:")
    forwarder(pe32, steam / "steamclient.dll")
    forwarder(pe64, steam / "bin64/steamclient.dll")
    copy(steam / "bin64/steamclient.dll", steam / "steamclient64.dll")
    subprocess.run(["x86_64-w64-mingw32-gcc", "-O2", "-mwindows", "-o", str(steam / "steam.exe"),
                    str(HERE / "steam_stub.c"), "-ladvapi32", "-luser32"], check=True)
    print(f"  {steam / 'steam.exe'} (stub)")

    bat = prefix / "drive_c/launch.bat"
    bat.write_text(
        "@echo off\r\n"
        'start "" "C:\\Program Files (x86)\\Steam\\steam.exe"\r\n'
        "ping -n 3 127.0.0.1 >nul\r\n"
        f'cd /d "{game_dir}"\r\n'
        f'start "" "{exe}"\r\n',
        encoding="ascii",
    )
    plist = contents / "Info.plist"
    with open(plist, "rb") as f:
        data = plistlib.load(f)
    data["Program Name and Path"] = "/launch.bat"
    data["CLI Custom Commands"] = (
        f'export SteamAppId={appid}; export SteamGameId={appid}; '
        f'export STEAM_COMPAT_CLIENT_INSTALL_PATH="{STEAM_MAC}"'
    )
    data["Debug Mode"] = 1
    data["WINEDEBUG"] = "-all,+steamclient,+loaddll,err+all"
    with open(plist, "wb") as f:
        plistlib.dump(data, f)
    print("Info.plist: launch.bat + Steam variables; log at Contents/SharedSupport/Logs/LastRunWine.log")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4])
