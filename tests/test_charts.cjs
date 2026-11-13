const { test } = require('node:test');
const assert = require('node:assert/strict');
const charts = require('../cli/web/charts.js');
const at = seconds => new Date(Date.UTC(2026, 10, 13) + seconds * 1000).toISOString();

test('chart uses elapsed time, shows single samples and does not bridge unavailable or stale gaps', () => {
  const plot = charts.plot([{ at: at(0), value: 0 }, { at: at(2), value: 10 }, { at: at(3), value: null },
    { at: at(10), value: 20 }, { at: at(40), value: 30 }], Date.parse(at(120)));
  assert.equal(plot.path, 'M56.00,170.00 L64.73,120.00  M99.67,70.00 M230.67,20.00');
  assert.equal(plot.count, 4);
  assert.equal(charts.plot([{ at: at(0), value: 10 }], Date.parse(at(121))).count, 0);
  assert.equal(charts.plot([{ at: at(0), value: null }], Date.parse(at(120))).count, 0);
});

test('counter rates use elapsed seconds and break on resets, gaps and duplicate timestamps', () => {
  const samples = [0, 2, 4, 6, 8, 8, 30].map((n, i) => ({ at: at(n), value: [0, 20, null, 50, 5, 10, 20][i] }));
  assert.deepEqual(charts.rate(samples).map(p => p.value), [null, 10, null, null, null, null, null]);
});

test('uptime is a readout while changing license usage stays graphed', () => {
  assert.equal(charts.hasGraph({ id: 'app.uptime', type: 'number', kind: 'gauge' }), false);
  assert.equal(charts.hasGraph({ id: 'license.usage.records', type: 'number', kind: 'gauge' }), true);
  assert.equal(charts.hasGraph({ id: 'system.cores', type: 'number', kind: 'static' }), false);
});

test('identity tracking distinguishes disappearance from enumeration failure and missing CPU', () => {
  const samples = [
    { at: at(0), processes: { entities: { 'p:1': { state: 'executing', cpu: 0.1 } } } },
    { at: at(2), processes: { entities: { 'p:1': { state: 'waiting' } } } },
    { at: at(4), processes: { entities: {} } },
    { at: at(6), processes: { entities: null } },
  ];
  const series = charts.entities(samples, 'processes', 'p:1');
  assert.deepEqual(series.map(p => p.state), ['executing', 'waiting', 'absent', 'unavailable']);
  assert.deepEqual(series.map(p => p.value), [10, null, null, null]);
  assert.deepEqual(charts.cpu(samples).map(p => p.value), [10, null, 0, null]);
});
