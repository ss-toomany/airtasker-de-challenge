# Decisions

Trade-offs made to fit this in scope, and what I'd change in a real production system.

## Trade-offs made

- **Risk scoring is uniform across task categories** — a `Tax Return` and a
  `Roof Cleaning` job get the same four-factor treatment. Considered
  gating/weighting by category (outdoor vs. indoor), but several categories
  are genuinely ambiguous (Photography, Event Setup, Cleaning), and a
  category-weighted model felt more subjective than the threshold-based
  scoring itself. Documented as a known simplification in `SPEC.md` rather
  than a hidden one.
- **`weather_risk_score` is my own addition, not fully specified upfront** —
  the original scoring rules only defined how to derive `weather_risk_label`
  (worst-factor rule); I defined the numeric score as the sum of the 4
  factor scores (range 4–12) since the brief requires both columns.
- **`raw_weather_forecast` is not incremental.** Every materialization
  re-fetches the full 108-day window (92 past + 16 forecast) for every
  location and does `CREATE OR REPLACE TABLE`, discarding whatever was
  there before. Fine at ~20 locations/one-off run; wasteful and lossy at
  real scale (see below).
- **No retry logic on the Open-Meteo calls.** Error handling (P2) only
  covers *failing gracefully* — logging and skipping a bad location rather
  than crashing the whole run. Deliberately kept separate from retry
  policy, since backoff strategy and which errors are worth retrying is
  its own design decision, not a one-line addition.
- **The unit test covers the per-factor thresholds, not the mart's
  aggregation.** `int_tasks_locations_weather_forecast`'s scoring logic
  (HIGH/MEDIUM/LOW bands) is unit-tested; `fact_tasks_weather_risk`'s
  mode-with-tiebreak and average-score aggregation isn't. Prioritized the
  more error-prone piece (four independent, asymmetric threshold bands)
  given the "at least 1" bar.

## What I'd do differently in production

- **Partition the ingestion asset** (by day, and likely by location too)
  instead of one monolithic fetch-everything run. Smaller units of work
  means independent retries/backfills instead of re-running everything on
  any single failure.
- **Make ingestion incremental**, keyed on `(location_id, time)`, instead
  of full overwrite. Two reasons: avoid re-fetching unchanged historical
  data, and — more importantly — *stop destroying forecast history*. A
  forecast for next Tuesday made today isn't the same as one made a week
  ago; overwriting means losing the ability to ever ask "what did the
  forecast look like when this task was scheduled/cancelled?"
- **At real scale (e.g. ~1M distinct locations), deduplicate geospatially
  before fetching**, not after. Weather models have a fixed grid
  resolution (~9–25km); two locations a few km apart return identical
  underlying data. Snapping to a coarser grid first turns "1M locations"
  into a much smaller, more honest number of actual API calls — a better
  fix than just parallelizing the naive per-location loop.
- **Add retry logic** with exponential backoff on transient failures
  (timeouts, 5xx) — explicitly not on 4xx client errors, which won't
  succeed on retry and just waste time/quota.
- **Swap DuckDB for a real concurrent warehouse** (Snowflake/BigQuery/
  Redshift-equivalent) before this went anywhere near production. Not a
  volume problem — the actual pain, which came up repeatedly while
  building this — is DuckDB's single-writer file lock: an interactive
  `duckdb` shell left open blocks `dbt`/Dagster from writing at all, with
  no queuing, just a hard lock error. Fine for local dev, not for a
  system with more than one person/process touching it.
- **Extend unit test coverage to the mart's aggregation logic** (mode +
  tie-break, average score across matched hours), not just the per-factor
  thresholds.
- **Wire up dbt source freshness checks** for `raw_tasks` and
  `raw_weather_forecast` so "how stale is this data" is an observable,
  alertable fact instead of an unanswered question in the Dagster UI.
