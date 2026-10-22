---
id: 4
titulo: "FPS baixo no teste com D9VK dentro do Wine"
tipo: bug
urgencia: P2
status: aberto
modulos: [wine]
criado: 2026-10-22
iniciado: null
concluido: null
commits: []
relacionados: [2]
validacao: null
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

