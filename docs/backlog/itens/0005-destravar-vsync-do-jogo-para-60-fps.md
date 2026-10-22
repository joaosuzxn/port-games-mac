---
id: 5
titulo: "Destravar VSync do jogo para 60 FPS"
tipo: melhoria
urgencia: P1
status: descartado
modulos: [jogo, wine]
criado: 2026-10-22
iniciado: null
concluido: null
commits: []
relacionados: [4, 2]
validacao: null
---
## Contexto

Pedido do dono (2026-10-22): mudar o limite de VSync de 30 para 60 FPS. Hoje o jogo roda cravado em 30 (VSync 30Hz embutido nos dados, não no registro; ver docs/analises/2026-10-22-medicoes-fps.md). Antes era não-objetivo (alterar dados do jogo); agora é decisão do dono. Risco: física/velocidade presa ao FPS.

## Como reproduzir

## Proposta

Preferência: (1) arquivo de configuração solto dentro do app (ResourceFileOverride?), (2) forçar pela camada gráfica, (3) cópia editada do .pak dentro do app. Nunca alterar jogo/. Validar velocidade do jogo com o dono. ADR supersede parcial do 0003.

## Notas de execução
2026-10-22: Config.txt do misc.pak não é aplicado pelo executável final; só daria trocando 4 bytes numa cópia do Cars.exe. Dono decidiu manter 30 FPS e não modificar o executável. Detalhes em docs/analises/2026-10-22-medicoes-fps.md.
