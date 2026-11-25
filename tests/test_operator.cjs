const { test } = require('node:test');
const assert = require('node:assert/strict');
const operator = require('../cli/web/operator.js');

test('fragment yields viewer and operator tokens independently', () => {
  assert.deepEqual(operator.tokens('#token=abc&operator=def'), { viewer: 'abc', operator: 'def' });
  assert.deepEqual(operator.tokens('#token=abc'), { viewer: 'abc', operator: null });
});

test('no-op arguments match the server pattern exactly', () => {
  assert.deepEqual(operator.noopArgs('ok note_1.-'), { note: 'ok note_1.-' });
  for (const bad of ['', 'x'.repeat(33), 'a;rm', '<b>', 1, undefined]) assert.throws(() => operator.noopArgs(bad));
});

test('states never present acceptance or a timeout as success', () => {
  assert.match(operator.describe({ action: 'operator.noop', state: 'accepted' }), /no result from 4D yet/);
  const late = operator.describe({ action: 'operator.noop', state: 'failed', error: 'outcome_unknown', lateState: 'completed' });
  assert.match(late, /may still have run/);
  assert.match(late, /later reported completed/);
  assert.match(operator.describe({ action: 'operator.noop', state: 'cancelled', error: 'stale_target' }), /never dispatched/);
  assert.equal(operator.reason('unmapped_code'), 'unmapped_code');
});

test('confirmation countdown and ordering', () => {
  assert.equal(operator.secondsLeft('2026-11-14T00:01:00Z', Date.parse('2026-11-14T00:00:00.500Z')), 60);
  assert.equal(operator.secondsLeft('2026-11-14T00:00:00Z', Date.parse('2026-11-14T00:01:00Z')), 0);
  const ordered = operator.newestFirst([{ requestedAt: '2026-11-14T00:00:01Z' }, { requestedAt: '2026-11-14T00:00:02Z' }]);
  assert.equal(ordered[0].requestedAt, '2026-11-14T00:00:02Z');
  assert.deepEqual(operator.headers(), { 'Content-Type': 'application/json', 'X-Dashboard-Action': 'operator' });
});

test('monitor action arguments match the server catalog', () => {
  assert.deepEqual(operator.argsFor('monitor.cadence', { seconds: '5' }), { seconds: 5 });
  for (const bad of ['1', '3', '', '5.5']) assert.throws(() => operator.argsFor('monitor.cadence', { seconds: bad }));
  assert.deepEqual(operator.argsFor('monitor.diagnostics', { note: 'ignored' }), {});
  assert.throws(() => operator.argsFor('monitor.restart', {}));
});

test('cadence and diagnostics are described without overstating', () => {
  assert.match(operator.summary({ action: 'monitor.cadence', args: { seconds: 10 } }), /10 s for this run/);
  assert.equal(operator.cadence({ cadence: { seconds: 5, observedIntervalsMs: [5003, 4998] } }), 'Sampling every 5 s; measured 5.0, 5.0 s.');
  assert.match(operator.cadence({ cadence: { seconds: 2, observedIntervalsMs: [] } }), /no interval measured yet/);
  assert.match(operator.describe({ action: 'monitor.cadence', state: 'failed', error: 'outcome_unknown', lateState: 'completed' }), /not applied/);
  const rows = operator.diagnosticRows({ cadence: { seconds: 5 }, actionStates: { completed: 2 }, viewers: 1 });
  assert.deepEqual(rows, [['cadence', '5 s'], ['actionStates', 'completed 2'], ['viewers', '1']]);
});

test('catalog specs drive argument building for any action', () => {
  const sleep = { id: 'operator.sleep', args: { seconds: { type: 'integer', min: 1, max: 20 } } };
  assert.deepEqual(operator.argsFor('operator.sleep', { seconds: '4' }, sleep), { seconds: 4 });
  for (const bad of ['0', '21', '2.5', '', 'x']) assert.throws(() => operator.argsFor('operator.sleep', { seconds: bad }, sleep));
  assert.throws(() => operator.argsFromSpec({ args: { p: { type: 'path' } } }, { p: '/etc' }));
  assert.match(operator.describe({ action: 'operator.sleep', state: 'running', progress: { phase: 'sleeping', percent: 50 } }), /sleeping 50%/);
  assert.match(operator.describe({ action: 'operator.noop', state: 'completed', unverified: true }), /unverified/);
});

test('cache actions describe their effect and refusals plainly', () => {
  assert.match(operator.summary({ action: 'cache.size', args: { sizeMiB: 2048 } }), /2048 MiB.*host application must approve/);
  assert.match(operator.summary({ action: 'cache.flush', args: {} }), /pending database changes to disk/);
  assert.match(operator.describe({ action: 'cache.size', state: 'failed', error: 'cache_size_policy' }), /75% of physical memory/);
  assert.match(operator.describe({ action: 'cache.size', state: 'failed', error: 'host_denied' }), /did not approve/);
  const size = { args: { sizeMiB: { type: 'integer', min: 100, max: 1048576 } } };
  assert.deepEqual(operator.argsFor('cache.size', { sizeMiB: '2048' }, size), { sizeMiB: 2048 });
  assert.throws(() => operator.argsFor('cache.size', { sizeMiB: '99' }, size));
});

test('log viewer keeps a bounded window and explains failures', () => {
  const lines = n => Array.from({ length: n }, (_, i) => ({ text: String(i) }));
  const forward = operator.mergeLines(lines(1500), lines(800), 'forward', 2000);
  assert.equal(forward.lines.length, 2000); assert.equal(forward.evicted, 300); assert.equal(forward.lines[0].text, '300');
  const backward = operator.mergeLines(lines(1500), lines(800), 'backward', 2000);
  assert.equal(backward.lines.length, 2000); assert.equal(backward.lines.at(-1).text, '1199');
  assert.match(operator.logReason('rotated'), /reopen it/);
  assert.match(operator.logReason('audit_unavailable'), /nothing was shown/);
  assert.deepEqual(Object.fromEntries(new URLSearchParams(operator.logsQuery('v', 'c.1', 'backward', 200))), { view: 'v', cursor: 'c.1', direction: 'backward', limit: '200' });
  assert.match(operator.logFileLabel({ name: 'audit.jsonl', size: 2048, modified: '2026-11-15T00:00:00Z' }), /audit\.jsonl — 2\.0 KiB/);
});

test('log viewer builds filtered and time-jump queries', () => {
  assert.deepEqual(Object.fromEntries(new URLSearchParams(operator.logsQuery('v', 'c.1', 'forward', 50, 'ERROR'))), { view: 'v', cursor: 'c.1', direction: 'forward', limit: '50', level: 'ERROR' });
  assert.equal(new URLSearchParams(operator.logsQuery('v', 'c.1', 'forward', 50, '')).has('level'), false);
  assert.deepEqual(Object.fromEntries(new URLSearchParams(operator.logsJumpQuery('v', '2026-11-15T10:30:15', 200, 'WARN'))), { view: 'v', time: '2026-11-15T10:30:15', limit: '200', level: 'WARN' });
  assert.equal(new URLSearchParams(operator.logsJumpQuery('v', '2026-11-15T10:30', 200)).has('level'), false);
  assert.match(operator.logReason('invalid_time'), /valid date/);
  assert.match(operator.logReason('unsupported_filter'), /no levels/);
  assert.match(operator.logNote({ limited: true }, false), /without finding any/);
  assert.match(operator.logNote({ limited: true }, true), /without finding more/);
  assert.match(operator.logNote({ atTime: false }, false), /No lines at or after/);
  assert.equal(operator.logNote({}, true), '');
});

test('virtual log list draws only the visible rows', () => {
  const none = operator.logWindow(0, 400, 20, 0, 20);
  assert.deepEqual(none, { start: 0, end: 0, padTop: 0, padBottom: 0 });
  // 2000 rows at 20 px: the top shows rows 0..21 plus overscan, never the whole list.
  const top = operator.logWindow(0, 400, 20, 2000, 20);
  assert.equal(top.start, 0); assert.equal(top.end, 41); assert.equal(top.padTop, 0); assert.equal(top.padBottom, (2000 - 41) * 20);
  const middle = operator.logWindow(10000, 400, 20, 2000, 20);
  assert.equal(middle.start, 480); assert.equal(middle.end, 480 + 20 + 21 + 20);
  assert.ok(middle.end - middle.start <= 62);
  assert.equal(middle.padTop + (middle.end - middle.start) * 20 + middle.padBottom, 2000 * 20, 'padding keeps the scroll height');
  const bottom = operator.logWindow(2000 * 20 - 400, 400, 20, 2000, 20);
  assert.equal(bottom.end, 2000); assert.equal(bottom.padBottom, 0);
  // Out-of-range and degenerate inputs stay inside the list.
  assert.equal(operator.logWindow(-50, 400, 20, 10, 20).start, 0);
  assert.equal(operator.logWindow(99999, 400, 20, 10, 20).end, 10);
  assert.deepEqual(operator.logWindow(0, 400, 0, 10, 20), { start: 0, end: 0, padTop: 0, padBottom: 0 });
});
