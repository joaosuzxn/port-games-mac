# Medições de FPS — Carros.app (2026-10-22)

Mac Apple M5, macOS 27, engine WS12WineSikarugir 11.0_1, tela cheia com `EmulateModeset` (ADR 0002), log de depuração
desligado. Mesmo trecho: corrida rápida, primeira pista, ~30 s / uma volta. D9VK medido pelo HUD do Metal (dono);
WineD3D pelo canal `fps` do Wine (`WINEDEBUG=-all,fps`, uma amostra por ~1 s, últimas 40 amostras da corrida).

| # | Camada | Resolução do jogo | FPS médio | Mínimo | Observação |
|---|---|---|---|---|---|
| 1 | D9VK (DXVK 3.1.1 → Vulkan KosmicKrisp → Metal) | 800×600 (padrão) | ~25 | quedas visíveis | dono relatou "picos para baixo" |
| 2 | WineD3D (OpenGL) | 800×600 | 30,2 | 29,8 | cravado em 30 |
| 3 | WineD3D (OpenGL) | 1600×1200, MSAA 4x, efeitos ligados | 30,2 | 29,8 | cravado em 30; sem custo extra |

- 30 FPS é o **teto do próprio jogo**: o executável tem modos de VSync `30Hz`/`60Hz`/`OFF` e `ForceMin30Hz`, com 30Hz
  como padrão. Não é ajuste de registro (`HKCU\Software\THQ\Cars\Settings\Display` guarda só `Resolution`,
  `MultiSampleType`, `FullscreenEffects`); vem dos dados internos (`.pak`). Destravar 60 exigiria alterar dados do jogo
  (não-objetivo da spec).
- CPU com D9VK: ~70% somados entre threads, nenhuma em 100% (medição no menu, não conclusiva).
- D3DMetal não testado: no Sikarugir cobre só Direct3D 11/12; o jogo é Direct3D 9.
- O HUD do Metal não aparece com WineD3D (OpenGL), nem com `MTL_HUD_ENABLED=1`.

## Tentativa de 60 FPS (backlog #5, descartada pelo dono)

- A configuração de VSync vem de `data\Debug\config.txt` dentro de `Data/misc.pak` (`[General] VSync=30hz`), lida pela
  função em `0x58b730` (`VSync`, padrão `"30Hz"`; `30Hz`→modo 1, `60Hz`→modo 2, outro→desligado; objeto em `[0x7c6394]+0x10`).
- Formato `.pak`: `u32 n` + `n × (nome[100], u32 offset, u32 tamanho)`; offsets relativos ao fim da tabela (`4 + n×108`).
- O jogo procura cada `.pak` primeiro na raiz (`D:\misc.pak`) e depois em `data\`: uma cópia na raiz é usada no lugar.
- Mesmo com a cópia na raiz (`VSync=60hz`, `PrintFPS=T`) nada mudou: o executável final **não aplica** o `config.txt`
  e usa o padrão do código (`30Hz`).
- Único caminho restante: trocar 4 bytes numa cópia do `Cars.exe` (operando do `push 0x7399c4` em `0x58b831` →
  `0x7399a4`, texto `"60Hz"`). O dono preferiu manter 30 FPS e não modificar o executável (2026-10-22).
- O WineD3D apresenta com `swap_interval` padrão do swapchain; o jogo cria o back buffer no tamanho da tela (1470×956).
