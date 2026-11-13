'use strict';
const DashboardCharts = (() => {
  const windowMs = 120000;
  function hasGraph(metric) {
    return metric.type === 'number' && metric.kind !== 'static' && metric.id !== 'app.uptime';
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
  function plot(samples, end) {
    const start = end - windowMs;
    const visible = samples.filter(p => Date.parse(p.at) >= start && Date.parse(p.at) <= end);
    const values = visible.filter(p => Number.isFinite(p.value)).map(p => p.value);
    const lo = Math.min(0, ...values), hi = Math.max(1, ...values);
    let drawing = false;
    let previousAt;
    const path = visible.map(p => {
      if (!Number.isFinite(p.value)) { drawing = false; return ''; }
      if (previousAt !== undefined && Date.parse(p.at) - previousAt > 15000) drawing = false;
      const x = 56 + (Date.parse(p.at) - start) * 524 / windowMs;
      const y = 170 - (p.value - lo) * 150 / (hi - lo);
      const command = drawing ? 'L' : 'M'; drawing = true; previousAt = Date.parse(p.at);
      return `${command}${x.toFixed(2)},${y.toFixed(2)}`;
    }).join(' ');
    return { path, lo, hi, start, end, count: values.length };
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
  return { windowMs, hasGraph, rate, plot, entities, cpu };
})();
if (typeof module !== 'undefined') module.exports = DashboardCharts;
