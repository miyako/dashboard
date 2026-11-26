# Measurement history contract (M5)

Written before the implementation; the reference for `cli/history.go`, the
`/api/history` route and the chart range picker.

## Owner decisions

| Decision | Choice |
| --- | --- |
| Where | In the Go CLI's memory: one shared record for every viewer, recorded whether or not a browser is open |
| Retention | Raw samples for the last hour; 1-minute buckets for the last 24 hours |
| Restarts | History starts empty with each CLI run; nothing is written to disk |
| Browser storage | None; viewers fetch windows on demand |

## What is recorded

- Every **dynamic numeric** metric (`type:"number"`, `kind` `gauge` or
  `counter`), as reported in `snapshot`/`update` frames. No text, booleans,
  static values, process or session lists, or activity identities. Process and
  session **counts** are already numeric gauges and are recorded.
- At most **72 series** (64 for 4D plus room for the CLI's own five `cli.*` gauges). A new series beyond 72 is not recorded.
- Times are the frame's `sampledAt`, never the browser's clock. Retention is
  measured back from the newest recorded sample, so it is deterministic.

## Tiers

| Tier | Holds | Bound |
| --- | --- | --- |
| Raw | Each sample: time and value, or an explicit gap when the metric was unavailable | Last hour, and at most 1800 points per series |
| Minute | One bucket per UTC minute with any sample | Last 24 hours, at most 1440 per series |

The 1800-point raw cap equals one hour at the 2-second default. Manual
refreshes (at most one per second) can shorten raw coverage; minute buckets
are unaffected.

Bucket fields: `count` (available samples), `gaps` (unavailable samples),
`min`, `max`, `mean`, `last` (null when `count` is 0) and, for counters,
`rate` and `resets`.

Counter rates keep the live graphs' elapsed-time rules. An increment between
two consecutive available samples counts only when the later value is not
smaller and they are 0–15 s apart. A decrease is a **reset**: it is counted,
never treated as negative traffic. `rate` = summed increments / summed
elapsed seconds of those increments, assigned to the bucket of the later
sample, or null when no increment qualified. Rates are never averaged across
resets.

Worst-case memory: 72 series × (1800 raw + 1440 buckets), about 10 MB.

## API

`GET /api/history?metric=<id>&from=<RFC3339>&to=<RFC3339>&resolution=raw|minute`

- Needs the viewer cookie, like every `/api/` route. Read-only GET with exactly
  these four parameters, each once; anything else gives 400.
- `from < to`. Span at most 24 h, and at most 1 h for `raw`. An unknown metric
  ID gives 404.
- At most 240 history requests per minute per CLI; otherwise 429.
- Response: `metric {id,label,unit,kind}`, `resolution`, `from`, `to`,
  `coverage {rawSince, minuteSince}` (null when empty) and `points`, ordered
  by time and only those inside `[from, to]`. Raw points are `{at, value|null}`;
  minute points are `{at, count, gaps, min, max, mean, last[, rate, resets]}`.
- The SSE state is unchanged: viewers still receive the 60-point live history.

## Browser

- A range picker: **Live (2 min)**, 15 min, 1 h, 6 h, 24 h. Live behaves as
  before. Other ranges show a fixed window ending when it was chosen, with
  **Earlier** / **Later** (half-window steps) and **Back to live**.
- Up to 1 h uses raw samples; longer ranges use minute buckets, drawn as
  the mean (gauges), last value (counter totals) or rate (counter rates),
  with a min–max band for gauges, and labelled "1-minute buckets".
- Gaps stay gaps: no line across missing samples or empty minutes. The
  chart says where recorded history begins, so time before the CLI started is
  not shown as zero.
- Cards keep showing the latest live values. Process and session timelines
  stay live-only.

## Not in scope

Persistence across CLI restarts, browser storage, per-identity process or
session history, export, and aggregation across instances.
