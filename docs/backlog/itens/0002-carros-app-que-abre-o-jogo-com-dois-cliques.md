---
id: 2
titulo: "Carros.app que abre o jogo com dois cliques"
tipo: feature
urgencia: P1
status: aberto
modulos: [app, wine]
criado: 2026-10-22
iniciado: null
concluido: null
commits: []
relacionados: [1]
validacao: null
---
## Contexto

Pedido do dono: entrar no Mac e abrir o Carros 2006 na hora, sem configurar CrossOver, Whisky nem nada. Descompilar
foi descartado (meses de trabalho); o caminho proposto é um .app com Wine + tradução D3D→Metal embutidos
(ADR 0001, Proposed). Vira feature quando a spec for aprovada.

## Como reproduzir

## Proposta

Brainstorming em andamento. Depende do resultado do #1 (DRM, API gráfica). Candidatos: Sikarugir (wrapper pronto)
ou montagem própria com builds Gcenx; camada gráfica a escolher por teste.

## Notas de execução
2026-10-22: Spike: jogo roda no Wine (Sikarugir) com área virtual + D: como CD rotulado DISC2. Ver docs/analises/2026-10-22-teste-rapido-wine.md.
2026-10-22: Spec aprovada pelo dono (docs/specs/2026-10-22-carros-app-design.md); plano em docs/plans/2026-10-22-carros-app.md.
2026-10-22: Artefatos com URL oficial e SHA-256 conferidos: Template-1.0.24.tar.xz e WS12WineSikarugir11.0_1.tar.xz (github.com/Sikarugir-App).
