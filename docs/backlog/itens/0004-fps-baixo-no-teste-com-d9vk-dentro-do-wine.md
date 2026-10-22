---
id: 4
titulo: "FPS baixo no teste com D9VK dentro do Wine"
tipo: bug
urgencia: P2
status: feito
modulos: [wine]
criado: 2026-10-22
iniciado: null
concluido: 2026-10-22
commits: [90778b0]
relacionados: [2]
validacao: pendente
---
## Contexto

No spike (CarrosTeste.app, D9VK, área virtual 1280x720, Debug Mode e WINEDEBUG ligados) o jogo roda, mas o dono achou o FPS bem baixo.

## Como reproduzir

1. Abrir ~/Applications/Sikarugir/CarrosTeste.app.
2. Passar pelos vídeos e entrar numa corrida.
3. Observar a fluidez (FPS baixo).

## Proposta

Medir FPS (METAL_HUD) e comparar uma variável por vez: sem log de depuração, WineD3D, D3DMetal, resolução da área virtual.

## Notas de execução
2026-10-22: WineD3D: 30 FPS cravados (teto do jogo, VSync 30Hz embutido), mínimo 29,8, também em 1600x1200. ADR 0003.
