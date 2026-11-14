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
    'monitor.cadence': 'Sampling interval',
    'monitor.diagnostics': 'Monitor diagnostics',
  };
  function argsFor(action, fields) {
    if (action === 'operator.noop') return noopArgs(fields.note);
    if (action === 'monitor.cadence') {
      const seconds = Number(fields.seconds);
      if (![2, 5, 10].includes(seconds)) throw new Error('Interval must be 2, 5 or 10 seconds');
      return { seconds };
    }
    if (action === 'monitor.diagnostics') return {};
    throw new Error('Unknown action');
  }
  function reason(code) { return reasons[code] || code || ''; }
  function describe(record) {
    let text = `${record.action}: ${states[record.state] || record.state}`;
    if (record.error) text += ` (${reason(record.error)})`;
    if (record.lateState) text += `; 4D later reported ${record.lateState} (not applied)`;
    if (record.action === 'monitor.cadence' && record.result) text += `; sampling every ${record.result.seconds} s`;
    return text;
  }
  function summary(confirmation) {
    const args = confirmation.args || {};
    if (confirmation.action === 'monitor.cadence') return `Change the sampling interval to ${args.seconds} s for this run (resets to 2 s on restart)`;
    if (confirmation.action === 'monitor.diagnostics') return 'Collect monitor diagnostics (counters only)';
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
  return { tokens, noopArgs, argsFor, labels, reason, describe, summary, cadence, diagnosticRows, secondsLeft, headers, newestFirst };
})();
if (typeof module !== 'undefined') module.exports = DashboardOperator;
