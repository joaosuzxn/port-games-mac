# Lançador de jogos Windows da Steam no Mac — desenho

- **Data:** 2026-10-22
- **Backlog:** #3 (guarda-chuva), #8 motor, #9 app SwiftUI, #10 RDR2; base provada em #7 (spike da ponte)
- **Base:** docs/analises/2026-10-22-spike-ponte-steam.md · ADRs 0001–0003 · código atual em `tools/builder/`
  (motor do Carros, em Python) e `spikes/steam-bridge/`

## Intenção

O dono quer abrir **um app de Mac** e jogar os jogos **Windows** da sua biblioteca Steam como se fossem de Mac:
abre o app → a biblioteca aparece → baixa o jogo → joga. Sem CrossOver, sem Whisky, sem configurar Wine, sem Steam
de Windows rodando escondida e sem emulador de DRM. O que vale é a experiência de app nativo.

No começo é para o próprio dono, que vai **testar muitos jogos para calibrar as receitas** antes de qualquer lançamento.
Depois, a intenção é que **outras pessoas** usem — por isso as escolhas de agora não podem fechar esse caminho.

## O que já está provado

- **Motor do Carros** (`tools/builder/`): monta um `.app` autocontido com Wine do Sikarugir (template 1.0.24, engine
  WS12WineSikarugir 11.0_1), prefixo, receita por jogo (registro, renderizador, drive de CD, saves), tela cheia por
  `EmulateModeset` (ADR 0002), WineD3D a 30 FPS no Carros (ADR 0003). 55 testes.
- **Ponte com a Steam do Mac** (spike #7): `lsteamclient` do Proton (commit `164e0cc` + 3 arquivos do NotProton),
  compilado contra o Wine 11.0, faz um jogo Windows falar com a `steamclient.dylib` da **Steam para Mac aberta e
  logada**. Funciona com `steam_api` (Spacewar) e com **SteamStub** (`Cars.exe` da Steam). Peças: `lsteamclient.dll`
  i386/x86_64 + `lsteamclient.so`, forwarders `steamclient.dll`/`steamclient64.dll` (gerados pelo `peforward.py` do
  Neutron), `steam.exe` falso, variáveis `SteamAppId`/`SteamGameId`/`STEAM_COMPAT_CLIENT_INSTALL_PATH`.

## Objetivos

1. **App nativo SwiftUI** (decisão do dono), um só app para todos os jogos.
2. **Requisito:** Steam para Mac instalada, aberta e logada (decisão do dono). O app detecta a falta dela e orienta.
3. **Biblioteca em grade de capas** (decisão do dono): os jogos da conta, com capa, nome e estado.
4. **Ação direto na capa** (decisão do dono): `Baixar` → progresso na própria capa → `Jogar`. Detalhes e ajustes num
   menu secundário (botão direito), não numa página.
5. **Login por QR code** do app Steam no celular (decisão do dono) para o que precisar de conta além da Steam do Mac
   (download). Nenhuma senha digitada no nosso app.
6. **Jogar** usando a ponte com a Steam do Mac — DRM SteamStub e `steam_api` resolvidos sem remover proteção.
7. **Receitas por jogo**: o que o Carros precisou à mão (renderizador, registro, drive de CD, executável, saves) vira
   dado. Jogo sem receita: **"Baixar e tentar"** com a receita genérica (o dono vai testar muitos jogos).
8. **Modo de teste** para calibrar receitas: trocar renderizador, ligar/desligar `EmulateModeset`, overrides de DLL,
   variáveis de ambiente e chaves de registro; ver o log; salvar como receita do jogo.
9. **Escolher o disco** de instalação (o RDR2 tem ~120 GB; o Mac do dono tem ~112 GB livres).
10. **Primeiros jogos:** Carros (já funciona) e Red Dead Redemption 2.
11. Saves e ajustes de cada jogo sobrevivem a reinstalar o app e o jogo.

## Não-objetivos (agora)

- Distribuir para outras pessoas (assinatura, notarização, instalador, atualização automática). Fica para depois.
- Jogos com anti-cheat em modo online (BattlEye, EAC, VAC em matchmaking) — RDR Online incluso.
- Rodar a Steam de Windows dentro do Wine (rejeitado pelo dono).
- Emulador de Steam / remoção de DRM (Goldberg, Steamless) — rejeitado pelo dono.
- Modificar executáveis ou dados dos jogos (mantido desde o Carros; o dono recusou destravar 60 FPS assim).
- Jogos que já têm versão nativa para Mac: continuam na Steam do Mac (ver "Decisões do Claude").

## Antiobjetivos (fracasso mesmo funcionando)

- O usuário ter de abrir terminal, Wine, winecfg ou editar arquivos para jogar.
- Pedir senha da Steam no nosso app.
- Perder saves ou ajustes ao atualizar o app, a engine ou reinstalar um jogo.
- Mexer na instalação da Steam do Mac de um jeito que estrague os jogos nativos de Mac do usuário.
- Prender o projeto a um produto pago (CrossOver) ou a builds específicos da Steam com patch binário.

## Restrições

| Restrição | Consequência |
|---|---|
| Licença do `lsteamclient` = Steamworks SDK License (não é open source) | Fontes e binários nunca no git. Uso pessoal ok. Antes de distribuir, decidir estratégia (ex.: compilar na máquina do usuário). |
| A ponte é compilada contra uma versão de Wine (11.0) | Ponte e engine andam juntas: trocar a engine = recompilar e retestar a ponte. |
| Compilar/rodar código de terceiros exige aprovação do dono no modo automático do Claude Code | Passos de build da ponte e de ferramentas externas ficam em scripts que o dono aprova. |
| Wine x86_64 sob Rosetta 2 | Jogos 32 e 64 bits via WoW64; ponte com metades i386 e x86_64. |
| RDR2: só roda com DirectX 12 + **D3DMetal** (Vulkan não funciona no Mac, pelos relatos); o Rockstar Launcher não abre na engine atual (ServicesPipeTimeout; UI exige D3D10.1 + Direct2D) | RDR2 é a peça de maior risco; pode exigir outra engine Wine (ex.: build FOSS do CrossOver 26.3 com patches, PR #293 do Sikarugir) e o D3DMetal (uso pessoal ok, não distribuível). Conta Rockstar obrigatória no primeiro uso. |
| 16 GB de RAM e ~112 GB livres no Mac do dono | Escolha de disco obrigatória; aviso de espaço antes de baixar. |
| Bug #11: criar prefixo trava se outro app com Wine estiver aberto | O motor serializa criação de prefixo e não cria prefixo com jogo rodando. |

## O que o dono decidiu

- SwiftUI; grade de capas; ação direto na capa; login por QR.
- Steam para Mac obrigatória; ponte estilo Proton (rota 3) em vez de Steam Windows no Wine ou emulador.
- Escopo inicial pessoal, com testes de muitos jogos antes de lançar; outras pessoas no futuro.
- Carros e RDR2 como primeiros jogos; manter 30 FPS no Carros sem alterar o jogo.
- Código em inglês; documentação em português.

## Decisões do Claude (o dono pode contestar)

- **Arquitetura em três camadas:** `LauncherApp` (SwiftUI, só interface) → `LauncherCore` (pacote Swift: biblioteca,
  downloads, receitas, prefixos, ponte, lançamento) → artefatos externos (engine Wine, ponte, DepotDownloader).
  O motor sai do Python para **Swift**, porque o app precisa rodar sem Python instalado (o `python3` do macOS depende
  das Command Line Tools). O `tools/builder/` em Python continua como referência e para montar `.app` avulsos, até o
  `LauncherCore` cobrir o mesmo comportamento (com os mesmos casos de teste).
- **Nome provisório do app:** "Port Games" (do repositório `port-games-mac`); trocar depois é barato.
- **Um prefixo Wine por jogo**, em `~/Library/Application Support/PortGames/games/<appid>/` (ou no disco escolhido),
  em vez de um `.app` por jogo. A engine Wine e a ponte ficam uma vez só, compartilhadas, versionadas por pasta.
- **Download pelo DepotDownloader** (GPL-2.0, binário único para macOS arm64, `-os windows`, login `-qr`), executado
  como processo separado. Rejeitado: o truque `steam_dev.cfg` (`@sSteamCmdForcePlatformType windows`) que faz a Steam
  do Mac baixar versões Windows — ele troca também os jogos que têm versão Mac pela versão Windows (fere o antiobjetivo).
- **Biblioteca:** jogos da conta com capa (CDN da Steam, arte vertical 600×900) e marcação de "tem versão Mac" —
  esses mostram "Abrir na Steam" em vez de Baixar.
- **Receita genérica padrão:** WineD3D para D3D9 e anteriores, `EmulateModeset` ligado, ponte ligada; renderizador
  para D3D11/12 a definir por teste. Receitas versionadas no repositório, por appid; ajustes do modo de teste ficam
  como receita local do usuário (sobrepõe a do repositório).
- **Lançamento:** se a Steam do Mac não estiver aberta, abri-la (`open -ga Steam`) e esperar o login; então
  `steam.exe` falso + jogo com `SteamAppId`/`SteamGameId`. Executável e argumentos vêm da configuração de lançamento
  Windows do appinfo do jogo (ou da receita).
- **Ordem de construção:** #8 motor (`LauncherCore`, com testes) → #9 app SwiftUI → #10 RDR2 (começa por um spike de
  engine/Rockstar Launcher).

## Deixado para quem constrói

- Como obter a lista de jogos da conta e o appinfo (Web API com o token do login por QR, cache do appinfo da Steam do
  Mac, ou SteamKit), desde que: lista completa da conta, nomes, capas, plataformas e configuração de lançamento Windows;
  no máximo **um** QR por máquina, lembrado entre sessões.
- Como empacotar engine, ponte e DepotDownloader dentro do app ou num cache baixado na primeira execução.
- Formato exato da receita em Swift (partindo das chaves atuais em inglês de `tools/builder/recipes/*.json`).
- Detecção de renderizador necessário (D3D8/9/10/11/12, Vulkan, OpenGL) a partir das importações do executável.
- Estrutura de logs do modo de teste.

## Critérios de aceite (do conjunto)

1. Com a Steam do Mac aberta e logada, o app mostra a biblioteca completa da conta em grade de capas.
2. Primeiro uso: um QR, e nada mais pede login (exceto a conta Rockstar no RDR2).
3. Carros: `Baixar` → progresso na capa → `Jogar` abre o jogo em tela cheia, com a ponte (sem o `bak/Cars.exe`).
4. Um jogo sem receita pode ser baixado e tentado; o modo de teste permite ajustar e salvar a receita.
5. Escolha de disco funciona, com aviso de espaço insuficiente.
6. Saves e receitas locais sobrevivem a apagar e reinstalar o jogo e a atualizar o app.
7. Nenhuma alteração na instalação da Steam do Mac que afete os jogos nativos de Mac.
8. RDR2: modo história jogável (critério da peça #10, com risco declarado).
