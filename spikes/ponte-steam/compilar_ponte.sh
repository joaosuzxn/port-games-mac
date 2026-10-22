#!/bin/bash
# SPIKE (descartável): compila a ponte lsteamclient (Proton 164e0cc + overlay do NotProton) contra o Wine 11.0.
# Fontes e build ficam em ~/Library/Caches/portcarros/fontes (licença Steamworks SDK: nunca no git).
# Pré-requisitos já feitos: brew install mingw-w64 bison flex; árvore do Wine 11.0 configurada; ntdll.so compilado.
set -euo pipefail

F="$HOME/Library/Caches/portcarros/fontes"
export PATH="/opt/homebrew/opt/flex/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH"
M="$F/wine/dlls/lsteamclient/Makefile.in"

echo "==> 1/3 Makefile.in só com as fontes .c (no Wine 11.0 o make compila os .cpp do lado Mac com o mingw)"
python3 - "$M" <<'EOF'
import re, sys
p = sys.argv[1]
t = open(p).read()
t = "\n".join(l for l in t.split("\n") if not re.match(r"^\s*\S+\.cpp\s*\\?\s*$", l))
t = re.sub(r"\\\n(\s*\n)", r"\n\1", t)
open(p, "w").write(t)
print("    .cpp restantes:", t.count(".cpp"))
EOF

echo "==> 1b/3 winbase.h do Wine 11.0: macro-armadilha de wcsncpy só em C (o SDK do macOS 27 a dispara no C++)"
python3 - "$F/wine/include/winbase.h" <<'EOF'
import sys
p = sys.argv[1]
t = open(p).read()
old = ("#define strncpy(d,s,n) error do_not_use_strncpy_use_lstrcpynA_or_memcpy_instead\n"
       "#define wcsncpy(d,s,n) error do_not_use_wcsncpy_use_lstrcpynW_or_memcpy_instead\n")
if "portcarros:" not in t:
    assert t.count(old) == 1
    t = t.replace(old, "#ifndef __cplusplus /* portcarros: o SDK do macOS 27 declara wcsncpy pelo <array> do libc++ */\n"
                  + old + "#endif\n")
    open(p, "w").write(t)
print("    ok")
EOF

echo "==> 2/3 metades Windows (i386 e x86_64)"
cd "$F/wine-build-dual"
make -j10 dlls/lsteamclient/i386-windows/lsteamclient.dll dlls/lsteamclient/x86_64-windows/lsteamclient.dll > "$F/make-pe.log" 2>&1 \
  || { tail -20 "$F/make-pe.log"; exit 1; }
ls -la dlls/lsteamclient/*-windows/lsteamclient.dll

echo "==> 3/3 metade Mac (lsteamclient.so x86_64) pelo build.sh do NotProton"
cd "$F/notproton"
WINE_BUILD="$F/wine-build-dual" WINE_SRC_REL=../wine ./lsteamclient/build.sh --unix > "$F/build-unix.log" 2>&1 \
  || { tail -20 "$F/build-unix.log"; exit 1; }
tail -2 "$F/build-unix.log"
echo "==> pronto"
