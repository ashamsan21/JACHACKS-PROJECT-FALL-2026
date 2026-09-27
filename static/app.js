const $ = (id) => document.getElementById(id);
let result = null;
let controller = null;
let revision = 0;
let busy = false;
let stale = false;
let selectedNode = null;
let toastTimer;
const escapeHTML = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmt = (n) => Number(n).toLocaleString();

function notify(text, error = false) {
  $('notice').textContent = text;
  $('notice').classList.toggle('error', error);
  $('notice').hidden = !text;
}
function toast(text) {
  $('toast').textContent = text;
  $('toast').hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $('toast').hidden = true, 2400);
}
function setBusy(value) {
  busy = value;
  const hasDocument = !!$('document').files[0];
  $('compile').disabled = value || (!hasDocument && !$('prompt').value.trim());
  $('compileText').textContent = value ? (hasDocument ? 'Converting…' : 'Cleaning…') : (hasDocument ? 'Convert to Markdown' : 'Clean prompt');
  $('compileIcon').classList.toggle('spinning', value);
  $('compile').setAttribute('aria-busy', String(value));
}
function edited() {
  revision++;
  if (controller) controller.abort();
  setBusy(false);
  stale = !!result;
  $('copy').disabled = true;
  $('charCount').textContent = `${fmt($('prompt').value.length)} characters`;
  $('resultStatus').textContent = stale ? 'Input changed · recompile' : 'Ready to compile';
  $('resultStatus').className = `status ${stale ? 'stale' : ''}`;
  if (stale) notify('Results below are from the previous compilation. Compile again to update them.');
}

async function compile() {
  if (busy || (!$('prompt').value.trim() && !$('document').files[0])) return;
  const current = revision;
  controller = new AbortController();
  setBusy(true);
  notify('');
  $('resultStatus').className = 'status';
  $('resultStatus').textContent = 'Running Jac walkers…';
  const form = new FormData();
  form.append('prompt', $('prompt').value);
  form.append('budget', '1024');
  if ($('document').files[0]) form.append('document', $('document').files[0]);
  try {
    const response = await fetch('/api/compile', {method:'POST', body:form, signal:controller.signal});
    const data = await response.json();
    if (!response.ok) throw new Error(typeof data.detail === 'string' ? data.detail : 'Unable to compile this request.');
    if (current !== revision) return;
    result = data;
    stale = false;
    render();
  } catch (error) {
    if (error.name === 'AbortError' || current !== revision) return;
    notify(error.message || 'Could not reach the compiler. Check that the server is running.', true);
    $('resultStatus').textContent = 'Compilation failed';
    $('copy').disabled = true;
  } finally {
    if (current === revision) { setBusy(false); controller = null; }
  }
}

function render() {
  const m = result.metrics;
  const documentMode = result.mode === 'document';
  $('before').textContent = `~${fmt(m.before)}`;
  $('after').textContent = `~${fmt(m.after)}`;
  $('percent').textContent = `${m.percent > 0 ? '−' : m.percent < 0 ? '+' : ''}${Math.abs(m.percent)}%`;
  $('saved').textContent = `${fmt(Math.abs(m.saved))} ${m.saved >= 0 ? 'fewer' : 'more'} est. tokens`;
  $('optimized').textContent = result.optimized;
  $('outputLabel').textContent = documentMode ? 'MARKDOWN OUTPUT' : 'OPTIMIZED PROMPT';
  $('download').hidden = !documentMode;
  $('beforeLabel').textContent = documentMode ? 'PDF text tokens' : 'input tokens';
  $('afterLabel').textContent = documentMode ? 'Markdown tokens' : 'output tokens';
  $('meaningLock').hidden = documentMode;
  $('insights').hidden = documentMode;
  $('analysis').hidden = documentMode;
  renderVocabulary(documentMode ? [] : (result.vocabulary || []));
  $('contextPreview').hidden = !result.context;
  $('contextPreview').textContent = result.context ? `ATTACHED CONTEXT\n${result.context}\n\n${result.context_note}` : '';
  $('copy').disabled = false;
  $('resultStatus').textContent = documentMode ? 'PDF converted' : 'Prompt cleaned';
  $('resultStatus').className = 'status success';
  const verified = result.locks.filter(lock => lock.passed).length;
  $('lockSummary').textContent = result.locks.length ? `${verified} rewritten safely · ${result.locks.length - verified} restored to original wording.` : 'No explicit constraints detected. Review the output.';
  $('lockBadge').textContent = result.lock_ok ? (verified ? 'VERIFIED' : 'NO LOCKS') : 'RESTORED';
  $('nodeCount').textContent = result.graph.nodes.length;
  $('analysisMeta').textContent = `${result.graph.nodes.length} NODES · ${result.graph.edges.length} EDGES · ${result.duration_ms} ms`;
  $('footerStatus').textContent = `${result.trace.length} Jac walkers executed · 0 model calls`;
  if (!m.within_budget) notify(`Estimated output is ${fmt(m.after)} tokens, above ${fmt(m.budget)} tokens.`);
  else if (result.context_note) notify(result.context_note);
  renderInsights();
  renderGraph();
  renderDiff();
  $('traceView').innerHTML = `<p class="muted">Executed by the Jac runtime for this compilation. Total: ${result.duration_ms} ms.</p>` + result.trace.map((item, i) => `<div class="trace-row"><span class="trace-index">${String(i + 1).padStart(2,'0')} ✓</span><div><strong>${escapeHTML(item.walker)}</strong><small>${escapeHTML(item.detail)}</small></div></div>`).join('');
}

function renderVocabulary(items) {
  $('vocabulary').hidden = !items.length;
  $('vocabularyItems').replaceChildren(...items.slice(0, 5).map(item => {
    const card = document.createElement('div'); card.className = 'vocabulary-item';
    const term = document.createElement('strong'); term.textContent = item.term;
    const meaning = document.createElement('small'); meaning.textContent = item.meaning;
    card.append(term, meaning); return card;
  }));
}

function renderInsights() {
  const items = result.issues.filter(issue => ['ambiguity','verbosity'].includes(issue.type));
  const card = (item) => `<div class="insight ${escapeHTML(item.type)}"><span class="icon">${item.type === 'ambiguity' ? '△' : '≋'}</span><div><strong>${escapeHTML(item.title)}</strong><p>${escapeHTML(item.detail)}</p></div></div>`;
  $('insights').innerHTML = items.slice(0, 3).map(card).join('') + (items.length > 3 ? `<details><summary>${items.length - 3} more observations</summary>${items.slice(3).map(card).join('')}</details>` : '');
}

function renderGraph() {
  const nodes = result.graph.nodes;
  const children = nodes.filter(node => node.id !== 'request');
  const container = $('graphCanvas');
  const width = Math.max(280, container.clientWidth);
  const columns = width >= 555 ? 2 : 1;
  const rootWidth = columns === 2 ? 135 : 105;
  const nodeWidth = columns === 2 ? 175 : Math.min(175, width - 135);
  const height = Math.max(220, Math.ceil(children.length / columns) * 89 + 20);
  container.style.maxHeight = '430px';
  container.innerHTML = `<div class="graph-layout" style="height:${height}px"></div>`;
  const layout = container.firstElementChild;
  layout.style.minWidth = `${columns === 2 ? 555 : 280}px`;
  const positions = new Map([['request', {x: 4, y: height / 2 - 30}]]);
  children.forEach((node, i) => positions.set(node.id, {x: (columns === 2 ? width - 367 : width - nodeWidth - 4) + (i % columns) * 185, y: 10 + Math.floor(i / columns) * 89}));
  const paths = result.graph.edges.map(edge => {
    const a = positions.get(edge.source), b = positions.get(edge.target);
    const sx = a.x + rootWidth, sy = a.y + 29, tx = b.x, ty = b.y + 29;
    return `<path d="M${sx},${sy} C${sx + 25},${sy} ${tx - 25},${ty} ${tx},${ty}"/>`;
  }).join('');
  layout.innerHTML = `<svg class="graph-svg" aria-hidden="true">${paths}</svg>` + nodes.map(node => {
    const p = positions.get(node.id);
    return `<button class="graph-node ${escapeHTML(node.kind)}" style="left:${p.x}px;top:${p.y}px;width:${node.id === 'request' ? rootWidth : nodeWidth}px" data-node="${escapeHTML(node.id)}" aria-label="Inspect ${escapeHTML(node.kind)}: ${escapeHTML(node.text)}"><span class="node-kind">${escapeHTML(node.kind)} <span>${node.protected ? '◇ LOCKED' : '↗'}</span></span><span class="node-text">${escapeHTML(node.result || node.text)}</span></button>`;
  }).join('');
  layout.querySelectorAll('[data-node]').forEach(button => button.addEventListener('click', () => inspectNode(button.dataset.node)));
  inspectNode(children.find(node => node.protected)?.id || children[0]?.id || 'request');
}

function inspectNode(id) {
  selectedNode = id;
  const node = result.graph.nodes.find(item => item.id === id);
  document.querySelectorAll('[data-node]').forEach(button => { button.classList.toggle('selected', button.dataset.node === id); button.setAttribute('aria-pressed', String(button.dataset.node === id)); });
  if (id === 'request') {
    $('inspector').innerHTML = `<span class="tiny-label">COMPILATION ROOT</span><h3>Your request</h3><p>This graph was traversed by Jac walkers. Each child represents a source clause, classified by deterministic rules.</p><span class="tag">${result.graph.edges.length} connected clauses</span>`;
    return;
  }
  $('inspector').innerHTML = `<span class="tiny-label">${escapeHTML(node.kind.toUpperCase())} · ${escapeHTML(node.id)}</span><h3>${node.protected ? 'Locked to your words.' : 'Traceable to the source.'}</h3><blockquote>${escapeHTML(node.text)}</blockquote><span class="tiny-label">${node.protected ? 'PROTECTION RULES' : 'COMPILER ACTION'}</span><div>${(node.reasons.length ? node.reasons : [node.status]).map(reason => `<span class="tag">${escapeHTML(reason)}</span>`).join('')}</div>${node.result !== node.text ? `<p>After compilation:</p><blockquote>${escapeHTML(node.result || '(Repeated instruction removed)')}</blockquote>` : ''}<div class="offset">SOURCE CHARACTERS ${node.start}–${node.end} · ZERO-BASED</div>`;
}

function renderDiff() {
  $('diffRows').innerHTML = result.diff.map(item => `<div class="diff-row"><div class="diff-kind ${item.kind}">${item.kind}<small>${escapeHTML(item.scope)}</small></div><div class="diff-content">${item.kind === 'preserved' ? `<p>${escapeHTML(item.original)}</p>` : `<p><del>${escapeHTML(item.original)}</del></p>${item.result ? `<p><ins>${escapeHTML(item.result)}</ins></p>` : ''}`}<small>${escapeHTML(item.reason)}</small></div></div>`).join('');
}

function showTab(view) {
  document.querySelectorAll('.tab').forEach(button => { const active = button.dataset.view === view; button.classList.toggle('selected', active); button.setAttribute('aria-selected', String(active)); button.tabIndex = active ? 0 : -1; });
  ['graph','diff','trace'].forEach(name => $(`${name}View`).hidden = name !== view);
  if (view === 'graph' && result) renderGraph();
}
document.querySelectorAll('.tab').forEach((button, index, all) => {
  button.addEventListener('click', () => showTab(button.dataset.view));
  button.addEventListener('keydown', (event) => {
    if (!['ArrowRight','ArrowLeft','Home','End'].includes(event.key)) return;
    event.preventDefault();
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? all.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + all.length) % all.length;
    showTab(all[next].dataset.view); all[next].focus();
  });
});
$('prompt').addEventListener('input', edited);
$('compile').addEventListener('click', compile);
$('clear').addEventListener('click', () => {
  $('prompt').value = ''; $('document').value = ''; updateFile(); edited(); result = null; stale = false;
  $('before').textContent = $('after').textContent = $('percent').textContent = '—';
  $('saved').textContent = 'tokens saved'; $('optimized').textContent = 'Your compiled prompt will appear here.';
  $('resultStatus').textContent = 'Ready to compile'; $('resultStatus').className = 'status';
  $('lockSummary').textContent = 'Requirements are verified locally or restored.'; $('lockBadge').textContent = 'ENABLED';
  $('download').hidden = true;
  $('vocabulary').hidden = true; $('vocabularyItems').replaceChildren();
  $('contextPreview').hidden = true; $('insights').innerHTML = ''; $('nodeCount').textContent = '0';
  $('graphCanvas').innerHTML = '<div class="empty-state">Your intent, made visible.<small>Compile a prompt to explore its graph.</small></div>';
  $('inspector').innerHTML = '<span class="tiny-label">NODE INSPECTOR</span><p>Select a node after compilation.</p>';
  $('diffRows').innerHTML = ''; $('traceView').textContent = 'Compile a prompt to see walker execution.';
  $('analysisMeta').textContent = 'Awaiting compilation'; $('footerStatus').textContent = 'No prompts stored · no external model requests';
  notify(''); $('prompt').focus();
});
function updateFile() {
  const file = $('document').files[0];
  $('fileLabel').innerHTML = file ? `${escapeHTML(file.name)}<small>${fmt(Math.ceil(file.size/1024))} KB · ready to convert</small>` : 'Convert document <small>PDF, TXT, MD · up to 4 MB</small>';
  $('removeFile').hidden = !file;
  setBusy(false);
}
$('document').addEventListener('change', () => { edited(); const file = $('document').files[0]; if (file && file.size > 4000000) { $('document').value = ''; notify('Choose a file smaller than 4 MB.', true); } updateFile(); });
$('removeFile').addEventListener('click', () => { $('document').value = ''; updateFile(); edited(); });
$('attach').addEventListener('click', () => $('document').click());
$('copy').addEventListener('click', async () => { if (!result || stale) return; try { await navigator.clipboard.writeText(result.compiled); toast('Compiled context copied'); } catch { notify('Clipboard access was denied. Select and copy the compiled text manually.', true); } });
$('download').addEventListener('click', () => {
  if (!result || stale || result.mode !== 'document') return;
  const url = URL.createObjectURL(new Blob([result.compiled], {type:'text/markdown;charset=utf-8'}));
  const link = document.createElement('a');
  link.href = url; link.download = result.filename || 'document.md';
  document.body.append(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  toast(`${link.download} created`);
});
document.addEventListener('keydown', event => { if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') { event.preventDefault(); compile(); } });
let resizeTimer;
window.addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { if (result && !$('graphView').hidden) renderGraph(); }, 150); });
fetch('/api/health').then(response => { if (response.ok) $('healthDot').classList.add('online'); }).catch(() => {});
$('prompt').value = '';
edited();
