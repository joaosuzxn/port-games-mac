# Carros.app — desenho

- **Data:** 2026-10-22
- **Backlog:** #2 (este desenho), #4 (FPS baixo), #3 (generalizar — fora deste escopo)
- **Base:** docs/analises/2026-10-22-pesquisa-carros-mac.md, 2026-10-22-inspecao-executavel.md, 2026-10-22-teste-rapido-wine.md
- **Decisão de caminho:** ADR 0001 (app com camada de tradução, não descompilação)

## Intenção

O dono comprou o Disney•Pixar Cars (2006, Steam App 331160), que só existe para Windows. Ele quer abrir o jogo no
Mac (Apple M5, macOS 27, tela 2560×1664 Retina) como qualquer app: dois cliques no `Carros.app` em Aplicativos,
o jogo abre em tela cheia e ele joga com um controle. O que o incomoda nas soluções existentes (CrossOver, Whisky)
é ter de instalar e configurar uma ferramenta — não a tecnologia por baixo. Wine dentro do app é aceito.

## Objetivos

1. **Um único `Carros.app`** autocontido: Wine, camada gráfica, bibliotecas, prefixo Windows e arquivos do jogo
   dentro do bundle. Funciona em `/Applications` sem nada mais instalado (nem Sikarugir, nem Wine, nem Steam).
2. **Dois cliques → jogo.** Sem janela de configuração, sem diálogo de CD, sem Steam. Abre direto nos vídeos de abertura.
3. **Tela cheia** ocupando a tela inteira. Se o jogo não oferecer a proporção 16:10 da tela, a imagem é **esticada**
   para preencher (decisão do dono), sem faixas pretas.
4. **Controle** funcionando além do teclado, cobrindo a maior gama possível de controles, por USB **e** Bluetooth
   (decisão do dono): no mínimo Xbox (One/Series), PlayStation (DualShock 4 e DualSense), Nintendo Switch Pro,
   8BitDo e genéricos reconhecidos pelo SDL. Mesmo layout lógico em todos (botões na posição do Xbox), sem o dono
   configurar nada; o controle conectado com o jogo já aberto também deve funcionar.
5. **Fluidez**: corrida com FPS estável — alvo 60 FPS, mínimo aceitável 30 FPS sem engasgos (item #4).
6. **Saves fora do app**, em `~/Documents/THQ/Cars/Save`, sobrevivendo a remontar ou apagar o app.
7. **Remontável com um comando**: um script do repositório monta o `Carros.app` do zero a partir dos arquivos do jogo
   em `jogo/` (baixados pelo dono com steamcmd) — para refazer depois de atualização do macOS ou em outro Mac.

## Não-objetivos

- Descompilar, modificar ou "crackear" o executável do jogo.
- Distribuir o app ou os arquivos do jogo para outras pessoas (jogo proprietário; uso pessoal).
- Ferramenta genérica para vários jogos (#3). O script deve ser escrito de forma que o específico do Carros fique
  separado (uma "receita"), mas sem construir catálogo, interface ou suporte a outros jogos agora.
- Integração com o cliente Steam (conquistas, nuvem): o jogo não usa.

## Antiobjetivos (fracasso mesmo funcionando)

- Abrir qualquer janela de configuração (Configure do Sikarugir, winecfg) no uso normal.
- Exigir que o dono mexa em Wine, registro, terminal ou instale algo para jogar.
- Perder saves ao remontar o app.
- Precisar do Sikarugir Creator instalado para montar ou para jogar.

## Restrições e fatos provados no teste rápido

| Fato | Consequência obrigatória |
|---|---|
| `Cars.exe` da Steam tem SteamStub; `bak/Cars.exe` é o mesmo build sem DRM | Usar `bak/Cars.exe` como executável do jogo dentro do app |
| `bak/Cars.exe` exige drive tipo CD com rótulo de volume `DISC2` | Drive `D:` = pasta do jogo, tipo `cdrom` no registro, `.windows-label` = `DISC2` |
| Troca de resolução em tela cheia é recusada pelo macOS e o jogo quebra | Rodar na área de trabalho virtual do Wine; para tela cheia, área virtual do tamanho da tela |
| 32 bits, Direct3D 9, DirectSound, DirectInput 8, Bink | Wine com WoW64; camada D3D9 (D9VK funcionou; WineD3D criou o device) |
| Funcionou: wrapper Sikarugir template 1.0.24 + engine WS12WineSikarugir 11.0_1 + D9VK | Ponto de partida conhecido-bom |
| A janela Configure regrava o `Info.plist` | O app final não deve expor nem depender dela |
| Editar `system.reg`/`user.reg` com o wineserver vivo é perdido | O script só mexe no prefixo com o Wine parado (ou via `wine reg`) |
| Pastas desnecessárias: `_jvm`, `_uninst`, `_CommonRedist`, `steamapps`, `Cars.exe` com DRM | Não entram no app |

## O que o dono decidiu

- Caminho: app com Wine embutido (ADR 0001).
- Só o `Carros.app` instalado; Wine dentro dele é aceito.
- Tela cheia, imagem esticada se a proporção não bater.
- Jogar com controle; cobrir a maior gama de controles, por USB e Bluetooth.
- O Claude commita em branch; merge na `main` após o ok do dono.

## Decisões do Claude (o dono pode contestar)

- **Montagem por script próprio**, sem a interface do Sikarugir: baixa template de wrapper e engine Wine em versões
  fixadas (as mesmas do teste: template 1.0.24, WS12WineSikarugir 11.0_1) das publicações oficiais do Sikarugir/Gcenx,
  com checagem de integridade, para uma pasta de cache fora do git. Ferramentas usadas só pelo script de montagem
  (curl, tar, PlistBuddy) já vêm no macOS.
- **Separação receita × motor**: o que é do Carros (executável, rótulo `DISC2`, pastas a excluir, ícone, camada
  gráfica, chaves de registro) fica num arquivo de receita; o resto do script não conhece o Carros.
- **Saves**: manter o comportamento do teste (Documents do Windows → `~/Documents` do Mac).
- **Ícone**: extraído do próprio `Cars.exe` (recurso de ícone) e convertido para `.icns`.
- **Nome e identificador**: `Carros.app`, bundle id próprio estável (ex.: `local.portcarros.carros`).

## Fatos de partida (verificados em 2026-10-22)

- `jogo/` existe com a árvore completa (steamcmd, buildid 454676, `StateFlags 4`, 1,1 GB).
  `bak/Cars.exe` SHA-1 `a175e49a8cd3aa67ffd71b7cf1a8d0c90b527902`; `Cars.exe` (com SteamStub) SHA-1
  `d4a2f16e033ef096607404509efd5d3540eabf8e`. O script deve conferir o hash do `bak/Cars.exe` e parar se não bater.
  Não há SafeDisc nem outro arquivo de disco: a única exigência é o rótulo `DISC2` (ver análise do teste).
- Os artefatos que funcionaram já estão no cache local do Sikarugir:
  `~/Library/Application Support/Sikarugir/Template/Template-1.0.24.app` e
  `~/Library/Application Support/Sikarugir/Engines/WS12WineSikarugir11.0_1.tar.xz`
  (SHA-256 `67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e`).
- O wrapper testado já carrega **dentro do bundle** tudo de que o D9VK precisa: `Frameworks/libvulkan*.dylib`,
  `Frameworks/libvulkan_kosmickrisp.dylib` (driver Vulkan sobre Metal), `libMoltenVK.dylib`, e as DLLs do D9VK em
  `SharedSupport/renderer/d9vk`. Nada disso depende do Sikarugir instalado.

## Decisões do Claude após a revisão (o dono pode contestar)

- **Origem dos artefatos**: primeira task do plano localiza as URLs oficiais e hashes do template 1.0.24 e da engine
  11.0_1. Se não houver URL estável, o script usa uma cópia guardada em cache local do projeto (fora do git),
  semeada a partir do cache do Sikarugir acima, conferida por SHA-256. "Do zero" (aceite 7) passa a significar
  "do cache de artefatos do projeto", não da internet.
- **Base do bundle**: reaproveitar o template do Sikarugir (launcher + `Info.plist`), configurado pelo script;
  o `Configure.app` é removido do bundle final.
- **Prefixo dentro do bundle**, gravável em execução (como no teste). Drive `D:`, tipo `cdrom` e `.windows-label`
  ficam gravados no prefixo na montagem — não são recriados a cada abertura. O app é assinado ad hoc e sem
  quarentena ao final da montagem; alteração posterior do prefixo não impede a abertura local.
- **Saves**: em vez de ligar a pasta Documentos inteira do Mac, o prefixo liga só `Documents/THQ` →
  `~/Documents/THQ` (menos exposição). Saves existentes ali são preservados; o script nunca apaga essa pasta.
- **Regra de parada do FPS**: se nenhuma combinação (camadas gráficas, log desligado, resolução) chegar a 30 FPS
  estáveis, parar e voltar ao dono com as medições antes de mudar de abordagem. Medição com o HUD do Metal
  (`MTL_HUD_ENABLED`) e/ou `DXVK_HUD=fps`.

## Deixado para quem constrói

- Camada gráfica final e ajustes de desempenho, escolhidos por medição (item #4): D9VK vs WineD3D vs D3DMetal (se
  cobrir D3D9), log de depuração desligado, resolução da área virtual (nativa 2560×1664 vs metade em Retina), opções
  do DXVK/vsync. Registrar a escolha num ADR.
- Como obter tela cheia sem bordas (área virtual do tamanho da tela + janela em tela cheia do macOS, ou outra opção
  da engine) desde que satisfaça "dois cliques → tela cheia".
- Mapeamento do controle (SDL/HID do Wine para DirectInput 8) e eventuais ajustes; testar com o controle do dono.
- Onde fica o cache de downloads, estrutura de pastas do script, linguagem do script (zsh ou Python 3 do sistema).
- Assinatura ad hoc / remoção de quarentena para o app abrir sem aviso do Gatekeeper no próprio Mac.
- Como verificar automaticamente o que for verificável (estrutura do bundle, plist, registro, rótulo) e quais
  verificações dependem do dono olhando a tela.

## Critérios de aceite

1. Com o Sikarugir desinstalado (ou ausente), `Carros.app` em `/Applications` abre com dois cliques direto nos vídeos.
2. Nenhum diálogo de CD, de erro ou de configuração.
3. Tela cheia, sem bordas de janela, imagem esticada sem faixas pretas.
4. Controle funciona no menu e na corrida, por USB e Bluetooth (testar ao menos o controle do dono; demais modelos pela cobertura do SDL).
5. Corrida a ≥ 30 FPS estáveis (alvo 60), medido com HUD.
6. Saves persistem após apagar e remontar o app.
7. `script de montagem` roda do zero (cache vazio) e gera um app equivalente.
8. Validado pelo dono jogando (backlog `validacao=ok`).
