# 0004 — Login único: o QR do app alimenta o DepotDownloader

- **Status:** Accepted
- **Data:** 2026-10-23
- **Módulo(s):** infra, app
- **Decisor:** dono — sessão Claude de 2026-10-23

## Contexto
A spec do lançador exige **no máximo um QR por máquina**, lembrado entre sessões. O app já faz login por QR na
Web API da Steam (`IAuthenticationService/BeginAuthSessionViaQR`, `platform_type=1`/SteamClient — Task 9) e
guarda o refresh token no Keychain. O download usa o DepotDownloader 3.4.0 (GPL-2.0, executável único macOS
arm64), que tem login próprio. Fazer o usuário escanear dois QRs, um para cada, viola a spec.

O que a pesquisa achou no código da tag `DepotDownloader_3.4.0`:
- Com `-remember-password`, ele guarda `nome da conta → refresh token` em `account.config`: protobuf
  (protobuf-net, `AccountSettingsStore`, campo 4 `LoginTokens`; campos 2 e 5 são outros dados), comprimido
  com `DeflateStream` cru. O arquivo fica em `~/Library/Application Support/IsolatedStorage/<h1>/<h2>/Url.<h3>/AssemFiles/`,
  e `<h3>` depende do **caminho do binário**.
- O token que ele próprio obtém é do mesmo tipo do nosso (SteamKit usa `SteamClient` por padrão) e vai direto
  como `access_token` no logon; ele não inspeciona o JWT.
- O `-qr` dele desenha o QR em ASCII no terminal, **sem** a URL em texto, e não há modo "só login".

## Decisão
O app faz o único QR e **grava o refresh token no `account.config` do DepotDownloader**; o download roda com
`-username <conta> -remember-password`.

- O DepotDownloader fica num caminho fixo (cache de artefatos do lançador, conferido por SHA-256), para o
  `Url.<hash>` não mudar.
- O arquivo do store é localizado depois de uma execução do binário (ou procurando `account.config` sob
  `IsolatedStorage`), nunca adivinhando o hash.
- Escrita: ler o que existe, mesclar só o campo 4 (preservando 2 e 5), comprimir e trocar por rename; só com o
  DepotDownloader parado.
- Token rejeitado ("Access token was rejected", saída ≠ 0): o app trata como sessão inválida da Task 9 (novo QR).

## Alternativas rejeitadas
| Alternativa | Prós | Contras | Por que não |
|---|---|---|---|
| `-qr` do próprio DepotDownloader como login único | Sem formato privado para escrever | Só QR ASCII no terminal, sem URL; exige `-app` (não há "só login"); o app teria de decodificar arte ASCII | Não dá para mostrar na interface gráfica de forma confiável |
| Fork GPL-2.0 com opção `-token` (ou stdin) | Interface explícita, sem depender do store | Compilar com SDK do .NET; mais uma ferramenta para manter a cada versão | Trabalho e manutenção maiores para um projeto pessoal |
| Embutir SteamKit2 num downloader próprio | Um store só, controle total | Reimplementar o download de depots (.NET ou porta para Swift) | Fora de escala agora |

## Consequências
- Positivas: um QR, interface nossa (Task 9 pronta), o DepotDownloader continua um binário oficial sem patch.
- Negativas / dívidas:
  - Dependemos de um formato interno (estável desde a 3.x, sem campo de versão). Atualizar o DepotDownloader
    exige rodar o teste de integração do store antes de trocar o SHA-256 fixado.
  - Não verificado com login real: aceitação do token do QR pelo logon do DepotDownloader e pela
    `GetOwnedGames` — primeiro passo do teste com o dono (Task 9 Step 5 e Task 10 Step 5).
  - SHA-256 do zip não tem fonte oficial (release sem checksum): fixado no primeiro download (TOFU).

## Referências
- Spec: `docs/specs/2026-10-22-lancador-design.md` (critério "um QR por máquina").
- Plano: `docs/plans/2026-10-22-launcher-core.md`, Task 10 Step 0.
- Fontes: github.com/SteamRE/DepotDownloader tag `DepotDownloader_3.4.0` (`AccountSettingsStore.cs`,
  `Steam3Session.cs`, `ContentDownloader.cs`, `Program.cs`); SteamKit `SteamUser.cs` (logon com `AccessToken`).
