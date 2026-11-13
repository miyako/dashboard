'use strict';
const $ = id => document.getElementById(id);
let stream, lastSample, currentState, connected = false;
const cardNodes = new Map(), graphNodes = new Map();
const format = value => new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value);
const axisFormat = value => new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 1 }).format(value);
const el = (tag, text, cls) => { const node = document.createElement(tag); if (text !== undefined) node.textContent = text; if (cls) node.className = cls; return node; };
const svgEl = (tag, attrs = {}, text) => {
  const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
  Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value));
  if (text !== undefined) node.textContent = text;
  return node;
};
function theme(value) {
  if (value === 'system') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = value;
}
$('theme').addEventListener('change', event => { theme(event.target.value); try { localStorage.setItem('appearance', event.target.value); } catch { /* Storage is optional in private browsers. */ } });
try { const saved = localStorage.getItem('appearance'); if (['system', 'dark', 'light'].includes(saved)) { $('theme').value = saved; theme(saved); } } catch { /* System appearance remains available. */ }
function tabs(ids) {
  const buttons = ids.map(id => $('tab-' + id));
  function activate(button) {
    buttons.forEach(item => {
      const selected = item === button;
      item.setAttribute('aria-selected', String(selected)); item.tabIndex = selected ? 0 : -1;
      $(item.getAttribute('aria-controls')).hidden = !selected;
    });
    redrawGraphs();
  }
  buttons.forEach((button, i) => {
    button.addEventListener('click', () => activate(button));
    button.addEventListener('keydown', event => {
      let index;
      if (event.key === 'ArrowRight') index = (i + 1) % buttons.length;
      else if (event.key === 'ArrowLeft') index = (i + buttons.length - 1) % buttons.length;
      else if (event.key === 'Home') index = 0;
      else if (event.key === 'End') index = buttons.length - 1;
      else return;
      event.preventDefault(); buttons[index].focus(); activate(buttons[index]);
    });
  });
}
tabs(['live', 'static', 'database', 'activity']); tabs(['snapshot', 'tracking']);
function drawMetric(metric, samples = [], key = metric.id, unit = metric.unit) {
  let node = cardNodes.get(key);
  if (!node) {
    node = el('article', undefined, 'card'); node.append(el('h3'), el('p', '', 'value'), el('p', '', 'detail'));
    cardNodes.set(key, node);
  }
  node.children[0].textContent = metric.label;
  const available = metric.availability === 'available';
  node.children[1].textContent = available ? `${typeof metric.value === 'number' ? format(metric.value) : String(metric.value)}${metric.unit ? ' ' + metric.unit : ''}` : metric.availability;
  node.children[2].textContent = available ? `${metric.kind} / ${metric.id}` : metric.reason;
  if (DashboardCharts.hasGraph(metric)) {
    let graph = node.querySelector('svg');
    if (!graph) {
      graph = svgEl('svg', { viewBox: '0 0 600 205', role: 'img', class: 'chart' });
      node.append(graph);
    }
    graphNodes.set(key, { graph, samples, metric, unit });
    drawPlot(graphNodes.get(key));
  } else {
    node.querySelector('svg')?.remove(); graphNodes.delete(key);
  }
  return node;
}
function drawOverlay(group, state) {
  const key = 'overlay-' + group.id;
  let node = cardNodes.get(key);
  if (!node) {
    node = el('article', undefined, 'card');
    node.append(el('h3', group.label), el('div', undefined, 'legend'), el('p', '', 'detail'),
      svgEl('svg', { viewBox: '0 0 600 205', role: 'img', class: 'chart' }));
    cardNodes.set(key, node);
  }
  const rate = group.mirrored && $('counter-mode').value === 'rate';
  const unit = rate ? group.unit + '/s' : group.unit;
  const series = group.metrics.filter(item => group.mirrored || state.metrics[item.id]).map(item => ({
    metric: state.metrics[item.id] || { availability: 'missing', reason: 'No measurements provided' },
    label: item.label, color: group.metrics.indexOf(item),
    samples: rate ? DashboardCharts.rate(state.history[item.id] || []) : state.history[item.id] || [],
  }));
  node.children[1].replaceChildren(...series.map((item, i) => {
    const metric = item.metric;
    const value = metric.availability === 'available' ? `${format(metric.value)} ${group.unit}` : `${metric.availability}: ${metric.reason}`;
    return el('span', `${item.label}: ${value}`, 'series-key series-' + item.color);
  }));
  node.children[2].textContent = group.mirrored
    ? `Read above / write below the centered time axis / shared ${unit} scale. Readouts are cumulative totals.`
    : `Overlapping traces / shared ${group.unit} scale`;
  const item = { graph: node.children[3], metric: { label: group.label }, series, unit, mirrored: group.mirrored };
  graphNodes.set(key, item); drawPlot(item);
  return node;
}
function drawPlot({ graph, samples, metric, unit, series, mirrored }) {
  let lines = series || [{ samples, label: metric.label }];
  const integer = DashboardCharts.integerUnit(unit);
  const geometry = (mirrored ? DashboardCharts.mirror : DashboardCharts.overlay)(lines.map(item => item.samples), Date.now(), integer);
  const { scale: plot, plots } = geometry;
  if (mirrored) lines = lines.map((line, i) => ({ ...line, samples: geometry.series[i] }));
  graph.setAttribute('aria-label', mirrored
    ? `${metric.label}: reads above zero, writes below zero, centered time axis; ${plot.count} available samples, up to ${format(plot.hi)} ${unit} in either direction`
    : `${metric.label}: ${plot.count} available samples in the last two minutes, ${unit || 'value'} from ${format(plot.lo)} to ${format(plot.hi)}`);
  const nodes = [svgEl('title', {}, graph.getAttribute('aria-label'))];
  const divisions = mirrored ? 4 : 3;
  for (let i = 0; i <= divisions; i++) {
    const y = 20 + i * 150 / divisions;
    nodes.push(svgEl('line', { x1: 56, x2: 580, y1: y, y2: y, class: 'gridline' }));
    const value = plot.hi - (plot.hi - plot.lo) * i / divisions;
    const tick = mirrored ? Math.abs(value) : value;
    nodes.push(svgEl('text', { x: 48, y: y + 4, 'text-anchor': 'end', class: 'axis' }, integer ? new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(tick) : axisFormat(tick)));
  }
  lines.forEach((line, i) => {
    const color = 'series-' + (line.color ?? i);
    nodes.push(svgEl('path', { d: plots[i].path, class: 'trace ' + color }));
    for (const sample of line.samples) {
      const at = Date.parse(sample.at);
      if (at < plot.start || at > plot.end || !Number.isFinite(sample.value)) continue;
      const dot = svgEl('circle', { cx: 56 + (at - plot.start) * 524 / DashboardCharts.windowMs,
        cy: 170 - (sample.value - plot.lo) * 150 / (plot.hi - plot.lo), r: 2.5, class: 'sample-dot ' + color });
      dot.append(svgEl('title', {}, `${line.label} / ${new Date(at).toLocaleTimeString()}: ${format(mirrored ? Math.abs(sample.value) : sample.value)} ${unit}`)); nodes.push(dot);
    }
  });
  if (mirrored) {
    nodes.push(svgEl('line', { x1: 56, x2: 580, y1: 95, y2: 95, class: 'zero-axis' }),
      svgEl('text', { x: 580, y: 12, 'text-anchor': 'end', class: 'axis' }, 'Read'),
      svgEl('text', { x: 580, y: 190, 'text-anchor': 'end', class: 'axis' }, 'Write'));
  }
  for (let i = 0; i <= 2; i++) {
    const at = plot.start + i * DashboardCharts.windowMs / 2;
    nodes.push(svgEl('text', { x: 56 + i * 262, y: mirrored ? 111 : 196,
      'text-anchor': i === 0 ? 'start' : i === 2 ? 'end' : 'middle',
      class: 'axis time-axis' }, new Date(at).toLocaleTimeString()));
  }
  if (!plot.count) nodes.push(svgEl('text', { x: 318, y: mirrored ? 57 : 96, 'text-anchor': 'middle', class: 'axis' }, 'No available samples'));
  graph.replaceChildren(...nodes);
}
function redrawGraphs() {
  for (const item of graphNodes.values()) if (item.graph.isConnected && !item.graph.closest('[hidden]')) drawPlot(item);
  if (currentState && !$('view-activity').hidden && !$('activity-tracking').hidden) timelines(currentState);
}
function table(kind, entries, state) {
  const rows = Object.values(entries || {}).sort((a, b) => a.id.localeCompare(b.id));
  const prefix = kind === 'processes' ? 'process' : 'session', count = state.metrics[prefix + '.count'];
  $(prefix + '-count').textContent = count?.availability === 'available' ? `(${rows.length} visible)` : '(unavailable)';
  const truncated = state.metrics[prefix + '.truncated']?.value === true;
  $(prefix + '-availability').textContent = count?.availability !== 'available' ? (count?.reason || 'Enumeration unavailable') : truncated ? 'List truncated to 512 visible identities.' : 'Latest collected snapshot.';
  const nodes = rows.map(row => {
    const tr = el('tr'); const fields = [row.id, row.type, row.state];
    if (kind === 'processes') fields.push(row.cpu === undefined ? 'Unavailable' : `${(row.cpu * 100).toFixed(2)}%`);
    fields.forEach(value => { const td = el('td', value); td.title = String(value); tr.append(td); }); return tr;
  });
  if (!nodes.length) { const tr = el('tr'), td = el('td', count?.availability === 'available' ? 'No visible entries' : 'Enumeration unavailable'); td.colSpan = kind === 'processes' ? 4 : 3; tr.append(td); nodes.push(tr); }
  $(kind).replaceChildren(...nodes);
}
function timeline(prefix, samples) {
  const graph = svgEl('svg', { viewBox: '0 0 600 76', role: 'img', class: 'timeline' });
  const end = Date.now(), start = end - DashboardCharts.windowMs;
  const states = [...new Set(samples.map(s => s.state))].sort();
  graph.setAttribute('aria-label', `${prefix} state history: ${states.join(', ')}`);
  for (let i = 0; i < samples.length; i++) {
    const sample = samples[i], at = Date.parse(sample.at), next = samples[i + 1] ? Math.min(end, Date.parse(samples[i + 1].at)) : end;
    if (at > end || next < start) continue;
    // Do not extend an observed state indefinitely after sampling stops.
    const until = Math.min(next, at + 15000);
    if (until < start) continue;
    const x = 12 + (Math.max(start, at) - start) * 576 / DashboardCharts.windowMs;
    const width = Math.max(2, (until - Math.max(start, at)) * 576 / DashboardCharts.windowMs);
    const rect = svgEl('rect', { x, y: 8, width, height: 32, class: 'state-block state-' + stateColor(sample.state) });
    rect.append(svgEl('title', {}, `${new Date(at).toLocaleTimeString()}: ${sample.state}`)); graph.append(rect);
  }
  graph.append(svgEl('text', { x: 12, y: 65, class: 'axis' }, new Date(start).toLocaleTimeString()),
    svgEl('text', { x: 588, y: 65, 'text-anchor': 'end', class: 'axis' }, new Date(end).toLocaleTimeString()));
  const legend = el('div', undefined, 'legend');
  states.forEach(state => legend.append(el('span', state, 'state-key state-' + stateColor(state))));
  $(prefix + '-timeline').replaceChildren(graph, legend);
}
function stateColor(state) {
  if (state === 'unavailable' || state === 'absent') return state;
  return [...state].reduce((n, c) => n + c.charCodeAt(0), 0) % 8;
}
function timelines(state) {
  const samples = state.activity || [];
  for (const [prefix, kind] of [['process', 'processes'], ['session', 'sessions']]) {
    const select = $(prefix + '-identity'), previous = select.value;
    const ids = new Set(Object.keys(state[kind] || {}));
    for (const sample of [...samples].reverse()) for (const id of Object.keys(sample[kind].entities || {})) ids.add(id);
    const visible = [...ids].slice(0, 512);
    const options = visible.map(id => {
      const option = el('option', id + (state[kind]?.[id] ? '' : ' (not in latest visible list)')); option.value = id; return option;
    });
    select.replaceChildren(...options);
    if (visible.includes(previous)) select.value = previous;
    select.disabled = !visible.length;
    $(prefix + '-history-note').textContent = visible.length ? `${visible.length} recent identities${ids.size > 512 ? ' shown (selector capped at 512)' : ''}. Tracking uses actual collected samples.` : 'No identities available to track.';
    const history = DashboardCharts.entities(samples, kind, select.value);
    timeline(prefix, history);
    if (prefix === 'process' && select.value) {
      const latest = history.at(-1);
      const metric = { id: select.value, label: 'Selected process CPU', type: 'number', kind: 'gauge', unit: '%',
        availability: Number.isFinite(latest?.value) ? 'available' : 'missing', value: latest?.value, reason: 'CPU unavailable or identity absent from latest visible sample' };
      $('process-cpu').replaceChildren(drawMetric(metric, history, 'selected-process'));
    } else if (prefix === 'process') { $('process-cpu').replaceChildren(); graphNodes.delete('selected-process'); }
  }
}
function render(state) {
  currentState = state; connected = state.status === 'connected'; lastSample = state.sampledAt;
  $('status').textContent = state.status === 'connected' ? 'Connected to collecting instance' : state.status;
  $('refresh').disabled = !connected;
  $('sample').textContent = state.sampledAt ? `Sample ${state.seq} / ${new Date(state.sampledAt).toLocaleTimeString()}` : 'Waiting for first sample';
  const groups = { metrics: [], 'static-metrics': [], 'database-metrics': [], 'process-trends': [], 'session-trends': [] };
  graphNodes.clear();
  const combined = new Map([...DashboardCharts.overlaps, ...DashboardCharts.mirrors].flatMap(group => group.metrics.map(item => [item.id, group])));
  for (const metric of Object.values(state.metrics || {}).sort((a, b) => a.id.localeCompare(b.id))) {
    if (combined.has(metric.id)) {
      const group = combined.get(metric.id);
      if (group.metrics.find(item => state.metrics[item.id]).id === metric.id) {
        groups[group.mirrored ? 'database-metrics' : 'metrics'].push(drawOverlay(group, state));
      }
      continue;
    }
    let group = metric.kind === 'static' || metric.id === 'app.uptime' ? 'static-metrics' : metric.id.startsWith('database.') ? 'database-metrics' :
      metric.id.startsWith('process.') ? 'process-trends' : metric.id.startsWith('session.') ? 'session-trends' : 'metrics';
    let samples = state.history[metric.id] || [], unit = metric.unit;
    if (metric.kind === 'counter' && group === 'database-metrics' && $('counter-mode').value === 'rate') {
      samples = DashboardCharts.rate(samples); unit = metric.unit ? metric.unit + '/s' : '/s';
    }
    const node = drawMetric(metric, samples, metric.id, unit);
    if (unit !== metric.unit) node.children[2].textContent += ` / graph: ${unit} (latest value is total)`;
    groups[group].push(node);
  }
  const cpu = DashboardCharts.cpu(state.activity || []), latestCPU = cpu.at(-1)?.value;
  groups['process-trends'].push(drawMetric({ id: 'process.cpuSum', label: 'Visible processes: summed CPU', type: 'number', kind: 'gauge', unit: '%',
    availability: Number.isFinite(latestCPU) ? 'available' : 'missing', value: latestCPU, reason: 'One or more visible CPU values or enumeration unavailable' }, cpu));
  for (const [id, nodes] of Object.entries(groups)) $(id).replaceChildren(...(nodes.length ? nodes : [el('p', 'No measurements provided for this view.')]));
  for (const [id, node] of cardNodes) if (!node.isConnected) cardNodes.delete(id);
  $('info').replaceChildren(...Object.entries(state.info || {}).flatMap(([key, value]) => [el('dt', key), el('dd', value)]));
  $('scope').textContent = `Collecting instance: ${state.info?.role || 'unknown'} / ${state.info?.platform || 'unknown'} (not automatically server-wide)`;
  table('processes', state.processes, state); table('sessions', state.sessions, state); timelines(state);
  if (state.lastAction) $('action').textContent = state.lastAction.ok ? 'Sample refreshed' : `Refresh failed: ${state.lastAction.error}`;
}
$('counter-mode').addEventListener('change', () => { if (currentState) render(currentState); });
for (const prefix of ['process', 'session']) $(prefix + '-identity').addEventListener('change', () => timelines(currentState));
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
  redrawGraphs();
  if (lastSample && Date.now() - Date.parse(lastSample) > 15000) { $('status').textContent = 'Stale / no recent measurements'; $('refresh').disabled = true; }
}, 1000);
const token = new URLSearchParams(location.hash.slice(1)).get('token');
history.replaceState(null, '', location.pathname);
if (token) authenticate(token).catch(error => { $('status').textContent = error.message; $('login').hidden = false; });
else connect();
