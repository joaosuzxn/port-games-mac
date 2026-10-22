# Carros.app — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Um script do repositório monta, a partir de `jogo/`, um `Carros.app` autocontido (Wine + D3D9 + prefixo + jogo) que abre o Carros 2006 em tela cheia com dois cliques, com controle e FPS jogável.

**Architecture:** Python 3 do sistema, só biblioteca padrão. Um "motor" genérico (`tools/montar/`) lê uma receita JSON por jogo (`tools/montar/receitas/carros.json`), garante os artefatos (template Sikarugir 1.0.24 e engine WS12WineSikarugir 11.0_1) num cache verificado por hash, monta o bundle a partir do template, cria o prefixo pelo launcher do próprio template (`wineskinlauncher WSS-wineprefixcreate`), copia o jogo e aplica os ajustes provados no teste rápido. Testes `unittest` cobrem a lógica pura; o que depende de Wine/tela é verificado com o dono.

**Tech Stack:** Python 3 (stdlib: `json`, `plistlib`, `hashlib`, `shutil`, `subprocess`, `tarfile`, `struct`, `unittest`), `sips`/`iconutil`/`codesign`/`xattr` do macOS, Wine do Sikarugir (dentro do bundle).

**Spec:** `docs/specs/2026-10-22-carros-app-design.md` (ler junto) · análises em `docs/analises/2026-10-22-*.md`

## Global Constraints

- Nada instalado no Mac para jogar além do `Carros.app`; nada de `brew`/`pip`/`npm` sem aprovação do dono. Script usa só stdlib + ferramentas do macOS.
- Arquivos do jogo e o `.app` gerado nunca entram no git (`jogo/`, `build/` já no `.gitignore`); cache de artefatos fora do repositório: `~/Library/Caches/portcarros/artefatos`.
- Executável usado: `bak/Cars.exe`, SHA-1 `a175e49a8cd3aa67ffd71b7cf1a8d0c90b527902`, copiado como `Cars.exe`. Se o hash não bater, parar sem montar.
- Excluir do app: `_jvm`, `_uninst`, `_CommonRedist`, `steamapps`, `THQ Website.url`, `Cars.exe` original (com SteamStub), `bak`.
- Drive `D:` → pasta do jogo, tipo `cdrom`, rótulo `DISC2` (arquivo `.windows-label`).
- Área de trabalho virtual do Wine sempre ligada (troca de resolução em tela cheia derruba o jogo).
- Engine: `WS12WineSikarugir11.0_1.tar.xz`, SHA-256 `67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e`. Template: `Template-1.0.24.app`.
- Nunca editar `system.reg`/`user.reg` com o Wine do bundle vivo: sempre `parar_wine()` antes.
- Saves: só `Documents/THQ` do prefixo ligado a `~/Documents/THQ`; o script nunca apaga nada em `~/Documents/THQ`.
- `Configure.app` removido do bundle final; `Debug Mode` = 0 no app final.
- Commits em branch `feat/carros-app`, arquivo por arquivo, mensagem com coautoria do Claude; sem merge na `main` sem o ok do dono.
- Testes: `python3 -m unittest discover -s tools/montar -t tools/montar -v`.

## Review Focus

- **Montar duas vezes seguidas** → a segunda substitui o app anterior por inteiro, sem aninhar `Carros.app/Carros.app` nem herdar prefixo velho (teste em Task 3).
- **Saves já existentes em `~/Documents/THQ/Cars/Save`** → montar, remontar e apagar o app não mexe neles (teste em Task 4).
- **`jogo/` ausente, incompleto ou com hash diferente** → erro claro em português, nada é montado nem apagado (teste em Task 4 e Task 5).
- **App movido para `/Applications` (caminho com espaço, outro local)** → nada no `Info.plist`, registro ou links aponta para `build/` (teste em Task 3 e Task 4).
- **Monitor diferente do usado na montagem (tela externa, outra resolução)** → o jogo ainda abre e preenche a tela principal; tamanho da área virtual decidido na abertura, não fixo na montagem, se a engine permitir (verificação em Task 6).

---

### Task 1: Receita do jogo

**Files:**
- Create: `tools/montar/receita.py`
- Create: `tools/montar/receitas/carros.json`
- Test: `tools/montar/test_receita.py`

**Interfaces:**
- Produces:
  - `@dataclass(frozen=True) ChaveRegistro(colmeia: Literal["system","user"], chave: str, valores: dict[str, str | int])` — `int` vira `dword:XXXXXXXX`, `str` vira `"..."`.
  - `@dataclass(frozen=True) Receita(nome: str, nome_app: str, bundle_id: str, pasta_jogo: str, exe_origem: str, exe_destino: str, sha1_exe: str, excluir: tuple[str, ...], rotulo_cd: str | None, pasta_saves: str | None, renderizador: Literal["d9vk","wined3d","d3dmetal"], registro: tuple[ChaveRegistro, ...])`
  - `carregar_receita(caminho: Path) -> Receita`; erro `ReceitaInvalida(Exception)` com mensagem em português citando o campo.

- [ ] **Step 1: Testes que falham** — `test_carrega_carros` (carrega `receitas/carros.json`: `nome == "carros"`, `nome_app == "Carros"`, `bundle_id == "local.portcarros.carros"`, `exe_origem == "bak/Cars.exe"`, `exe_destino == "Cars.exe"`, `sha1_exe == "a175e49a8cd3aa67ffd71b7cf1a8d0c90b527902"`, `rotulo_cd == "DISC2"`, `pasta_saves == "THQ"`, `renderizador == "d9vk"`, `"_jvm" in excluir` e os demais da Global Constraints), `test_registro_carros` (contém `ChaveRegistro("system", r"Software\Wine\Drives", {"d:": "cdrom"})` e `ChaveRegistro("user", r"Software\Wine\Explorer", {"Desktop": "Default"})`), `test_campo_faltando` (JSON sem `sha1_exe` → `ReceitaInvalida` cuja mensagem contém `"sha1_exe"`), `test_renderizador_invalido` (`"vulkan"` → `ReceitaInvalida`), `test_sha1_malformado` (não 40 hex → `ReceitaInvalida`).
- [ ] **Step 2:** Rodar `python3 -m unittest discover -s tools/montar -t tools/montar -v` → FAIL (módulo inexistente).
- [ ] **Step 3:** Escrever `receitas/carros.json` com os valores acima; a área virtual começa em `Software\Wine\Explorer\Desktops {"Default": "1280x720"}` (valor provado; Task 6 ajusta). Implementar `carregar_receita` validando tipos e campos obrigatórios.
- [ ] **Step 4:** Rodar os testes → PASS.
- [ ] **Step 5:** Commit `feat: receita do Carros e leitor de receitas`.

### Task 2: Artefatos verificados (template e engine)

**Files:**
- Create: `tools/montar/artefatos.py`, `tools/montar/artefatos.json`
- Test: `tools/montar/test_artefatos.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `sha256_arquivo(p: Path) -> str`; `sha256_pasta(p: Path) -> str` (determinístico: caminhos relativos ordenados + conteúdo + bit de executável; ignora `.DS_Store`).
  - `@dataclass(frozen=True) Artefato(nome: str, arquivo: str, sha256: str, url: str | None)`; `carregar_artefatos(caminho: Path) -> dict[str, Artefato]` (chaves `"template"`, `"engine"`).
  - `garantir_artefato(a: Artefato, cache: Path, fontes_locais: list[Path]) -> Path` — devolve o caminho no cache; se ausente, copia da primeira fonte local que tiver `a.arquivo` com hash certo, senão baixa de `a.url` (urllib) se houver; confere hash depois. Erro `ArtefatoInvalido` (mensagem diz o que faltou e onde procurou).
  - Fonte local padrão: `~/Library/Application Support/Sikarugir/Template` e `.../Engines`.

- [ ] **Step 1: Pesquisa** — localizar a publicação oficial (GitHub releases do Sikarugir/Gcenx) do `Template-1.0.24` e de `WS12WineSikarugir11.0_1.tar.xz`. Se achar URL estável cujo hash bate com o cache local, preencher `url`; senão `null`. Calcular o `sha256_pasta` do template local e gravar em `artefatos.json`. Anotar a conclusão no item #2 do backlog (`set 2 nota=...`).
- [ ] **Step 2: Testes que falham** — `test_sha256_pasta_deterministico` (duas pastas iguais criadas em ordem diferente → mesmo hash; mudar 1 byte → hash diferente), `test_garante_de_fonte_local` (artefato fake em pasta temporária vira cópia no cache), `test_hash_errado_recusa` (fonte com conteúdo diferente → `ArtefatoInvalido`, cache continua sem o arquivo), `test_ja_no_cache_nao_copia` (segunda chamada não lê a fonte), `test_sem_fonte_sem_url` → `ArtefatoInvalido` com os caminhos procurados na mensagem.
- [ ] **Step 3:** Rodar → FAIL. **Step 4:** Implementar. **Step 5:** Rodar → PASS.
- [ ] **Step 6:** Commit `feat: cache de artefatos verificado por hash`.

### Task 3: Montagem do bundle

**Files:**
- Create: `tools/montar/bundle.py`
- Test: `tools/montar/test_bundle.py`

**Interfaces:**
- Consumes: `Receita` (Task 1), caminhos de `garantir_artefato` (Task 2).
- Produces:
  - `montar_bundle(template: Path, engine_tar: Path, saida: Path, receita: Receita) -> Path` — cria `saida/<nome_app>.app` a partir de cópia do template (substitui por inteiro se já existir, montando numa pasta temporária ao lado e trocando no fim), extrai `wswine.bundle/` da engine para `Contents/SharedSupport/wine/`, remove `Contents/Configure.app`, chama `configurar_info_plist`. Devolve o caminho do app.
  - `configurar_info_plist(plist: Path, receita: Receita) -> None` — `CFBundleName`/`CFBundleIdentifier` da receita; `Program Name and Path` = `/Games/<nome_app>/<exe_destino>`; flags do renderizador (`D9VK`, `DXVK`, `D3DMETAL` só a da receita = 1); `Debug Mode` = 0; `WINEDEBUG` = `-all`; `Symlinks In User Folder` = 0 (saves tratados na Task 4).

- [ ] **Step 1: Testes que falham** (template e engine falsos mínimos montados no teste: `Contents/Info.plist` com as chaves do Sikarugir, `Contents/Configure.app/`, tar.xz com `wswine.bundle/bin/wine`) — `test_monta_estrutura` (`SharedSupport/wine/bin/wine` existe e é executável; `Configure.app` não existe), `test_info_plist` (valores acima, incluindo `Program Name and Path == "/Games/Carros/Cars.exe"`, `D9VK == 1`, `DXVK == 0`, `D3DMETAL == 0`, `Debug Mode == 0`), `test_remontar_substitui` (montar duas vezes → um único `Carros.app`, sem `Carros.app/Carros.app`, arquivo extra criado entre as montagens some), `test_plist_sem_caminho_absoluto` (nenhum valor string do plist contém o caminho de `saida`).
- [ ] **Step 2:** Rodar → FAIL. **Step 3:** Implementar. **Step 4:** Rodar → PASS.
- [ ] **Step 5:** Commit `feat: montagem do bundle a partir do template`.

### Task 4: Prefixo, jogo, drive de CD, registro e saves

**Files:**
- Create: `tools/montar/prefixo.py`
- Test: `tools/montar/test_prefixo.py`

**Interfaces:**
- Consumes: `Receita`, `ChaveRegistro` (Task 1); app de `montar_bundle` (Task 3).
- Produces:
  - `criar_prefixo(app: Path) -> Path` — roda `Contents/MacOS/wineskinlauncher WSS-wineprefixcreate`, espera terminar, chama `parar_wine`; devolve `Contents/SharedSupport/prefix`. Erro `PrefixoFalhou` se `system.reg` não existir ao fim.
  - `parar_wine(app: Path, tempo_max: float = 30.0) -> None` — `wineskinlauncher WSS-wineserverkill`; espera não haver processo cujo comando contenha o caminho do app ou `C:\`-processos do prefixo; após `tempo_max`, `SIGKILL`.
  - `copiar_jogo(origem: Path, destino: Path, receita: Receita) -> None` — confere SHA-1 de `origem/exe_origem` antes de copiar qualquer coisa (`JogoInvalido` se faltar pasta, faltar exe ou hash diferente); copia sem os itens de `excluir`; grava `exe_origem` como `destino/exe_destino`.
  - `configurar_drive_cd(prefixo: Path, alvo_relativo: str, rotulo: str) -> None` — link `dosdevices/d:` → `../drive_c/<alvo_relativo>` (relativo), arquivo `.windows-label` com `rotulo` na raiz do alvo.
  - `aplicar_registro(prefixo: Path, chaves: Iterable[ChaveRegistro]) -> None` — grava em `system.reg`/`user.reg` no formato do Wine (`[Chave\\Com\\Barras] <timestamp>`, `"nome"="valor"`, `"nome"=dword:00000001`); **idempotente**: se a seção existe, substitui os valores em vez de duplicar a seção.
  - `ligar_saves(prefixo: Path, pasta: str, documentos_mac: Path) -> None` — em `drive_c/users/*/Documents/` (ou `My Documents`), cria `pasta` como link para `documentos_mac/pasta` (cria `documentos_mac/pasta` se não existir; nunca apaga conteúdo existente).

- [ ] **Step 1: Testes que falham** (pastas temporárias; jogo falso com `bak/Cars.exe` cujo SHA-1 é injetado numa receita de teste) — `test_copia_sem_excluidos` (nenhum de `_jvm`, `_uninst`, `_CommonRedist`, `steamapps`, `bak` no destino; `Cars.exe` do destino tem o conteúdo de `bak/Cars.exe`), `test_hash_errado_nao_copia` (`JogoInvalido` e destino vazio), `test_jogo_ausente` (`JogoInvalido` com mensagem citando `jogo/` e o comando do steamcmd da análise), `test_drive_cd` (`d:` é link relativo, não absoluto; `.windows-label` contém `DISC2`), `test_registro_formato` (`system.reg` ganha `[Software\\Wine\\Drives]` com `"d:"="cdrom"`; dword formatado `dword:00000001`), `test_registro_idempotente` (aplicar duas vezes → a seção aparece uma vez), `test_saves_preservados` (`documentos_mac/THQ/Cars/Save/slot1` pré-existente continua lá depois de `ligar_saves` e depois de apagar o prefixo).
- [ ] **Step 2:** Rodar → FAIL. **Step 3:** Implementar. **Step 4:** Rodar → PASS.
- [ ] **Step 5: Verificação real de `criar_prefixo`/`parar_wine`** — num app montado pela Task 3 em `build/`: `criar_prefixo` termina, `system.reg` existe e `ps` não mostra processo do app. Aplicar registro, rodar `WSS-wineboot` + `parar_wine`, e conferir que a seção `[Software\\Wine\\Drives]` sobreviveu (prova de que o registro não foi sobrescrito).
- [ ] **Step 6:** Commit `feat: prefixo, cópia do jogo, drive de CD, registro e saves`.

### Task 5: Comando `montar`, ícone e finalização

**Files:**
- Create: `tools/montar/montar.py`, `tools/montar/icone.py`
- Test: `tools/montar/test_icone.py`, `tools/montar/test_montar.py`
- Modify: `CLAUDE.md` (seção Estrutura e um parágrafo "Montar o app")

**Interfaces:**
- Consumes: tudo das Tasks 1–4.
- Produces:
  - `extrair_icone(exe: Path, destino_icns: Path) -> bool` — lê `RT_GROUP_ICON`/`RT_ICON` do `.rsrc` do PE, monta `.ico` do maior ícone, converte com `sips` → PNG → `iconutil` → `.icns`; `False` (sem erro) se o exe não tiver ícone.
  - CLI: `python3 tools/montar/montar.py <receita> [--saida build] [--cache ~/Library/Caches/portcarros/artefatos] [--instalar]` → `main(argv: list[str]) -> int`. Ordem: carregar receita → conferir `jogo/` (falha antes de tocar em `build/`) → garantir artefatos → `montar_bundle` → `criar_prefixo` → `copiar_jogo` para `drive_c/Games/<nome_app>` → drive de CD → registro → saves → ícone em `Contents/Resources/` + `CFBundleIconFile` → `parar_wine` → `xattr -dr com.apple.quarantine` → `codesign --force --deep -s -`. `--instalar` copia para `/Applications/<nome_app>.app` (substituindo). Saída: uma linha por etapa, em português; código 0 só se tudo deu certo.

- [ ] **Step 1: Testes que falham** — `test_icone_cars` (pula se `jogo/bak/Cars.exe` não existir; senão gera `.icns` não vazio), `test_icone_sem_recurso` (PE mínimo sem `.rsrc` → `False`), `test_main_sem_jogo` (`main(["carros", "--saida", tmp])` com receita apontando para pasta inexistente → código ≠ 0, `tmp` continua vazio), `test_main_receita_inexistente` → código ≠ 0 e mensagem citando o nome.
- [ ] **Step 2:** Rodar → FAIL. **Step 3:** Implementar. **Step 4:** Rodar → PASS.
- [ ] **Step 5: Montagem real** — `python3 tools/montar/montar.py carros` → `build/Carros.app`; `codesign -v build/Carros.app` sem erro; `du -sh` registrado.
- [ ] **Step 6: Com o dono** — dono abre `build/Carros.app` com dois cliques: vídeos tocam, sem diálogo de CD/erro/configuração, menu responde. Resultado anotado no item #2.
- [ ] **Step 7:** Commit `feat: comando montar com ícone, assinatura e instalação`.

### Task 6: Tela cheia esticada

**Files:**
- Modify: `tools/montar/receitas/carros.json` (área virtual e opções da engine), `tools/montar/bundle.py` ou `prefixo.py` só se precisar de nova chave genérica (com teste)
- Create: `docs/decisions/0002-tela-cheia.md`

- [ ] **Step 1: Experimentos com o dono** (um por vez, app remontado a cada um): área virtual = tamanho da tela principal em pontos (`system_profiler SPDisplaysDataType`/`NSScreen`) vs em pixels com `RetinaMode`; a janela da área virtual ocupando a tela sem bordas (tela cheia do macOS ou opção da engine); resolução escolhida no menu do jogo. Critério: tela inteira, sem bordas, sem faixas pretas, imagem esticada se a proporção não for 16:10.
- [ ] **Step 2:** Se a engine permitir decidir o tamanho na abertura (ex.: `Desktop` sem tamanho fixo, ou comando no launcher), preferir isso ao valor fixo — cobre monitor externo (Review Focus). Testar com o dono, se ele tiver monitor externo; senão registrar como não verificado.
- [ ] **Step 3:** ADR 0002 com a escolha e as alternativas testadas. Ajustar receita e, se houver código novo, seu teste.
- [ ] **Step 4:** Commit `feat: tela cheia esticada` (+ ADR).

### Task 7: Desempenho (backlog #4)

**Files:**
- Modify: `tools/montar/receitas/carros.json`
- Create: `docs/decisions/0003-camada-grafica.md`, `docs/analises/2026-10-xx-medicoes-fps.md`

- [ ] **Step 1: Linha de base** — app da Task 6, log desligado, HUD ligado (`METAL_HUD` = 1 no plist ou `DXVK_HUD=fps` em "Unix Commands"), mesma pista e mesmo trecho: dono informa FPS médio/mínimo.
- [ ] **Step 2: Comparar, uma variável por vez** — `d9vk` vs `wined3d` vs `d3dmetal` (se a engine aceitar D3D9); resolução do jogo; vsync/limitador do DXVK (`dxvk.conf` ao lado do exe: `d3d9.presentInterval`, `dxgi.maxFrameLatency`). Registrar cada medição na análise.
- [ ] **Step 3: Regra de parada** — se nada chegar a 30 FPS estáveis, parar e levar as medições ao dono antes de qualquer mudança de abordagem.
- [ ] **Step 4:** Fixar a melhor combinação na receita, ADR 0003, fechar #4 (`set 4 status=feito commits=+sha validacao=pendente`).
- [ ] **Step 5:** Commit `perf: camada gráfica e ajustes de FPS`.

### Task 8: Controles

**Files:**
- Modify: `tools/montar/receitas/carros.json` (chaves do `winebus`)
- Create: `docs/analises/2026-10-xx-controles.md`

- [ ] **Step 1:** Ligar o backend SDL do Wine na receita: `system` → `System\CurrentControlSet\Services\winebus` com `"Enable SDL"=1` e `"Map Controllers"=1` (layout Xbox para qualquer controle reconhecido pelo SDL embutido em `Frameworks/libSDL2*`). Teste de receita atualizado (`test_registro_carros` inclui a chave).
- [ ] **Step 2: Com o dono** — controle dele por **cabo** e por **Bluetooth**: navega no menu, acelera/freia/vira na corrida; conectar **com o jogo já aberto** também funciona. Registrar modelo testado e resultado.
- [ ] **Step 3:** Se algum botão vier trocado, ajustar mapeamento (config do jogo ou `SDL_GAMECONTROLLERCONFIG` via "Unix Commands") e registrar. Modelos não testados ficam listados na análise como "cobertos pelo SDL, não testados".
- [ ] **Step 4:** Commit `feat: suporte a controles via SDL`.

### Task 9: Aceite final e fechamento

**Files:**
- Modify: `docs/backlog/itens/0002-*.md`, `docs/backlog/itens/0004-*.md`, `CLAUDE.md`, memória do projeto

- [ ] **Step 1: Aceite do zero** — esvaziar `~/Library/Caches/portcarros/artefatos` e `build/`, rodar `montar.py carros --instalar`, e com o dono conferir os 8 critérios de aceite da spec (inclusive: desinstalar o Sikarugir Creator antes, ou movê-lo para fora de `/Applications`, com o ok dele; saves continuam após apagar e remontar).
- [ ] **Step 2:** Rodar a suíte inteira → PASS.
- [ ] **Step 3:** Apagar o wrapper de teste `~/Applications/Sikarugir/CarrosTeste.app` (com o ok do dono).
- [ ] **Step 4:** Fechar #2 (virar `feature` antes, `status=feito`, commits, `validacao=ok` se o dono confirmou), atualizar ADR 0001 para `Accepted` via novo status, memória ("Próxima sessão começa AQUI").
- [ ] **Step 5:** Commit `docs: fechamento do Carros.app`.
