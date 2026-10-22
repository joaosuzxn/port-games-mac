---
id: 2
titulo: "Carros.app que abre o jogo com dois cliques"
tipo: feature
urgencia: P1
status: feito
modulos: [app, wine]
criado: 2026-10-22
iniciado: null
concluido: 2026-10-22
commits: [68fccd2]
relacionados: [1]
validacao: ok
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
2026-10-22: Task 5: build/Carros.app montado pelo script (sem Sikarugir Creator); dono abriu, sem diálogos, ícone ok, jogou normalmente.
2026-10-22: Dono declarou o objetivo concluído: abre com dois cliques, tela cheia esticada, 30 FPS, controle funciona com layout deslocado (#6). Aceite 'do zero com --instalar' (Task 9) não executado.
