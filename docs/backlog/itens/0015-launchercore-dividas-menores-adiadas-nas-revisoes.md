---
id: 15
titulo: "LauncherCore: dívidas menores adiadas nas revisões (ver docs/analises/2026-10-23-launcher-core-decisoes.md)"
tipo: bug
urgencia: P3
status: aberto
modulos: [app, infra]
criado: 2026-10-23
iniciado: null
concluido: null
commits: []
relacionados: [8, 9, 14]
validacao: null
---
## Contexto
As revisões por task e a revisão final do LauncherCore (#8) acharam 52 itens menores que ficaram para depois
(robustez com entrada corrompida, processos órfãos, casos de borda, testes). Lista agrupada e graduada por efeito em
`docs/analises/2026-10-23-launcher-core-decisoes.md`, seção "Dívidas adiadas".

## Como reproduzir

## Proposta
Antes do app SwiftUI (#9), resolver os que ele vai bater: extração/`codesign` fora do pool de threads, `stop()`
depois de `wait()`, conta sem jogos, `account-store.path` fora de `tools/`, `LaunchEntry` completo (3º jogo).

## Notas de execução

