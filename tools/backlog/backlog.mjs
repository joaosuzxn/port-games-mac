// Backlog CLI for the Carros port. Plain Node, no dependencies.
// Usage: node tools/backlog/backlog.mjs <new|set|list|next|board|check> [...]
// Field rules in docs/backlog/README.md.
//
// Data format (frontmatter fields, their values, body sections) and command-line
// parameters keep the Portuguese names documented in docs/backlog/README.md; the
// item properties read from the frontmatter (titulo, tipo, urgencia...) are named after them.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const itemsDir = path.join(root, 'docs', 'backlog', 'itens');
const boardFile = path.join(root, 'docs', 'backlog', 'BACKLOG.md');

const TYPES = ['bug', 'melhoria', 'ideia', 'feature', 'tarefa'];
const PRIORITIES = ['P0', 'P1', 'P2', 'P3'];
const STATUSES = ['aberto', 'em-andamento', 'feito', 'descartado'];
const VALIDATIONS = [null, 'pendente', 'ok'];
const MODULES = ['jogo', 'wine', 'app', 'docs', 'infra'];
const FIELDS = ['id', 'titulo', 'tipo', 'urgencia', 'status', 'modulos', 'criado', 'iniciado', 'concluido', 'commits', 'relacionados', 'validacao'];
const LIST_FIELDS = new Set(['modulos', 'commits', 'relacionados']);
const SECTIONS = ['## Contexto', '## Como reproduzir', '## Proposta', '## Notas de execução'];

// Text of the generated board (docs/backlog/BACKLOG.md) and of the item line printed by
// list/next/board. It is documentation content, so it stays in Portuguese.
const TEXT = {
  boardTitle: '# Backlog — Port do Carros',
  boardNote: (date) => `> Gerado por \`backlog board\` em ${date}. Não editar à mão: edite os itens em \`itens/\` e gere de novo.`,
  now: 'Agora',
  nextCycle: 'Próximo ciclo',
  whenPossible: 'Quando der',
  awaiting: 'Aguardando o dono testar',
  empty: '(vazio)',
  inProgressSince: 'em andamento desde',
  doneOn: 'feito em',
  daysAgo: (days) => `há ${days} dias`,
};

const today = () => new Date().toLocaleDateString('sv-SE');
const fail = (msg) => { console.error(msg); process.exit(1); };

// --- frontmatter (subset of YAML: scalar, "string", null, [a, b]) ---------------
function parseValue(raw) {
  const s = raw.trim();
  if (s === '' || s === 'null') return null;
  if (s.startsWith('[')) {
    return s.slice(1, -1).split(',').map((x) => x.trim()).filter(Boolean)
      .map((x) => (x.startsWith('"') ? JSON.parse(x) : x));
  }
  if (s.startsWith('"')) return JSON.parse(s);
  return s;
}

function formatValue(key, v) {
  if (v === null || v === undefined) return 'null';
  if (Array.isArray(v)) return '[' + v.map((x) => (/^[\w.-]+$/.test(String(x)) ? x : JSON.stringify(String(x)))).join(', ') + ']';
  if (key === 'titulo') return JSON.stringify(v);
  return /^[\w.-]+$/.test(String(v)) ? String(v) : JSON.stringify(String(v));
}

function readItems() {
  if (!fs.existsSync(itemsDir)) return [];
  return fs.readdirSync(itemsDir).filter((f) => /^\d{4}-.*\.md$/.test(f)).sort().map((file) => {
    const text = fs.readFileSync(path.join(itemsDir, file), 'utf8');
    const m = text.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
    if (!m) fail(`${file}: no frontmatter`);
    const item = { file, body: m[2] };
    for (const line of m[1].split('\n')) {
      const c = line.match(/^(\w+):\s*(.*)$/);
      if (c) item[c[1]] = parseValue(c[2]);
    }
    item.id = Number(item.id);
    return item;
  });
}

function writeItem(item) {
  const fm = FIELDS.map((c) => `${c}: ${formatValue(c, item[c])}`).join('\n');
  fs.writeFileSync(path.join(itemsDir, item.file), `---\n${fm}\n---\n${item.body}`, 'utf8');
}

const slug = (t) => t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
  .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 50).replace(/-$/, '');

const daysSince = (date) => Math.max(0, Math.round((Date.now() - new Date(date + 'T00:00:00')) / 86400e3));

function formatLine(it) {
  const base = `#${it.id} · ${it.tipo} · ${it.urgencia} · ${(it.modulos ?? []).join(', ')} · ${it.titulo}`;
  if (it.status === 'em-andamento') return `${base} · ${TEXT.inProgressSince} ${it.iniciado}`;
  if (it.status === 'feito') return `${base} · ${TEXT.doneOn} ${it.concluido}${it.commits?.length ? ' · ' + it.commits.join(', ') : ''}`;
  return `${base} · ${TEXT.daysAgo(daysSince(it.criado))}`;
}

const active = (items) => items.filter((i) => i.status === 'aberto' || i.status === 'em-andamento');
const awaitingValidation = (items) => items.filter((i) => i.status === 'feito' && i.validacao === 'pendente');
const byPriority = (a, b) => PRIORITIES.indexOf(a.urgencia) - PRIORITIES.indexOf(b.urgencia) || a.id - b.id;

// --- commands ---------------------------------------------------------------------
function writeBoard(items = readItems()) {
  const lines = [TEXT.boardTitle, '', TEXT.boardNote(today()), ''];
  const section = (title, list) => {
    lines.push(`## ${title}`);
    lines.push(...(list.length ? list.map((i) => `- ${formatLine(i)}`) : [`- ${TEXT.empty}`]));
    lines.push('');
  };
  const a = active(items).sort((x, y) => x.id - y.id);
  section(TEXT.now, a.filter((i) => i.urgencia === 'P0' || i.urgencia === 'P1'));
  section(TEXT.nextCycle, a.filter((i) => i.urgencia === 'P2'));
  section(TEXT.whenPossible, a.filter((i) => i.urgencia === 'P3'));
  section(TEXT.awaiting, awaitingValidation(items));
  fs.writeFileSync(boardFile, lines.join('\n'), 'utf8');
}

function parseOptions(args) {
  const o = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) o[args[i].slice(2)] = args[i + 1] ?? '', i++;
  }
  return o;
}

function cmdNew(args) {
  const o = parseOptions(args);
  for (const c of ['titulo', 'tipo', 'urgencia', 'modulos']) if (!o[c]) fail(`new: missing --${c}`);
  const items = readItems();
  const id = Math.max(0, ...items.map((i) => i.id)) + 1;
  const item = {
    id, titulo: o.titulo, tipo: o.tipo, urgencia: o.urgencia, status: 'aberto',
    modulos: o.modulos.split(',').map((x) => x.trim()), criado: today(), iniciado: null, concluido: null,
    commits: [], relacionados: o.relacionados ? o.relacionados.split(',').map((x) => x.trim()) : [], validacao: null,
    file: `${String(id).padStart(4, '0')}-${slug(o.titulo)}.md`,
    body: SECTIONS.map((s) => `${s}\n\n`).join(''),
  };
  const errors = validate(item, false);
  if (errors.length) fail(`new: ${errors.join('; ')}`);
  writeItem(item);
  writeBoard();
  console.log(`#${id} · docs/backlog/itens/${item.file}`);
}

function cmdSet(args) {
  const [idText, ...pairs] = args;
  const items = readItems();
  const item = items.find((i) => i.id === Number(idText));
  if (!item) fail(`set: item #${idText} does not exist`);
  for (const pair of pairs) {
    const k = pair.indexOf('=');
    if (k < 1) fail(`set: use field=value (got "${pair}")`);
    const field = pair.slice(0, k);
    const value = pair.slice(k + 1);
    if (field === 'nota') {
      item.body = item.body.replace(/\s*$/, '') + `\n${today()}: ${value}\n`;
      continue;
    }
    if (!FIELDS.includes(field) || field === 'id') fail(`set: unknown field "${field}"`);
    if (LIST_FIELDS.has(field)) {
      item[field] = value.startsWith('+')
        ? [...(item[field] ?? []), ...value.slice(1).split(',').map((x) => x.trim()).filter(Boolean)]
        : value.split(',').map((x) => x.trim()).filter(Boolean);
    } else {
      item[field] = value === '' || value === 'null' ? null : value;
    }
    if (field === 'status' && value === 'em-andamento' && !item.iniciado) item.iniciado = today();
    if (field === 'status' && value === 'feito' && !item.concluido) item.concluido = today();
  }
  const errors = validate(item, false);
  if (errors.length) fail(`set: ${errors.join('; ')}`);
  writeItem(item);
  writeBoard();
  console.log(formatLine(item));
}

function cmdList(args) {
  const o = parseOptions(args);
  const matches = (v, filter) => !filter || filter.split(',').includes(v);
  const items = readItems().filter((i) =>
    matches(i.status, o.status) && matches(i.tipo, o.tipo) && matches(i.urgencia, o.urgencia) &&
    matches(i.validacao ?? '', o.validacao) && (!o.modulo || (i.modulos ?? []).includes(o.modulo)));
  if (!items.length) console.log('(no items)');
  for (const i of items.sort(byPriority)) console.log(formatLine(i));
}

function cmdNext() {
  const items = readItems();
  const queue = active(items).sort(byPriority);
  console.log(queue.length ? queue.map(formatLine).join('\n') : '(queue empty)');
  const pending = awaitingValidation(items);
  if (pending.length) console.log(`\n${TEXT.awaiting}:\n` + pending.map(formatLine).join('\n'));
}

function validate(it, full) {
  const e = [];
  if (!it.titulo) e.push('missing titulo');
  if (!TYPES.includes(it.tipo)) e.push(`invalid tipo "${it.tipo}"`);
  if (!PRIORITIES.includes(it.urgencia)) e.push(`invalid urgencia "${it.urgencia}"`);
  if (!STATUSES.includes(it.status)) e.push(`invalid status "${it.status}"`);
  if (!VALIDATIONS.includes(it.validacao)) e.push(`invalid validacao "${it.validacao}"`);
  if (!it.modulos?.length) e.push('missing modulos');
  for (const m of it.modulos ?? []) if (!MODULES.includes(m)) e.push(`unknown modulo "${m}"`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(it.criado ?? '')) e.push('invalid criado');
  if (it.status === 'feito' && !it.concluido) e.push('feito without concluido');
  if (!full) return e;
  if (!it.file.startsWith(String(it.id).padStart(4, '0') + '-')) e.push('id differs from the file name prefix');
  const positions = SECTIONS.map((s) => it.body.indexOf(s));
  if (positions.some((p) => p < 0)) e.push('body sections missing');
  else if (positions.some((p, i) => i && p < positions[i - 1])) e.push('body sections out of order');
  else {
    const section = (n) => it.body.slice(positions[n] + SECTIONS[n].length, positions[n + 1] ?? undefined).trim();
    if (it.tipo === 'bug' && !section(1)) e.push('bug without "Como reproduzir"');
    if (it.status === 'descartado' && !section(3)) e.push('descartado without a reason note');
  }
  return e;
}

function cmdCheck() {
  let failures = 0;
  for (const it of readItems()) {
    const e = validate(it, true);
    if (e.length) { failures++; console.log(`✗ ${it.file}: ${e.join('; ')}`); }
  }
  console.log(failures ? `${failures} item(s) with problems` : '✓ backlog ok');
  process.exit(failures ? 1 : 0);
}

const [cmd, ...rest] = process.argv.slice(2);
const commands = { new: cmdNew, set: cmdSet, list: cmdList, next: cmdNext, board: () => writeBoard(), check: cmdCheck };
if (!commands[cmd]) fail('Usage: backlog.mjs <new|set|list|next|board|check> — see docs/backlog/README.md');
commands[cmd](rest);
