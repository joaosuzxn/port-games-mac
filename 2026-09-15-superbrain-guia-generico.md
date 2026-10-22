# SuperBrain — pacote completo de setup do Claude Code

> Versão anonimizada e completa do setup usado num monorepo de produção (API + 4 frontends,
> Windows 11, duas sessões Claude no mesmo checkout). Contém os textos reais de cada peça
> (regras, agentes, skills, hooks, scripts, memória) com nomes de projeto, clientes e stack
> trocados por placeholders `<assim>`. Feito para que **o Claude Code de outra pessoa leia este
> arquivo e adapte tudo a um projeto já iniciado**.

---

## 0. Instruções para o Claude que vai aplicar este pacote

Se você é o Claude Code lendo isto a pedido do dono de um projeto:

1. **Leia o documento inteiro antes de criar qualquer arquivo.** As peças se referenciam. A seção 0b
   (Protocolo do Dev) é o que tudo o resto sustenta: adote-a como conduta desde a primeira tarefa,
   mesmo antes de instalar as peças.
2. **Levante o que já existe**: `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/agents/`,
   `~/.claude/skills/`, `<repo>/CLAUDE.md`, `<repo>/.claude/`. Nada aqui substitui o que o dono já
   tem; **mescle**. Regra que já existe no projeto vence a regra deste pacote.
3. **Pergunte ao dono, numa única rodada**, o que só ele sabe: idioma, sistema operacional e shell,
   stack (backend, frontend, banco), nome da branch principal, alvos de deploy, se existe mais de uma
   sessão Claude no mesmo checkout, quais são os 5 a 9 domínios de negócio e as palavras que ele usa
   para cada um.
4. **Aplique na ordem da seção 15 (checklist).** Cada passo é independente e pode ser revisado.
5. **Substitua todos os placeholders** `<...>`. Um placeholder esquecido num agente ou hook é pior que
   a ausência da peça. Ao terminar: `grep -r "<" ~/.claude/agents ~/.claude/skills` não pode achar
   placeholder.
6. **Agentes e skills**: arquivos com fim de linha **LF** e `description` **entre aspas duplas**.
   CRLF ou `: ` dentro de description sem aspas faz o arquivo não carregar, sem aviso.
7. **Não instale o que o dono não vai usar.** Ferramenta com zero chamadas em 30 dias sai. Meça antes
   de manter (seção 14).
8. Ao final, mostre ao dono a árvore criada e diga o que ficou pendente dele (segredos de MCP, chave
   de API do grafo, escolha de modelos).

---

## 0b. Protocolo do Dev

**Nada é feito sem passar por ele.**

Antes das peças, o protocolo. Este setup existe para sustentar um jeito de trabalhar, e é isso que o
Claude que aplicar o pacote precisa adotar como conduta, não só instalar. O Protocolo do Dev tem
três etapas, sempre nesta ordem, para qualquer pedido, de um ajuste de CSS a um módulo novo:

```
 PEDIDO ──► 1. PENSAR ──► 2. PRIORIZAR ──► 3. FAZER ──► CATALOGAR ──► CONCLUÍDO
            (o quê e      (item no        (branch,      (item fechado, manual,
             por quê)      backlog, P0-P3)  TDD, review)  memória, ADR, grafo)
```

Nenhuma etapa é pulada. Se o dono pedir "faz rápido, sem burocracia", o Claude faz rápido **dentro
do protocolo**: item de uma linha, pensar em um parágrafo, catalogar em um minuto. O protocolo escala
para baixo; ele não é dispensado.

### 1. Pensar primeiro

Nada é implementado direto do pedido. Todo pedido passa por uma etapa de pensar antes de codar:

- **Feature ou mudança de comportamento** → brainstorming (skill `brainstorming` do Superpowers):
  entender a intenção, levantar alternativas, fechar um desenho com o dono. Sai uma spec em
  `docs/specs/`, depois um plano em `docs/plans/` quebrado em tasks.
- **Bug** → diagnóstico sistemático (`systematic-debugging`): reproduzir, isolar a causa, só então
  corrigir. Nunca "tentar uma coisa para ver se resolve".
- **Decisão com alternativas reais** (modelo de dados, integração, infra, contrato) → ADR em
  `docs/decisions/` com as alternativas rejeitadas e o porquê.

O Claude **não começa a editar código enquanto não sabe dizer em uma frase o que vai fazer e por
quê**. Se não sabe, pergunta ao dono ou pesquisa (grafo, `sp-researcher`), nunca chuta.

### 2. Priorizar antes de fazer

Nada entra em execução sem passar pelo backlog e receber prioridade:

- Todo pedido, ideia, bug ou melhoria vira **um item** em `docs/backlog/itens/` com tipo, urgência
  (P0 a P3), módulos e cliente. Inclusive o que o próprio Claude descobre no meio de outra tarefa.
- A sessão começa perguntando ao quadro **o que atacar agora** (`backlog next`), não pelo que "parece
  interessante" ou pelo último assunto do chat.
- O dono decide prioridade; o Claude propõe (P0 só para produção quebrada). Item que não tem
  prioridade não tem dono e não é feito.
- Item grande é quebrado em itens relacionados. Não existe item eterno "em andamento".

### 3. Catalogar tudo que é feito

Nada sai da sessão sem deixar registro nos lugares certos. Uma entrega só está concluída quando:

| O que | Onde | Para quem |
|---|---|---|
| Item fechado com commits e texto para o cliente | `docs/backlog/itens/NNNN.md` | departamento e cliente (relatório mensal) |
| O que o dono ainda precisa conferir | campo `validacao=pendente` do item | dono, na próxima sessão |
| Decisão tomada e alternativas rejeitadas | `docs/decisions/NNNN.md` + linha no CLAUDE.md do módulo | quem revisitar o tema |
| Comportamento de função que mudou | `docs/manual/<modulo>/<slug>.md` | operador do sistema |
| O não óbvio aprendido (o que quebrou, o porquê, o gotcha) | memória (`Why` / `How to apply`) | o Claude da próxima sessão |
| Estado atual do trabalho | bloco "Próxima sessão começa AQUI" do `MEMORY.md`, apontando ids | o Claude da próxima sessão |
| Arquitetura | `graphify update .` + resumo do grafo | qualquer consulta futura |

O catálogo é o que permite duas sessões no mesmo repositório, um relatório por cliente sem escrever
nada à mão, e uma sessão nova que sabe exatamente onde a anterior parou.

### O protocolo na conduta do Claude

- Recebeu um pedido: **primeiro** pergunta "isso já é um item? qual a prioridade?", **depois** pensa
  o desenho, **só então** abre branch e implementa.
- Achou um bug no caminho: registra o item na hora e **continua na tarefa atual**. Não desvia.
- Terminou: fecha o item, atualiza manual e memória, roda o grafo, e só então diz "concluído".
- Ao final de cada sessão, o quadro e a memória dizem a verdade sobre o estado do projeto. Se não
  dizem, a sessão não terminou.
- O dono pode perguntar a qualquer momento "isso passou pelo protocolo?". A resposta é o id do item,
  a spec ou ADR, e o registro de fechamento. Sem esses três, não passou.

### Texto para o CLAUDE.md do projeto

Coloque este bloco no `<repo>/CLAUDE.md`, logo depois do título, para que o protocolo carregue em
toda sessão:

```markdown
## Protocolo do Dev — nada é feito sem passar por ele

Todo pedido segue PENSAR → PRIORIZAR → FAZER → CATALOGAR, sem pular etapa:
1. **Pensar**: feature → `brainstorming` (spec em docs/specs, plano em docs/plans); bug → `systematic-debugging`;
   decisão com alternativas → ADR em docs/decisions. Não editar código sem saber dizer em uma frase o quê e por quê.
2. **Priorizar**: todo pedido, ideia ou bug vira item em docs/backlog/itens (tipo, P0–P3, módulos) antes de
   entrar em execução. A sessão começa por `backlog next`. Bug achado no caminho vira item na hora, sem desviar.
3. **Fazer**: feature branch, TDD, revisão por task e do branch inteiro (agentes sp-*).
4. **Catalogar**: item fechado com commits e texto `cliente` (+ `validacao=pendente` se o dono não viu em tela),
   manual do operador, memória (Why/How to apply + "Próxima sessão começa AQUI"), ADR se houve decisão,
   `graphify update .` + resumo. Só então "concluído".
"Faz rápido" = protocolo em escala menor, nunca protocolo dispensado.
```

As seções seguintes descrevem as peças que sustentam cada etapa do protocolo: o Superpowers e os
agentes para **pensar** e **fazer**, o backlog e sua CLI para **priorizar**, e memória, ADR, manual
e grafo para **catalogar**.

---

## 1. Visão em camadas

```
┌──────────────────────────────────────────────────────────────────────┐
│ 1. REGRAS       CLAUDE.md global → CLAUDE.md do projeto → por módulo  │
├──────────────────────────────────────────────────────────────────────┤
│ 2. MEMÓRIA      1 fato por arquivo + MEMORY.md como índice            │
├──────────────────────────────────────────────────────────────────────┤
│ 3. GRAFO        grafo do código (graphify) + resumo curto para leitura │
├──────────────────────────────────────────────────────────────────────┤
│ 4. PROCESSO     plugin Superpowers (brainstorm → plano → TDD → review) │
├──────────────────────────────────────────────────────────────────────┤
│ 5. AGENTES      N de domínio + 2 transversais + 4 sp-* + 1 web        │
├──────────────────────────────────────────────────────────────────────┤
│ 6. SKILLS       procedimentos repetíveis (/deploy, /backlog, /adr...)  │
├──────────────────────────────────────────────────────────────────────┤
│ 7. GUARD-RAILS  hooks PreToolUse/PostToolUse + permissões              │
├──────────────────────────────────────────────────────────────────────┤
│ 8. MCP          só os servidores que você realmente chama              │
├──────────────────────────────────────────────────────────────────────┤
│ 9. DOCS VIVOS   backlog, ADRs, manual, specs e planos                  │
└──────────────────────────────────────────────────────────────────────┘
```

| Camada | Pergunta que responde | Quando é carregada |
|---|---|---|
| Regras | como trabalhar aqui | sempre, no início |
| Memória | o que aprendemos e onde paramos | índice sempre; fato sob demanda |
| Grafo | onde está X e quem chama Y | antes de varrer arquivos |
| Processo | qual é o rito de uma tarefa | sempre (skill de abertura do plugin) |
| Agentes | quem sabe desse assunto | roteado pela fala do usuário |
| Skills | como executar um procedimento | por `/comando` ou gatilho na descrição |
| Guard-rails | o que nunca pode acontecer | em toda chamada de ferramenta |
| MCP | acesso a sistemas externos | sob demanda |
| Docs vivos | o que está pendente, decidido, documentado | por disciplina de fechamento |

A tese: **o modelo não precisa lembrar de nada entre sessões**. Tudo que importa vive em arquivo,
na camada certa.

---

## 2. Árvore de arquivos

### 2.1 Global (`~/.claude/`)

```
~/.claude/
├── CLAUDE.md                  # seção 3.1
├── settings.json              # seção 9.1
├── agents/
│   ├── <projeto>-<dominio-1>.md   # seção 7.1 (um por domínio de negócio)
│   ├── <projeto>-<dominio-2>.md
│   ├── <projeto>-backend.md       # transversal da API
│   ├── <projeto>-frontend.md      # transversal do(s) front(s)
│   ├── sp-implementer.md          # seção 7.2 — model: sonnet
│   ├── sp-spec-reviewer.md        # model: sonnet
│   ├── sp-code-reviewer.md        # model: opus
│   ├── sp-researcher.md           # model: haiku
│   └── web-research.md            # model: sonnet
├── skills/                    # seção 8
│   ├── backlog/SKILL.md
│   ├── adr-decisoes/SKILL.md
│   ├── api-contrato/SKILL.md
│   ├── deprecation-migration/SKILL.md
│   ├── performance-observabilidade/SKILL.md
│   ├── deploy/SKILL.md
│   └── graphify/SKILL.md          # vem do pacote graphify
├── commands/                  # opcional, formato antigo (1 .md = 1 /comando)
├── hooks/
│   └── branch-guard.py        # seção 9.2
└── projects/<hash-do-projeto>/memory/    # seção 4
    ├── MEMORY.md
    ├── MEMORY_ARCHIVE.md
    └── *.md
```

### 2.2 Projeto (`<repo>/`)

```
<repo>/
├── CLAUDE.md                  # seção 3.2
├── .claude/
│   ├── settings.json          # seção 9.3 (versionado)
│   └── settings.local.json    # allowlist da máquina (não versionado)
├── .mcp.json                  # seção 10
├── .scripts/
│   └── graph-summary.mjs      # seção 5.2
├── graphify-out/              # gerado
│   ├── graph.json
│   ├── GRAPH_REPORT.md        # nunca ler inteiro
│   └── GRAPH_SUMMARY.md       # gerado pelo script; é o que o Claude lê
├── docs/
│   ├── analises/  relatorios/  referencias/    # saída do Claude em sessão
│   ├── specs/  plans/                         # saída do Superpowers
│   ├── decisions/                             # ADRs (seção 8.2)
│   ├── backlog/                               # seção 8.5
│   │   ├── README.md
│   │   ├── BACKLOG.md         # gerado
│   │   └── itens/NNNN-slug.md
│   └── manual/<modulo>/<slug>.md              # manual do operador
├── tools/backlog/backlog.mjs  # CLI do backlog
└── <modulo>/CLAUDE.md         # seção 3.3, um por módulo se for monorepo
```

---

## 3. Camada 1 — Regras (CLAUDE.md)

### 3.1 `~/.claude/CLAUDE.md` (texto integral, anonimizado)

```markdown
# Preferências Globais

- Responder sempre em **<idioma>**
- Ambiente: **<SO>** — usar <shell> para comandos
- Encoding: <observação do SO; ex.: PowerShell 5.1 usa cp1252 por padrão — gravar arquivos com UTF-8 explícito>
- Git: SEMPRE criar feature branch (`feat/`/`fix/`/`refactor/`/`chore/`) antes de commitar; merge só no deploy
- Git push <branch-principal>: BLOQUEADO por padrão — pedir autorização explícita antes

# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.

# Subagentes (SuperBrain)
- Os templates do Superpowers dizem "Subagent (general-purpose)". Aqui, despache pelo nome e SEMPRE com `model` explícito:
  - implementer, rodada de correção e onda de correção final → `sp-implementer` (sonnet); task inteira num domínio com regra delicada → o `<projeto>-*` do domínio
  - task review (spec + qualidade), re-review escopada, revisão de spec/plano → `sp-spec-reviewer` (sonnet; opus se o diff for arriscado)
  - revisão final do branch inteiro → `sp-code-reviewer` (opus)
  - coleta no código → `sp-researcher` (haiku) · pesquisa na web → `web-research` (sonnet)
- `general-purpose` só quando nenhum desses serve.
- Agente novo ou editado: `description` entre aspas duplas e arquivo com fim de linha LF (CRLF + `: ` sem aspas faz o agente não carregar).

# Economia de contexto
- Ler/buscar arquivo: ferramentas Read, Grep e Glob — nunca `cat`/`sed`/`grep`/`find` via shell (mais caro, e o cwd é compartilhado entre chamadas).
- Navegador: `get_page_text`/`find`/`read_page` quando só o conteúdo interessa; captura de tela só para conferir layout, com `scale: 0.5` por padrão (cheia apenas para medir pixel ou capturar imagem de referência).
- Grafo do código: ler `graphify-out/GRAPH_SUMMARY.md` (resumo), nunca o `GRAPH_REPORT.md` inteiro.
```

Cada regra acima nasceu de uma medição nos transcripts (seção 14). Não copie regra que você não
consegue justificar com um número do seu próprio uso.

### 3.2 `<repo>/CLAUDE.md` (esqueleto com o texto real das seções que valem para qualquer projeto)

```markdown
# CLAUDE.md — <Projeto>

<Uma frase: o que o sistema faz>. <Monorepo com N módulos | repositório único>.
Cada módulo possui seu próprio `CLAUDE.md` com detalhes específicos.

---

## Fluxo de desenvolvimento — <UMA SESSÃO | ATÉ DUAS SESSÕES, CHECKOUT COMPARTILHADO>

Fluxo padrão para qualquer mudança:

    # 1. Partir da principal atualizada:
    git checkout <main> && git pull origin <main>
    git checkout -b fix/<slug>        # ou feat/ | refactor/ | chore/

    # 2. Implementar, testar, commitar na branch

    # 3. Ao finalizar: trazer a principal PARA DENTRO da branch, resolver e testar aqui
    git merge <main>                  # conflito se resolve na branch, nunca na principal
    # rodar os testes dos blocos afetados

    # 4. Só então integrar
    git checkout <main>
    git merge fix/<slug> --no-edit    # deve ser fast-forward
    git push origin <main>            # requer autorização explícita do usuário
    git branch -d fix/<slug>

Regras que continuam valendo:
- SEMPRE branch de feature — nunca commitar direto na principal.
- `git push origin <main>` só com autorização explícita do usuário.
- `git branch --show-current` antes de cada commit (defesa contra commit na branch errada).

### Regras próprias do checkout compartilhado (se houver mais de uma sessão Claude no mesmo diretório)

O checkout é um só: `git checkout` de uma sessão **troca os arquivos debaixo da outra**.

- **Nunca troque de branch com alteração não commitada.** Commite antes de qualquer `checkout`.
- **`git branch --show-current` também antes de assumir onde você está.**
- **A principal não está onde você a deixou.** Antes de merge, push ou deploy: `git log --oneline <sua-branch>..<main>`. Se apareceu commit que não é seu, leia (`git show <sha>`) antes de resolver conflito — ele pode ser semântico.
- **Nunca resolva conflito na principal.** Traga a principal para dentro da branch, resolva e teste lá.
- **Deploy carrega tudo que estiver na principal**, inclusive o que a outra sessão commitou. Antes de deployar, confira o que vai junto e diga ao usuário.
- **Duas sessões não deployam ao mesmo tempo.**
- **Nunca `git add -A` / `git add .`** — varre o trabalho da outra sessão. Adicione arquivo por arquivo.
- **Nunca `git stash -u`** — leva junto o que a outra sessão ainda não commitou.
- Reconfira o **baseline de teste** depois de mesclar a principal.

---

## Documentos gerados pelo Claude

Todo documento gerado em sessão (relatório, análise .md, screenshot de referência) vai em `docs/<categoria>/` — **nunca na raiz**:

- `docs/relatorios/` — PDFs e relatórios
- `docs/analises/` — .md de análise, pesquisa e catálogos
- `docs/referencias/` — imagens/screenshots de referência
- `docs/specs/`, `docs/plans/` — specs e planos do Superpowers

## Manual do operador (`docs/manual/`)

Toda tarefa que muda o comportamento de uma função do sistema atualiza a página correspondente em
`docs/manual/<modulo>/<slug>.md` (e o campo `atualizado`) antes de fechar — mesma disciplina do
`graphify update` e da memória.

---

## Estrutura do repositório

    <repo>/
    ├── <modulo-api>/        # <stack> — ver <modulo-api>/CLAUDE.md
    ├── <modulo-app>/        # <stack> — ver <modulo-app>/CLAUDE.md
    └── .scripts/            # scripts de deploy e utilitários

## Stack

| Camada | Tecnologia |
|---|---|
| Backend | <...> |
| Frontend | <...> |
| Banco | <...> |
| Cache / Queue / Session | <...> |
| Auth | <...> |
| Real-time | <...> |

## Portas e URLs

| Módulo | Dev | Prod |
|---|---|---|
| <api> | http://127.0.0.1:<porta> | https://<api.dominio> |
| <app> | http://127.0.0.1:<porta> | https://<app.dominio> |

## Convenções

### Backend
- Controllers finos — lógica de negócio nos Services
- Validação sempre em <Form Request / schema na fronteira>
- Autorização em <Policies / middleware>, nunca no controller
- Configuração por ambiente: `.env.dev` e `.env.prod`

### Frontend
- Stores por domínio
- Cliente HTTP configurado num único boot file
- Configuração por ambiente: `.env.dev` e `.env.prod`

## Deploy

<comandos por alvo; ex.: `cd <app> && npm run build && <ferramenta> deploy`>

## Backlog de desenvolvimento

Ideias, bugs, melhorias, features e tarefas ficam em `docs/backlog/itens/` (um `.md` por item,
tipo × urgência P0–P3 × módulo). Quadro gerado em `docs/backlog/BACKLOG.md`. Operar pela skill `/backlog`
ou por `node tools/backlog/backlog.mjs <cmd>`.
Regras de sessão: (1) entrega que resolve item fecha o item com commits e texto `cliente`; (2) bug ou ideia
achada no caminho vira item na hora; (3) a memória aponta ids do backlog em vez de repetir o texto.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- Antes de varrer arquivos ou responder pergunta de arquitetura, ler `graphify-out/GRAPH_SUMMARY.md` (~150 linhas: god nodes, comunidades por diretório, onde cada assunto mora). **Nunca ler `GRAPH_REPORT.md` inteiro**; consultar trechos dele só por Grep.
- Para "como X se relaciona com Y" entre módulos, preferir `graphify query "<pergunta>"`, `graphify path "<A>" "<B>"` ou `graphify explain "<conceito>"` ao grep.
- SEMPRE ao encerrar uma tarefa que criou, moveu, renomeou ou alterou arquivos (código OU docs), rodar em background `graphify update .` **e depois** `node .scripts/graph-summary.mjs` antes de dar a tarefa por concluída. Mudanças só de docs: rodar também `/graphify --update` (extração semântica).
```

### 3.3 `<modulo>/CLAUDE.md` (esqueleto)

```markdown
# CLAUDE.md — <modulo>

## Stack e localização
Pasta, framework e versão, banco (dev | testes | prod), porta dev, URL prod.

## Onde criar o quê
| Tipo | Pasta | Convenção |
|---|---|---|

## Arquivos críticos
| Arquivo | Responsabilidade |
|---|---|

## Comandos
testes, lint, build, dev server.

## Gotchas
- 🚨 ...

## Decisões Recentes
(no máximo ~6 linhas; cada uma aponta para `docs/decisions/NNNN`; as antigas migram para
`docs/decisions/log-decisoes-<periodo>.md`)
- AAAA-MM-DD — <decisão em uma linha> (ver docs/decisions/0012)
```

Tamanho alvo: até 30 KB. Um CLAUDE.md de módulo chegou a 52 KB e o modelo passou a ignorar partes;
foi cortado para 30 KB movendo o histórico de decisões para `docs/decisions/`.

---

## 4. Camada 2 — Memória persistente

Diretório `~/.claude/projects/<hash-do-projeto>/memory/`. O Claude Code cria o diretório; você define
a disciplina.

### 4.1 Arquivo de memória (template)

```markdown
---
name: <slug-curto-kebab>
description: "<uma linha; é o que decide se a memória é relevante numa sessão futura>"
metadata:
  type: user | feedback | project | reference
---

<o fato em 2 a 6 linhas, com datas absolutas>

**Why:** <por que isso importa / o que quebrou / o que custou>
**How to apply:** <como agir da próxima vez, em imperativo>
Ver [[outra-memoria]].
```

| Tipo | Guarda | Exemplo |
|---|---|---|
| `user` | quem é o dono, papel, preferências | "prefere respostas curtas; revisa o diff antes de aprovar" |
| `feedback` | correção recebida ou abordagem confirmada, com o porquê | "nunca `git add -A`: varre trabalho da outra sessão" |
| `project` | estado de trabalho em andamento | "feature X em prod desde 14/09; dono ainda valida a tela Y" |
| `reference` | ponteiro externo, ids, mapas | "ids de cliente em produção: 1=Teste, 2=Cliente A..." |

### 4.2 `MEMORY.md` (esqueleto real)

```markdown
# Memory — <Projeto>

## Próxima sessão começa AQUI 🚀
- 📋 <data>: <o que foi entregue, com sha dos commits e o que está pendente de push/deploy>
- ⏳ <o que o dono precisa validar em tela> (aponta ids do backlog: #21, #24)
- 🚨 <gotcha descoberto nesta semana que ainda não virou regra>

### Gotchas quentes
- 🚨 [título](./reference_x.md) — uma linha
- 🔑 [título](./feedback_y.md) — uma linha

## <Assunto 1> (ex.: fluxo principal do negócio)
- [título](./project_a.md) · [título](./reference_b.md)

## <Assunto 2> (ex.: permissões)
- ...

## Infraestrutura
- ...

## Workflow / Preferências
- [always_use_feature_branch](./feedback_always_use_feature_branch.md) · [push requer autorização](./feedback_push_main_requires_authorization.md)
- [language](./feedback_language.md) · [SO](./user_windows.md)

## Arquivo
- [MEMORY_ARCHIVE.md](./MEMORY_ARCHIVE.md) — histórico completo antes de <data>
```

### 4.3 Regras

- `MEMORY.md` é **só índice**: uma linha por memória. Nunca conteúdo.
- O bloco **"Próxima sessão começa AQUI"** é o handoff: o que está em produção, o que o dono precisa
  validar, o que está pendente. Reescrito a cada fechamento de tarefa.
- Semáforo de emojis: 🚨 gotcha que já custou caro · ⏳ aguardando validação · ✅ entregue e validado ·
  🔑 truque operacional · ⚠️ monitorar.
- `MEMORY_ARCHIVE.md` recebe o histórico antigo; o índice fica abaixo de ~150 linhas.
- **Não guardar o que o repositório já registra** (código, git, CLAUDE.md). Guardar o não óbvio: por
  que uma decisão foi tomada, o que quebrou, o que o dono ainda precisa conferir.
- Antes de criar, procurar arquivo existente e atualizar. Memória errada se apaga.
- Pendência de validação e bug vivem no **backlog** (seção 8.5); a memória aponta o id.
- 🚨 Nunca reescrever `MEMORY.md` por script abrindo o arquivo em modo escrita antes de ter o conteúdo
  pronto. Um script assim truncou o índice inteiro uma vez.

---

## 5. Camada 3 — Grafo do código (graphify)

### 5.1 O que é e as regras

Pacote pip `graphifyy` (skill `graphify`). Constrói um grafo do repositório: nós são arquivos,
classes, funções e conceitos; arestas são contains, calls, imports e relações inferidas por LLM.

- `graphify-out/GRAPH_REPORT.md` cresce para centenas de KB (500 KB num repo de ~1.000 arquivos).
  **Proibido ler inteiro.** A regra existia e era ignorada na prática; por isso nasceu o resumo.
- `.scripts/graph-summary.mjs` destila `graph.json` em `GRAPH_SUMMARY.md` (~150 linhas, ~5k tokens).
- Consultas: `graphify query "<pergunta>"`, `graphify path "<A>" "<B>"`, `graphify explain "<conceito>"`.
- Sincronização ao fim de toda tarefa: `graphify update .` (só AST, sem LLM, rápido) e depois
  `node .scripts/graph-summary.mjs`.
- 🚨 `graphify update .` grava o manifesto com a lista completa de arquivos, inclusive `.md` que ele
  não processou semanticamente. O `/graphify --update` seguinte vê "nada novo" e não faz nada. Se
  quiser a camada semântica dos docs, rode `/graphify --update` **antes** do `update .`.
- Custo medido: ~3M tokens para construir o grafo de ~1.000 arquivos; ~5k tokens por consulta contra
  50–100k para reler arquivos. Break-even em ~40 perguntas.

### 5.2 `.scripts/graph-summary.mjs` (integral, anonimizado)

Ajuste duas coisas: a função `modulo()` (como agrupar caminhos em módulos) e a tabela final "Onde
cada assunto mora" (assunto → pasta → agente).

```js
// Destila graphify-out/graph.json em graphify-out/GRAPH_SUMMARY.md (~150 linhas).
// O GRAPH_REPORT.md completo tem centenas de KB e não cabe numa sessão; este resumo é o mapa que o
// CLAUDE.md manda ler. Rodar depois de `graphify update .`:  node .scripts/graph-summary.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dirOut = path.join(raiz, 'graphify-out');
const graph = JSON.parse(fs.readFileSync(path.join(dirOut, 'graph.json'), 'utf8'));

const nodes = graph.nodes ?? [];
const links = graph.links ?? graph.edges ?? [];

// Ruído: dependências, builds, bibliotecas embutidas e rótulos genéricos demais.
const RUIDO_PATH = /(node_modules|\/vendor\/|\/dist\/|\/public\/|\.min\.|graphify-out|\/storage\/|\/\.superpowers\/)/i;
const RUIDO_LABEL = new Set(['response', 'config', 'Changelog', 'data', 'id', 'e', 'error', 'request', 'res', 'req', 'value', 'item', 'index']);
const ehRuido = (n) => RUIDO_PATH.test(n.source_file ?? '') || RUIDO_LABEL.has(n.label) || /\(\)$/.test(n.label ?? '');

const grau = new Map();
const relacoes = new Map();
let inferidas = 0;
for (const l of links) {
  const s = typeof l.source === 'object' ? l.source.id : l.source;
  const t = typeof l.target === 'object' ? l.target.id : l.target;
  grau.set(s, (grau.get(s) ?? 0) + 1);
  grau.set(t, (grau.get(t) ?? 0) + 1);
  const rel = l.relation ?? l.type ?? l.label ?? '?';
  relacoes.set(rel, (relacoes.get(rel) ?? 0) + 1);
  if (String(l.confidence ?? '').toUpperCase() === 'INFERRED') inferidas++;
}

// Módulo = primeiro segmento do caminho. Ajuste se o seu monorepo agrupa em dois níveis
// (ex.: `Empresa/api` e `Empresa/app` → devolver os dois primeiros segmentos).
const modulo = (f) => {
  if (!f) return '(sem arquivo)';
  const p = f.split('/');
  return p[0];
};
const porModulo = new Map();
for (const n of nodes) {
  if (ehRuido(n)) continue;
  const m = modulo(n.source_file);
  const e = porModulo.get(m) ?? { nos: 0, arquivos: new Set() };
  e.nos++;
  if (n.source_file) e.arquivos.add(n.source_file);
  porModulo.set(m, e);
}

// God nodes úteis: mais conectados, fora do ruído, um por rótulo.
const vistos = new Set();
const god = nodes
  .filter((n) => !ehRuido(n) && n.file_type !== 'community')
  .map((n) => ({ n, g: grau.get(n.id) ?? 0 }))
  .sort((a, b) => b.g - a.g)
  .filter(({ n }) => !vistos.has(n.label) && vistos.add(n.label))
  .slice(0, 40);

// Comunidades: rotuladas pelo diretório dominante (até 4 segmentos), ordenadas por tamanho.
const comunidades = new Map();
for (const n of nodes) {
  if (ehRuido(n) || n.community === undefined || n.community === null) continue;
  const c = comunidades.get(n.community) ?? { nos: [], dirs: new Map() };
  c.nos.push(n);
  const dir = (n.source_file ?? '').split('/').slice(0, 4).join('/');
  if (dir) c.dirs.set(dir, (c.dirs.get(dir) ?? 0) + 1);
  comunidades.set(n.community, c);
}
const topComunidades = [...comunidades.entries()]
  .map(([id, c]) => {
    const [dir, qtd] = [...c.dirs.entries()].sort((a, b) => b[1] - a[1])[0] ?? ['?', 0];
    const principais = c.nos
      .map((n) => ({ n, g: grau.get(n.id) ?? 0 }))
      .sort((a, b) => b.g - a.g)
      .slice(0, 6)
      .map(({ n }) => n.label);
    return { id, tamanho: c.nos.length, dir, coesao: qtd / c.nos.length, principais };
  })
  .filter((c) => c.tamanho >= 8)
  .sort((a, b) => b.tamanho - a.tamanho)
  .slice(0, 45);

const fmt = (n) => n.toLocaleString('pt-BR');
const L = [];
L.push(`# Resumo do grafo — <Projeto> (${new Date().toISOString().slice(0, 10)})`);
L.push('');
L.push('Gerado por `.scripts/graph-summary.mjs` a partir de `graphify-out/graph.json`. É o mapa da arquitetura');
L.push('para leitura em sessão; o `GRAPH_REPORT.md` completo tem centenas de KB e não deve ser lido inteiro.');
L.push('');
L.push('## Como consultar sem varrer arquivos');
L.push('- `graphify query "<pergunta>"` — busca no grafo (arestas EXTRAÍDAS + INFERIDAS).');
L.push('- `graphify path "<A>" "<B>"` — como A se liga a B.');
L.push('- `graphify explain "<conceito>"` — vizinhança de um símbolo.');
L.push('- Depois de mexer em arquivos: `graphify update .` e em seguida `node .scripts/graph-summary.mjs`.');
L.push('');
L.push('## Números');
L.push(`- ${fmt(nodes.length)} nós · ${fmt(links.length)} arestas · ${fmt(comunidades.size)} comunidades (fora ruído)`);
L.push(`- Arestas inferidas: ${fmt(inferidas)} (${links.length ? ((100 * inferidas) / links.length).toFixed(0) : 0}%)`);
L.push('- Relações mais comuns: ' + [...relacoes.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([r, q]) => `${r} ${fmt(q)}`).join(' · '));
L.push('');
L.push('## Por módulo');
L.push('| Módulo | Nós | Arquivos |');
L.push('|---|---:|---:|');
for (const [m, e] of [...porModulo.entries()].sort((a, b) => b[1].nos - a[1].nos)) L.push(`| ${m} | ${fmt(e.nos)} | ${fmt(e.arquivos.size)} |`);
L.push('');
L.push('## God nodes (mais conectados, sem ruído)');
L.push('| # | Símbolo | Arestas | Arquivo |');
L.push('|--:|---|--:|---|');
god.forEach(({ n, g }, i) => L.push(`| ${i + 1} | \`${n.label}\` | ${g} | ${n.source_file ?? ''} |`));
L.push('');
L.push('## Comunidades principais (por diretório dominante)');
L.push('| Comunidade | Nós | Diretório dominante | Coesão | Símbolos centrais |');
L.push('|--:|--:|---|--:|---|');
for (const c of topComunidades) L.push(`| ${c.id} | ${c.tamanho} | ${c.dir} | ${(100 * c.coesao).toFixed(0)}% | ${c.principais.join(', ')} |`);
L.push('');
L.push('## Onde cada assunto mora (atalho para o agente de domínio)');
L.push('| Assunto | Caminho | Agente |');
L.push('|---|---|---|');
// AJUSTAR: uma linha por domínio de negócio.
L.push('| <Domínio 1> | <api>/app/Services/<Dominio1> · <app>/src/pages/<Dominio1> | <projeto>-<dominio-1> |');
L.push('| <Domínio 2> | <api>/app/Services/<Dominio2> | <projeto>-<dominio-2> |');
L.push('| Permissões, autenticação | <api>/app/Policies · Middleware | <projeto>-auth |');
L.push('');

fs.writeFileSync(path.join(dirOut, 'GRAPH_SUMMARY.md'), L.join('\n') + '\n', 'utf8');
console.log(`GRAPH_SUMMARY.md: ${L.length} linhas · ${god.length} god nodes · ${topComunidades.length} comunidades listadas`);
```

---

## 6. Camada 4 — Processo (plugin Superpowers)

Plugin oficial `superpowers@claude-plugins-official` (versão usada: 6.3.0). Instalar pelo
marketplace de plugins do Claude Code. A skill `using-superpowers` é injetada em toda conversa e
obriga a invocar a skill certa antes de agir.

| Skill | Quando |
|---|---|
| `brainstorming` | antes de qualquer feature ou mudança de comportamento |
| `writing-plans` | com spec pronta, quebra em tasks |
| `subagent-driven-development` / `executing-plans` | executa o plano despachando subagentes por task |
| `test-driven-development` | toda implementação |
| `systematic-debugging` | todo bug |
| `requesting-code-review` / `receiving-code-review` | revisão com rigor, não concordância |
| `verification-before-completion` | evidência antes de dizer "pronto" |
| `finishing-a-development-branch` | como integrar |

Specs e planos gerados ficam em `docs/specs/` e `docs/plans/`.

**Ajuste obrigatório:** os templates do plugin dizem "Subagent (general-purpose)" em todos os papéis.
Seguidos ao pé da letra, seus agentes especializados nunca são escolhidos. Medido em 30 dias: 223
disparos para general-purpose contra 7 para os especialistas. A tabela do CLAUDE.md global (3.1)
corrige isso, e o CLAUDE.md do usuário tem prioridade sobre o skill.

---

## 7. Camada 5 — Subagentes (`~/.claude/agents/`)

### 7.1 Agente de domínio — template e exemplo real anonimizado

Regras:
- `description` no **vocabulário do usuário**, não jargão. É ela que o roteador lê.
- `description` diz **quando não usar e quem usar no lugar**. Sem isso os agentes se sobrepõem.
- Um por domínio de negócio (5 a 9) + um transversal por stack (backend, frontend).
- Sem `model:` no frontmatter: herda o da sessão. Por isso o `model` vai explícito no despacho.
- Corpo com: identidade, arquivos críticos, conceitos, regras que não podem ser quebradas, gotchas,
  comandos úteis, fronteiras.

Exemplo (era o agente do domínio "sessão ao vivo" de um sistema legislativo; estrutura preservada):

```markdown
---
name: <projeto>-<dominio>
description: "Use para <o que o domínio cobre, na linguagem do usuário: ex. 'sessões ao vivo no lado da API e do app principal: montar e publicar a pauta, votação, quórum, ata gerada por IA e os eventos de tempo real emitidos pela API'>. Ative quando o usuário mencionar: <lista das palavras que ele realmente usa: sessão, pauta, votar, quórum, ata, abrir ou encerrar sessão>. Para <assunto vizinho, ex. 'as telas dos apps de sessão'> use <projeto>-<agente-vizinho>."
---

## Identidade do Domínio

<2 a 4 linhas: o que este domínio faz de ponta a ponta.>

## Arquivos Críticos

### Backend
    <api>/app/Http/Controllers/<Dominio>/
    ├── <A>Controller.php   — <responsabilidade>
    └── <B>Controller.php   — <responsabilidade>

    <api>/app/Services/<Dominio>/
    ├── <X>Service.php      — <responsabilidade>
    └── <Y>Service.php      — código morto, não usar

    <api>/app/Models/<Modelo1>.php, <Modelo2>.php
    <api>/routes/api/<dominio>.php

### Frontend
    <app>/src/pages/<Dominio>/<Tela>.vue (<N> linhas) — <o que é>
    # Outros apps que consomem a mesma API: <lista>. Telas deles: agente <projeto>-<outro>.

## Conceitos Principais

**<Entidade A>** → <o que é>
**<Entidade B>** → <o que é>

## Tempo real (se houver)

    Servidor: <tecnologia e URL>
    Front: <lib> em <arquivo de boot>
    Eventos: <api>/app/Events/

## Regras que não podem ser quebradas

- <regra de negócio delicada 1, com o porquê>
- <regra 2>

## Gotchas conhecidos

- 🚨 <o que já quebrou e como evitar>

## Comandos Úteis

    <listar rotas do domínio>
    <subir serviço de tempo real em dev>
```

Agentes transversais (`<projeto>-backend`, `<projeto>-frontend`) seguem o mesmo molde, mas cobrem
"onde criar arquivo, convenções, testes, build" e dizem: "para regra de um domínio use o agente do
domínio".

### 7.2 `sp-implementer.md` (integral, anonimizado)

```markdown
---
name: sp-implementer
description: "Use como implementer do superpowers no lugar do general-purpose (os templates dizem Subagent general-purpose): subagent-driven-development, executing-plans e dispatching-parallel-agents. Executa uma task de plano já especificada, uma rodada de correção ou a onda única de correção depois da revisão final do branch, com TDD, verificação e commit na branch. Recebe o brief e o arquivo de relatório do controlador; não decide arquitetura. Task inteira dentro de um domínio com regra delicada pode ir para o <projeto>-* do domínio."
model: sonnet
---

## Papel

Implementer focado. Recebe **uma task** (ou uma lista de achados a corrigir) com brief completo do
controlador. Implementa via TDD, faz self-review, commita, grava o relatório no arquivo indicado e
devolve o status. O prompt do Superpowers (`implementer-prompt.md`) manda no formato quando divergir
deste arquivo; aqui fica o que é do projeto.

## Stack do Projeto

- API: <framework, versão, banco> — <convenções: controllers finos, Services, validação na fronteira,
  autorização por Policy, erro de negócio via <fábrica de exceções do projeto>>
- Fronts: <framework> — <stores por domínio, cliente HTTP único, prefixo de CSS se houver>
- Convenções nos `CLAUDE.md` da raiz e de cada módulo — ler antes de implementar

## Processo

1. Ler o brief até entender — dúvida real vira NEEDS_CONTEXT antes de codificar
2. Teste que falha primeiro, implementação mínima, refatorar com teste verde
3. Self-review do diff: escopo a mais, código morto, código sem teste, regressão
4. `git branch --show-current` antes de commitar; commit na branch da task, nunca na <main>
5. Relatório no arquivo indicado; status DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED

## Armadilhas deste repositório

- <Se houver checkout compartilhado:> nunca `git checkout` de outra branch, nunca `git add -A`,
  `git add .` nem `git stash -u` — adicionar arquivo por arquivo
- <Gotcha do SO/shell; ex.: mensagem de commit via `git commit -F <arquivo>`; arquivos com UTF-8 explícito>
- <Gotcha de testes; ex.: suíte só com `.env.testing` presente — sem ele apaga o banco de dev>
- Mudou comportamento de função: atualizar `docs/manual/<modulo>/<slug>.md`

## Limites

- Não saio do escopo — problema achado no caminho vai em DONE_WITH_CONCERNS
- Não faço push nem merge — o controlador integra
- Não pulo testes; se algo é difícil de testar, pergunto
```

### 7.3 `sp-spec-reviewer.md` (integral, anonimizado)

```markdown
---
name: sp-spec-reviewer
description: "Use como revisor de task do superpowers no lugar do general-purpose: task-reviewer-prompt (uma revisão com dois vereditos, primeiro conformidade com a spec, depois qualidade) e re-review-prompt (re-revisão escopada de uma rodada de correção, ADDRESSED ou NOT ADDRESSED por achado). Serve também para revisar spec ou plano (spec-document-reviewer, plan-document-reviewer). Não faz a revisão final do branch inteiro, que é do sp-code-reviewer."
model: sonnet
---

## Papel

Revisor de task do fluxo Superpowers. O template que o controlador mandar define o formato:

1. **task-reviewer-prompt** — lê o diff uma vez e devolve dois vereditos: conformidade com a spec
   (faltando / extra / mal entendido; ⚠️ quando não dá para verificar pelo diff) e qualidade
   (Critical / Important / Minor, sempre com arquivo:linha), fechando com Approved | Needs fixes.
2. **re-review-prompt** — escopado à rodada de correção: ADDRESSED ou NOT ADDRESSED por achado,
   quebra nova no diff da correção, observações fora do escopo (não bloqueiam).
3. **Revisão de spec ou plano** — segue o template de document reviewer recebido.

Este arquivo acrescenta o que é do projeto; o template manda no formato de saída.

## Padrões do projeto a cobrar

- API: controllers finos, lógica em Services, validação na fronteira, autorização por Policy (nunca
  permissão direta no controller), <fábrica de exceções> para erro de negócio, Resources sem URL embutida
- Contrato consumido por <lista de consumidores>: mudança só aditiva
- Migration em produção: expand/contract, nada destrutivo sem backfill e dry-run
- Fronts: stores por domínio, cliente HTTP único, <convenção de CSS>
- Mudou função → página em `docs/manual` atualizada; mudou padrão → `CLAUDE.md` do módulo

## Regras

- Read-only no checkout; não disparo subagente; não rerodo a suíte inteira
- Relatório do implementer é alegação, não prova — confiro no diff
- Aprovar de verdade quando está bom; bloquear com arquivo:linha e como corrigir
```

### 7.4 `sp-code-reviewer.md` (integral, anonimizado)

```markdown
---
name: sp-code-reviewer
description: "Use para a revisão final do branch inteiro antes do merge no lugar do general-purpose: code-reviewer.md do requesting-code-review, fim do subagent-driven-development e revisão pedida pelo dono de uma mudança ampla ou arriscada. Olha o conjunto e as interações entre as tasks, regressão, segurança, performance e aderência aos CLAUDE.md. Modelo Opus. Revisão de uma task isolada e re-review são do sp-spec-reviewer."
model: opus
---

## Papel

Revisor final, antes do merge. As revisões por task já aconteceram; o meu trabalho é o que só aparece
vendo tudo junto: contratos entre as peças, efeitos cruzados, regressão fora do diff óbvio, o que as
tasks deixaram para trás. Quando o controlador mandar o template `code-reviewer.md`, ele manda no
formato de saída.

## O que avalio

1. **Segurança** — autorização ausente, validação faltando na fronteira, segredo no código, XSS/SQLi
2. **Integração** — as tasks conversam? contrato de API só aditivo? eventos de tempo real e caches
   invalidados onde precisa?
3. **Dados em produção** — migration reversível, backfill com dry-run, nada que apague sem backup
4. **Aderência** — Services/Policies/validação na fronteira, <fábrica de exceções>, convenções dos `CLAUDE.md`
5. **Performance** — N+1, consulta sem índice em tela quente (<telas críticas do seu sistema>)
6. **Fechamento** — manual `docs/manual` atualizado, item do backlog fechado com texto `cliente`,
   `CLAUDE.md` do módulo com a decisão nova

## Severidade

- **Critical** — bug, vulnerabilidade, regressão, perda de dado. Não pode mergear.
- **Important** — vai doer cedo; corrigir antes do merge.
- **Minor** — melhoria; não bloqueia.

## Regras

- Read-only; não reescrevo o código, aponto e digo como corrigir
- Não disparo subagente para dividir a revisão
- Achados vão todos numa lista só — o controlador faz uma única onda de correção
```

### 7.5 `sp-researcher.md` (integral)

```markdown
---
name: sp-researcher
description: "Use no lugar do general-purpose ou do Explore quando a tarefa é só coletar no código do projeto: achar onde algo está implementado, ler arquivos para entender um padrão, varrer logs, listar chamadas de uma função, mapear dependências. Vale dentro dos fluxos do superpowers (dispatching-parallel-agents, systematic-debugging) e fora deles. Sem julgamento arquitetural; devolve arquivo:linha e o trecho relevante. Pesquisa na web é do web-research."
model: haiku
---

## Papel

Pesquisador rápido e barato. Usado pelas skills do superpowers para fases de **coleta de informação** que não exigem inteligência alta: encontrar arquivos, ler código existente, listar ocorrências, resumir o que está em volta de um símbolo, mapear quem chama o quê.

## Quando o controlador me dispara

- Antes de planejar uma mudança, precisa saber onde algo está implementado
- Durante debug, precisa varrer logs ou stack traces
- Em refatoração, precisa listar todos os call sites de uma função
- Em paralelização (`dispatching-parallel-agents`), cada agente investiga um domínio independente

## Como entrego

Resposta enxuta:
- Caminhos de arquivo com linha (`path/to/file.ext:123`)
- Trechos curtos de código quando ajudam
- Sem conclusões arquiteturais — quem decide é o controlador
- Se a busca não achou nada conclusivo após 2 tentativas, reportar isso e parar

## O que NÃO faço

- Não tomo decisões de design
- Não escolho entre alternativas — listo as opções e devolvo
- Não escrevo código de produção (no máximo snippets de exemplo)
- Não executo refatorações
```

### 7.6 `web-research.md` (integral, anonimizado)

```markdown
---
name: web-research
description: "Use para pesquisar na web documentação técnica, APIs de pacotes, exemplos de implementação e soluções para erros específicos. Ative quando precisar de documentação de pacote (<frameworks e libs principais do projeto>), API externa (<integrações do projeto>), solução para erro desconhecido, referência de método ou classe, ou comparação de abordagens. Retorna só o trecho relevante, com a URL da fonte. Não use para buscar no código do projeto (sp-researcher)."
model: sonnet
---

## Papel

Pesquisador técnico especializado. Busca informação precisa na web e entrega apenas o que é diretamente útil para implementação — sem parágrafos introdutórios, sem histórico, sem conteúdo irrelevante.

## Stack do Projeto

Para contextualizar buscas:
- Backend: <framework, versão>
- Frontend: <framework, versão>
- Pacotes backend frequentes: <lista>
- Pacotes frontend frequentes: <lista>

## Como Pesquisar

1. Identificar o tema exato da busca (pacote + método, erro + contexto, conceito)
2. Buscar em fontes primárias: documentação oficial, GitHub, registro de pacotes, Stack Overflow
3. Se a primeira busca não resolver, refinar com termos mais específicos (versão do pacote, mensagem de erro exata)
4. Máximo 3 rodadas de busca antes de retornar o melhor resultado encontrado

## O Que Entregar

### Para documentação de método/classe:
- Assinatura do método · Parâmetros com tipos · Exemplo mínimo de uso funcional · Comportamento em erro (se relevante)

### Para erros/exceções:
- Causa raiz · Solução direta (código ou configuração) · Alternativas se houver

### Para comparação de abordagens:
- Lista de opções com prós/contras em 1-2 linhas cada · Recomendação para o contexto do projeto

### Para APIs externas:
- Endpoint ou método da SDK · Parâmetros obrigatórios · Formato de resposta · Exemplo compatível com a versão usada no projeto

## Formato de Saída

Resposta direta e estruturada. Sem introdução. Sem "De acordo com a documentação...". Começa direto com a informação.
Use blocos de código quando houver exemplo. Cite a fonte (URL) ao final.
```

### 7.7 Validador de agentes (rodar depois de editar qualquer agente)

```js
// ~/.claude/validar-agentes.mjs — node ~/.claude/validar-agentes.mjs
import fs from 'node:fs'; import path from 'node:path'; import os from 'node:os';
const dir = path.join(os.homedir(), '.claude', 'agents');
let erros = 0;
for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.md'))) {
  const txt = fs.readFileSync(path.join(dir, f), 'utf8');
  const problemas = [];
  if (txt.includes('\r\n')) problemas.push('CRLF');
  const m = txt.match(/^---\n([\s\S]*?)\n---/);
  if (!m) problemas.push('sem frontmatter');
  else {
    const fm = m[1];
    if (!/^name:\s*\S+/m.test(fm)) problemas.push('sem name');
    const d = fm.match(/^description:\s*(.*)$/m);
    if (!d) problemas.push('sem description');
    else if (!/^".*"$/.test(d[1].trim()) && /:\s/.test(d[1])) problemas.push('description com ": " sem aspas');
  }
  if (/<[a-z][a-z0-9-]*>/.test(txt)) problemas.push('placeholder <...> sobrando');
  if (problemas.length) { erros++; console.log(`✗ ${f}: ${problemas.join(', ')}`); } else console.log(`✓ ${f}`);
}
process.exit(erros ? 1 : 0);
```

---

## 8. Camada 6 — Skills

Formato: `~/.claude/skills/<nome>/SKILL.md` com frontmatter `name` e `description`. A `description`
é o gatilho automático: escreva nela a situação concreta com as palavras que o usuário usa.

### 8.1 Template de skill

```markdown
---
name: <nome>
description: "Use quando <situação concreta, com as palavras que o usuário usa> — <o que a skill entrega>. Também vale quando <segundo gatilho>."
---

# /<nome> — <título>

## Quando usar
- ...
- **Não** para: ...

## Processo
1. ...

## Regras do projeto
- ...

## Anti-racionalização
| Desculpa | Realidade |
|---|---|

## Red flags
- ...

## Verificação
- [ ] ...
```

### 8.2 `adr-decisoes/SKILL.md` (integral, anonimizado)

```markdown
---
name: adr-decisoes
description: "Use ao tomar ou registrar uma decisão arquitetural no <Projeto> (infra, integração externa, modelo de dados, contrato de API, escolha 'A vs B' entre abordagens, aposentadoria de um sistema) — cria/atualiza ADR em docs/decisions/ com contexto, decisão, alternativas rejeitadas e consequências, e sincroniza o 'Decisões Recentes' do CLAUDE.md do módulo e a memória."
---

# ADRs — Architecture Decision Records — <Projeto>

Adaptado de `addyosmani/agent-skills` (skill `documentation-and-adrs`, MIT). Código mostra
**o quê**; o ADR guarda **o porquê** e **o que foi rejeitado**. Aqui quem mais lê são os
agentes (Claude Code, subagentes) e o "eu futuro" do dono — 10 minutos de ADR poupam horas
de re-debate e re-descoberta em sessão.

## Quando usar

- Escolha entre abordagens com impacto além de um arquivo: modelo de dados, infra, integração
  externa, contrato de API (mudança de shape), segurança.
- Aposentadoria de sistema (ver skill `deprecation-migration`).
- Toda vez que o brainstorming do superpowers fechar um design com "decisão do dono".
- **Não** para: fix pontual, refactor local, escolha óbvia sem alternativa real.

## Onde e como

- Diretório: `docs/decisions/` (criar se não existir). Nome: `NNNN-slug-curto.md`, numeração
  sequencial global, nunca reiniciar. Data no corpo, não no nome.
- Um ADR por decisão. **Nunca apagar nem reescrever** um ADR aceito: superseder com outro
  (`Status: Superseded by 0023`).
- O rolling log "Decisões Recentes" no `CLAUDE.md` do módulo continua existindo — recebe **uma
  linha** apontando para o ADR (`ver docs/decisions/0012`). A memória do projeto recebe o link também.

## Template

    # NNNN — Título curto da decisão

    - **Status:** Proposed | Accepted | Superseded by NNNN | Deprecated
    - **Data:** AAAA-MM-DD
    - **Módulo(s):** <lista>
    - **Decisor:** dono do produto — sessão Claude de AAAA-MM-DD

    ## Contexto
    Requisitos, restrições, o problema real (com números quando houver: p95, custo, volume).

    ## Decisão
    O que foi escolhido, em uma frase. Depois o desenho essencial.

    ## Alternativas rejeitadas
    | Alternativa | Prós | Contras | Por que não |
    |---|---|---|---|

    ## Consequências
    - Positivas
    - Negativas / dívidas assumidas (com follow-ups e onde estão registrados)
    - Impacto em: frontends, migração de dados, deploy, docs/skills, custo

    ## Referências
    Spec/plano, commits, memória, tickets.

## Processo

1. Verificar se já existe ADR sobre o tema (`docs/decisions/`, grep). Se existir, superseder.
2. Escrever **antes** de implementar quando a decisão vem do brainstorming; ou logo após, quando
   nasce durante a implementação.
3. Listar alternativas de verdade consideradas (mínimo 1), com o motivo da rejeição.
4. Registrar consequências e dívidas — o que fica pendente vira follow-up na memória.
5. Atualizar `CLAUDE.md` do módulo (1 linha) + memória. Rodar `graphify update .`.

## Anti-racionalização

| Desculpa | Realidade |
|---|---|
| "O código é autodocumentado" | O código mostra o quê; o ADR explica o porquê e o que foi descartado. |
| "Documento quando estabilizar" | Estabiliza mais rápido documentado. Decisão sem registro é re-decidida na próxima sessão. |
| "Ninguém lê" | Agentes leem. A memória de sessão é volátil; o repo não. |
| "ADR é burocracia" | 10 minutos agora contra horas de investigação/regressão depois. |
| "Já está no CLAUDE.md" | O rolling log é resumo; sem alternativas rejeitadas, a mesma discussão volta. |

## Red flags

- Decisão relevante só na memória do Claude ou no chat.
- "Decisões Recentes" com parágrafos gigantes misturando decisão e nota operacional.
- Alternativa rejeitada sem motivo escrito.
- ADR editado retroativamente em vez de superseder.
- `CLAUDE.md` desatualizado depois de mudança de padrão.

## Verificação

- [ ] ADR criado/superseded em `docs/decisions/` com numeração sequencial.
- [ ] Alternativas rejeitadas listadas com motivo.
- [ ] Consequências e dívidas registradas, follow-ups apontados.
- [ ] Linha no "Decisões Recentes" do `CLAUDE.md` do módulo + memória atualizada.
- [ ] `graphify update .` rodado.
```

### 8.3 `api-contrato/SKILL.md` (integral, anonimizado)

```markdown
---
name: api-contrato
description: "Use ao criar ou alterar endpoint, Resource, validação de entrada, evento de broadcast ou shape de resposta da API do <Projeto> consumida por <lista de consumidores> — contrato antes da implementação, mudança só aditiva (nunca BREAKING shape), erro num formato único, validação na fronteira, paginação obrigatória, idempotência real em ações que mudam estado."
---

# Contrato de API — <Projeto>

Adaptado de `addyosmani/agent-skills` (skill `api-and-interface-design`, MIT). Uma API alimenta
**<N> consumidores**: <lista>. **Hyrum's Law**: com consumidores suficientes, todo comportamento
observável vira contrato — inclusive o campo "temporário" no Resource e a ordem da lista.

## Quando usar

- Endpoint novo ou alterado; Resource com campo novo/removido/renomeado.
- Evento de broadcast com payload novo — os fronts dependem do shape.
- Validação nova; mudança de validação que afeta cliente existente.
- Ação que muda estado e pode ser repetida (duplo clique, reconexão, retry do app).

## Processo

1. **Contrato primeiro.** Antes de codar: método + rota, schema de entrada, schema de saída,
   códigos de erro. Escrever no plano/spec. Os tipos são a documentação.
2. **Validar na fronteira, só lá.** Entrada validada no request; respostas de terceiros validadas ao
   entrar; Services confiam no que já passou.
3. **Erro num formato só.** <fábrica de exceções do projeto> → `{success:false, message, errors?, code}`.
   Nunca resposta de erro ad hoc, nunca 500 com trace. 🚨 Erro bruto 5xx aparece no front como "CORS"
   e engana o diagnóstico.
4. **Adicionar, não modificar.** Campo novo é opcional e aditivo. Remover/renomear = deprecação com a
   skill `deprecation-migration` (flag substituta + período de convivência). Nunca mudar tipo de campo
   existente. Mudança de shape de lista = BREAKING → ADR + versionar ou aditivo.
5. **Nomear previsível.** Rotas no padrão do módulo, campos JSON num único case, enums estáveis,
   booleanos `is_/has_`.
6. **Idempotência de verdade.** Ação que muda estado e pode repetir:
   - Chave natural ou lock na linha, `unique` no banco, status guard ("só rascunho publica").
   - Duplicata em voo tem resposta **deliberada**: 409, esperar, ou 202 — nunca segunda execução.
   - Se aceitar chave de idempotência, **honrar** (guardar resultado por chave). `SELECT` + `INSERT`
     sem constraint é race, não guard.
7. **Paginação obrigatória** em lista; filtros explícitos; ordenação estável (`orderBy` + `id` como
   desempate).

## Regras do projeto que fazem parte do contrato

- <escopo por tenant/unidade: header, middleware; testar isolamento>
- Resource expõe relação só quando carregada → o controller decide o eager load; documentar quais
  endpoints carregam o quê.
- URLs assinadas sob demanda, nunca embutidas em listagem.
- Cache de endpoint → toda mutação relevante invalida.
- Broadcast: todo evento carrega versão de estado; versão igual ≠ estado igual → `force` em resync.
- Endpoint novo declara Policy/permissão, não checagem de papel no controller.

## Anti-racionalização

| Desculpa | Realidade |
|---|---|
| "Documento depois" | Schema de entrada + Resource SÃO a doc. Defina antes. |
| "Ninguém usa esse campo" | Se é observável, algum consumidor usa. Grep nos apps antes de remover. |
| "Mantemos as duas versões" | Custo dobra e cria dependência diamante entre apps com deploys separados. |
| "A fila garante exactly-once" | Não garante entre crash do consumer e side effect. Idempotência no receptor. |
| "Aceitar a chave já basta" | Header é contrato; guardar resultado por chave é a implementação. |
| "É só um campo a mais no JSON" | Aditivo e opcional, sim. Renomear/tipar diferente, não. |

## Red flags

- Mesmo endpoint devolvendo shapes diferentes por condição.
- Erro fora da fábrica de exceções; 500 vazando exceção.
- Validação espalhada em Service/Model em vez da fronteira.
- Campo removido/renomeado sem flag substituta e período de convivência.
- Lista sem paginação; ordenação sem desempate.
- Verbo na URL; case misturado nos campos.
- Ação repetível sem lock/constraint/status guard.
- Resposta de terceiro usada sem validar.

## Verificação

- [ ] Rota, entrada, saída e erros definidos antes do código e cobertos por teste.
- [ ] Mudança aditiva e opcional; nada removido/renomeado sem `deprecation-migration`.
- [ ] Erros via fábrica de exceções, formato único; sem 5xx bruto.
- [ ] Lista paginada, ordenação estável, escopo por tenant testado.
- [ ] Ação que muda estado: guard de idempotência + resposta para duplicata decidida e testada (chamar duas vezes no teste).
- [ ] Eager loads documentados por endpoint; cache invalidado na mutação.
- [ ] Consumidores afetados listados e, se houve mudança de shape, ADR + ordem de deploy definida.
```

### 8.4 `deprecation-migration/SKILL.md` (integral, anonimizado)

```markdown
---
name: deprecation-migration
description: "Use ao aposentar código, endpoint, coluna, tabela, serviço externo ou fluxo do <Projeto>, ao migrar consumidores entre implementações e em qualquer migration de schema em produção — expand/contract, backfill, command de conversão com --dry-run e backup, remoção só com uso zero."
---

# Deprecação e migração — <Projeto>

Adaptado de `addyosmani/agent-skills` (skill `deprecation-and-migration`, MIT). Princípio:
**código é passivo, não ativo** — cada linha custa teste, doc, segurança e atenção. O valor está
na funcionalidade, não no código antigo.

## Quando usar

- Remover ou substituir: endpoint, coluna/tabela, service, job, integração, flag, permissão.
- Migrar consumidores: <lista de fronts, scripts, integrações>.
- Migration de schema em produção.
- Decidir "mantém ou aposenta" um caminho legado.

## Antes de tocar: 5 perguntas

1. Ainda entrega valor único? (o substituto cobre 100% dos casos reais em prod?)
2. Quantos consumidores dependem? — listar todos, inclusive scripts, configs, skills e memória que citam.
3. Existe substituto **provado em produção**?
4. Custo de migrar cada consumidor?
5. Custo de NÃO migrar (bug latente, segurança, banimento de serviço externo)?

## Processo (4 etapas, nunca pular)

1. **Construir o substituto** — cobre os casos críticos, tem testes, roda em prod com feature
   flag/env desligado quando possível (padrão: serviço não configurado degrada com log de aviso,
   nunca quebra o fluxo).
2. **Anunciar e documentar** — ADR em `docs/decisions/` + "Decisões Recentes" do `CLAUDE.md` do
   módulo + memória: o que sai, quando, por quê, guia de migração.
3. **Migrar incrementalmente** — consumidor por consumidor. **The Churn Rule:** quem controla a
   infra migra os usuários; não esperar que "migrem sozinhos". Command idempotente com `--dry-run`
   + backup JSON automático antes de mutar.
4. **Remover o antigo** — só após **uso zero medido** (logs, métricas de request, `grep` no repo
   inteiro incluindo configs, skills e memória). Remoção em deploy próprio.

## Schema em produção: expand → backfill → contract

| Fase | Deploy | Regra |
|---|---|---|
| Expand | 1 | Adicionar coluna/tabela nullable ou com default. Código antigo e novo válidos. |
| Backfill | 1 ou 2 | Em lotes, throttled, idempotente, re-executável. Nunca `UPDATE` de tabela inteira sob lock em horário de pico. |
| Cutover | 2 | Código passa a ler/escrever o novo; o antigo ainda existe. |
| Contract | 3 | `drop` da coluna/tabela antiga em migration separada, depois de zero referências. |

- 🚨 **Schema e código dependente nunca no mesmo deploy**: durante o rollout o script de deploy roda
  `migrate` antes de recarregar o código — se o código antigo ainda lê a coluna removida, quebra.
- Toda migration destrutiva tem `down()` testado e **backup antes** (dump da tabela, não do banco inteiro).
- Dados legados em formato antigo quebram buscas por igualdade: o command de conversão roda em prod
  **antes** de ativar o código novo.

## Padrões de migração

- **Strangler**: novo serviço por trás da mesma interface, tráfego roteado aos poucos.
- **Adapter**: tradutor de interface legada para a nova.
- **Feature flag / env**: serviço desligado por ausência de env, ligado por tenant ou global.
- **Expand/contract**: acima.

## Anti-racionalização

| Desculpa | Realidade |
|---|---|
| "Ainda funciona, por que remover?" | Código sem dono acumula dívida de segurança em silêncio. |
| "Alguém pode precisar depois" | Reconstruir custa menos que manter "por via das dúvidas". Git guarda o histórico. |
| "Migração é cara demais" | Custa menos que 2-3 anos de manutenção dupla. |
| "Os usuários migram sozinhos" | Não migram. Command + guia, ou faça você. |
| "É só renomear a coluna" | Durante o rollout antigo e novo coexistem; um deles quebra. Expand/contract. |
| "Deixo a flag/coluna lá, não atrapalha" | Zombie code: sem dono, com consumidor. Vira o próximo bug. |

## Red flags

- Deprecação sem substituto provado; aviso sem ferramenta de migração.
- "Soft deprecation" em limbo por meses (branch nunca mergeada).
- Feature nova em cima de sistema deprecado.
- Remoção sem medir uso; schema + código no mesmo deploy; backfill bloqueando tabela.
- Referência sobrevivente em config, skill, memória ou script de servidor.

## Verificação antes de dar por concluído

- [ ] Substituto em produção, com teste e degradação limpa.
- [ ] ADR + `CLAUDE.md` "Decisões Recentes" + memória atualizados.
- [ ] Todos os consumidores migrados (lista explícita, verificada por log/grep).
- [ ] Command de migração de dados rodado em prod com backup e `--dry-run` antes.
- [ ] Código, testes, config, env, docs e skills do antigo removidos; `grep` no repo limpo.
- [ ] Migration destrutiva em deploy próprio, `down()` testado, backup guardado.
- [ ] `graphify update .` rodado.
```

### 8.5 `performance-observabilidade/SKILL.md` (integral, anonimizado)

```markdown
---
name: performance-observabilidade
description: "Use quando houver lentidão reportada ou medida no <Projeto> (<telas críticas>, endpoints com p95 alto, listagens pesadas, N+1, bundle dos apps), antes de otimizar qualquer coisa, ao adicionar índice/cache/preload, e ao instrumentar métricas/alertas — medir baseline, corrigir um gargalo por vez, re-medir igual, reverter o que não vence a variância e proteger com budget/alerta."
---

# Performance e observabilidade — <Projeto>

Adaptado de `addyosmani/agent-skills` (skills `performance-optimization` e
`observability-and-instrumentation`, MIT). Regra única: **sem medição não existe otimização**.
Melhoria que não supera a variância entre execuções é revertida.

## Quando usar

- Reclamação ou alerta de lentidão em <telas e endpoints críticos>.
- Antes de adicionar índice, cache, preload/eager load, aumentar pool ou worker.
- Suspeita de regressão após deploy (comparar métricas antes/depois).
- Feature que mexe com volume (import, dashboard, relatórios).
- **Não usar** antes de evidência: otimização prematura é complexidade sem retorno.

## Ferramentas nossas (usar estas, não inventar)

| Camada | Ferramenta |
|---|---|
| Carga | <k6 ou equivalente; cenário de referência e onde está> |
| API por endpoint | <tabela de métricas de request; endpoint de consulta avg/p50/p95/p99/5xx> |
| Sistema | <serviço de monitor, thresholds, alertas> |
| Banco | `EXPLAIN (ANALYZE, BUFFERS)`; `pg_stat_statements`; `pg_stat_activity` (ou equivalentes) |
| Erros | <agregação de logs de erro> |
| Frontend | DevTools Performance, Lighthouse, tamanho do bundle no build |
| Cache | <serviços de cache do projeto e TTLs> |

## Processo (5 passos, nesta ordem)

1. **MEASURE** — baseline com número: p95 do endpoint, tempo da query (`EXPLAIN ANALYZE`), duração
   do teste de carga, LCP/INP no app. Registrar comando e condições.
2. **IDENTIFY** — o gargalo real, não o presumido. É banco (N+1, seq scan, lock)? é app
   (serialização, chamada externa)? é rede/tempo real? é frontend (bundle, re-render, polling)?
3. **FIX** — um gargalo por vez. Padrões: preload por lote nas listagens, URL assinada sob demanda,
   cache com chave por tenant e invalidação em mutação, versão de estado + resync no tempo real.
4. **VERIFY** — re-medir com o **mesmo** comando e condições. Ganho tem que passar a variância
   run-to-run. Não venceu → reverter (mudança neutra é dívida perpétua).
5. **GUARD** — threshold no monitor, budget de bundle, teste que falha em N+1 (contar queries),
   teste de carga antes de evento grande.

## Regras específicas

- **Índice**: só com plano antes/depois; considerar custo de escrita; verificar se o planner usa.
- **Cache**: declarar chave completa (tenant, user, locale, filtros) e estratégia de invalidação.
  Cache sem invalidação em mutação = bug de staleness.
- **Listagem**: sempre paginada; nunca carregar tabela inteira em Resource.
- **Chamada externa**: timeout explícito, nunca na listagem, preferir job.
- **Registrar tentativas** (mantidas e revertidas) na memória/ADR para não repetir ideia falha.

## Observabilidade (instrumentar antes de otimizar)

- Toda operação nova pesada ganha log estruturado com `duration_ms`, ids e resultado.
- Endpoint novo entra automaticamente nas métricas de request (middleware); conferir que aparece.
- Job novo: log de início/fim/falha; falha silenciosa é red flag.
- Métrica que importa ao usuário tem threshold ou alerta, não só log.

## Anti-racionalização

| Desculpa | Realidade |
|---|---|
| "Otimizo depois" | Dívida de performance compõe; anti-padrões óbvios se corrigem agora. |
| "Na minha máquina é rápido" | Produção tem <recursos limitados / pico de uso>. |
| "É óbvio que isso melhora" | Se não mediu, não sabe. Perfil primeiro. |
| "Só adicionar um índice" | Ler o plano; índice inútil custa em toda escrita. |
| "Só cachear" | Cache de coisa rápida não ganha nada e cria staleness. |
| "Não piorou, deixa" | Neutro é revert; manutenção para sempre. |
| "Já escrevi, fica" | Custo afundado; a medição não liga para o tempo gasto. |

## Red flags

- Otimização sem profiling; várias mudanças numa medição só.
- N+1 em Resource/listagem; endpoint de lista sem paginação.
- Índice sem plano; cache sem chave completa ou sem invalidação.
- Pool/worker aumentado sem descobrir quem segura conexão.
- Bundle crescendo sem revisão.
- "Ganho" que exigiu mudar/pular teste.
- Mesma otimização falha tentada de novo sem registro.

## Verificação

- [ ] Antes/depois com números, mesmo comando e condições.
- [ ] Ganho maior que a variância; o que não venceu foi revertido.
- [ ] Gargalo identificado nomeado; uma mudança por medição.
- [ ] Sem N+1 novo; listagem paginada; índice com plano; cache com chave e invalidação.
- [ ] Guarda criada (threshold, budget, teste de contagem de queries ou carga).
- [ ] Tentativas registradas (memória/ADR). Testes existentes passam.
```

### 8.6 Backlog: skill + formato dos itens + CLI

**`docs/backlog/README.md` (integral, anonimizado):**

```markdown
# Backlog de desenvolvimento

Um arquivo por item em `itens/NNNN-slug.md`. `BACKLOG.md` é gerado — nunca editar à mão.
Operar sempre pela CLI (`node tools/backlog/backlog.mjs <cmd>`) ou pela skill `/backlog`;
editar o arquivo à mão só para escrever Contexto, Como reproduzir e Proposta.

## Campos do cabeçalho

| Campo | Valores | Regra |
|---|---|---|
| id | inteiro | igual ao prefixo do nome; sequencial global, nunca reaproveitado |
| titulo | texto livre, uma linha | obrigatório; vira o slug do arquivo |
| tipo | bug, melhoria, ideia, feature, tarefa | bug: deveria funcionar e não funciona · melhoria: funciona, pode ficar melhor · ideia: ainda não decidido · feature: novo e aprovado · tarefa: infra, deploy, débito, docs |
| urgencia | P0, P1, P2, P3 | P0 agora (produção quebrada) · P1 esta semana · P2 próximo ciclo · P3 quando der |
| status | aberto, em-andamento, feito, descartado | feito exige `concluido` + commit (+ `cliente` em bug/melhoria/feature); descartado exige motivo |
| modulos | <lista de módulos do projeto> | ao menos um |
| unidades | todas, <clientes/tenants> | filtra o relatório por cliente |
| origem | dono, cliente:<nome>, usuario:<nome> | quem pediu |
| criado / iniciado / concluido | AAAA-MM-DD | a CLI preenche iniciado e concluido |
| commits | ["repo sha", ...] | `set N commits="+repo sha"` acrescenta |
| sessao | link da sessão Claude que fechou o item | opcional |
| relacionados | [ids] | opcional |
| cliente | frase(s) sem termo técnico | vai para o relatório do cliente; `check` recusa arquivo, sha, endpoint, commit, PR, controller, migration, payload |
| validacao | pendente, ok | conferência do dono na tela depois da entrega. `pendente` = entregue sem o dono ver; `ok` = conferiu; vazio = não se aplica |

## Corpo

Exatamente estas seções, nesta ordem: `## Contexto`, `## Como reproduzir` (obrigatória em bug),
`## Proposta`, `## Notas de execução` (uma linha por data; `set N nota=...` acrescenta).

## Comandos

    node tools/backlog/backlog.mjs new --tipo bug --urgencia P1 --modulos <mod> --titulo "..." [--unidades x] [--origem cliente:x]
    node tools/backlog/backlog.mjs set 12 status=em-andamento
    node tools/backlog/backlog.mjs set 12 status=feito commits="<repo> <sha>" cliente="..." validacao=pendente
    node tools/backlog/backlog.mjs set 12 validacao=ok nota="Dono conferiu em tela."
    node tools/backlog/backlog.mjs list --status aberto --modulo <mod>
    node tools/backlog/backlog.mjs list --validacao pendente
    node tools/backlog/backlog.mjs next
    node tools/backlog/backlog.mjs board
    node tools/backlog/backlog.mjs report --periodo AAAA-MM [--tipo tecnico|cliente] [--unidade x] [--pdf]
    node tools/backlog/backlog.mjs check

## Regras de sessão

1. Entrega que resolve um item termina com `set <id> status=feito commits=... cliente=...`.
2. Bug ou ideia encontrada no caminho vira item na hora.
3. `check` antes de commitar itens; `board` depois de qualquer alteração (a CLI já faz).
4. Commits de itens em branch `chore/backlog-...`, mensagem `backlog: #id título`.
5. Entrega que foi para produção sem o dono ver na tela fecha com `validacao=pendente`; quando ele
   conferir, `validacao=ok` + nota.
```

**Item (exemplo do formato):**

```markdown
---
id: 12
titulo: "Botão de exportar não aparece no celular"
tipo: bug
urgencia: P1
status: aberto
modulos: [app]
unidades: [todas]
origem: cliente:<nome>
criado: 2026-09-11
iniciado: null
concluido: null
commits: []
sessao: null
relacionados: []
cliente: null
validacao: null
---
## Contexto
...

## Como reproduzir
1. ...

## Proposta
...

## Notas de execução
2026-09-12: ...
```

**A CLI** (`tools/backlog/backlog.mjs`, ~230 linhas em Node sem dependências): lê os `.md` de
`itens/`, parseia o frontmatter, implementa `new` (próximo id + arquivo do template), `set`
(atualiza campos; `+valor` acrescenta em listas; `nota=` acrescenta linha datada), `list`/`next`
(filtros; `next` ordena por urgência e separa "aguardando validação"), `board` (regenera
`BACKLOG.md`), `check` (valida campos, seções e jargão em `cliente`), `report` (markdown por
período/tipo/cliente, opcionalmente PDF). Peça ao seu Claude para escrevê-la a partir desta descrição
e do README; o `check` de jargão é uma lista de regex (`\b[0-9a-f]{7,}\b`, `endpoint`, `controller`,
`migration`, `payload`, `PR`, caminhos com `/`).

**`backlog/SKILL.md` (integral, anonimizado):**

```markdown
---
name: backlog
description: "Use para lançar, consultar, priorizar, iniciar, concluir ou descartar itens do backlog de desenvolvimento do <Projeto> (ideias, bugs, melhorias, features, tarefas, por urgência P0–P3 e módulo) e para gerar o relatório técnico ou o relatório de mudanças para um cliente — '/backlog bug P1 app: ...', '/backlog next', '/backlog relatório setembro <cliente> pdf'. Também vale quando, no meio de outra tarefa, aparece um bug ou ideia que precisa ser registrado, ou quando uma entrega fecha um item."
---

# /backlog — backlog de desenvolvimento do <Projeto>

Fonte: `docs/backlog/itens/*.md` (regras em `docs/backlog/README.md`).
CLI: `node tools/backlog/backlog.mjs <cmd>` (new, set, list, next, board, report, check).
Quadro gerado: `docs/backlog/BACKLOG.md`. Relatórios: `docs/relatorios/backlog/`.

## Interpretar o pedido

O dono fala natural. Deduza e confirme só o que faltar:

- **tipo**: "não funciona / quebrou / erro" → bug · "podia / melhorar / ficou feio" → melhoria · "e se / ideia" → ideia · "vamos fazer / precisamos de" já decidido → feature · infra, deploy, docs, débito → tarefa.
- **urgência**: "agora / produção" → P0 · "esta semana / está atrapalhando" → P1 · sem pressa explícita em bug ou melhoria → P2 · ideia / polimento → P3. Se o dono deu P0–P3, use.
- **módulos**: pelo assunto. Tela = front; regra/dados = api; os dois quando o fix precisa dos dois.
- **unidades**: cliente citado → nome canônico; nada citado → todas.
- **título**: uma linha, sem "bug:" no começo. Contexto vai no corpo.

Para **bug**, antes de considerar o item completo, pergunte (ou extraia da conversa) como reproduzir
e escreva na seção `## Como reproduzir`. Sem isso o `check` falha.

## Fluxos

**Lançar**: `new` com os campos deduzidos → editar o arquivo para preencher Contexto/Como reproduzir/Proposta com o que a conversa já disse → mostrar `#id · arquivo` ao dono. Não pergunte o que já está na conversa.

**Consultar**: `next` (o que atacar agora; no fim, o que aguarda validação) · `list --status aberto --modulo x` · `list --urgencia P1 --status aberto,em-andamento` · "o que falta eu conferir?" → `list --validacao pendente`.

**Iniciar**: `set <id> status=em-andamento` no começo da tarefa que vai resolvê-lo.

**Concluir**: ao fechar a entrega — `set <id> status=feito commits="repo sha" cliente="frase(s) para o cliente" sessao="<link desta sessão>"` e `set <id> nota="o que foi feito / o que ficou para validar"`. Se foi para produção sem o dono ver na tela, acrescente `validacao=pendente`. O texto `cliente` é para o operador: diga o que mudou na tela ou no comportamento, sem nome de arquivo, commit, endpoint, controller, migration, payload ou PR.

**Validar**: quando o dono diz que conferiu — `set <id> validacao=ok nota="Dono conferiu em tela."`.

**Descartar**: `set <id> status=descartado nota="motivo"`.

**Relatório**: `report --periodo AAAA-MM --tipo tecnico|cliente [--unidade x] [--pdf]`.

**Commit dos itens**: branch `chore/backlog-<slug>`, `git add docs/backlog/itens/<arquivo> docs/backlog/BACKLOG.md`, mensagem `backlog: #id título`, fast-forward na principal. `check` antes do commit.

## Regras que valem em toda sessão, mesmo sem /backlog

1. Toda entrega que resolve um item fecha o item (status=feito, commits, cliente) antes de dar a tarefa por concluída.
2. Bug ou ideia que aparece no meio de outra tarefa vira item na hora (`new`), sem esperar o fim.
3. O quadro `BACKLOG.md` é a fonte do "Próxima sessão começa AQUI" da memória: a memória aponta ids (`#12`), não repete texto.
4. Fechar item com `cliente` não substitui atualizar o manual do operador quando a função mudou.
5. Pendência de validação em tela vive no campo `validacao` do item, não na memória.

## Não fazer

- Não editar `BACKLOG.md` à mão. Não criar item sem passar pela CLI (o id vem dela).
- Não usar o backlog para tarefas de uma sessão só; só o que sobrevive à sessão.
- Não inventar urgência P0: só produção quebrada.
```

### 8.7 `deploy/SKILL.md` (esqueleto)

```markdown
---
name: deploy
description: "Use para deploy do <Projeto>: '/deploy <alvo>' (api | app | all). Build, checagem de branch, deploy e verificação pós-deploy."
---

# /deploy <alvo>

## Antes
1. `git branch --show-current` — deploy só a partir da <main>.
2. `git log --oneline origin/<main>..<main>` — se houver commit que não é seu, liste ao dono antes.
3. `git status --porcelain` limpo.

## Alvos
| Alvo | Comandos |
|---|---|
| api | `<ssh/host> && <script de deploy: pull, deps, migrate, cache>` |
| app | `cd <app> && <build> && <deploy>` |
| all | api, depois app |

## Depois
- Smoke test: <URL de health>, <tela crítica>.
- Registrar sha deployado na memória ("Próxima sessão começa AQUI").
- Fechar itens do backlog que a entrega resolve.
```

### 8.8 Outras skills que valem a pena

- `disk-cleanup` (Windows): quando o disco C: fica abaixo de 5 GB, arquivos JSON/SQLite de apps
  (`.claude.json`, estado do editor) truncam durante a escrita e o Claude reabre "como nova
  instalação". A skill diagnostica (`Get-PSDrive C`), limpa npm-cache, arquivos `.corrupted.*` do
  editor, bundles `.tmp`, e manda **parar antes de qualquer build/deploy** em disco apertado.
- Skills de **importação de dados** de sistemas legados (uma por sistema de origem), com import
  idempotente por tenant e `references/` com o mapeamento de campos.
- Skills **administrativas** (nota fiscal mensal, relatório para cliente): mesmo formato, mostram que
  skill é qualquer procedimento repetível.

---

## 9. Camada 7 — Guard-rails

### 9.1 `~/.claude/settings.json` (integral, anonimizado)

```json
{
  "permissions": { "defaultMode": "auto" },
  "model": "<modelo principal>",
  "effortLevel": "high",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [ { "type": "command", "command": "py <home>/.claude/hooks/branch-guard.py" } ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [ { "type": "command",
          "command": "py -c \"import sys,json;d=json.load(sys.stdin);p=d.get('tool_input',{}).get('file_path','');print('[LEMBRETE] Arquivo de código alterado. Se mudou padrão, fluxo ou regra de negócio, atualize o CLAUDE.md do módulo correspondente.' if any(p.endswith(e) for e in ['.php','.vue','.js','.ts','.py','.go','.rb','.cs']) else '',end='')\"" } ]
      }
    ]
  },
  "enabledPlugins": { "superpowers@claude-plugins-official": true },
  "autoMode": {
    "allow":     [ "$defaults", "Bash(<cli> config list:*)", "Bash(<cli> describe:*)" ],
    "soft_deny": [ "$defaults", "Bash(<cli> <subcomando destrutivo>:*)", "Bash(<storage> rm:*)", "Bash(<cli> firewall-rules delete:*)" ],
    "environment": [
      "### Org-wide",
      "**Organization**: <nome> (<tipo de sistema>)",
      "**Cloud provider(s)**: <provedor, projeto, região>; <hosting dos fronts>; <DNS/proxy>",
      "**Repository visibility**: assume private unless proven otherwise",
      "**Secrets management**: <gerenciador de segredos>; per-module .env / .env.dev / .env.prod files",
      "**Default / protected branches**: <main> — feature branches required, direct commits disallowed, push requires explicit user authorization",
      "**CI/CD deploy targets**: <alvos e scripts>",
      "**Network posture**: <firewall, quem pode falar com quem>",
      "**Trusted internal domains**: <lista>",
      "**Trusted cloud buckets**: <lista>",
      "**Key internal services**: <VM, banco, websocket>",
      "**Sensitive data locations & audiences**: .env* files across all modules; <dumps>; <auditorias>",
      "**Sensitive remote targets**: any host/namespace/bucket with prod or production as a whole word/segment",
      "**Protected deployment namespaces / environments**: production for <módulos>",
      "**Protected IaC scopes**: firewall rules, IAM, RBAC, networking, quota; anything tagged prod",
      "### User-specific",
      "**Primary use of Claude Code**: software development (<stack>)",
      "**Trusted repo**: <caminho local>",
      "**Org-specific CLIs**: <lista de CLIs de uso rotineiro>"
    ]
  },
  "tui": "fullscreen",
  "theme": "dark"
}
```

O bloco `autoMode.environment` é texto livre que descreve o **perímetro de confiança**. O modo
automático usa isso para decidir o que executa sozinho e o que pede confirmação. Vale a pena
escrevê-lo com calma: é a diferença entre "pede confirmação para tudo" e "faz o rotineiro sozinho e
pergunta só no que é destrutivo ou de produção".

### 9.2 `~/.claude/hooks/branch-guard.py` (integral)

```python
"""PreToolUse guard para git (funciona com uma sessao; obrigatorio com duas no mesmo checkout).

Regras:
  * `git commit` em main/master  -> DENY (crie feature branch).
  * `git add -A` / `--all` / `git add .` -> DENY (varre o trabalho da outra sessao;
    adicione arquivo por arquivo).
  * `git stash -u` / `--include-untracked` / `-a` / `--all` -> DENY (leva o que a
    outra sessao ainda nao commitou).
  * `git checkout <branch>` / `git switch <branch>` com arvore suja -> ASK (a troca
    muda os arquivos debaixo da outra sessao; commite antes, ou confirme).
    `-b`/`-c`, `checkout -- <arquivo>` e `checkout <ref> -- <path>` passam.

Notas de implementacao:
  * bloqueia via hookSpecificOutput.permissionDecision ("deny" | "ask"). `sys.exit(1)`
    NAO bloqueia nada (testado): o harness trata exit 1 como erro nao-bloqueante.
  * descobre o repositorio a partir de `cd <path> &&` ou `git -C <path>` no proprio
    comando — num monorepo de modulos independentes o CWD do hook e o errado.
  * ignora corpo de heredoc antes de casar a regex: um comando que apenas GRAVAVA
    texto contendo as palavras-chave era recusado como se fosse commit.
"""
import sys, json, re, subprocess

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

command = (data.get('tool_input', {}) or {}).get('command', '') or ''

_HEREDOC_INI = re.compile(r'<<-?\s*(["\']?)([A-Za-z_][A-Za-z0-9_]*)\1')


def sem_heredoc(cmd):
    """Devolve o comando sem os corpos de heredoc (a linha que abre e preservada)."""
    linhas = cmd.split('\n')
    saida = []
    i = 0
    while i < len(linhas):
        linha = linhas[i]
        saida.append(linha)
        delims = [m.group(2) for m in _HEREDOC_INI.finditer(linha)]
        i += 1
        for delim in delims:
            while i < len(linhas) and linhas[i].strip() != delim:
                i += 1
            if i < len(linhas):
                i += 1
    return '\n'.join(saida)


executavel = sem_heredoc(command)

if not re.search(r'\bgit\b', executavel):
    sys.exit(0)


def decidir(decisao, motivo):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decisao,
            "permissionDecisionReason": motivo,
        }
    }))
    sys.exit(0)


def _arg(m):
    return m.group(2) or m.group(3) or m.group(4)


def _resolve_var(valor, cmd):
    """`$api` (PowerShell) ou `$API`/`${API}` (bash) definido no proprio comando -> valor literal."""
    m = re.match(r'^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$', valor or '')
    if not m:
        return valor
    nome = m.group(1)
    d = re.search(r'\$?' + re.escape(nome) + r'\s*=\s*("([^"]+)"|\'([^\']+)\'|(\S+))', cmd)
    return _arg(d) if d else valor


def repo_dir(cmd):
    """Diretorio do repo alvo, inferido do comando; None = usar o CWD do hook."""
    m = re.search(r'git\s+-C\s+("([^"]+)"|\'([^\']+)\'|(\S+))', cmd)
    if m:
        return _resolve_var(_arg(m), cmd)
    m = re.search(r'(?:^|;|&&)\s*(?:Set-Location|cd)\s+("([^"]+)"|\'([^\']+)\'|(\S+))\s*(?:&&|;)', cmd, re.I)
    if m:
        return _resolve_var(_arg(m), cmd)
    return None


class RepoIndeterminado(Exception):
    pass


def git(*args):
    argv = ['git']
    d = repo_dir(executavel)
    if d:
        if d.startswith('$') or d.startswith('%'):
            raise RepoIndeterminado(d)
        argv += ['-C', d]
    argv += list(args)
    try:
        return subprocess.check_output(argv, text=True, stderr=subprocess.DEVNULL)
    except Exception as e:
        raise RepoIndeterminado(d or '(cwd)') from e


INDETERMINADO = ("Nao consegui verificar o repositorio (caminho em variavel nao resolvida ou fora de "
                 "um repo git: %s). Confirme se o comando e seguro, ou reescreva com o caminho literal.")


# Um "segmento" e um comando git isolado (sem atravessar pipe/`;`/`&&`).
SEG = r'\bgit\b[^|;&\n]*?'

# --- git add -A / --all / .  --------------------------------------------------
m = re.search(SEG + r'\badd\b([^|;&\n]*)', executavel)
if m:
    args = m.group(1)
    if re.search(r'(^|\s)(-A|--all|-[a-zA-Z]*A[a-zA-Z]*)(\s|$)', args) or re.search(r'(^|\s)\.{1,2}/?(\s|$)', args):
        decidir("deny",
                "BLOQUEADO: `git add -A` / `git add .` varre o trabalho nao commitado da outra "
                "sessao (checkout compartilhado). Adicione arquivo por arquivo: `git add <caminho>`.")

# --- git stash -u / --include-untracked / -a / --all ---------------------------
m = re.search(SEG + r'\bstash\b([^|;&\n]*)', executavel)
if m:
    args = m.group(1)
    if re.search(r'(^|\s)(-u|--include-untracked|-a|--all|-[a-zA-Z]*[ua][a-zA-Z]*)(\s|$)', args):
        decidir("deny",
                "BLOQUEADO: `git stash -u/-a` leva junto o que a outra sessao ainda nao commitou. "
                "Use `git stash push -- <caminhos>` ou commite antes.")

# --- git checkout <branch> / git switch <branch> com arvore suja --------------
m = re.search(SEG + r'\b(checkout|switch)\b([^|;&\n]*)', executavel)
if m:
    args = m.group(2)
    cria = re.search(r'(^|\s)(-b|-B|-c|-C|--orphan)(\s|$)', args)
    so_arquivo = re.search(r'(^|\s)--(\s|$)', args)
    if not cria and not so_arquivo:
        try:
            sujo = git('status', '--porcelain', '--untracked-files=normal').strip()
        except RepoIndeterminado as e:
            decidir("ask", "ATENCAO (troca de branch): " + INDETERMINADO % e)
        if sujo:
            resumo = '\n'.join(sujo.split('\n')[:8])
            decidir("ask",
                    "ATENCAO: trocar de branch com alteracao nao commitada muda os arquivos "
                    "debaixo da outra sessao (checkout compartilhado). Commite antes, ou confirme "
                    "se sabe que essas alteracoes sao suas/inofensivas:\n" + resumo)

# --- git commit em main/master --------------------------------------------------
if re.search(SEG + r'\bcommit\b', executavel):
    try:
        branch = git('branch', '--show-current').strip()
    except RepoIndeterminado as e:
        decidir("ask", "ATENCAO (commit): " + INDETERMINADO % e)
    if branch in ('main', 'master'):
        decidir("deny",
                "BLOQUEADO: commit direto em [%s] nao e permitido. Crie uma feature branch "
                "primeiro (feat/ | fix/ | refactor/ | chore/)." % branch)

sys.exit(0)
```

Se a branch principal não se chama `main`/`master`, ajuste a última regra. Se o Python não está
como `py` no PATH, troque o comando do hook em `settings.json` (`python3`, etc.).

**Teste do hook** (`testa-hook.py`): alimenta o script com `{"tool_input":{"command": ...}}` para
cada caso e confere a decisão. Casos mínimos: commit em main (deny), commit em branch (passa),
`add -A` (deny), `add .` (deny), `add arquivo` (passa), `stash -u` (deny), `stash` (passa),
`checkout -b x` (passa), `checkout x` com árvore suja (ask), `checkout -- arquivo` (passa), heredoc
contendo "git commit" (passa), `git -C <path> commit` (usa o path).

### 9.3 `<repo>/.claude/settings.json` (integral)

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "CMD=$(py -c \"import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',d).get('command',''))\" 2>/dev/null || true); case \"$CMD\" in *grep*|*rg\\ *|*ripgrep*|*find\\ *|*fd\\ *|*ack\\ *|*ag\\ *)   [ -f graphify-out/graph.json ] &&   echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"graphify: Knowledge graph exists. Read graphify-out/GRAPH_SUMMARY.md (short map: god nodes, communities, where each subject lives) before searching raw files; never read GRAPH_REPORT.md whole. Prefer graphify query/path/explain for cross-module questions.\"}}'   || true ;; esac"
          }
        ]
      }
    ]
  }
}
```

### 9.4 `<repo>/.claude/settings.local.json` (não versionado)

Allowlist da máquina para não pedir confirmação em comandos rotineiros de leitura e build
(`php artisan:*`, `npm run *`, `git commit *`, etc.) e lista de MCPs habilitados. Cresce com o
uso; o comando `/fewer-permission-prompts` sugere entradas a partir dos transcripts.

---

## 10. Camada 8 — MCP

`<repo>/.mcp.json`. Segredos por variável de ambiente ou placeholder que o dono preenche
localmente; nunca no arquivo versionado.

```json
{
  "mcpServers": {
    "chrome-devtools": { "command": "npx", "args": ["-y", "chrome-devtools-mcp@latest"] },
    "postgres": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://<user>:<senha>@127.0.0.1:5432/<banco_de_teste>"] },
    "github": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"], "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "<token>" } }
  }
}
```

| Servidor | Para quê |
|---|---|
| navegador (chrome-devtools ou extensão Claude in Chrome) | testar telas, ler console, capturar layout |
| banco de dados | consultar o banco de teste local (nunca o de produção) |
| github | issues e PRs |

Regra: **medir uso antes de manter**. Um conjunto de 6 plugins de orquestração com ~400 ferramentas
registradas ficou 30 dias com zero chamadas e só pesava no contexto de toda sessão. Foi desligado.

---

## 10b. Departamento de desenvolvimento — do pedido ao relatório do cliente

É a etapa **Priorizar** do Protocolo do Dev (0b) em detalhe. O backlog não é uma lista de ideias: é
o **controle de tarefas do departamento**. Tudo que vai sobreviver à sessão passa por ele, e ele é a
fonte do que o Claude ataca a seguir, do que o dono precisa validar e do que o cliente recebe como
relatório. As peças (skill 8.6, README, CLI) já foram descritas; aqui está o **fluxo** e o **quadro**.

### Fluxo de um item

```
 pedido do dono / cliente / bug achado no caminho
        │
        ▼
 [1] LANÇAR    /backlog "<fala natural>"  → a skill deduz tipo, urgência, módulos, cliente
        │       cria itens/NNNN-slug.md (status=aberto) e preenche Contexto / Como reproduzir / Proposta
        ▼
 [2] PRIORIZAR quadro BACKLOG.md regenerado: Agora (P0/P1) · Próximo ciclo (P2) · Quando der (P3)
        │       `next` devolve a fila ordenada — é o "o que faço agora" de cada sessão
        ▼
 [3] INICIAR   set N status=em-andamento  (no começo da sessão que vai resolver)
        │       → brainstorming/plano/implementação (Superpowers) numa feature branch
        ▼
 [4] ENTREGAR  merge + deploy
        │       set N status=feito commits="repo sha" cliente="frase para o operador" sessao=<link>
        │       set N nota="o que foi feito / o que ficou para conferir"
        │       foi para produção sem o dono ver na tela? → validacao=pendente
        ▼
 [5] VALIDAR   quadro mostra "Aguardando validação em tela"; `next` lista no fim
        │       dono confere e diz "deu certo" → set N validacao=ok nota="Dono conferiu em tela."
        ▼
 [6] REPORTAR  report --periodo AAAA-MM --tipo cliente [--unidade X] [--pdf]
                um relatório por cliente com o que mudou para ele, em linguagem de operador
                report --tipo tecnico → relatório interno com commits e módulos
```

Ramificações: `status=descartado nota="motivo"` em qualquer ponto; `relacionados=` liga itens que
formam um pacote de entrega; item grande vira vários itens relacionados, nunca um item eterno.

### O quadro (`docs/backlog/BACKLOG.md`, gerado)

```markdown
# Backlog — <Projeto>

> Gerado por `backlog board` em AAAA-MM-DD. Não editar à mão: edite os itens em `itens/` e gere de novo.

## Agora
- #25 · ideia · P1 · app · <título> · há 1 dias

## Próximo ciclo
- #2 · bug · P2 · api · <título> · há 4 dias
- #49 · melhoria · P2 · api, app · <título> · em andamento desde AAAA-MM-DD

## Quando der
- #1 · tarefa · P3 · api · <título> · há 4 dias

## Aguardando validação em tela
- #52 · bug · app · <título> · em produção desde AAAA-MM-DD · app 613e8de
- #21 · feature · api · <título> · em produção desde AAAA-MM-DD · api 2960faeb, api 500dda90
```

Regras do quadro:
- Seções por urgência (P0 e P1 em "Agora"); dentro da seção, por id.
- Item em andamento mostra a data de início; item feito com `validacao=pendente` sai da fila e vai
  para "Aguardando validação em tela" com sha dos commits.
- Item feito e validado (ou sem validação aplicável) sai do quadro; fica só no arquivo e nos relatórios.
- `next` na CLI é o mesmo quadro em uma linha por item, ordenado por urgência, com os pendentes de
  validação num bloco próprio no fim.

### Os relatórios (`docs/relatorios/backlog/`)

Gerados por `report`, um por período; saem em `.md`, `.html` e opcionalmente `.pdf`.

**Relatório do cliente** (`AAAA-MM-<cliente>.md`), um por cliente que teve item no período. Só usa o
campo `cliente` de cada item, agrupado por tipo. É o que o cliente recebe:

```markdown
# O que mudou no <Projeto> — <Cliente> — <mês de AAAA>

## Correções
- <frase do campo cliente do item, sem termo técnico>

## Melhorias
- ...

## Novidades
- ...
```

**Relatório técnico** (`AAAA-MM-tecnico.md`): todos os itens do período com id, tipo, módulos,
commits, datas, notas de execução e quem validou. Serve para o próprio departamento e para
faturamento ou prestação de contas.

O `check` da CLI recusa texto `cliente` com jargão (sha, endpoint, controller, migration, payload,
PR, caminho de arquivo). Isso garante que o relatório do cliente nunca precise de edição manual.

### Como isso se liga ao resto do SuperBrain

| Peça | Papel no fluxo |
|---|---|
| Skill `/backlog` | interpreta a fala do dono, opera a CLI, aplica as 5 regras de sessão |
| Memória ("Próxima sessão começa AQUI") | aponta ids do quadro (`#21 validacao=pendente`) em vez de repetir texto |
| Superpowers | do passo [3] ao [4]: brainstorming, plano, implementação, revisão |
| `sp-code-reviewer` | no item 6 do que avalia: "item do backlog fechado com texto `cliente`" |
| Manual do operador | fechar item com `cliente` não dispensa atualizar a página da função |
| Hook de git | branch `chore/backlog-<slug>` para commitar os itens; nunca na principal |
| ADR | decisão tomada dentro de um item ganha ADR e o item aponta para ele |

### Regras que valem em toda sessão, mesmo sem `/backlog`

1. Toda entrega que resolve um item fecha o item antes de dar a tarefa por concluída.
2. Bug ou ideia que aparece no meio de outra tarefa vira item na hora.
3. O quadro é a fonte do handoff entre sessões; a memória aponta ids.
4. Pendência de validação em tela vive no campo `validacao` do item.
5. Não inventar P0: só produção quebrada ou evento do cliente em risco.

### Para adaptar

- Troque a lista de módulos e de clientes nos campos `modulos` e `unidades`.
- Se não há múltiplos clientes, `unidades` vira `[todas]` sempre e o relatório do cliente sai um só.
- Se o dono não valida em tela, remova `validacao`; se valida, é o campo mais importante do fluxo.
- Seções do relatório do cliente (Correções, Melhorias, Novidades) mapeiam tipo bug, melhoria,
  feature. Tarefa e ideia não entram no relatório do cliente.

---

## 11. Camada 9 — Documentos vivos

| Onde | O que | Disciplina de fechamento |
|---|---|---|
| `docs/backlog/itens/*.md` | 1 item por arquivo | entrega fecha o item; bug achado no caminho vira item; memória aponta o id |
| `docs/decisions/` | ADRs + log de decisões antigas | CLAUDE.md do módulo mantém só ~6 "Decisões Recentes" |
| `docs/manual/<modulo>/<slug>.md` | manual do operador, 1 página por função | toda tarefa que muda comportamento atualiza a página antes de fechar |
| `docs/specs/`, `docs/plans/` | saída do Superpowers | |
| `docs/analises/`, `docs/relatorios/`, `docs/referencias/` | tudo que o Claude gera em sessão | nunca na raiz do repositório |

Formato de página do manual: frontmatter com `titulo`, `modulo`, `permissao` (quem vê), `atualizado`
(data); corpo em linguagem de operador, sem termo técnico, com capturas em `docs/manual/img/`. Um
gerador roda no build do front e falha em página inválida, o que força a disciplina.

---

## 12. Ciclo de uma tarefa

1. **Abertura**: carrega CLAUDE.md (3 níveis), `MEMORY.md` e a skill `using-superpowers`.
2. **Pedido** → skill de processo (brainstorming ou systematic-debugging) → agente de domínio roteado
   pelo vocabulário da fala.
3. **Antes de varrer código**: `GRAPH_SUMMARY.md` ou `graphify query`.
4. **Branch**: `git checkout -b feat/...` (hook nega commit na principal).
5. **Implementação**: plano → `sp-implementer` por task (TDD) → `sp-spec-reviewer` por task →
   `sp-code-reviewer` no branch inteiro → uma onda de correção.
6. **Fechamento**: manual atualizado, item do backlog fechado, ADR se houve decisão, memória com o não
   óbvio, `graphify update .` + script de resumo.
7. **Deploy**: `/deploy <alvo>`; push na principal só com "pode" explícito.

---

## 13. Gotchas que custaram caro (para não repetir)

- Agente com CRLF ou description sem aspas não carrega e ninguém avisa.
- `sys.exit(1)` num hook não bloqueia nada. Só `permissionDecision` bloqueia.
- O CWD de um hook num monorepo é o errado; ler o path do próprio comando.
- Hook de git barrando um comando que só gravava texto com "git commit" dentro (heredoc).
- Regra "leia o relatório do grafo" ignorada porque o relatório tinha 500 KB. Regra impossível é
  regra ignorada; criar o resumo resolveu.
- Templates do plugin de processo mandando `general-purpose` e anulando todos os agentes.
- 400 ferramentas de MCP registradas e nunca chamadas, pesando em toda sessão.
- Capturas de tela em escala cheia consumindo 79% do volume de resultado de ferramenta.
- Script que reescrevia `MEMORY.md` abrindo o arquivo em modo escrita antes do conteúdo pronto:
  truncou o índice inteiro.
- Disco com menos de 5 GB: arquivos de estado de apps truncam e o Claude "esquece" a instalação.
- Duas sessões no mesmo checkout: `git add -A`, `stash -u` e `checkout` sujo destroem o trabalho da
  outra. Worktrees foram testados e aposentados pelo custo de dependências e `.env` por cópia.

---

## 14. Medir para manter vivo

Os transcripts ficam em `~/.claude/projects/<hash>/*.jsonl`, um JSON por linha. Cada linha de
resposta do modelo tem `type: "assistant"`, `message.model`, `message.usage` e `message.content[]`
com itens `{type: "tool_use", name, input}`; os resultados vêm em linhas `type: "user"` com
`tool_result`. Script de referência:

```js
// ~/.claude/medir-uso.mjs — node ~/.claude/medir-uso.mjs <dias>
import fs from 'node:fs'; import path from 'node:path'; import os from 'node:os';
const dias = Number(process.argv[2] ?? 30);
const desde = Date.now() - dias * 86400e3;
const raiz = path.join(os.homedir(), '.claude', 'projects');
const porModelo = new Map(), porTool = new Map(), bytesTool = new Map(), porAgente = new Map(), porMcp = new Map();
const add = (m, k, v = 1) => m.set(k, (m.get(k) ?? 0) + v);
const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(path.join(d, e.name)) : e.name.endsWith('.jsonl') ? [path.join(d, e.name)] : []);
for (const f of walk(raiz)) {
  if (fs.statSync(f).mtimeMs < desde) continue;
  for (const linha of fs.readFileSync(f, 'utf8').split('\n')) {
    if (!linha) continue; let j; try { j = JSON.parse(linha); } catch { continue; }
    const msg = j.message; if (!msg) continue;
    if (j.type === 'assistant') {
      const u = msg.usage ?? {};
      add(porModelo, msg.model ?? '?', (u.input_tokens ?? 0) + (u.output_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0));
      for (const c of msg.content ?? []) if (c.type === 'tool_use') {
        add(porTool, c.name);
        if (c.name === 'Agent') add(porAgente, c.input?.subagent_type ?? 'general-purpose');
        if (c.name.startsWith('mcp__')) add(porMcp, c.name.split('__')[1]);
      }
    } else if (j.type === 'user') {
      for (const c of (Array.isArray(msg.content) ? msg.content : [])) if (c.type === 'tool_result') {
        const tam = JSON.stringify(c.content ?? '').length;
        add(bytesTool, j.toolUseResult?.tool ?? c.tool_use_id?.slice(0, 8) ?? '?', tam);
      }
    }
  }
}
const top = (m, n = 15) => [...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, n);
console.log('Tokens por modelo', top(porModelo));
console.log('Chamadas por ferramenta', top(porTool));
console.log('Bytes de resultado', top(bytesTool));
console.log('Despachos por subagente', top(porAgente));
console.log('Chamadas por servidor MCP', top(porMcp));
```

| Métrica | O que revelou no setup original |
|---|---|
| Tokens por modelo | quanto vai para a sessão principal vs subagentes |
| Chamadas por ferramenta e bytes de resultado | capturas de tela eram 79% do volume; 452 `cat`/`grep` em 7 dias |
| Despachos por subagente | 223 general-purpose × 7 especialistas |
| MCP sem uso | 400 ferramentas, zero chamadas |

Repetir mensalmente. Cada regra do CLAUDE.md global deve apontar para um número.

---

## 15. Checklist de adaptação a um projeto já iniciado

Ordem recomendada; cada passo é independente e revisável.

1. **Inventário**: listar o que já existe em `~/.claude/` e `<repo>/.claude/`. Não sobrescrever nada
   sem mostrar o diff ao dono.
2. **`~/.claude/CLAUDE.md`** (3.1): mesclar. Idioma, SO, git, tabela de subagentes, economia de contexto.
3. **`<repo>/CLAUDE.md`** (3.2): colocar o bloco "Protocolo do Dev" (0b) logo depois do título e
   mesclar as seções de fluxo git, docs gerados, manual, backlog e graphify ao que já existe. Não
   duplicar stack/portas se já estão descritas.
4. **`<modulo>/CLAUDE.md`** (3.3): só se for monorepo. Cortar para ≤ 30 KB movendo histórico para
   `docs/decisions/`.
5. **Plugin Superpowers** (6): instalar; confirmar que `using-superpowers` aparece no início da sessão.
6. **Agentes `sp-*` e `web-research`** (7.2 a 7.6): copiar, preencher a stack, validar com 7.7.
7. **Agentes de domínio** (7.1): um por domínio que o dono nomeou, com as palavras dele na description.
8. **Hook `branch-guard.py`** (9.2) + `settings.json` (9.1): ajustar nome da branch principal e o
   comando Python. Rodar os casos de teste.
9. **Hook do projeto** (9.3): só depois do grafo existir.
10. **Memória** (4): criar `MEMORY.md` com o esqueleto e o bloco "Próxima sessão começa AQUI"
    preenchido com o estado real de hoje; converter notas soltas do dono em memórias tipadas.
11. **Grafo** (5): instalar `graphifyy`, rodar `/graphify` no repo, copiar o script de resumo, ajustar
    `modulo()` e a tabela "Onde cada assunto mora", rodar e conferir `GRAPH_SUMMARY.md`.
12. **Skills** (8): `backlog` (com README, pasta `itens/` e CLI; fluxo do departamento em 10b), `adr-decisoes`, `api-contrato`,
    `deprecation-migration`, `performance-observabilidade`, `deploy`. Preencher as tabelas de
    ferramentas com as do projeto.
13. **Docs vivos** (11): criar `docs/{analises,relatorios,referencias,specs,plans,decisions,backlog,manual}`.
14. **MCP** (10): só os que o dono vai usar; segredos fora do arquivo versionado.
15. **`autoMode.environment`** (9.1): escrever o perímetro de confiança com o dono.
16. **Validação final**: `node ~/.claude/validar-agentes.mjs`; `grep -r "<" ~/.claude/agents ~/.claude/skills`
    sem placeholder; abrir uma sessão nova e pedir "o que você sabe deste projeto?" para conferir que
    CLAUDE.md, memória e agentes carregaram.
17. **Um mês depois**: rodar `medir-uso.mjs` (14) e cortar o que não foi usado.
