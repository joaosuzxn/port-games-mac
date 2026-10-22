# 0001 — Caminho do port: .app com camada de tradução, não descompilação

- **Status:** Proposed
- **Data:** 2026-10-22
- **Módulo(s):** app, wine
- **Decisor:** dono — sessão Claude de 2026-10-22

## Contexto

O dono quer jogar o Carros 2006 (Steam 331160, só Windows) no Mac Apple Silicon "na hora", sem configurar
CrossOver ou Whisky. O que incomoda é a configuração, não a tecnologia por baixo. O código-fonte nunca foi liberado.

## Decisão

Empacotar o jogo original num `Carros.app` autônomo com Wine + tradução Direct3D→Metal embutidos, iniciando o
`.exe` direto. A ferramenta (Sikarugir ou montagem própria) e a camada gráfica serão escolhidas em ADRs próprios,
depois de inspecionar o executável (backlog #1).

## Alternativas rejeitadas

| Alternativa | Prós | Contras | Por que não |
|---|---|---|---|
| Descompilar e recompilar para arm64/Metal | Nativo de verdade, sem Wine/Rosetta | 6–18 meses mesmo com IA; reescrever gráficos, som, input; risco alto de não terminar | O objetivo é jogar, não o desafio |
| Usar CrossOver/Whisky direto | Zero trabalho de empacotamento | Exige abrir e configurar o programa; Whisky descontinuado | É exatamente o que o dono não quer |

## Consequências

- Positivas: entrega em horas/dias; o jogo roda sem modificação.
- Negativas: depende de Rosetta 2 (o x86 é traduzido); depende de manter o Wine empacotado funcionando em
  atualizações do macOS.
- Fica aberto: confirmar DRM e API gráfica (#1); spec da feature (#2).

## Referências

docs/analises/2026-10-22-pesquisa-carros-mac.md · backlog #1, #2
