'use strict';
// Pure operator helpers shared by the page and node tests. See docs/operator-actions.md.
const DashboardOperator = (() => {
  const notePattern = /^[A-Za-z0-9 _.-]{1,32}$/;
  const states = {
    requested: 'Awaiting your confirmation',
    accepted: 'Dispatched; no result from 4D yet',
    running: 'Running in 4D',
    completed: 'Completed',
    failed: 'Failed',
    cancelled: 'Cancelled (never dispatched)',
  };
  const reasons = {
    withdrawn: 'withdrawn by you',
    expired: 'confirmation expired',
    session_expired: 'operator session expired',
    logged_out: 'operator session ended',
    stale_target: 'the instance changed or stopped reporting; request again',
    argument_mismatch: 'confirmation did not match the request',
    wrong_actor: 'confirmed from another operator session',
    busy: 'another action was in flight',
    unknown_confirmation: 'confirmation already used or unknown',
    dispatch_failed: 'could not reach 4D',
    outcome_unknown: 'no result within 30 s; it may still have run',
    audit_unavailable: 'audit log unavailable; nothing ran',
    audit_incomplete: 'completed, but the final audit record could not be written',
    rate_limited: 'too many requests; wait a minute',
    confirmation_limit: 'too many pending confirmations',
    target_unavailable: '4D is not reporting; try again when the stream is live',
    action_not_enabled: 'this action is not enabled by the host',
    invalid_arguments: 'invalid arguments',
    operator_session_limit: 'too many operator sessions',
    invalid_operator_token: 'operator token rejected',
  };
  function tokens(hash) {
    const params = new URLSearchParams(String(hash).replace(/^#/, ''));
    return { viewer: params.get('token'), operator: params.get('operator') };
  }
  function noopArgs(note) {
    if (typeof note !== 'string' || !notePattern.test(note)) throw new Error('Note: 1 to 32 letters, digits, spaces, _ . or -');
    return { note };
  }
  const labels = {
    'operator.noop': 'No-op (changes nothing)',
    'operator.sleep': 'Test: timed no-op',
    'operator.exclusiveSleep': 'Test: timed no-op that pauses sampling',
    'monitor.cadence': 'Sampling interval',
    'monitor.diagnostics': 'Monitor diagnostics',
  };
  // Builds arguments from the catalog's closed specs (text pattern, integer enum or range); the server re-validates.
  function argsFromSpec(entry, fields) {
    const args = {};
    for (const [name, spec] of Object.entries(entry.args || {})) {
      const raw = fields[name];
      if (spec.type === 'text') {
        if (typeof raw !== 'string' || !new RegExp(spec.pattern).test(raw)) throw new Error(`${name}: invalid value`);
        args[name] = raw;
      } else if (spec.type === 'integer') {
        const n = Number(raw);
        const ok = Number.isInteger(n) && String(raw).trim() !== '' && (spec.enum ? spec.enum.includes(n) : n >= spec.min && n <= spec.max);
        if (!ok) throw new Error(spec.enum ? `${name} must be one of ${spec.enum.join(', ')}` : `${name} must be ${spec.min} to ${spec.max}`);
        args[name] = n;
      } else throw new Error(`${name}: unsupported argument type`);
    }
    return args;
  }
  const builtIn = {
    'operator.noop': { args: { note: { type: 'text', pattern: '^[A-Za-z0-9 _.-]{1,32}$' } } },
    'monitor.cadence': { args: { seconds: { type: 'integer', enum: [2, 5, 10] } } },
    'monitor.diagnostics': { args: {} },
  };
  function argsFor(action, fields, entry = builtIn[action]) {
    if (!entry) throw new Error('Unknown action');
    return argsFromSpec(entry, fields);
  }
  function reason(code) { return reasons[code] || code || ''; }
  function describe(record) {
    let text = `${record.action}: ${states[record.state] || record.state}`;
    if (record.error) text += ` (${reason(record.error)})`;
    if (record.lateState) text += `; 4D later reported ${record.lateState} (not applied)`;
    if (record.state === 'running' && record.progress) text += ` (${record.progress.phase} ${record.progress.percent}%)`;
    if (record.state === 'completed' && record.unverified) text += ' (unverified: no observable effect to check)';
    if (record.action === 'monitor.cadence' && record.result) text += `; sampling every ${record.result.seconds} s`;
    return text;
  }
  function summary(confirmation) {
    const args = confirmation.args || {};
    if (confirmation.action === 'monitor.cadence') return `Change the sampling interval to ${args.seconds} s for this run (resets to 2 s on restart)`;
    if (confirmation.action === 'monitor.diagnostics') return 'Collect monitor diagnostics (counters only)';
    if (confirmation.action === 'operator.sleep') return `Run a ${args.seconds} s test no-op on the 4D executor`;
    if (confirmation.action === 'operator.exclusiveSleep') return `Run a ${args.seconds} s test no-op that pauses sampling (viewers see maintenance)`;
    return `${confirmation.action} with note "${args.note}"`;
  }
  function cadence(status) {
    const c = status.cadence;
    if (!c) return '';
    const observed = c.observedIntervalsMs.length ? `measured ${c.observedIntervalsMs.map(ms => (ms / 1000).toFixed(1)).join(', ')} s` : 'no interval measured yet';
    return `Sampling every ${c.seconds} s; ${observed}.`;
  }
  function diagnosticRows(result) {
    const rows = [];
    for (const [key, value] of Object.entries(result || {})) {
      if (key === 'cadence') rows.push(['cadence', `${value.seconds} s`]);
      else if (value !== null && typeof value === 'object') rows.push([key, Object.entries(value).map(([k, v]) => `${k} ${v}`).join(', ') || 'none']);
      else rows.push([key, String(value)]);
    }
    return rows;
  }
  function secondsLeft(expiresAt, now) {
    return Math.max(0, Math.ceil((Date.parse(expiresAt) - now) / 1000));
  }
  function headers() { return { 'Content-Type': 'application/json', 'X-Dashboard-Action': 'operator' }; }
  function newestFirst(records) { return [...records].sort((a, b) => b.requestedAt.localeCompare(a.requestedAt)); }
  return { tokens, noopArgs, argsFor, argsFromSpec, labels, reason, describe, summary, cadence, diagnosticRows, secondsLeft, headers, newestFirst };
})();
if (typeof module !== 'undefined') module.exports = DashboardOperator;
