---
id: 6
titulo: "Botões do controle deslocados (PS5) e L2/R2 viram câmera"
tipo: bug
urgencia: P2
status: aberto
modulos: [wine, jogo]
criado: 2026-10-22
iniciado: null
concluido: null
commits: []
relacionados: [2]
validacao: null
---
## Contexto

Controle DualSense (PS5). O jogo espera o controle do Xbox original: tabela interna A=0, B=1, X=2, Y=3, Preto=4,
Branco=5, LT=6, RT=7, Start=12, Back=13 (Cars.exe ~0x36fa00); esquemas em `UI.pak` → `data\UI\controller_presets_xbox.txt`
(esquema 1: acelerar A, frear X, turbo Preto, câmera Branco). O registro só guarda Device/Preset/GamePadID — não há
mapeamento por botão. Wine (winebus SDL, Map Controllers=1) entrega o controle no padrão Xbox moderno.

## Como reproduzir

1. Abrir Carros.app com um DualSense conectado.
2. Na corrida: ○ acelera e ✕ freia (esperado no esquema 1: ✕ acelera, □ freia).
3. L2/R2 movem a câmera como o analógico direito (deveriam ser gatilhos).

## Proposta

Medir os índices DInput reais no `joy.cpl` (abrir no app: Program Name `/windows/system32/control.exe`, Flags `joy.cpl`)
para todos os botões; comparar com o que o jogo espera. Hipótese: o jogo usa numeração de pad genérico de PC
(1=esquerda, 2=baixo, 3=direita, 4=cima) e gatilhos como botões/eixo Z. Caminhos: Map Controllers=0, mapeamento SDL
(SDL_GAMECONTROLLERCONFIG), mapeamento de eixos do dinput do Wine. Sem alterar o executável.

## Notas de execução

