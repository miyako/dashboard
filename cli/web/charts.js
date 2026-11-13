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
    { id: 'disk-bytes', label: 'Disk I/O (bytes)', unit: 'bytes', mirrored: true, metrics: [
      { id: 'database.diskReadBytes', label: 'Read' },
      { id: 'database.diskWriteBytes', label: 'Write' },
    ] },
    { id: 'disk-count', label: 'Disk I/O (operations)', unit: 'operations', mirrored: true, metrics: [
      { id: 'database.diskReadCount', label: 'Read' },
      { id: 'database.diskWriteCount', label: 'Write' },
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
  function plot(samples, end, { integer = false, range } = {}) {
    const start = end - windowMs;
    const visible = samples.filter(p => Date.parse(p.at) >= start && Date.parse(p.at) <= end);
    const values = visible.filter(p => Number.isFinite(p.value)).map(p => p.value);
    let lo = range ? range.lo : Math.min(0, ...values), hi = range ? range.hi : Math.max(1, ...values);
    if (integer && !range) {
      const step = Math.max(1, Math.ceil((hi - lo) / 3));
      lo = Math.floor(lo / step) * step; hi = lo + step * 3;
    }
    let drawing = false;
    let previousAt;
    const path = visible.map(p => {
      if (!Number.isFinite(p.value)) { drawing = false; return ''; }
      if (previousAt !== undefined && Date.parse(p.at) - previousAt > 15000) drawing = false;
      const x = 56 + (Date.parse(p.at) - start) * 524 / windowMs;
      const y = 170 - (p.value - lo) * 150 / (hi - lo);
      const point = drawing && integer ? `H${x.toFixed(2)} V${y.toFixed(2)}` : `${drawing ? 'L' : 'M'}${x.toFixed(2)},${y.toFixed(2)}`;
      drawing = true; previousAt = Date.parse(p.at);
      return point;
    }).join(' ');
    return { path, lo, hi, start, end, count: values.length };
  }
  function overlay(series, end, integer = false) {
    const scale = plot(series.flat(), end, { integer });
    return { scale, plots: series.map(samples => plot(samples, end, { integer, range: scale })) };
  }
  function mirror(series, end, integer = false) {
    const signed = series.map((samples, i) => samples.map(sample => ({
      ...sample, value: i === 1 && Number.isFinite(sample.value) ? -sample.value : sample.value,
    })));
    const bounds = plot(signed.flat(), end);
    let magnitude = Math.max(Math.abs(bounds.lo), bounds.hi);
    if (integer) magnitude = Math.max(2, Math.ceil(magnitude / 2) * 2);
    const range = { lo: -magnitude, hi: magnitude };
    return { scale: plot(signed.flat(), end, { range }), series: signed,
      plots: signed.map(samples => plot(samples, end, { integer, range })) };
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
  return { windowMs, hasGraph, overlaps, mirrors, integerUnit, rate, plot, overlay, mirror, entities, cpu };
})();
if (typeof module !== 'undefined') module.exports = DashboardCharts;
