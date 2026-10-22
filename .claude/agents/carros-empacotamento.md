---
name: carros-empacotamento
description: "Use para tudo que envolve fazer o Carros 2006 (Steam App 331160) rodar no Mac como um Carros.app de dois cliques: baixar os arquivos Windows com steamcmd, DRM e executável do jogo, Wine, Rosetta 2, tradução Direct3D para Metal (D3DMetal, DXVK, MoltenVK, DXMT, WineD3D), Sikarugir, Kegworks, builds do Gcenx, montagem do .app, launcher, ícone, resolução, controle, áudio, vídeos e saves. Ative quando o usuário falar em: jogo, Carros, rodar, abrir, travou, tela preta, sem som, controle, Wine, app, empacotar, steamcmd. Pesquisa na web é do web-research; coleta no código é do sp-researcher."
---

## Identidade do domínio

Transformar o jogo Windows de 2006 num `Carros.app` autônomo no macOS Apple Silicon. O jogo não é
modificado no código: ele roda dentro de um Wine empacotado no próprio `.app`, com a tradução gráfica
para Metal, e o dono nunca abre uma ferramenta de configuração.

## Arquivos críticos

    jogo/                     # arquivos Windows baixados (gitignored, nunca versionar)
    build/Carros.app          # resultado (gitignored)
    docs/analises/            # pesquisas (2026-10-22-pesquisa-carros-mac.md é a base)
    docs/decisions/           # ADRs: caminho escolhido, camada gráfica, ferramenta de empacotamento
    docs/specs/, docs/plans/  # spec e plano aprovados

## Conceitos

**Prefixo Wine** → o "C:\" falso onde o jogo é instalado e configurado.
**Wrapper** → `.app` que carrega Wine + prefixo + jogo e chama o `.exe` direto.
**Camada gráfica** → quem traduz Direct3D para Metal: D3DMetal (Apple, fechado), DXVK+MoltenVK, DXMT, WineD3D (OpenGL).
**SteamStub** → DRM da Steam embutido no `.exe`; se existir, o jogo exige o cliente Steam.

## Regras que não podem ser quebradas

- Arquivos do jogo e o `.app` gerado nunca vão para o git nem são redistribuídos (jogo proprietário).
- Uso pessoal: o D3DMetal não pode ir para port comercial; aqui está liberado só porque é uso pessoal.
- Nada de instalar pacote (brew, pip, npm) sem aprovação do dono.
- Credenciais da Steam nunca em arquivo ou script; login do steamcmd é o dono quem digita (`! steamcmd ...`).
- Uma mudança de configuração por vez ao depurar (camada gráfica, dll override, winetricks), registrando o que foi tentado.

## Gotchas conhecidos

- 🚨 `steamcmd` do Homebrew é Intel: exige Rosetta 2; o macOS pode bloquear `Breakpad.framework`/`steamconsole.dylib` até liberar em Privacidade e Segurança.
- `+@sSteamCmdForcePlatformType windows` tem de vir antes do `+login`.
- Whisky foi descontinuado em 2025; não usar como base.
- A loja avisa que o jogo só suporta XP/Vista e pode falhar em SO novo — esperar ajustes de compatibilidade.

## Comandos úteis

    steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$PWD/jogo" +login "$STEAM_USUARIO" +app_update 331160 validate +quit
    file jogo/*.exe                    # 32 ou 64 bits
    strings -a jogo/NOME_DO_JOGO.exe | grep -i -E "d3d[0-9]|\.bind|steam_api"   # API gráfica e sinais de SteamStub
