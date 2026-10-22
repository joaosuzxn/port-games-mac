# 0002 — Tela cheia: emulação de troca de resolução (EmulateModeset), sem área virtual

- **Status:** Accepted
- **Data:** 2026-10-22
- **Módulo(s):** wine, app
- **Decisor:** dono — sessão Claude de 2026-10-22

## Contexto

O Carros 2006 só oferece resoluções 4:3/5:4 (640×480 a 1600×1200) e começa em 800×600 em tela cheia exclusiva. No
macOS (driver winemac) a troca de resolução é recusada (`ChangeDisplaySettings` → -2) e o jogo quebra ao criar o
device. O teste rápido contornou com a área de trabalho virtual do Wine, mas ela abre numa janela: com 1280×720 ou
mesmo com o tamanho exato da tela (1470×956 pontos), o jogo encolhe a área para 800×600 ao trocar de modo. O dono quer
tela cheia, imagem esticada.

## Decisão

Ligar a emulação de troca de resolução do win32u do Wine 11 (`HKCU\Software\Wine\X11 Driver "EmulateModeset"="y"`; o
nome da chave é histórico, a opção vale para todos os drivers) e **não** usar área de trabalho virtual. O jogo "troca"
para 800×600, a janela continua em tela cheia na resolução real e a imagem é escalada (esticada) para preencher.
Verificado pelo dono: abre direto em tela cheia, esticado, vídeos/menu/corrida normais.

## Alternativas rejeitadas

| Alternativa | Prós | Contras | Por que não |
|---|---|---|---|
| Área virtual 1280×720 (teste rápido) | Provada contra o crash | Janela, não tela cheia | Fere o objetivo de tela cheia |
| Área virtual do tamanho da tela (1470×956) | Sem bordas quando cobre a tela | O jogo encolhe a área para 800×600 ao trocar de modo; tamanho fixo na montagem quebra com monitor diferente | Testado: abre em 800×600 |
| Patchear o jogo para modo janela | Controle total | Altera o executável (não-objetivo da spec) | Fora do escopo |

## Consequências

- Positivas: tela cheia em qualquer monitor, sem tamanho fixo na montagem (cobre o item do Review Focus sobre monitor externo).
- Negativas: depende de um recurso do Wine ≥ 10; se a engine mudar, reverificar.
- O desempenho (FPS) é tratado no backlog #4 / ADR 0003.

## Referências

docs/analises/2026-10-22-teste-rapido-wine.md · plano docs/plans/2026-10-22-carros-app.md (Task 6) · backlog #2
