'use strict';
const $ = id => document.getElementById(id);
let stream, lastSample, connected = false;
const cardNodes = new Map();
const el = (tag, text, cls) => { const node = document.createElement(tag); if (text !== undefined) node.textContent = text; if (cls) node.className = cls; return node; };
function theme(value) {
  if (value === 'system') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = value;
}
$('theme').addEventListener('change', event => { theme(event.target.value); try { localStorage.setItem('appearance', event.target.value); } catch { /* Storage is optional in private browsers. */ } });
try { const saved = localStorage.getItem('appearance'); if (['system', 'dark', 'light'].includes(saved)) { $('theme').value = saved; theme(saved); } } catch { /* System appearance remains available. */ }
function drawMetric(metric, history) {
  let node = cardNodes.get(metric.id);
  if (!node) {
    node = el('article', undefined, 'card'); node.append(el('h3'), el('p', '', 'value'), el('p', '', 'detail'));
    const graph = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    graph.setAttribute('viewBox', '0 0 240 34'); graph.setAttribute('aria-hidden', 'true');
    graph.append(document.createElementNS(graph.namespaceURI, 'polyline')); node.append(graph); cardNodes.set(metric.id, node);
  }
  node.children[0].textContent = metric.label;
  const available = metric.availability === 'available';
  node.children[1].textContent = available ? `${typeof metric.value === 'number' ? new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(metric.value) : String(metric.value)}${metric.unit ? ' ' + metric.unit : ''}` : metric.availability;
  node.children[2].textContent = available ? `${metric.kind} / ${metric.id}` : metric.reason;
  const samples = history || [];
  const lo = Math.min(...samples.map(p => p.value)), hi = Math.max(...samples.map(p => p.value));
  node.children[3].children[0].setAttribute('points', samples.map((p, i) => `${i * 240 / Math.max(1, samples.length - 1)},${32 - (p.value - lo) * 30 / (hi - lo || 1)}`).join(' '));
  return node;
}
function table(kind, entries) {
  const rows = Object.values(entries || {}).sort((a, b) => a.id.localeCompare(b.id));
  $(kind === 'processes' ? 'process-count' : 'session-count').textContent = `(${rows.length})`;
  const nodes = rows.map(row => {
    const tr = el('tr'); const fields = [row.id, row.type, row.state];
    if (kind === 'processes') fields.push(row.cpu === undefined ? 'Unavailable' : `${(row.cpu * 100).toFixed(2)}%`);
    fields.forEach(value => { const td = el('td', value); td.title = String(value); tr.append(td); }); return tr;
  });
  if (!nodes.length) { const tr = el('tr'), td = el('td', 'No visible entries'); td.colSpan = kind === 'processes' ? 4 : 3; tr.append(td); nodes.push(tr); }
  $(kind).replaceChildren(...nodes);
}
function render(state) {
  connected = state.status === 'connected'; lastSample = state.sampledAt;
  $('status').textContent = state.status === 'connected' ? 'Connected to collecting instance' : state.status;
  $('refresh').disabled = !connected;
  $('sample').textContent = state.sampledAt ? `Sample ${state.seq} / ${new Date(state.sampledAt).toLocaleTimeString()}` : 'Waiting for first sample';
  const metrics = Object.values(state.metrics || {}).sort((a, b) => (a.kind === 'static') - (b.kind === 'static') || a.id.localeCompare(b.id));
  for (const id of cardNodes.keys()) if (!state.metrics[id]) cardNodes.delete(id);
  if (metrics.length) $('metrics').replaceChildren(...metrics.map(m => drawMetric(m, state.history[m.id])));
  else $('metrics').replaceChildren(el('p', 'Waiting for measurements. Missing values are not zero.'));
  const info = Object.entries(state.info || {}).flatMap(([key, value]) => [el('dt', key), el('dd', value)]);
  $('info').replaceChildren(...info);
  $('scope').textContent = `Collecting instance: ${state.info?.role || 'unknown'} / ${state.info?.platform || 'unknown'} (not automatically server-wide)`;
  table('processes', state.processes); table('sessions', state.sessions);
  if (state.lastAction) $('action').textContent = state.lastAction.ok ? 'Snapshot refreshed' : `Refresh failed: ${state.lastAction.error}`;
}
function connect() {
  if (stream) stream.close();
  stream = new EventSource('/api/events');
  stream.addEventListener('state', event => {
    try { render(JSON.parse(event.data)); $('login').hidden = true; }
    catch { $('status').textContent = 'Invalid server update'; }
  });
  stream.onerror = () => { connected = false; $('refresh').disabled = true; $('status').textContent = 'Disconnected / reconnecting'; $('login').hidden = false; };
}
async function authenticate(token) {
  const response = await fetch('/api/session', { method: 'POST', body: token });
  if (!response.ok) throw new Error('Access token rejected');
  $('token').value = ''; connect();
}
$('auth').addEventListener('submit', async event => {
  event.preventDefault();
  try { await authenticate($('token').value); } catch (error) { $('status').textContent = error.message; }
});
$('refresh').addEventListener('click', async () => {
  $('refresh').disabled = true;
  try {
    const response = await fetch('/api/refresh', { method: 'POST', headers: { 'X-Dashboard-Action': 'refresh' } });
    if (!response.ok) throw new Error(await response.text());
    $('action').textContent = 'Refresh requested...';
  } catch (error) { $('action').textContent = `Refresh failed: ${error.message}`; }
  finally { $('refresh').disabled = !connected; }
});
setInterval(() => {
  if (lastSample && Date.now() - Date.parse(lastSample) > 15000) { $('status').textContent = 'Stale / no recent measurements'; $('refresh').disabled = true; }
}, 3000);
const token = new URLSearchParams(location.hash.slice(1)).get('token');
history.replaceState(null, '', location.pathname);
if (token) authenticate(token).catch(error => { $('status').textContent = error.message; $('login').hidden = false; });
else connect();
