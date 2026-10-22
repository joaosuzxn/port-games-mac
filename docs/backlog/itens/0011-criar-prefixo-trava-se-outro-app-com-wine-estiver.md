---
id: 11
titulo: "Criar prefixo trava se outro app com Wine estiver aberto"
tipo: bug
urgencia: P3
status: aberto
modulos: [wine, infra]
criado: 2026-10-22
iniciado: null
concluido: null
commits: []
relacionados: [7, 8]
validacao: null
---
## Contexto

`build.py carros-steam` estourou o limite de 300 s em `create_prefix` com o Spacewar.app (outro bundle Sikarugir) rodando; sem ele, 66 s.

## Como reproduzir

1. Abrir build/Spacewar.app.
2. Rodar `python3 tools/builder/build.py carros-steam`.
3. Etapa do prefixo estoura 300 s.

## Proposta

## Notas de execução

