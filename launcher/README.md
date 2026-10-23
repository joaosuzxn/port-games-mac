# Lançador — motor (`LauncherCore`) e `launcherctl`

O motor do lançador de jogos Steam de Windows no Mac (#8). A interface SwiftUI é o #9; por enquanto tudo se usa
pelo terminal com o `launcherctl`. Desenho: `docs/specs/2026-10-22-lancador-design.md`; plano:
`docs/plans/2026-10-22-launcher-core.md`.

## O que precisa

- Mac Apple Silicon com Rosetta 2, Xcode (Swift 6) e a **Steam para Mac instalada e logada**.
- A ponte com a Steam do Mac publicada (uma vez, e de novo quando mudar a engine):

      bash spikes/steam-bridge/build_bridge.sh

  Ela compila o `lsteamclient` (licença do Steamworks SDK: **nunca vai para o git**) e publica em
  `~/Library/Application Support/PortGames/bridge/ws12-wine-sikarugir-11.0_1/`.

## Compilar e testar

    swift build -c release --package-path launcher        # gera launcher/.build/release/launcherctl
    swift test --package-path launcher                    # testes (sem Wine, rede nem Steam)
    PORTGAMES_INTEGRATION=1 swift test --package-path launcher   # + testes com Wine/arquivos reais

Os testes de integração rodam o Wine de verdade: dentro do Claude Code precisam do sandbox desligado.

## Usar

    launcherctl login                  # QR para escanear no app da Steam do celular (uma vez por Mac)
    launcherctl library                # jogos da conta: appid, estado, nome
    launcherctl install 331160         # baixa a versão Windows (Carros, ~1,1 GB) em PortGames/games/331160
    launcherctl install 331160 --library /Volumes/Jogos   # noutro disco (APFS ou Mac OS Expandido)
    launcherctl play 331160            # abre a Steam do Mac se precisar e inicia o jogo (Ctrl-C para)
    launcherctl status 331160          # estado da instalação e receita efetiva
    launcherctl update 331160          # baixa o build novo (quando `library` mostra "update")
    launcherctl uninstall 331160       # apaga os arquivos do jogo; saves e receita ficam
    launcherctl recipe 331160 --renderer d9vk --env DXVK_HUD=fps   # modo de teste: receita local
    launcherctl logout

## Onde ficam as coisas

| Pasta | O quê |
|---|---|
| `~/Library/Application Support/PortGames/engines/` | Wine compartilhado (Sikarugir) |
| `…/PortGames/prefixes/<appid>/` | prefixo do jogo — **saves**; nunca apagado por desinstalar/atualizar |
| `…/PortGames/games/<appid>/` | arquivos do jogo (ou `<biblioteca>/<appid>`) |
| `…/PortGames/recipes/<appid>.json` | receita local (modo de teste) |
| `…/PortGames/logs/` | `<appid>.log` (Wine), `<appid>-download.log`, `qr.png` |
| `…/PortGames/tools/` | DepotDownloader 3.4.0 (baixado e conferido por SHA-256) |
| Keychain, serviço `com.portgames.steam` | login da Steam (refresh token) |

O login é um só (ADR 0004): o QR do `launcherctl login` também é gravado no `account.config` do DepotDownloader.
