# Pesquisa — Carros 2006 rodando no Mac (2026-10-22)

Feita pelo agente `web-research`. O que não foi confirmado está marcado. PCGamingWiki devolveu 403 e o ProtonDB
não renderiza sem JS: os dois **não foram lidos**.

## Confirmado

- **Steam App ID 331160** — "Disney•Pixar Cars", THQ/Disney, lançamento 06/07/2006, só Windows, EULA de terceiros.
  A loja avisa: "suporta apenas SOs antigos (Me/2000/XP/Vista)". https://store.steampowered.com/app/331160
- Port de PC feito pela **Beenox** (os consoles foram da Rainbow Studios).
  https://en.wikipedia.org/wiki/Cars_(video_game)
- Não confundir com 343140 ("Radiator Springs Adventures").
- **steamcmd** baixa o depot Windows num Mac:
  `steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "<dir>" +login <conta> +app_update 331160 validate +quit`.
  Cask do Homebrew é Intel (Rosetta 2). O macOS pode bloquear `Breakpad.framework`/`steamconsole.dylib` até liberar
  em Privacidade e Segurança. https://formulae.brew.sh/cask/steamcmd
- **Whisky**: descontinuado, repositório arquivado em 2025. Não usar.
- **Sikarugir** (sucessor do Wineskin, mantido): gera `.app` com D3DMetal (GPTK), DXVK, DXMT, WineD3D, CNC-DDRAW.
  macOS ≥ 14.6. D3DMetal é fechado e proibido em port comercial; uso pessoal ok. https://github.com/Sikarugir-App/Sikarugir
- **Kegworks**: ativo (push em 2026-10-18).
- **Gcenx macOS_Wine_builds**: wine-devel/staging 11.18 (2026-09-25), exige GStreamer.framework.
- Licença: empacotar para uso pessoal ok; redistribuir o jogo não (proprietário).

## Não confirmado (fechar com o item #1 do backlog)

- **DRM**: uma base lista "Steam" como DRM, mas nada confirma SteamStub no `.exe`. Testar rodando o `.exe` sem Steam e
  procurando seção `.bind` / `steam_api.dll`.
- **API gráfica / bits**: provavelmente D3D9 32 bits (suposição, não fonte).
- **Wine/Proton/Mac**: nenhum relato achado para 331160. Conferir https://www.protondb.com/app/331160 e WineHQ AppDB.
- **Estabilidade**: um comentário não verificado fala em travamentos ao salvar na versão Steam.

## Comunidade

- Nenhuma descompilação ou reimplementação do Cars 2006 encontrada.
- `itsmeft24` no GitHub tem `cars-research` (jogos Rainbow/Incinerator) e `hi-octane-hook` (Mater-National, não o 2006).
- Wiki de mods: https://modcars.fandom.com/wiki/Cars (não aberta).
