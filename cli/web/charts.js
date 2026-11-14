'use strict';
const DashboardCharts = (() => {
  const windowMs = 120000;
  function hasGraph(metric) {
    return metric.type === 'number' && metric.kind !== 'static' && metric.id !== 'app.uptime';
  }
  const overlaps = [
    { id: 'network', label: 'Network traffic (machine)', unit: 'B/s', metrics: [
      { id: 'app.networkInputThroughput', label: 'Inbound' },
      { id: 'app.networkOutputThroughput', label: 'Outbound' },
    ] },
    { id: 'cache', label: 'Cache memory', unit: 'bytes', metrics: [
      { id: 'cache.usedMem', label: 'Used' },
      { id: 'cache.maxMem', label: 'Capacity' },
    ] },
  ];
  const mirrors = [
    { id: 'disk-bytes', label: 'Database I/O (bytes)', unit: 'bytes', mirrored: true, metrics: [
      { id: 'database.diskReadBytes', label: 'Disk read' },
      { id: 'database.diskWriteBytes', label: 'Disk write' },
      { id: 'database.cacheReadBytes', label: 'Cache read' },
      { id: 'database.cacheMissBytes', label: 'Cache miss' },
    ] },
    { id: 'disk-count', label: 'Database I/O (operations)', unit: 'operations', mirrored: true, metrics: [
      { id: 'database.diskReadCount', label: 'Disk read' },
      { id: 'database.diskWriteCount', label: 'Disk write' },
      { id: 'database.cacheReadCount', label: 'Cache read' },
      { id: 'database.cacheMissCount', label: 'Cache miss' },
    ] },
  ];
  function integerUnit(unit) {
    return ['records', 'processes', 'sessions', 'operations'].includes(unit);
  }
  function rate(samples) {
    return samples.map((sample, i) => {
      const previous = samples[i - 1];
      const seconds = previous ? (Date.parse(sample.at) - Date.parse(previous.at)) / 1000 : 0;
      const value = seconds > 0 && seconds <= 15 && Number.isFinite(sample.value) && Number.isFinite(previous.value) && sample.value >= previous.value
        ? (sample.value - previous.value) / seconds : null;
      return { at: sample.at, value };
    });
  }
  // History ranges: live keeps the two-minute window; longer ranges read /api/history.
  const ranges = { live: windowMs, '15m': 900000, '1h': 3600000, '6h': 21600000, '24h': 86400000 };
  function resolution(span) { return span <= 3600000 ? 'raw' : 'minute'; }
  function view(range, end) {
    const span = ranges[range] || windowMs;
    return { range, windowMs: span, end, resolution: resolution(span), gapMs: resolution(span) === 'minute' ? 90000 : 15000 };
  }
  function historyQuery(id, v) {
    return new URLSearchParams({ metric: id, from: new Date(v.end - v.windowMs).toISOString(), to: new Date(v.end).toISOString(), resolution: v.resolution }).toString();
  }
  function rangeNote(v, coverageStarts, locale) {
    if (v.range === 'live') return 'Live: rolling two-minute window / up to 60 actual samples. Gaps mean unavailable data, not zero. Refresh collects a new sample.';
    const time = ms => new Date(ms).toLocaleString(locale, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
    let note = `History ${time(v.end - v.windowMs)} – ${time(v.end)} / ${v.resolution === 'raw' ? 'every recorded sample' : '1-minute buckets (line: mean or rate; band: min–max)'}. Gaps mean unavailable data or no recording, not zero.`;
    const starts = coverageStarts.filter(Boolean).map(Date.parse);
    if (starts.length && Math.min(...starts) > v.end - v.windowMs) note += ` Recording began ${time(Math.min(...starts))} (history starts empty with each dashboard run).`;
    else if (!starts.length) note += ' Nothing recorded for this range yet.';
    return note + ' Cards show latest live values; process and session timelines stay live.';
  }
  // Status flags that seldom change live on Instance information, still updated every sample (#17).
  const instanceStatusIDs = ['datastore.adminProtected', 'datastore.locked', 'web.running'];
  // Which view a metric card belongs to; null hides it. Retained-license records exist only on 4D Server.
  function placement(metric, role) {
    if (metric.id.startsWith('license.usage.') && role !== 'server') return null;
    if (metric.kind === 'static' || metric.id === 'app.uptime' || instanceStatusIDs.includes(metric.id)) return 'static-metrics';
    if (metric.id.startsWith('database.')) return 'database-metrics';
    if (metric.id.startsWith('process.')) return 'process-trends';
    if (metric.id.startsWith('session.')) return 'session-trends';
    return 'metrics';
  }
  // Live graphs glide left between redraws: the plot moves as time passes since it was drawn.
  function scrollOffset(drawnAt, now, span) { return -Math.max(0, now - drawnAt) * 524 / span; }
  const refreshReasons = {
    collector_timeout: '4D did not answer within 10 s',
    collector_busy: '4D was busy collecting; try again',
  };
  // Only the refresh this browser requested produces a notification; scheduled samples never do.
  function refreshOutcome(lastAction, pendingId) {
    if (!pendingId || !lastAction || lastAction.id !== pendingId) return null;
    return lastAction.ok ? { kind: 'ok', text: 'Sample refreshed' }
      : { kind: 'fail', text: `Refresh failed: ${refreshReasons[lastAction.error] || lastAction.error || 'unknown error'}` };
  }
  function fromRaw(points) { return points.map(p => ({ at: p.at, value: p.value })); }
  // Minute buckets are drawn at their midpoint; empty buckets are gaps, never zero.
  function fromMinute(points, mode) {
    return points.map(p => {
      const at = new Date(Date.parse(p.at) + 30000).toISOString();
      const value = p[mode] ?? null;
      return mode === 'mean' ? { at, value, min: p.min ?? null, max: p.max ?? null } : { at, value };
    });
  }
  function plot(samples, end, { integer = false, range, windowMs: span = windowMs, gapMs = 15000 } = {}) {
    const start = end - span;
    const visible = samples.filter(p => Date.parse(p.at) >= start && Date.parse(p.at) <= end);
    const values = visible.flatMap(p => [p.value, p.min, p.max]).filter(Number.isFinite);
    let lo = range ? range.lo : Math.min(0, ...values), hi = range ? range.hi : Math.max(1, ...values);
    if (integer && !range) {
      const step = Math.max(1, Math.ceil((hi - lo) / 3));
      lo = Math.floor(lo / step) * step; hi = lo + step * 3;
    }
    let drawing = false;
    let previousAt;
    const path = visible.map(p => {
      if (!Number.isFinite(p.value)) { drawing = false; return ''; }
      if (previousAt !== undefined && Date.parse(p.at) - previousAt > gapMs) drawing = false;
      const x = 56 + (Date.parse(p.at) - start) * 524 / span;
      const y = 170 - (p.value - lo) * 150 / (hi - lo);
      const point = drawing && integer ? `H${x.toFixed(2)} V${y.toFixed(2)}` : `${drawing ? 'L' : 'M'}${x.toFixed(2)},${y.toFixed(2)}`;
      drawing = true; previousAt = Date.parse(p.at);
      return point;
    }).join(' ');
    return { path, band: band(visible, start, span, gapMs, lo, hi), lo, hi, start, end, windowMs: span,
      count: visible.filter(p => Number.isFinite(p.value)).length };
  }
  // Closed min-max polygons per contiguous run of buckets that carry both bounds.
  function band(visible, start, span, gapMs, lo, hi) {
    const runs = [];
    let run = [], previousAt;
    for (const p of visible) {
      const at = Date.parse(p.at);
      if (!Number.isFinite(p.min) || !Number.isFinite(p.max) || (previousAt !== undefined && at - previousAt > gapMs)) {
        if (run.length) runs.push(run);
        run = [];
      }
      if (Number.isFinite(p.min) && Number.isFinite(p.max)) run.push(p);
      previousAt = at;
    }
    if (run.length) runs.push(run);
    const x = p => (56 + (Date.parse(p.at) - start) * 524 / span).toFixed(2);
    const y = v => (170 - (v - lo) * 150 / (hi - lo)).toFixed(2);
    return runs.filter(r => r.length > 1).map(r => 'M' + r.map(p => `${x(p)},${y(p.max)}`).join(' L') +
      ' L' + [...r].reverse().map(p => `${x(p)},${y(p.min)}`).join(' L') + ' Z').join(' ');
  }
  function overlay(series, end, integer = false, options = {}) {
    const scale = plot(series.flat(), end, { integer, ...options });
    return { scale, plots: series.map(samples => plot(samples, end, { integer, range: scale, ...options })) };
  }
  function mirror(series, end, integer = false, options = {}) {
    const signed = series.map((samples, i) => samples.map(sample => ({
      ...sample, value: i === 1 && Number.isFinite(sample.value) ? -sample.value : sample.value,
    })));
    const bounds = plot(signed.flat(), end, options);
    let magnitude = Math.max(Math.abs(bounds.lo), bounds.hi);
    if (integer) magnitude = Math.max(2, Math.ceil(magnitude / 2) * 2);
    const range = { lo: -magnitude, hi: magnitude };
    return { scale: plot(signed.flat(), end, { range, ...options }), series: signed,
      plots: signed.map(samples => plot(samples, end, { integer, range, ...options })) };
  }
  function entities(samples, kind, id) {
    return samples.map(sample => {
      const items = sample[kind].entities;
      const entity = items?.[id];
      return { at: sample.at, state: items === null ? 'unavailable' : entity ? entity.state : 'absent',
        value: entity?.cpu === undefined ? null : entity.cpu * 100 };
    });
  }
  function cpu(samples) {
    return samples.map(sample => {
      const items = sample.processes.entities;
      const values = items === null ? [] : Object.values(items);
      return { at: sample.at, value: items === null || values.some(e => e.cpu === undefined)
        ? null : values.reduce((sum, e) => sum + e.cpu * 100, 0) };
    });
  }
  return { windowMs, ranges, resolution, view, historyQuery, rangeNote, instanceStatusIDs, placement, scrollOffset, refreshOutcome, fromRaw, fromMinute, hasGraph, overlaps, mirrors, integerUnit, rate, plot, band, overlay, mirror, entities, cpu };
})();
if (typeof module !== 'undefined') module.exports = DashboardCharts;
