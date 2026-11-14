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
