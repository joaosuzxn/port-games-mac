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
