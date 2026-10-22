---
id: 1
titulo: "Baixar os arquivos Windows do Carros (App 331160) e inspecionar o executável"
tipo: tarefa
urgencia: P1
status: em-andamento
modulos: [jogo, infra]
criado: 2026-10-22
iniciado: 2026-10-22
concluido: null
commits: []
relacionados: []
validacao: null
---
## Contexto

Antes de escolher a camada gráfica e a ferramenta de empacotamento, é preciso ver o jogo de verdade. A pesquisa
(docs/analises/2026-10-22-pesquisa-carros-mac.md) não confirmou DRM, API gráfica nem compatibilidade com Wine.

## Como reproduzir

## Proposta

1. Instalar `steamcmd` (cask Intel, Rosetta 2) — com aprovação do dono.
2. Dono roda o login: `steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$PWD/jogo" +login <conta> +app_update 331160 validate +quit`.
3. Inspecionar: nome do .exe, 32/64 bits (`file`), Direct3D 8 ou 9 (`strings`), SteamStub (seção `.bind`, `steam_api.dll`), vídeos, tamanho.
4. Registrar o resultado em docs/analises e fechar o item.

## Notas de execução
2026-10-22: Download completo (1,1 GB). 32 bits, D3D9, DirectSound, DInput8, Bink. Cars.exe tem SteamStub; bak/Cars.exe é o mesmo build sem DRM. Ver docs/analises/2026-10-22-inspecao-executavel.md.
