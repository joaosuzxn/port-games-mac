# Teste rápido (spike) — Carros 2006 no Wine do Sikarugir (2026-10-22)

Descartável: wrapper `~/Applications/Sikarugir/CarrosTeste.app` (template 1.0.24, engine WS12WineSikarugir 11.0_1,
WoW64 sobre Rosetta 2, Mac Apple M5). **Resultado: o jogo roda — vídeos tocam, menu e corrida jogáveis; FPS baixo.**

## Bloqueios encontrados e o que resolveu (em ordem)

| # | Sintoma | Causa (evidência no log) | Solução (sem alterar o .exe) |
|---|---|---|---|
| 1 | Crash logo após criar o device, com D9VK **e** WineD3D | `NtUserChangeDisplaySettings ... returned -2`: o jogo pede troca de resolução em tela cheia, o macOS recusa, o jogo segue com device inválido | Área de trabalho virtual do Wine: `HKCU\Software\Wine\Explorer "Desktop"="Default"`, `Explorer\Desktops "Default"="1280x720"` |
| 2 | "Please insert the playdisk to run the game." | `bak/Cars.exe` é o binário da versão em disco: procura drive tipo CD (`GetDriveTypeA == 5`) com rótulo de volume igual a `DISC2` (rotina em 0x69ea50, string em 0x748f8c) | Drive `D:` → pasta do jogo (`dosdevices/d:`), `HKLM\Software\Wine\Drives "d:"="cdrom"`, arquivo `.windows-label` com `DISC2` na raiz da pasta |

Hipótese descartada: `DisableD3DXPSGP` (o jogo nem lê a chave). Um primeiro teste dela foi inválido porque o
wineserver ainda estava vivo e sobrescreveu o registro — **parar o Wine por completo antes de editar `system.reg`/`user.reg`**.

## Outros fatos

- D9VK (DXVK 3.1.1 d3d9) roda sobre o driver Vulkan "KosmicKrisp" (Mesa sobre Metal); reporta a GPU como Radeon RX 6700 XT.
- Saves em `C:\users\<user>\Documents\THQ\Cars\Save` → no wrapper o Documents é link para `~/Documents` real.
- A janela Configure do Sikarugir regrava o `Info.plist` ao fechar (voltou `Program Name and Path` para `/nothing.exe`).
- Um wrapper do Sikarugir é autocontido: Wine, camadas gráficas, prefixo e jogo ficam dentro do `.app`.

## Em aberto

- FPS baixo: testar sem log de depuração, WineD3D vs D9VK, D3DMetal (se cobrir D3D9), resolução da área virtual.
- Tela cheia de verdade (área virtual do tamanho da tela) e controle.
