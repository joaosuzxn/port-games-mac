# LauncherCore (motor do lançador, #8) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Um pacote Swift `LauncherCore` + CLI `launcherctl` que, com a Steam do Mac aberta e logada, lista os jogos da conta, baixa a versão Windows de um jogo, mostra quando há atualização e o abre pelo Wine com a ponte `lsteamclient` — sem UI (a UI SwiftUI é o #9).

**Architecture:** Pacote SwiftPM em `launcher/` com a biblioteca `LauncherCore` (toda a lógica, testável) e o executável `launcherctl` (fino, só argumentos e saída). O motor porta para Swift o comportamento provado em `tools/builder/` (Python) e em `spikes/steam-bridge/`, mas com **engine Wine compartilhada**, **um prefixo por jogo** e **Wine chamado direto** (sem o `wineskinlauncher` do Sikarugir), reproduzindo o ambiente que o launcher monta. Dados de jogos vêm do `appinfo.vdf` da Steam do Mac; posse da conta vem da Web API com o token do login por QR; download pelo DepotDownloader.

**Tech Stack:** Swift 6.4 (modo de linguagem 6), Foundation, CryptoKit, CoreImage (QR), Security (Keychain), Swift Testing (`import Testing`); `/usr/bin/tar`; artefatos externos: template Sikarugir 1.0.24 + engine WS12WineSikarugir11.0_1, ponte `lsteamclient` (compilada pelo dono), DepotDownloader 3.4.0 (macOS arm64).

**Spec:** `docs/specs/2026-10-22-lancador-design.md` · base: `docs/analises/2026-10-22-spike-ponte-steam.md`, `tools/builder/`, `spikes/steam-bridge/`

## Global Constraints

- Código, identificadores, comentários e mensagens em **inglês**; documentação em português (`CLAUDE.md` › Idioma).
- Swift 6.4, `swift-tools-version: 6.0`, `.macOS(.v15)`; **sem dependências SwiftPM de terceiros**.
- Testes: `swift test --package-path launcher`. Testes de integração (Wine/rede/Steam reais) só rodam com `PORTGAMES_INTEGRATION=1`.
- Raiz de dados: `~/Library/Application Support/PortGames/` — `engines/<engineID>/`, `bridge/<engineID>/`, `prefixes/<appID>/`, `games/<appID>/` (pasta padrão de jogos), `state/<appID>.json`, `recipes/<appID>.json` (receitas locais), `logs/<appID>.log`. Cache de downloads: `~/Library/Caches/PortGames/artifacts/` (fonte local extra: `~/Library/Caches/portcarros/artefatos`).
- `engineID` = `"ws12-wine-sikarugir-11.0_1"`. Artefatos (SHA-256): template `Template-1.0.24.tar.xz` `4b5f89eeb9ef139936bdfad33d9b420b05ea4597cb7d63376674f7a8e171321c`; engine `WS12WineSikarugir11.0_1.tar.xz` `67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e` (URLs em `tools/builder/artifacts.json`).
- Prefixo **sempre no disco interno**; arquivos do jogo no disco escolhido (APFS/HFS+); recusar exFAT/FAT.
- `lsteamclient` (Steamworks SDK License): **nunca no git** nem embutido no pacote; o motor só importa de uma pasta local.
- Compilar/rodar código de terceiros (ponte, DepotDownloader) exige aprovação do dono — passos marcados **[dono]**.
- Steam do Mac: `~/Library/Application Support/Steam/` (`appcache/appinfo.vdf`; `Steam.AppBundle/Steam/Contents/MacOS/steamclient.dylib`); processo `steam_osx`.
- Saves e receitas locais ficam fora de `games/<appID>/`; desinstalar/atualizar nunca apaga `prefixes/` nem `recipes/`.
- Atualização é **manual** (estado `updateAvailable`), nunca automática. Todo jogo roda pela versão Windows (depots `oslist` windows).
- Commits em `feat/launcher-core`, arquivo por arquivo, com a linha `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- **Steam do Mac fechada ou deslogada ao jogar** → o motor abre a Steam e espera; sem login em 60 s, erro claro em vez de jogo travado em "Steam must be running" (teste na Task 11).
- **Disco escolhido sem espaço ou em exFAT** → recusa antes de baixar, com mensagem dizendo quanto falta / por quê (teste na Task 10).
- **Download interrompido (rede, app fechado)** → jogo não fica marcado como instalado; nova tentativa retoma (teste na Task 10).
- **Desinstalar ou atualizar um jogo** → prefixo (saves) e receita local intactos (teste na Task 10).
- **Token do QR expirado ou revogado** → `library`/`install` pedem novo login sem travar nem apagar dados (teste na Task 9).

---

### Task 1: Pacote, caminhos e estado

**Files:** Create `launcher/Package.swift`, `launcher/Sources/LauncherCore/Paths.swift`, `launcher/Sources/LauncherCore/GameState.swift`, `launcher/Sources/launcherctl/main.swift`, `launcher/Tests/LauncherCoreTests/PathsTests.swift`; Modify `.gitignore` (+`launcher/.build/`).

**Interfaces — Produces:**
- `struct Paths: Sendable { init(root: URL, cache: URL); static let standard: Paths; var engines, bridge, prefixes, games, state, recipes, logs: URL; func prefix(_ appID: UInt32) -> URL; func gameDir(_ appID: UInt32, library: URL?) -> URL; func stateFile(_ appID: UInt32) -> URL; func ensureCreated() throws }`
- `struct GameState: Codable, Equatable, Sendable { var appID: UInt32; var installDir: String; var buildID: UInt64; var depotManifests: [UInt32: UInt64]; var installedAt: Date; var complete: Bool }` + `enum GameStateStore { static func load(_ appID: UInt32, paths: Paths) throws -> GameState?; static func save(_ s: GameState, paths: Paths) throws }` (escrita atômica: arquivo temporário + rename).

- [ ] **Step 1: Testes** — `pathsLayout` (raiz temporária → `prefix(331160)` == `<root>/prefixes/331160`, `gameDir(331160, library: nil)` == `<root>/games/331160`, `gameDir(…, library: X)` == `X/331160`); `stateRoundTrip` (save/load iguais, `depotManifests` preservado); `stateMissingIsNil`; `stateAtomic` (arquivo `.tmp` não sobra).
- [ ] **Step 2:** `swift test --package-path launcher` → FAIL (símbolos ausentes). **Step 3:** implementar; `launcherctl` imprime uso. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(launcher): package, paths and game state`.

### Task 2: Receitas

**Files:** Create `launcher/Sources/LauncherCore/Recipe.swift`, `launcher/Sources/LauncherCore/Resources/recipes/331160.json`, `launcher/Sources/LauncherCore/Resources/recipes/480.json`, `launcher/Tests/LauncherCoreTests/RecipeTests.swift`.

**Interfaces — Produces:**
- `enum Renderer: String, Codable { case wined3d, d9vk, dxvk, d3dmetal }`
- `struct RegistryKey: Codable, Equatable { enum Hive: String, Codable { case system, user }; var hive: Hive; var key: String; var values: [String: RegistryValue] }`, `enum RegistryValue: Codable, Equatable { case string(String), dword(UInt32) }` (JSON: string → `.string`, inteiro 0…0xFFFFFFFF → `.dword`; fora disso → erro).
- `struct Recipe: Codable, Equatable { var appID: UInt32?; var renderer: Renderer; var emulateModeset: Bool; var cdLabel: String?; var executable: String?; var arguments: [String]; var environment: [String: String]; var dllOverrides: [String: String]; var registry: [RegistryKey] }` — chaves JSON `app_id, renderer, emulate_modeset, cd_label, executable, arguments, environment, dll_overrides, registry` (registry no formato `hive/key/values` de `tools/builder/recipes`).
- `static let Recipe.generic` = `renderer .wined3d, emulateModeset true`, resto vazio.
- `struct RecipeStore { init(paths: Paths, bundled: Bundle = .module); func recipe(for appID: UInt32) -> Recipe; func saveLocal(_ r: Recipe, for appID: UInt32) throws; func hasBundled(_ appID: UInt32) -> Bool }` — ordem: local (`recipes/<appID>.json`) > embutida > `generic`.

- [ ] **Step 1: Testes** — `carrosRecipe` (331160: `renderer == .wined3d`, `emulateModeset`, `cdLabel == "DISC2"`, `executable == "Cars.exe"`, registry contém `user/Software\THQ\Cars\Settings\Display` com `Resolution: .dword(14)`, `MultiSampleType: .dword(4)`, `FullscreenEffects: .dword(1)` e `system/System\ControlSet001\Services\winebus` com `Enable SDL`/`Map Controllers` = `.dword(1)`); `genericFallback` (appID sem receita → `Recipe.generic`); `localOverridesBundled` (saveLocal com renderer `.d9vk` → `recipe(for: 331160).renderer == .d9vk`); `dwordOutOfRange` (`-1` e `4294967296` → erro de decodificação).
- [ ] **Step 2:** FAIL. **Step 3:** implementar; `331160.json` traduz `tools/builder/recipes/carros-steam.json` para o esquema novo (sem `exe_sha1`, `exclude`, `bundle_id`, `game_dir`; a chave `X11 Driver/EmulateModeset` vira `emulate_modeset: true`); `480.json` = genérica com `executable: "SteamworksExample.exe"`. **Step 4:** PASS. **Step 5:** Commit `feat(launcher): recipes with bundled and local overrides`.

### Task 3: Arquivos de registro do Wine

**Files:** Create `launcher/Sources/LauncherCore/RegistryFile.swift`, `launcher/Tests/LauncherCoreTests/RegistryFileTests.swift`.

**Interfaces — Produces:** `enum RegistryFile { static func apply(_ keys: [RegistryKey], prefix: URL) throws; static func replacePath(_ old: String, with new: String, prefix: URL) throws }` — porta de `apply_registry` e `relocate_registry` de `tools/builder/prefix.py` (mesmo formato `.reg`: `[Chave\\Com\\Barras] <timestamp>`, `"nome"="valor"`, `"nome"=dword:0000000e`; substitui valores na seção existente; idempotente; busca de seção sem diferenciar maiúsculas).

- [ ] **Step 1: Testes** — portar os casos de `tools/builder/test_prefix.py` para Swift: `appendsToExistingSection`, `createsSection`, `idempotent` (aplicar 2× → seção 1×, valor 1×), `replacesValue` (`Default` 1280x720 → 2560x1664), `escapesBackslashAndQuote`, `replacePathAllForms` (formas `Z:\\\\…`, `Z:\\…`, `/…`; não toca `Carros.app2`).
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS. **Step 5:** Commit `feat(launcher): Wine registry file editing`.

### Task 4: Engine compartilhada

**Files:** Create `launcher/Sources/LauncherCore/Artifacts.swift`, `launcher/Sources/LauncherCore/Engine.swift`, `launcher/Tests/LauncherCoreTests/EngineTests.swift`.

**Interfaces — Produces:**
- `struct Artifact { var file: String; var sha256: String; var url: URL? }`; `enum ArtifactStore { static func ensure(_ a: Artifact, cache: URL, localSources: [URL], download: (URL, URL) async throws -> Void) async throws -> URL }` (mesma semântica de `tools/builder/artifacts.py`: `.partial` + verificação; apaga `.partial` em erro).
- `struct Engine: Sendable { let id: String; let root: URL; var wineBin: URL /* root/wine/bin/wine */; var wineserver: URL; func rendererDir(_ r: Renderer) -> URL? /* renderer/d9vk|dxvk|d3dmetal/wine, nil p/ wined3d */ }`; `enum EngineInstaller { static func install(template: URL, engine: URL, id: String, paths: Paths) throws -> Engine }` — extrai com `/usr/bin/tar -xJf` numa pasta `.installing-*` e troca por rename; do template copia `Contents/Frameworks` → `root/Frameworks` e `Contents/SharedSupport/renderer` → `root/renderer`; da engine `wswine.bundle` → `root/wine`. Já instalada com o mesmo id → devolve sem refazer.

- [ ] **Step 1: Testes** — com tars falsos montados no teste (como `tools/builder/test_bundle.py`): `installsLayout` (`wine/bin/wine` executável, `Frameworks/`, `renderer/` existem), `idempotent`, `failedInstallKeepsPrevious` (tar corrompido → engine anterior intacta, sem `.installing-*`), `artifactHashMismatch` (→ erro, cache sem o arquivo).
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS. **Step 5:** Commit `feat(launcher): shared Wine engine install`.

### Task 5: Ambiente e execução do Wine

**Files:** Create `launcher/Sources/LauncherCore/WineEnvironment.swift`, `launcher/Sources/LauncherCore/WineRunner.swift`, `launcher/Tests/LauncherCoreTests/WineEnvironmentTests.swift`.

**Interfaces — Produces:**
- `enum WineEnvironment { static func make(engine: Engine, prefix: URL, recipe: Recipe, extra: [String: String] = [:]) -> [String: String] }` — reproduz o ambiente que o `wineskinlauncher` monta (capturado em 2026-10-22): `WINEPREFIX`, `CX_ROOT=<root>/wine`, `PATH=<root>/wine/bin:/usr/bin:/bin:/usr/sbin:/sbin`, `DYLD_FALLBACK_LIBRARY_PATH=<root>/wine/lib:<root>/wine/lib64:<root>/Frameworks:<root>/Frameworks/GStreamer.framework/Libraries:/usr/lib`, `WINEDLLPATH=<root>/wine/lib/wine/x86_64-windows:<root>/wine/lib/wine/i386-windows`, `WINEDLLPATH_PREPEND=<rendererDir>` (só d9vk/dxvk/d3dmetal), `GST_PLUGIN_PATH=<root>/Frameworks/GStreamer.framework/Libraries/gstreamer-1.0`, `WINEMSYNC=1`, `WINEBOOT_HIDE_DIALOG=1`, `ROSETTA_ADVERTISE_AVX=1`, `CX_FWD_COMPAT_GL_CTX=1`, `MVK_CONFIG_RESUME_LOST_DEVICE=1`, `SDL_JOYSTICK_MFI=0`, `WINEDEBUG=-all`; `WINEDLLOVERRIDES` = `dllOverrides` da receita (`nome=valor;…`, ordenado); `recipe.environment` e `extra` por último.
- `actor WineRunner { init(engine: Engine, prefix: URL, log: URL); func run(_ args: [String], env: [String: String], cwd: URL?) async throws -> Int32; func spawn(_ args: [String], env: [String: String], cwd: URL?) throws -> Process; func stop(timeout: Duration) async throws }` — `stop` = `wineserver -k` com o `WINEPREFIX` do jogo e espera o `wineserver` daquele prefixo sumir; depois do prazo, `SIGKILL` só em processos cujo executável está dentro de `engine.root`; sobrou → erro.
- [ ] **Step 0 [conferir]:** antes de codar, abrir um app de `build/` e confirmar com `ps -axEww` que nenhuma variável relevante mudou desde a captura (lista acima).
- [ ] **Step 1: Testes** — `environmentKeys` (todas as chaves/valores acima para engine em `/E` e prefixo `/P`), `rendererPrepend` (`.d9vk` → `WINEDLLPATH_PREPEND` = dir do d9vk; `.wined3d` → ausente), `dllOverridesSorted`, `recipeEnvironmentWins`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS.
- [ ] **Step 5: Integração** (`PORTGAMES_INTEGRATION=1`): com a engine real instalada pela Task 4, `run(["wineboot","-u"])` num prefixo temporário termina com 0 e cria `system.reg`; `stop` deixa zero processos. Teste `integrationWineboot`.
- [ ] **Step 6:** Commit `feat(launcher): Wine environment and runner`.

### Task 6: Prefixo do jogo

**Files:** Create `launcher/Sources/LauncherCore/PrefixManager.swift`, `launcher/Tests/LauncherCoreTests/PrefixManagerTests.swift`.

**Interfaces — Consumes:** `WineRunner`, `RegistryFile`, `Recipe`, `Paths`. **Produces:** `struct PrefixManager { init(paths: Paths, engine: Engine); func ensurePrefix(appID: UInt32, recipe: Recipe, gameDir: URL) async throws -> URL; func applyRecipe(_ r: Recipe, prefix: URL, gameDir: URL) throws }`
- `ensurePrefix`: cria com `wineboot -u` se não existir (sob lock exclusivo `prefixes/.create.lock` via `flock` — bug #11), para o Wine, aplica a receita.
- `applyRecipe` (Wine parado): registro da receita; `emulateModeset` → `user/Software\Wine\X11 Driver` `EmulateModeset="y"` (false → `"n"`); drive `G:` → `gameDir` (link `dosdevices/g:`); se `cdLabel`: drive `D:` → `gameDir` com `system/Software\Wine\Drives` `"d:"="cdrom"` e `.windows-label` em `gameDir`; `drive_c/users/*/Documents` como pasta real dentro do prefixo (saves ficam no prefixo, disco interno).

- [ ] **Step 1: Testes** (prefixo falso com `dosdevices/`, `system.reg`, `user.reg`, `drive_c/users/u/Documents` symlink para fora): `appliesCarros` (D: e G: links relativos/absolutos corretos, `.windows-label` = `DISC2`, `EmulateModeset`="y", Display dwords), `documentsBecomesRealDir` (o symlink para fora some, nada fora do prefixo é apagado), `lockSerializesCreation` (duas `ensurePrefix` concorrentes com runner falso → criações não se sobrepõem).
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS. **Step 5:** Commit `feat(launcher): per-game prefix`.

### Task 7: Ponte com a Steam do Mac

**Files:** Create `launcher/Sources/LauncherCore/PEForwarder.swift`, `launcher/Sources/LauncherCore/Bridge.swift`, `launcher/Tests/LauncherCoreTests/PEForwarderTests.swift`, `launcher/Tests/LauncherCoreTests/BridgeTests.swift`; Modify `spikes/steam-bridge/build_bridge.sh` (passo final: copia `lsteamclient.so`, as duas `.dll` e o `steam.exe` compilado com `-mwindows` para `~/Library/Application Support/PortGames/bridge/ws12-wine-sikarugir-11.0_1/`).

**Interfaces — Produces:**
- `enum PEForwarder { static func exports(of dll: Data) throws -> [String]; static func generate(from bridge: Data, target: String) throws -> Data }` — porta de `gen` do `peforward.py` do Neutron (Apache-2.0, citar no cabeçalho): PE só com cabeçalho e diretório de exportação de strings `target.<nome>`; mesma máquina (i386/x86_64) da ponte; sem `.data` nem código.
- `struct Bridge { init(paths: Paths, engineID: String) throws; func stage(into engine: Engine, prefix: URL) throws; static func environment(appID: UInt32) -> [String: String] }` — `stage` copia `lsteamclient.so` (remove assinatura com `codesign --remove-signature`) e as `.dll` para `wine/lib/wine/{x86_64-unix,x86_64-windows,i386-windows}` e `drive_c/windows/{system32,syswow64}`; gera forwarders em `drive_c/Program Files (x86)/Steam/steamclient.dll` (i386), `bin64/steamclient.dll` e `steamclient64.dll` (x86_64); copia `steam.exe`. `environment(appID)` = `SteamAppId`, `SteamGameId`, `STEAM_COMPAT_CLIENT_INSTALL_PATH=~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS`.
- [ ] **Step 0 [dono]:** rodar `bash spikes/steam-bridge/build_bridge.sh` (com o passo novo) para publicar a ponte em `PortGames/bridge/…`.
- [ ] **Step 1: Testes** — `forwarderExportsMatch` (para cada `.dll` em `PortGames/bridge/…` se existir, senão um PE mínimo montado no teste com 3 exports: `exports(of: generate(...))` == `exports(of: bridge)` e cada forward == `"lsteamclient.<nome>"`), `forwarderHasNoDataSection`, `forwarderMachineMatches`, `stageLayout` (pasta de ponte falsa → todos os destinos existem), `missingBridgeIsClearError` (mensagem cita `build_bridge.sh`).
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS. **Step 5:** Commit `feat(launcher): Steam bridge staging and PE forwarders`.

### Task 8: appinfo.vdf da Steam do Mac

**Files:** Create `launcher/Sources/LauncherCore/AppInfo.swift`, `launcher/Tests/LauncherCoreTests/AppInfoTests.swift`.

**Interfaces — Produces:** `struct AppInfo: Equatable { var appID: UInt32; var name: String; var oslist: [String]; var launch: [LaunchEntry]; var publicBuildID: UInt64?; var depots: [Depot] }`, `struct LaunchEntry: Equatable { var executable: String; var arguments: String; var oslist: [String] }`, `struct Depot: Equatable { var id: UInt32; var oslist: [String]; var osarch: String?; var publicManifest: UInt64?; var maxSize: UInt64? }`; `enum AppInfoReader { static func read(_ url: URL) throws -> [UInt32: AppInfo] }` — formato v29 (`magic 0x07564429`, universo, offset `Int64` da tabela de strings; entradas `appid u32, size u32, infostate u32, lastupdated u32, picstoken u64, sha1[20], changenumber u32, binsha1[20]`, KV binário com chaves por índice da tabela; tipos 0 sub, 1 string, 2 int32, 7 uint64, 8 fim) e v28 (`0x07564428`, chaves em string inline). `var AppInfo.windowsLaunch: LaunchEntry?` = primeira `LaunchEntry` com `oslist` vazio ou contendo `windows`.

- [ ] **Step 1: Testes** — `parsesV29Fixture` (arquivo v29 mínimo escrito pelo teste com 2 apps → nome, oslist, launch, buildid, depots), `parsesV28Fixture`, `truncatedFileThrows`, `realFileSmoke` (`PORTGAMES_INTEGRATION=1`: lê o `appinfo.vdf` real; 331160 → `Cars`, `Cars.exe`, buildid `454676`; 1174180 → `PlayRDR2.exe`).
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS. **Step 5:** Commit `feat(launcher): Steam appinfo.vdf reader`.

### Task 9: Conta Steam (QR) e biblioteca

**Files:** Create `launcher/Sources/LauncherCore/SteamAuth.swift`, `launcher/Sources/LauncherCore/Library.swift`, `launcher/Sources/LauncherCore/HTTP.swift`, `launcher/Tests/LauncherCoreTests/SteamAuthTests.swift`, `launcher/Tests/LauncherCoreTests/LibraryTests.swift`.

**Interfaces — Produces:**
- `protocol HTTPClient: Sendable { func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) }` + `URLSessionHTTPClient`.
- `struct SteamSession: Codable, Equatable { var accountName: String; var steamID: UInt64; var refreshToken: String; var accessToken: String }`; `protocol TokenStore { func load() throws -> SteamSession?; func save(_ s: SteamSession) throws; func clear() throws }` + `KeychainTokenStore` (serviço `com.portgames.steam`).
- `actor SteamAuth { init(http: HTTPClient, store: TokenStore); func beginQR() async throws -> (challengeURL: URL, poll: () async throws -> SteamSession?); func validSession() async throws -> SteamSession? }` — `IAuthenticationService/BeginAuthSessionViaQR/v1` (`device_friendly_name=Port Games`, `platform_type=1`), `PollAuthSessionStatus/v1` até receber tokens (respeitar `interval`; `new_challenge_url` substitui o QR); `GenerateAccessTokenForApp/v1` renova o access token; token revogado/expirado (401/`eresult` ≠ 1) → `clear()` e devolve `nil`.
- `enum QRImage { static func png(for url: URL, scale: CGFloat) throws -> Data }` (CoreImage `CIQRCodeGenerator`).
- `struct LibraryGame: Equatable { var appID: UInt32; var name: String; var coverURL: URL; var info: AppInfo?; var state: GameState?; var status: Status }`, `enum Status { case notInstalled, installing, installed, updateAvailable }`; `struct Library { init(http: HTTPClient, paths: Paths, appInfoURL: URL); func games(session: SteamSession) async throws -> [LibraryGame] }` — `IPlayerService/GetOwnedGames/v1` (`access_token`, `steamid`, `include_appinfo=1`, `include_played_free_games=1`); capa `https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/<id>/library_600x900.jpg`; `updateAvailable` quando `state.complete && info.publicBuildID != state.buildID`.
- [ ] **Step 1: Testes** (HTTPClient falso com respostas JSON gravadas): `qrHappyPath` (begin → poll pendente → poll com tokens → sessão salva), `qrNewChallengeURL`, `revokedTokenClearsAndReturnsNil`, `ownedGamesMergedWithAppInfo` (2 jogos, 1 com estado instalado buildid antigo → `.updateAvailable`, outro `.notInstalled`), `coverURL`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS. **Step 5 [integração, dono]:** `launcherctl login` mostra QR (PNG em `logs/qr.png` + URL), dono escaneia; `launcherctl library` lista Cars, Spacewar e RDR2. **Step 6:** Commit `feat(launcher): Steam QR login and owned library`.

### Task 10: Download, atualização e desinstalação

**Files:** Create `launcher/Sources/LauncherCore/Installer.swift`, `launcher/Sources/LauncherCore/DepotDownloader.swift`, `launcher/Tests/LauncherCoreTests/InstallerTests.swift`.

**Interfaces — Consumes:** `SteamSession`, `AppInfo`, `GameStateStore`, `ArtifactStore`. **Produces:**
- `protocol DepotDownloaderProtocol: Sendable { func download(appID: UInt32, depots: [Depot], into dir: URL, session: SteamSession, progress: @Sendable (Double) -> Void) async throws }`
- `protocol VolumeInspector: Sendable { func fileSystem(at: URL) throws -> String /* "apfs", "hfs", "exfat", "msdos"… */; func freeBytes(at: URL) throws -> UInt64 }` + `SystemVolumeInspector` (`URLResourceValues.volumeTypeName` / `volumeAvailableCapacityForImportantUsage`).
- `struct DepotDownloader: DepotDownloaderProtocol { init(binary: URL); func download(appID: UInt32, depots: [Depot], into dir: URL, session: SteamSession, progress: @Sendable (Double) -> Void) async throws }` — subprocesso; progresso lido das linhas `NN.NN%`.
- `struct Installer { init(paths: Paths, downloader: DepotDownloaderProtocol, volumes: VolumeInspector); func install(_ info: AppInfo, session: SteamSession, library: URL?, progress: @Sendable (Double) -> Void) async throws -> GameState; func update(...) async throws -> GameState; func uninstall(_ appID: UInt32) throws }` — depots = os com `oslist` contendo `windows` (ou vazio) e, se houver variantes, `osarch` "64" antes de "32"; antes de baixar: `VolumeInspector` confere formato (recusa exFAT/FAT/msdos) e espaço livre ≥ soma de `maxSize` + 5%; estado salvo com `complete: false` no início e `true` só no fim; `uninstall` apaga só `games/<appID>` e o estado.
- [ ] **Step 0 [pesquisa + dono]:** fixar o DepotDownloader 3.4.0 `DepotDownloader-macos-arm64.zip` (URL e SHA-256 em `launcher/Sources/LauncherCore/Resources/artifacts.json`) e decidir como ele usa a **mesma** sessão do QR: (a) gravar o refresh token no armazenamento de conta do DepotDownloader e chamar com `-username <conta> -remember-password`; se inviável, (b) usar o `-qr` dele **como** o login único do app (lendo a URL do QR da saída) e obter o access token da Web API pelo mesmo refresh token. Registrar a escolha num ADR (`docs/decisions/0004-login-unico-download.md`). Critério: um QR por máquina.
- [ ] **Step 1: Testes** (downloader e inspector falsos): `refusesExFAT`, `refusesInsufficientSpace` (mensagem com GB faltando), `interruptedNotComplete` (downloader lança no meio → estado `complete == false`, nova `install` chama o downloader de novo), `picksWindowsDepots` (Carros: só depots windows), `uninstallKeepsPrefixAndRecipe`, `updateKeepsPrefixAndRecipe` (buildid novo salvo).
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS. **Step 5 [integração, dono]:** `launcherctl install 331160` baixa ~1,1 GB em `games/331160` e grava buildid `454676`. **Step 6:** Commit `feat(launcher): install, update and uninstall via DepotDownloader`.

### Task 11: Jogar

**Files:** Create `launcher/Sources/LauncherCore/GameLauncher.swift`, `launcher/Sources/LauncherCore/SteamClientProbe.swift`, `launcher/Tests/LauncherCoreTests/GameLauncherTests.swift`.

**Interfaces — Consumes:** Tasks 2, 5, 6, 7, 8, 10. **Produces:** `protocol SteamClientProbe { func isRunning() -> Bool; func open() throws; func isLoggedIn() -> Bool }` (`pgrep -x steam_osx`; `open -ga Steam`; logado = `config/loginusers.vdf` tem `MostRecent "1"` e o processo existe); `struct GameLauncher { func play(appID: UInt32) async throws -> RunningGame }` — garante Steam do Mac (abre e espera login até 60 s, senão `LauncherError.steamNotLoggedIn`), engine, ponte (`Bridge.stage`), prefixo; executável = `recipe.executable` ou `info.windowsLaunch.executable` relativo a `G:\`; inicia `C:\Program Files (x86)\Steam\steam.exe` e depois o jogo com `cwd` na pasta do executável e `Bridge.environment(appID)`; log em `logs/<appID>.log`. `struct RunningGame { func wait() async -> Int32; func stop() async throws }`.
- [ ] **Step 1: Testes** (probe/runner falsos): `opensSteamWhenClosed`, `failsWhenNotLoggedInAfterTimeout` (timeout injetável), `usesRecipeExecutable` (Carros → `G:\Cars.exe`), `usesAppInfoLaunchWhenNoRecipe`, `notInstalledIsError`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS. **Step 5:** Commit `feat(launcher): play through the Mac Steam bridge`.

### Task 12: launcherctl e aceite

**Files:** Modify `launcher/Sources/launcherctl/main.swift`; Create `launcher/README.md` (português: como compilar, publicar a ponte e usar o CLI); Modify `CLAUDE.md` (Estrutura + Comandos), `README.md` (seção "Lançador (em construção)").

**Interfaces — Produces:** comandos `launcherctl login | logout | library | install <appid> [--library DIR] | update <appid> | uninstall <appid> | play <appid> | status <appid> | recipe <appid> [--renderer R] [--emulate-modeset on|off] [--env K=V]… [--dll NAME=VALUE]… [--show]` (`recipe` = modo de teste: grava a receita local via `RecipeStore.saveLocal`, partindo da receita efetiva); códigos de saída 0/1; mensagens em inglês.
- [ ] **Step 1: Testes** — `cliParsesCommands` (parser isolado em `LauncherCore/CLI.swift`: comandos válidos e inválidos → uso); `recipeCommandMergesOverEffective` (`recipe 331160 --renderer d9vk` mantém `cdLabel` DISC2 e troca só o renderer).
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS.
- [ ] **Step 5 [aceite com o dono]:** `swift build -c release --package-path launcher`; `launcherctl login` (QR) → `library` → `install 331160` → `play 331160`: Carros abre em tela cheia esticada, pela ponte (SteamStub, sem `bak/Cars.exe`), 30 FPS, saves em `prefixes/331160`. Repetir com 480 (Spacewar: dono aparece "Jogando Spacewar"). `uninstall 331160` + `install 331160` → saves continuam.
- [ ] **Step 6:** Fechar #8 no backlog (commits), memória "Próxima sessão começa AQUI". Commit `feat(launcher): launcherctl and acceptance`.
