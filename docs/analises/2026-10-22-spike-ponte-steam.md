# Spike: ponte dos jogos Windows com a Steam nativa do Mac (backlog #7) — 2026-10-22

**Resultado do teste 1: funcionou.** Spacewar (App 480, 32 bits, `steam_api.dll`, sem SteamStub) abriu no Wine do
Sikarugir conversando com a **Steam para Mac** aberta e logada: sem Steam de Windows, sem emulador. A Steam do Mac
mostrou o dono "Jogando Spacewar"; o jogo leu SteamID, `BLoggedOn`, lista de amigos (nomes), estatísticas,
conquistas e inventário. Linha de base sem a ponte: "Steam must be running (SteamAPI_Init() failed)".

## Peças

| Peça | Origem | Onde fica no app |
|---|---|---|
| `lsteamclient.dll` i386 + x86_64 (PE) | Proton `164e0cc` + overlay NotProton (3 arquivos), compilado contra **Wine 11.0** com mingw-w64 | `wine/lib/wine/{i386,x86_64}-windows/`, `prefix/.../syswow64`, `system32` |
| `lsteamclient.so` x86_64 (sem assinatura) | idem, `build.sh --unix` do NotProton | `wine/lib/wine/x86_64-unix/` |
| Forwarders `steamclient.dll` (i386), `bin64/steamclient.dll` + `steamclient64.dll` (x86_64) | `peforward.py` do Neutron (Apache-2.0), 74 exports → `lsteamclient` | `prefix/drive_c/Program Files (x86)/Steam/` |
| `steam.exe` falso | `spikes/ponte-steam/steam_stub.c` (base Neutron) | idem |
| Ambiente | `SteamAppId`/`SteamGameId`, `STEAM_COMPAT_CLIENT_INSTALL_PATH` = pasta do `steamclient.dylib` | `Info.plist` → "CLI Custom Commands" |

O `steamclient.dylib` da Steam para Mac é universal (x86_64 + arm64) e exporta `CreateInterface`/`Steam_*`; o ramo
`__APPLE__` do `unixlib.cpp` do Proton o carrega por `STEAM_COMPAT_CLIENT_INSTALL_PATH`.

## Ajustes para compilar contra o Wine 11.0 (o NotProton usa 11.15)

1. `configure`/`configure.ac`: `dlls/lsteamclient` registrado à mão (o `register-components.diff` não aplica no 11.0).
2. `Makefile.in` só com as fontes `.c` para o `make` das metades PE (o makedep do 11.0 compila os `.cpp` do lado unix com o mingw).
3. `include/winbase.h` da cópia local: macro-armadilha de `wcsncpy`/`strncpy` só em C (o SDK do macOS 27 a dispara pelo `<array>` do libc++).
Tudo em `spikes/ponte-steam/compilar_ponte.sh`; instalação em `spikes/ponte-steam/instalar_ponte.py`.

## Riscos e pendências

- **Licença**: `lsteamclient` = Steamworks SDK License (não open source). Uso pessoal ok; redistribuir num app para
  terceiros é risco. Fontes e binários ficam em `~/Library/Caches/portcarros/fontes`, nunca no git.
- Ferramentas instaladas (aprovadas pelo dono): `mingw-w64`, `bison`, `flex`.
- O modo automático do Claude Code bloqueia compilar/rodar código de terceiros; o dono aprovou os comandos do spike.

## Teste 2: SteamStub — funcionou

`Cars.exe` da Steam (App 331160, 32 bits, **com SteamStub**, SHA-1 `d4a2f16e…`), receita `carros-steam.json`
(igual à do Carros, mas sem trocar pelo `bak/Cars.exe`): o stub fez `ConnectToGlobalUser`, `GetSteamID`, `GetAppID`,
`GetConnectedUniverse`, `ReleaseUser` pela ponte e liberou o jogo — vídeos e menu normais, verificado pelo dono.
Conclusão: com a ponte, jogos com SteamStub rodam sem remover DRM.

## Achado lateral

Criar o prefixo (`WSS-wineprefixcreate`) travou 300 s enquanto o `Spacewar.app` estava aberto; com ele fechado,
66 s normais. Registrado como bug.
