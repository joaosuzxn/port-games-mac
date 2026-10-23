---
id: 14
titulo: "Login Steam: renovar o access token sem novo QR (Web API recusa token SteamClient: EResult 63/15)"
tipo: bug
urgencia: P1
status: aberto
modulos: [app, infra]
criado: 2026-10-23
iniciado: null
concluido: null
commits: []
relacionados: [8, 9]
validacao: null
---
## Contexto
O login por QR (`platform_type=1`, SteamClient) dá um access token de ~24 h (`aud=client,web`) e um refresh token
até 2027 (`aud=client,web,renew,derive`). Renovar o access token pela Web API
(`IAuthenticationService/GenerateAccessTokenForApp`) foi recusado na hora, com o refresh token novo e válido:
EResult 63 (`AccountLogonDenied`) e depois 15 (`AccessDenied`) — `PortGames/logs/steam-api.log`, 2026-10-23.
Paliativo já feito (30743c6): usa o access token do login enquanto vale; recusa pede novo login sem apagar nada.
Efeito hoje: depois de ~24 h, `library`/`install` pedem QR de novo.

## Como reproduzir
1. `launcherctl login` (QR). 2. Esperar o access token vencer (ou apagar só ele). 3. `launcherctl library`.

## Proposta
Hipótese (não verificada, lembrança da lib `steam-session`): tokens SteamClient só se renovam por conexão CM
(WebSocket), não pela Web API. Alternativas a decidir (ADR):
- renovar por conexão CM (implementar o mínimo do protocolo, ou usar o DepotDownloader/SteamKit para isso);
- QR com `platform_type=2` (WebBrowser) para a Web API e outro caminho para o DepotDownloader (fere "um QR");
- ler a biblioteca da conta sem Web API (dados locais da Steam do Mac logada).
Antes de escolher: testar `input_protobuf_encoded` e `renewal_type` no `GenerateAccessTokenForApp`.

## Notas de execução

