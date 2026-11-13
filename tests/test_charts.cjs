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

test('license counts use integer ticks and step traces without fractional interpolation', () => {
  const samples = [{at:at(0),value:1}, {at:at(2),value:2}, {at:at(4),value:null}, {at:at(6),value:0}];
  const plot = charts.plot(samples, Date.parse(at(120)), {integer:charts.integerUnit('records')});
  assert.equal(plot.path, 'M56.00,120.00 H64.73 V70.00  M82.20,170.00');
  assert.ok([0,1,2,3].every(i => Number.isInteger(plot.hi - (plot.hi-plot.lo)*i/3)));
  const empty = charts.plot([], Date.parse(at(120)), {integer:true});
  assert.ok([0,1,2,3].every(i => Number.isInteger(empty.hi - (empty.hi-empty.lo)*i/3)));
});

test('overlapping traces share a scale without summing capacity and usage or bridging gaps', () => {
  const used = [{at:at(0),value:60}, {at:at(2),value:null}, {at:at(4),value:20}];
  const capacity = [{at:at(0),value:100}, {at:at(4),value:100}];
  const overlay = charts.overlay([used,capacity], Date.parse(at(120)));
  assert.equal(overlay.scale.hi, 100);
  assert.equal(overlay.plots[0].path, 'M56.00,80.00  M73.47,140.00');
  assert.equal(overlay.plots[1].path, 'M56.00,20.00 L73.47,20.00');
  assert.ok(overlay.plots.every(plot => plot.lo === 0 && plot.hi === 100));
});

test('mirrored disk I/O centers zero with reads above and writes below on an equal scale', () => {
  const read = [{at:at(0),value:100}, {at:at(2),value:null}, {at:at(4),value:20}];
  const write = [{at:at(0),value:20}, {at:at(4),value:100}];
  const mirror = charts.mirror([read,write], Date.parse(at(120)));
  assert.equal(mirror.scale.hi, 100);
  assert.equal(mirror.scale.lo, -100);
  assert.equal(mirror.plots[0].path, 'M56.00,20.00  M73.47,80.00');
  assert.equal(mirror.plots[1].path, 'M56.00,110.00 L73.47,170.00');
  assert.equal((mirror.scale.hi + mirror.scale.lo) / 2, 0);
  assert.equal(write[1].value, 100);
  const missingRead = charts.mirror([[],write], Date.parse(at(120)));
  assert.equal(missingRead.plots[0].count, 0);
  assert.equal(missingRead.plots[1].path, mirror.plots[1].path);
  const empty = charts.mirror([[],[]], Date.parse(at(120)));
  assert.equal(empty.scale.hi, 1);
  assert.equal(empty.scale.lo, -1);
});

test('mirrored counter rates are computed before flipping writes and retain resets and integer totals', () => {
  const writes = [{at:at(0),value:10}, {at:at(2),value:30}, {at:at(4),value:1}, {at:at(6),value:5}];
  const mirror = charts.mirror([[],charts.rate(writes)], Date.parse(at(120)));
  assert.deepEqual(mirror.series[1].map(p=>p.value), [null,-10,null,-2]);
  const totals = charts.mirror([[],writes], Date.parse(at(120)), true);
  assert.ok([0,1,2,3,4].every(i => Number.isInteger(totals.scale.hi - (totals.scale.hi-totals.scale.lo)*i/4)));
});

test('cache reads and misses overlay with disk reads rather than contributing to a stacked total', () => {
  const series = [100,80,90,40].map(value=>[{at:at(0),value}]);
  const mirror = charts.mirror(series, Date.parse(at(120)));
  assert.equal(mirror.scale.hi, 100);
  assert.equal(mirror.scale.lo, -100);
  assert.deepEqual(mirror.plots.map(p=>p.path),
    ['M56.00,20.00','M56.00,155.00','M56.00,27.50','M56.00,65.00']);
  assert.deepEqual(mirror.series.map(s=>s[0].value), [100,-80,90,40]);
  const missing = charts.mirror([series[0],series[1],[],[{at:at(0),value:null}]], Date.parse(at(120)));
  assert.equal(missing.plots[2].count, 0);
  assert.equal(missing.plots[3].count, 0);
  assert.equal(missing.plots[1].path, mirror.plots[1].path);
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
