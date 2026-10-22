// CLI do backlog do port do Carros. Node puro, sem dependências.
// Uso: node tools/backlog/backlog.mjs <new|set|list|next|board|check> [...]
// Regras dos campos em docs/backlog/README.md.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const dirItens = path.join(raiz, 'docs', 'backlog', 'itens');
const arqQuadro = path.join(raiz, 'docs', 'backlog', 'BACKLOG.md');

const TIPOS = ['bug', 'melhoria', 'ideia', 'feature', 'tarefa'];
const URGENCIAS = ['P0', 'P1', 'P2', 'P3'];
const STATUS = ['aberto', 'em-andamento', 'feito', 'descartado'];
const VALIDACOES = [null, 'pendente', 'ok'];
const MODULOS = ['jogo', 'wine', 'app', 'docs', 'infra'];
const CAMPOS = ['id', 'titulo', 'tipo', 'urgencia', 'status', 'modulos', 'criado', 'iniciado', 'concluido', 'commits', 'relacionados', 'validacao'];
const LISTAS = new Set(['modulos', 'commits', 'relacionados']);
const SECOES = ['## Contexto', '## Como reproduzir', '## Proposta', '## Notas de execução'];

const hoje = () => new Date().toLocaleDateString('sv-SE');
const falhar = (msg) => { console.error(msg); process.exit(1); };

// --- frontmatter (subconjunto de YAML: escalar, "string", null, [a, b]) ---------
function lerValor(bruto) {
  const s = bruto.trim();
  if (s === '' || s === 'null') return null;
  if (s.startsWith('[')) {
    return s.slice(1, -1).split(',').map((x) => x.trim()).filter(Boolean)
      .map((x) => (x.startsWith('"') ? JSON.parse(x) : x));
  }
  if (s.startsWith('"')) return JSON.parse(s);
  return s;
}

function escreverValor(chave, v) {
  if (v === null || v === undefined) return 'null';
  if (Array.isArray(v)) return '[' + v.map((x) => (/^[\w.-]+$/.test(String(x)) ? x : JSON.stringify(String(x)))).join(', ') + ']';
  if (chave === 'titulo') return JSON.stringify(v);
  return /^[\w.-]+$/.test(String(v)) ? String(v) : JSON.stringify(String(v));
}

function lerItens() {
  if (!fs.existsSync(dirItens)) return [];
  return fs.readdirSync(dirItens).filter((f) => /^\d{4}-.*\.md$/.test(f)).sort().map((arquivo) => {
    const txt = fs.readFileSync(path.join(dirItens, arquivo), 'utf8');
    const m = txt.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
    if (!m) falhar(`${arquivo}: sem frontmatter`);
    const item = { arquivo, corpo: m[2] };
    for (const linha of m[1].split('\n')) {
      const c = linha.match(/^(\w+):\s*(.*)$/);
      if (c) item[c[1]] = lerValor(c[2]);
    }
    item.id = Number(item.id);
    return item;
  });
}

function gravar(item) {
  const fm = CAMPOS.map((c) => `${c}: ${escreverValor(c, item[c])}`).join('\n');
  fs.writeFileSync(path.join(dirItens, item.arquivo), `---\n${fm}\n---\n${item.corpo}`, 'utf8');
}

const slug = (t) => t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
  .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 50).replace(/-$/, '');

const diasDesde = (data) => Math.max(0, Math.round((Date.now() - new Date(data + 'T00:00:00')) / 86400e3));

function linha(it) {
  const base = `#${it.id} · ${it.tipo} · ${it.urgencia} · ${(it.modulos ?? []).join(', ')} · ${it.titulo}`;
  if (it.status === 'em-andamento') return `${base} · em andamento desde ${it.iniciado}`;
  if (it.status === 'feito') return `${base} · feito em ${it.concluido}${it.commits?.length ? ' · ' + it.commits.join(', ') : ''}`;
  return `${base} · há ${diasDesde(it.criado)} dias`;
}

const ativos = (itens) => itens.filter((i) => i.status === 'aberto' || i.status === 'em-andamento');
const aguardando = (itens) => itens.filter((i) => i.status === 'feito' && i.validacao === 'pendente');
const porUrgencia = (a, b) => URGENCIAS.indexOf(a.urgencia) - URGENCIAS.indexOf(b.urgencia) || a.id - b.id;

// --- comandos ---------------------------------------------------------------------
function quadro(itens = lerItens()) {
  const L = ['# Backlog — Port do Carros', '', `> Gerado por \`backlog board\` em ${hoje()}. Não editar à mão: edite os itens em \`itens/\` e gere de novo.`, ''];
  const secao = (titulo, lista) => {
    L.push(`## ${titulo}`);
    L.push(...(lista.length ? lista.map((i) => `- ${linha(i)}`) : ['- (vazio)']));
    L.push('');
  };
  const a = ativos(itens).sort((x, y) => x.id - y.id);
  secao('Agora', a.filter((i) => i.urgencia === 'P0' || i.urgencia === 'P1'));
  secao('Próximo ciclo', a.filter((i) => i.urgencia === 'P2'));
  secao('Quando der', a.filter((i) => i.urgencia === 'P3'));
  secao('Aguardando o dono testar', aguardando(itens));
  fs.writeFileSync(arqQuadro, L.join('\n'), 'utf8');
}

function opcoes(args) {
  const o = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) o[args[i].slice(2)] = args[i + 1] ?? '', i++;
  }
  return o;
}

function cmdNew(args) {
  const o = opcoes(args);
  for (const c of ['titulo', 'tipo', 'urgencia', 'modulos']) if (!o[c]) falhar(`new: falta --${c}`);
  const itens = lerItens();
  const id = Math.max(0, ...itens.map((i) => i.id)) + 1;
  const item = {
    id, titulo: o.titulo, tipo: o.tipo, urgencia: o.urgencia, status: 'aberto',
    modulos: o.modulos.split(',').map((x) => x.trim()), criado: hoje(), iniciado: null, concluido: null,
    commits: [], relacionados: o.relacionados ? o.relacionados.split(',').map((x) => x.trim()) : [], validacao: null,
    arquivo: `${String(id).padStart(4, '0')}-${slug(o.titulo)}.md`,
    corpo: SECOES.map((s) => `${s}\n\n`).join(''),
  };
  const erros = validar(item, false);
  if (erros.length) falhar(`new: ${erros.join('; ')}`);
  gravar(item);
  quadro();
  console.log(`#${id} · docs/backlog/itens/${item.arquivo}`);
}

function cmdSet(args) {
  const [idTxt, ...pares] = args;
  const itens = lerItens();
  const item = itens.find((i) => i.id === Number(idTxt));
  if (!item) falhar(`set: item #${idTxt} não existe`);
  for (const par of pares) {
    const k = par.indexOf('=');
    if (k < 1) falhar(`set: use campo=valor (recebi "${par}")`);
    const campo = par.slice(0, k);
    const valor = par.slice(k + 1);
    if (campo === 'nota') {
      item.corpo = item.corpo.replace(/\s*$/, '') + `\n${hoje()}: ${valor}\n`;
      continue;
    }
    if (!CAMPOS.includes(campo) || campo === 'id') falhar(`set: campo desconhecido "${campo}"`);
    if (LISTAS.has(campo)) {
      item[campo] = valor.startsWith('+')
        ? [...(item[campo] ?? []), ...valor.slice(1).split(',').map((x) => x.trim()).filter(Boolean)]
        : valor.split(',').map((x) => x.trim()).filter(Boolean);
    } else {
      item[campo] = valor === '' || valor === 'null' ? null : valor;
    }
    if (campo === 'status' && valor === 'em-andamento' && !item.iniciado) item.iniciado = hoje();
    if (campo === 'status' && valor === 'feito' && !item.concluido) item.concluido = hoje();
  }
  const erros = validar(item, false);
  if (erros.length) falhar(`set: ${erros.join('; ')}`);
  gravar(item);
  quadro();
  console.log(linha(item));
}

function cmdList(args) {
  const o = opcoes(args);
  const em = (v, filtro) => !filtro || filtro.split(',').includes(v);
  const itens = lerItens().filter((i) =>
    em(i.status, o.status) && em(i.tipo, o.tipo) && em(i.urgencia, o.urgencia) &&
    em(i.validacao ?? '', o.validacao) && (!o.modulo || (i.modulos ?? []).includes(o.modulo)));
  if (!itens.length) console.log('(nenhum item)');
  for (const i of itens.sort(porUrgencia)) console.log(linha(i));
}

function cmdNext() {
  const itens = lerItens();
  const fila = ativos(itens).sort(porUrgencia);
  console.log(fila.length ? fila.map(linha).join('\n') : '(fila vazia)');
  const pend = aguardando(itens);
  if (pend.length) console.log('\nAguardando o dono testar:\n' + pend.map(linha).join('\n'));
}

function validar(it, completo) {
  const e = [];
  if (!it.titulo) e.push('sem titulo');
  if (!TIPOS.includes(it.tipo)) e.push(`tipo inválido "${it.tipo}"`);
  if (!URGENCIAS.includes(it.urgencia)) e.push(`urgencia inválida "${it.urgencia}"`);
  if (!STATUS.includes(it.status)) e.push(`status inválido "${it.status}"`);
  if (!VALIDACOES.includes(it.validacao)) e.push(`validacao inválida "${it.validacao}"`);
  if (!it.modulos?.length) e.push('sem modulos');
  for (const m of it.modulos ?? []) if (!MODULOS.includes(m)) e.push(`modulo desconhecido "${m}"`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(it.criado ?? '')) e.push('criado inválido');
  if (it.status === 'feito' && !it.concluido) e.push('feito sem concluido');
  if (!completo) return e;
  if (!it.arquivo.startsWith(String(it.id).padStart(4, '0') + '-')) e.push('id diferente do prefixo do arquivo');
  const posicoes = SECOES.map((s) => it.corpo.indexOf(s));
  if (posicoes.some((p) => p < 0)) e.push('faltam seções do corpo');
  else if (posicoes.some((p, i) => i && p < posicoes[i - 1])) e.push('seções fora de ordem');
  else {
    const secao = (n) => it.corpo.slice(posicoes[n] + SECOES[n].length, posicoes[n + 1] ?? undefined).trim();
    if (it.tipo === 'bug' && !secao(1)) e.push('bug sem "Como reproduzir"');
    if (it.status === 'descartado' && !secao(3)) e.push('descartado sem nota de motivo');
  }
  return e;
}

function cmdCheck() {
  let erros = 0;
  for (const it of lerItens()) {
    const e = validar(it, true);
    if (e.length) { erros++; console.log(`✗ ${it.arquivo}: ${e.join('; ')}`); }
  }
  console.log(erros ? `${erros} item(ns) com problema` : '✓ backlog ok');
  process.exit(erros ? 1 : 0);
}

const [cmd, ...resto] = process.argv.slice(2);
const comandos = { new: cmdNew, set: cmdSet, list: cmdList, next: cmdNext, board: () => quadro(), check: cmdCheck };
if (!comandos[cmd]) falhar('Uso: backlog.mjs <new|set|list|next|board|check> — ver docs/backlog/README.md');
comandos[cmd](resto);
