# Carros (2006) no Mac

Transforma o **Disney•Pixar Carros (2006)** da sua biblioteca da Steam, que só existe para Windows, num
**`Carros.app`** para Mac com Apple Silicon. Você abre com dois cliques e o jogo começa em tela cheia, sem Steam e
sem programas como CrossOver ou Whisky.

O app leva dentro dele uma cópia do Wine, a camada que traduz o Windows para o macOS, e os arquivos do jogo baixados
da **sua** conta. Nada aqui é distribuído: cada pessoa monta o próprio app com o jogo que comprou.

---

## Do que você precisa

- Mac com chip Apple (M1 ou mais novo) e **macOS 14.6 ou mais recente**.
- O jogo **Disney•Pixar Cars** (Steam, App 331160) comprado na sua conta.
- Uns **4 GB livres**: 1,1 GB do download do jogo e cerca de 2,2 GB do app.
- **Homebrew**, só para instalar o `steamcmd` no passo 2 (https://brew.sh).
- Internet na primeira montagem, para baixar o Wine (~260 MB). As montagens seguintes usam o cache.

Python 3, `curl`, `tar` e as demais ferramentas usadas já vêm no macOS.

---

## Passo a passo

Todos os comandos rodam no **Terminal**, dentro da pasta deste projeto:

```sh
cd caminho/para/portcarros
```

### 1. Ligar o Rosetta 2 (uma vez só)

O jogo é um programa Intel de 32 bits, e o Rosetta traduz esse código para o chip Apple.

```sh
softwareupdate --install-rosetta --agree-to-license
```

Se o Rosetta já estiver instalado, o comando só avisa e termina.

### 2. Baixar o jogo da sua conta Steam (uma vez só)

Instale o `steamcmd`, a ferramenta de linha de comando da Valve:

```sh
brew install --cask steamcmd
```

Baixe a versão Windows do jogo para a pasta `jogo/` do projeto, trocando `SEU_USUARIO` pelo seu login da Steam:

```sh
steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$PWD/jogo" +login SEU_USUARIO +app_update 331160 validate +quit
```

- A senha e o código do Steam Guard são pedidos no próprio Terminal.
- Na primeira vez o `steamcmd` se atualiza sozinho, e isso demora um pouco.
- Se o macOS bloquear o `Breakpad.framework` ou o `steamconsole.dylib`, vá em **Ajustes do Sistema → Privacidade e
  Segurança**, clique em **Permitir mesmo assim** e rode o comando de novo.
- Ao final, a pasta `jogo/` tem cerca de 1,1 GB. Depois disso o `steamcmd` pode ser desinstalado
  (`brew uninstall --cask steamcmd`).

### 3. Montar e instalar o app

```sh
python3 tools/builder/build.py carros --install
```

Leva cerca de um minuto. O script:

1. confere se os arquivos do jogo são da versão esperada e para com uma mensagem clara se não forem;
2. baixa e confere o Wine e o modelo de app (só na primeira vez);
3. monta o `Carros.app`, cria o "Windows" interno e copia o jogo;
4. aplica os ajustes: tela cheia, drive de CD virtual, gráficos e controles;
5. com `--install`, copia o app para **Aplicativos**.

Sem `--install`, o app fica em `build/Carros.app` e você pode arrastá-lo para onde quiser.

### 4. Jogar

Abra **Carros** em Aplicativos, pelo Launchpad ou pelo Spotlight. Os vídeos de abertura tocam e o jogo entra em
tela cheia.

- **Sair:** use a opção de sair no menu do jogo.
- **Saves:** ficam em `~/Documents/THQ/Cars/Save`, fora do app. Apagar, remontar ou reinstalar o app não apaga
  o seu progresso.

---

## O que esperar

| Item | Como fica |
|---|---|
| Tela | Tela cheia na resolução do seu Mac, com a imagem esticada (o jogo é 4:3) |
| Gráficos | 1600×1200 internos, antisserrilhado 4x, efeitos ligados |
| Fluidez | **30 FPS estáveis**, que é o limite de fábrica do jogo |
| Som e vídeos | Normais |
| Controle | Configurado para controles por cabo e Bluetooth (Xbox, PlayStation, Switch Pro, 8BitDo e genéricos). Validação com controle real ainda pendente |

Ajustes de vídeo feitos no menu do jogo ficam guardados dentro do app. Quando você remonta o app, eles voltam aos
valores acima.

---

## Problemas comuns

**"game files not found" ou "is not the expected build" ao montar**
Refaça o passo 2. O script só aceita a versão atual da Steam, conferida por hash.

**O macOS diz que o app não pode ser aberto**
Clique com o botão direito em **Carros** → **Abrir** → **Abrir**. Isso só é necessário uma vez.

**Parou de abrir depois de uma atualização do macOS**
Remonte com `python3 tools/builder/build.py carros --install`. Os saves continuam onde estavam.

**Quero voltar os ajustes de vídeo ao padrão**
Remontar o app faz isso.

**Desinstalar**
Apague `Carros.app` de Aplicativos. Para apagar também os saves, remova `~/Documents/THQ/Cars`. Para apagar o
cache do Wine, remova `~/Library/Caches/portcarros`.

---

## Para quem mexe no projeto

```sh
python3 -m unittest discover -s tools/builder -t tools/builder   # testes
python3 tools/builder/build.py carros                            # só monta em build/
node tools/backlog/backlog.mjs next                              # o que fazer a seguir
```

- `tools/builder/recipes/carros.json` guarda tudo o que é específico do Carros: executável e hash, rótulo do CD,
  registro do Windows e camada gráfica.
- `tools/builder/artifacts.json` guarda as versões e hashes do Wine e do modelo de app (Sikarugir).
- As decisões estão em `docs/decisions/`, as investigações em `docs/analises/` e o desenho e o plano em
  `docs/specs/` e `docs/plans/`.
- `CLAUDE.md` traz as regras do projeto. A principal: os arquivos do jogo (`jogo/`) e o app gerado (`build/`)
  **nunca** entram no git.
