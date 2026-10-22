---
name: adr-decisoes
description: "Use ao tomar ou registrar uma decisão no port do Carros com alternativas reais (caminho do port, camada gráfica D3DMetal vs DXVK vs WineD3D, ferramenta de empacotamento, como baixar o jogo, como contornar DRM) — cria ADR em docs/decisions/ com contexto, decisão, alternativas rejeitadas e consequências, e atualiza a memória."
---

# ADRs — Port do Carros

Código mostra **o quê**; o ADR guarda **o porquê** e **o que foi rejeitado**. Quem mais lê são as
próximas sessões do Claude.

## Quando usar

- Escolha entre abordagens com impacto além de um arquivo: caminho do port, camada gráfica, ferramenta
  de empacotamento, versão do Wine, tratamento de DRM.
- Toda vez que o brainstorming fechar um desenho com "decisão do dono".
- **Não** para: ajuste pontual, escolha óbvia sem alternativa real.

## Onde e como

- `docs/decisions/NNNN-slug-curto.md`, numeração sequencial global, nunca reiniciar.
- Um ADR por decisão. **Nunca reescrever** um ADR aceito: superseder com outro (`Status: Superseded by 0007`).
- A memória do projeto recebe o link.

## Template

    # NNNN — Título curto da decisão

    - **Status:** Proposed | Accepted | Superseded by NNNN | Deprecated
    - **Data:** AAAA-MM-DD
    - **Módulo(s):** jogo | wine | app | docs | infra
    - **Decisor:** dono — sessão Claude de AAAA-MM-DD

    ## Contexto
    O problema real, com números quando houver (FPS, tempo de boot, tamanho do .app).

    ## Decisão
    O que foi escolhido, em uma frase. Depois o desenho essencial.

    ## Alternativas rejeitadas
    | Alternativa | Prós | Contras | Por que não |
    |---|---|---|---|

    ## Consequências
    - Positivas
    - Negativas / dívidas assumidas (com item do backlog)

    ## Referências
    Spec, plano, commits, pesquisa em docs/analises.

## Processo

1. Verificar se já existe ADR sobre o tema. Se existir, superseder.
2. Escrever **antes** de implementar quando a decisão vem do brainstorming; logo após, quando nasce na implementação.
3. Listar ao menos uma alternativa real com o motivo da rejeição.
4. Consequências e dívidas — o que fica pendente vira item no backlog.
5. Atualizar a memória.

## Red flags

- Decisão relevante só no chat ou na memória.
- Alternativa rejeitada sem motivo escrito.
- ADR editado retroativamente em vez de superseder.

## Verificação

- [ ] ADR em `docs/decisions/` com numeração sequencial.
- [ ] Alternativas rejeitadas com motivo.
- [ ] Consequências e dívidas registradas, com item do backlog quando couber.
- [ ] Memória atualizada.
