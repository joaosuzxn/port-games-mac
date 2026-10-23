# LauncherCore (#8) — decisões de execução e dívidas adiadas

Registro do que foi decidido durante a execução do plano `docs/plans/2026-10-22-launcher-core.md` (branch
`feat/launcher-core`, 2026-10-22/23) sem estar escrito no plano, e do que as revisões acharam e ficou para depois.
Decisões de desenho maiores estão nos ADRs (0004: login único). Dívidas abertas: backlog #14 e #15.

## Aceite com o dono (2026-10-23)

`launcherctl login` (QR) → `library` → `install 331160` (2 depots, 1,08 GB) → `play 331160`: o Carros abriu pelo
Wine compartilhado e pela ponte com a Steam do Mac, saves em `prefixes/331160/.../Documents/THQ`. O DepotDownloader
entrou na conta com o token do QR (ADR 0004 validado). Falta do aceite do plano: Spacewar (480) "Jogando Spacewar"
e desinstalar + instalar mantendo saves.

## Decisões (onde o plano foi ajustado)

**Ambiente e Wine**
- O ambiente do Wine copia o que o `wineskinlauncher` exporta de fato (captura ao vivo), não a lista do plano, que
  veio de uma captura truncada. Inclui `SikarugirAppWine11=1` — sem ele nenhum processo Windows abre.
- `WINEDLLPATH_PREPEND` com WineD3D aponta para o DXMT (padrão do Sikarugir, com o qual o Carros foi validado).
- A instalação da engine também copia `Resources/vulkan` (o driver Vulkan resolve `../../../Frameworks`).
- `stop()` manda SIGKILL só ao wineserver do prefixo, nunca a "tudo dentro da engine" (a engine é compartilhada).
- Nada de `Process.waitUntilExit()`: travava a suíte; espera de processo é por `terminationHandler`.

**Prefixo**
- Drives `D:`/`G:` são links absolutos para a pasta do jogo (que pode estar noutro disco).
- Prefixo "criado" = tem `system.reg`; o Wine é parado antes de editar o registro; criação serializada por lock só
  quando cria; não cria com outro jogo rodando (spec, bug #11); `wineboot` com prazo de 180 s.
- Nunca apaga o que não é nosso: drive que é pasta real → erro; pasta de usuário fora do prefixo → erro.

**Ponte com a Steam**
- O forwarder `steamclient.dll` segue o `peforward.py` do Neutron byte a byte (tem `.data` de 1 MB e um `DllMain`
  mínimo), contra o "sem .data nem código" do plano — a ponte não inicia sem `.data`. Conferido contra o Python.
- A ponte só troca arquivos da engine quando o conteúdo muda, por rename, já sem assinatura.

**Steam: appinfo, login e biblioteca**
- Depots: só Windows, sem redistribuíveis compartilhados nem DLC, idioma escolhido (inglês se faltar), 64 bits
  quando há 32 e 64.
- Login: `beginQR` + `waitForApproval`; o access token do login é usado enquanto vale; recusa de renovação pede novo
  login **sem apagar nada**; sem rede não é logout. Renovar de verdade = #14.
- "Steam do Mac logada" vem do `logs/connection_log.txt` (última linha com estado `Logged On`; arquivo em CRLF):
  `loginusers.vdf` e `registry.vdf` não têm marca confiável neste Mac.
- Biblioteca lista os jogos mesmo sem `appinfo.vdf` legível.

**Download**
- DepotDownloader 3.4.0 fixado por constante (SHA-256 do primeiro download; o release não publica checksum), num
  caminho fixo (o `account.config` dele depende do caminho do binário).
- Um `-depot` com todos os IDs (o repetido era ignorado); instalado só quando cada depot reporta "Downloaded".
- Progresso pelas linhas `NN.NN%` do depot em download ("Downloading depot N"), pesado pelo tamanho.
- Só "Access token was rejected" pede novo login; queda de rede é erro comum.
- Um download por jogo e um DepotDownloader por vez; desinstalar espera o download e recusa com o jogo aberto.
- Desinstalar apaga só a pasta `<appid>`; prefixo (saves) e receita local ficam. `logout` também tira o token do
  `account.config` (gravado 0600).

**Jogar**
- O `play` recebe a engine já instalada (quem chama instala); recusa jogo já rodando ou em download; em falha no
  meio para o Wine; `wait()` lança `CancellationError` e aceita vários esperando; `launcherctl stop <appid>` para
  um jogo que ficou rodando.

## Dívidas adiadas (menores, por efeito) — backlog #15

**Robustez com entrada corrompida:** cabeçalho de entrada < 60 bytes e laço sem limite no `appinfo.vdf`; checagens
do cabeçalho PE e `nameTable` sem teto; `account.config` ilegível tratado como vazio; item do Keychain corrompido
trava o `load()`; arquivo de estado corrompido vira "não instalado".

**Processos e concorrência:** SIGKILL com janela de reuso de PID; `run()` cancelado só manda SIGTERM;
DepotDownloader fica órfão se o lançador morrer; extração da engine e `codesign` ocupam uma thread do pool (envolver
para o app #9); corrida de reentrância entre `validSession` e `waitForApproval`.

**Comportamento:** checagem de espaço pede o jogo inteiro ao retomar/atualizar; instalar noutra `--library` deixa a
pasta antiga órfã; guarda do desinstalar olha só o último componente do caminho; `account-store.path` dentro de
`tools/` se perde com a pasta; token renovado pelo DepotDownloader deixa a cópia do Keychain velha (#14); conta sem
jogos dá erro em vez de grade vazia; QR sem margem branca, intervalo sem limite, um erro de rede aborta o login;
`open -ga Steam` sem checar saída; `LaunchEntry` sem `type`/`workingdir` (antes do 3º jogo); argumentos com aspas.

**Wine e prefixo:** nome da pasta do wineserver para `dev_t` com bit 31; `wineboot` que morre depois do
`system.reg` deixa prefixo "criado" sem reparo; entradas que não são pasta em `drive_c/users`; aplicação parcial
quando um drive é pasta real; link `d:` velho se a pasta do jogo mudou.

**Testes e código:** helpers de teste duplicados; `installedAt` como número em vez de ISO 8601; vários testes sem
caso de borda (cancelar antes de lançar, `holder` durante o `wineboot` real, `%2B` no corpo); testes do runner
precisam do `/usr/bin/cc`; `RecipeStore` não é `Sendable`; receita local inválida cai na embutida sem avisar;
`Bundle.module` precisa do bundle de recursos ao lado do executável (empacotar no #9); `QRImageError` sem mensagem.
