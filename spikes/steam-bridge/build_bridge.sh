#!/bin/bash
# SPIKE (disposable): builds the lsteamclient bridge (Proton 164e0cc + NotProton overlay) against Wine 11.0.
# Sources and build live in ~/Library/Caches/portcarros/fontes (Steamworks SDK license: never in git).
# Prerequisites already done: brew install mingw-w64 bison flex; Wine 11.0 tree configured; ntdll.so built.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"  # before the cd's below
F="$HOME/Library/Caches/portcarros/fontes"
export PATH="/opt/homebrew/opt/flex/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH"
M="$F/wine/dlls/lsteamclient/Makefile.in"

echo "==> 1/4 Makefile.in with only the .c sources (in Wine 11.0 make builds the Mac-side .cpp files with mingw)"
python3 - "$M" <<'EOF'
import re, sys
p = sys.argv[1]
t = open(p).read()
t = "\n".join(l for l in t.split("\n") if not re.match(r"^\s*\S+\.cpp\s*\\?\s*$", l))
t = re.sub(r"\\\n(\s*\n)", r"\n\1", t)
open(p, "w").write(t)
print("    remaining .cpp:", t.count(".cpp"))
EOF

echo "==> 1b/4 Wine 11.0 winbase.h: wcsncpy trap macro in C only (the macOS 27 SDK triggers it in C++)"
python3 - "$F/wine/include/winbase.h" <<'EOF'
import sys
p = sys.argv[1]
t = open(p).read()
old = ("#define strncpy(d,s,n) error do_not_use_strncpy_use_lstrcpynA_or_memcpy_instead\n"
       "#define wcsncpy(d,s,n) error do_not_use_wcsncpy_use_lstrcpynW_or_memcpy_instead\n")
if "portcarros:" not in t:
    assert t.count(old) == 1
    t = t.replace(old, "#ifndef __cplusplus /* portcarros: the macOS 27 SDK declares wcsncpy through libc++'s <array> */\n"
                  + old + "#endif\n")
    open(p, "w").write(t)
print("    ok")
EOF

echo "==> 2/4 Windows halves (i386 and x86_64)"
cd "$F/wine-build-dual"
make -j10 dlls/lsteamclient/i386-windows/lsteamclient.dll dlls/lsteamclient/x86_64-windows/lsteamclient.dll > "$F/make-pe.log" 2>&1 \
  || { tail -20 "$F/make-pe.log"; exit 1; }
ls -la dlls/lsteamclient/*-windows/lsteamclient.dll

echo "==> 3/4 Mac half (x86_64 lsteamclient.so) via NotProton's build.sh"
cd "$F/notproton"
WINE_BUILD="$F/wine-build-dual" WINE_SRC_REL=../wine ./lsteamclient/build.sh --unix > "$F/build-unix.log" 2>&1 \
  || { tail -20 "$F/build-unix.log"; exit 1; }
tail -2 "$F/build-unix.log"

echo "==> 4/4 publish for the launcher (LauncherCore Bridge) + steam.exe stub"
P="$HOME/Library/Application Support/PortGames/bridge/ws12-wine-sikarugir-11.0_1"
L="$F/wine-build-dual/dlls/lsteamclient"
mkdir -p "$P/i386-windows" "$P/x86_64-windows"
cp "$L/lsteamclient.so" "$P/lsteamclient.so"
cp "$L/i386-windows/lsteamclient.dll" "$P/i386-windows/lsteamclient.dll"
cp "$L/x86_64-windows/lsteamclient.dll" "$P/x86_64-windows/lsteamclient.dll"
# -mwindows: a GUI-subsystem stub, so starting it opens no console window
x86_64-w64-mingw32-gcc -O2 -mwindows -o "$P/steam.exe" "$HERE/steam_stub.c" -ladvapi32 -luser32
ls -la "$P" "$P"/*-windows
echo "==> done"
