# Inspeção do executável — Carros 2006, Steam 331160 (2026-10-22)

Download pelo steamcmd (depot Windows), buildid 454676, 1,1 GB, `StateFlags 4` (instalação completa).
Script de leitura do cabeçalho PE: análise ad hoc em sessão (seções, entry point, tabela de importação).

## Executáveis

| Arquivo | Tamanho | Seções | Entry point | Leitura |
|---|---|---|---|---|
| `Cars.exe` | 4.346.896 | .text .rdata .data .rsrc .reloc **.bind** | dentro de `.bind` | **SteamStub** (DRM da Steam): exige o cliente Steam |
| `bak/Cars.exe` | 3.943.936 | .text .rdata .data .rsrc .reloc | dentro de `.text` | **o mesmo build sem o SteamStub** (timestamp e seções idênticos) |

A própria distribuição da Steam traz o executável original sem DRM em `bak/`. Não é preciso remover DRM
nem usar ferramenta de terceiros: basta iniciar `bak/Cars.exe`. Ainda falta confirmar rodando (pode haver
checagem de CD herdada; o binário contém as strings `DISC` e `discerror.tga`).

## Tecnologia

- **PE32, Intel 80386** → 32 bits. Exige Wine com suporte a 32 bits (WoW64) sobre Rosetta 2.
- **Gráficos: Direct3D 9** (`d3d9.dll`); D3DX **linkado estático** (não precisa do redistribuível d3dx9_xx).
- **Som: DirectSound** (`DSOUND.dll`) + `WINMM.dll`.
- **Input: DirectInput 8** carregado dinamicamente (`dinput8.dll`), mais teclado e mouse via USER32.
- **Vídeos: Bink** (`binkw32.dll` incluso; vídeos `.bik` em `Data/AppStart`). Bink é software puro: não depende
  de codecs do Windows (nada de winetricks quartz/wmp).
- Dados em `.pak` dentro de `Data/`.

## Não necessário no .app

`_jvm/` e `_uninst/` (desinstalador Java do instalador antigo), `_CommonRedist/` (DirectX Jun2010, coberto
pelo Wine), `steamapps/` (metadados do steamcmd), `THQ Website.url`.

## Consequências para o desenho

- D3D9 é o caso mais bem suportado por todas as camadas (D3DMetal, DXVK, DXMT, WineD3D) → escolher por teste.
- Sem DRM a contornar: o `.app` não depende do Steam.
- O README menciona uma versão Mac da época (OS X 10.3, PowerPC) — não serve no Apple Silicon.
