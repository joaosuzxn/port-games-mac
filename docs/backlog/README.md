# Backlog de desenvolvimento

Um arquivo por item em `itens/NNNN-slug.md`. `BACKLOG.md` é gerado — nunca editar à mão.
Operar pela CLI (`node tools/backlog/backlog.mjs <cmd>`); editar o arquivo à mão só para escrever
Contexto, Como reproduzir e Proposta.

## Campos do cabeçalho

| Campo | Valores | Regra |
|---|---|---|
| id | inteiro | igual ao prefixo do nome; sequencial, nunca reaproveitado |
| titulo | uma linha | obrigatório; vira o slug do arquivo |
| tipo | bug, melhoria, ideia, feature, tarefa | bug: deveria funcionar e não funciona · melhoria: funciona, pode ficar melhor · ideia: ainda não decidido · feature: novo e aprovado · tarefa: infra, pesquisa, docs |
| urgencia | P0, P1, P2, P3 | P0 agora (algo que funcionava quebrou) · P1 esta semana · P2 próximo ciclo · P3 quando der |
| status | aberto, em-andamento, feito, descartado | feito exige `concluido`; descartado exige nota com o motivo |
| modulos | jogo, wine, app, docs, infra | ao menos um |
| criado / iniciado / concluido | AAAA-MM-DD | a CLI preenche iniciado e concluido |
| commits | [sha, ...] | `set N commits=+sha` acrescenta |
| relacionados | [ids] | opcional |
| validacao | pendente, ok | o dono testou o jogo rodando? `pendente` = entregue sem ele testar; `ok` = testou |

## Corpo

Exatamente estas seções, nesta ordem: `## Contexto`, `## Como reproduzir` (obrigatória em bug),
`## Proposta`, `## Notas de execução` (uma linha por data; `set N nota=...` acrescenta).

## Comandos

    node tools/backlog/backlog.mjs new --tipo bug --urgencia P1 --modulos wine --titulo "..."
    node tools/backlog/backlog.mjs set 12 status=em-andamento
    node tools/backlog/backlog.mjs set 12 status=feito commits=+abc1234 validacao=pendente
    node tools/backlog/backlog.mjs set 12 validacao=ok nota="Dono testou o jogo."
    node tools/backlog/backlog.mjs list --status aberto --modulo wine
    node tools/backlog/backlog.mjs next
    node tools/backlog/backlog.mjs board
    node tools/backlog/backlog.mjs check

## Regras de sessão

1. Entrega que resolve um item termina com `set <id> status=feito commits=...`.
2. Bug ou ideia encontrada no caminho vira item na hora.
3. `check` antes de commitar itens; a CLI regenera o quadro sozinha.
4. Entrega que o dono ainda não testou fecha com `validacao=pendente`.
