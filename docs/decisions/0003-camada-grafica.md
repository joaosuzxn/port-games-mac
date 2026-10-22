# 0003 — Camada gráfica: WineD3D (OpenGL), jogo em 1600×1200

- **Status:** Accepted
- **Data:** 2026-10-22
- **Módulo(s):** wine
- **Decisor:** dono — sessão Claude de 2026-10-22

## Contexto

Spec: alvo 60 FPS, mínimo 30 estáveis. No teste rápido e na linha de base o D9VK deu ~25 FPS com quedas (backlog #4).
Medições em docs/analises/2026-10-22-medicoes-fps.md.

## Decisão

Usar **WineD3D** (todas as chaves de renderizador do Sikarugir desligadas) e gravar no prefixo o vídeo do jogo em
1600×1200 (`Resolution`=14), MSAA 4x, efeitos ligados. Resultado: 30 FPS cravados, mínimo 29,8 — o teto de fábrica do
jogo (VSync 30Hz embutido).

## Alternativas rejeitadas

| Alternativa | Prós | Contras | Por que não |
|---|---|---|---|
| D9VK (DXVK → Vulkan → Metal) | Caminho "moderno"; funcionou no teste | ~25 FPS com quedas | Abaixo do mínimo da spec |
| D3DMetal | Metal direto | Só Direct3D 11/12 | Não cobre o D3D9 do jogo |
| Destravar 60 FPS | Mais fluido | Exige alterar dados do jogo (`.pak`); pode acelerar a física | Não-objetivo da spec |
| Manter 800×600 | Padrão do jogo | Imagem esticada mais borrada | 1600×1200 custa 0 FPS |

## Consequências

- Positivas: 30 FPS estáveis (critério 5 da spec atendido no mínimo; o alvo de 60 é inatingível sem alterar o jogo).
- Negativas: depende do OpenGL do macOS (legado, mas presente no macOS 27). Sem HUD de FPS na tela.
- Ajustes de vídeo feitos no menu do jogo ficam no prefixo dentro do app; remontar volta aos da receita.

## Referências

backlog #4 · ADR 0002 · plano Task 7
