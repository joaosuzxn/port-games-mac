# CLAUDE.md — Port do Carros (2006) para macOS

Faz o **Disney•Pixar Cars (2006, Steam App 331160, só Windows)** abrir no Mac Apple Silicon como um
`Carros.app` comum: dois cliques e o jogo começa, sem abrir CrossOver, Whisky nem configuração.
Projeto pessoal, uma pessoa, repositório único.

---

## Protocolo do Dev — nada é feito sem passar por ele

Todo pedido segue PENSAR → PRIORIZAR → FAZER → CATALOGAR, sem pular etapa:
1. **Pensar**: feature → `brainstorming` (spec em docs/specs, plano em docs/plans); bug → `systematic-debugging`;
   decisão com alternativas → ADR em docs/decisions (skill `adr-decisoes`). Não mexer em nada sem saber dizer em
   uma frase o quê e por quê.
2. **Priorizar**: todo pedido, ideia ou bug vira item em docs/backlog/itens (tipo, P0–P3, módulos) antes de
   entrar em execução. A sessão começa por `node tools/backlog/backlog.mjs next`. Bug achado no caminho vira item
   na hora, sem desviar.
3. **Fazer**: feature branch, teste/verificação antes de dizer "pronto", revisão por task e do conjunto (agentes sp-*).
4. **Catalogar**: item fechado com commits (+ `validacao=pendente` se o dono não testou o jogo rodando), memória
   (Why/How to apply + "Próxima sessão começa AQUI"), ADR se houve decisão. Só então "concluído".
"Faz rápido" = protocolo em escala menor, nunca protocolo dispensado.

---

## Fluxo de desenvolvimento — UMA SESSÃO

O Claude commita nas feature branches. Não há remoto configurado; push só com autorização explícita.

    git checkout main
    git checkout -b feat/<slug>          # ou fix/ | refactor/ | chore/
    # implementar, verificar, commitar arquivo por arquivo (nunca git add -A / git add .)
    git merge main                       # conflito se resolve na branch
    git checkout main && git merge feat/<slug> --no-edit   # fast-forward, depois que o dono aprovar
    git branch -d feat/<slug>

- SEMPRE branch de feature — nunca commitar direto na `main`.
- `git branch --show-current` antes de cada commit.
- Mensagem de commit termina com a linha de coautoria do Claude.

## Regra de ouro: arquivos do jogo

- 🚨 Os arquivos do jogo (baixados da conta Steam do dono) e o `Carros.app` gerado **nunca entram no git** e
  **nunca são redistribuídos**: o jogo é proprietário. Ficam em `jogo/` e `build/`, ambos no `.gitignore`.
- O repositório guarda só o que é nosso: scripts de download/montagem, configuração, launcher, docs.

---

## Documentos gerados pelo Claude

Nunca na raiz:
- `docs/analises/` — pesquisas e análises (.md)
- `docs/referencias/` — screenshots e imagens de referência
- `docs/specs/`, `docs/plans/` — specs e planos do Superpowers
- `docs/decisions/` — ADRs (skill `adr-decisoes`)

## Backlog

Itens em `docs/backlog/itens/` (um `.md` por item; tipo × P0–P3 × módulo). Quadro gerado em
`docs/backlog/BACKLOG.md`. Operar por `node tools/backlog/backlog.mjs <cmd>` (regras em `docs/backlog/README.md`).
Regras de sessão: (1) entrega que resolve item fecha o item com commits; (2) bug ou ideia achada no caminho vira
item na hora; (3) a memória aponta ids do backlog em vez de repetir o texto.

Módulos: `jogo` (arquivos, DRM, patches, saves) · `wine` (camada de tradução, D3D→Metal) · `app` (.app,
launcher, ícone) · `docs` · `infra` (ferramentas, scripts).

## Estrutura

    portcarros/
    ├── CLAUDE.md
    ├── .claude/agents/carros-empacotamento.md   # agente de domínio
    ├── .claude/skills/adr-decisoes/            # ADRs
    ├── docs/                                   # analises, specs, plans, decisions, backlog
    ├── tools/backlog/backlog.mjs               # CLI do backlog
    ├── tools/montar/                           # monta o .app (Python 3 stdlib); receitas/carros.json = o específico do jogo
    ├── jogo/      (gitignored)                 # arquivos Windows do jogo
    └── build/     (gitignored)                 # Carros.app gerado

## Montar o app

    python3 tools/montar/montar.py carros              # gera build/Carros.app (~2,2 GB, ~1 min)
    python3 tools/montar/montar.py carros --instalar   # e copia para /Applications
    python3 -m unittest discover -s tools/montar -t tools/montar   # testes

Artefatos (template Sikarugir 1.0.24 + engine WS12WineSikarugir 11.0_1) ficam em
`~/Library/Caches/portcarros/artefatos`, conferidos por SHA-256 (`tools/montar/artefatos.json`).
- 🚨 O launcher só cria o prefixo com o `Configure.app` presente (lê `remakedefaults.reg` dele); remover só no fim.
- 🚨 Editar `system.reg`/`user.reg` só com o Wine do app parado (`parar_wine`), senão o wineserver sobrescreve.

## Stack e ambiente

| Peça | O quê |
|---|---|
| Máquina | Mac Apple Silicon (arm64), macOS 27, zsh, Homebrew |
| Jogo | Cars 2006 PC (port da Beenox, THQ), Windows 32 bits provável, Direct3D a confirmar |
| Download | `steamcmd` com `+@sSteamCmdForcePlatformType windows` (cask Intel, roda via Rosetta 2) |
| Tradução | Wine (x86 via Rosetta 2) + D3D→Metal (D3DMetal/GPTK, DXVK+MoltenVK, DXMT ou WineD3D) — escolha em ADR |
| Empacotamento | candidato: Sikarugir (wrapper `.app`); alternativa: montagem própria com builds Gcenx |

Instalar pacote (brew, npm, pip) só com aprovação explícita do dono.

## graphify

Adiado: o projeto ainda não tem código suficiente. Entra quando houver scripts/launcher para mapear.
