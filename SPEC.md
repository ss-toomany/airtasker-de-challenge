# Solution Spec

## Asset graph

```
Assets: 
Raw Layer: 
- raw_tasks (DuckDB)
- raw_locations (dbt seed)
- raw_weather_forecast (Open-Meteo api)

Staging Layer:
- stg_tasks (dedup tasks)
- stg_locations (cast missing locations)
- stg_weather_forecast (take hourly rows)

Intermediate Layer: 
- int_tasks_locations_weather_forecast (join tasks, locations with weather forecast)

Presentation Layer: 
- fact_tasks_weather_risk (calculate risk score based on weather for each task)
```

---

## Risk model

**Inputs (Open-Meteo hourly variables):**

| Factor | Open-Meteo field | Unit as returned | Notes |
|---|---|---|---|
| Temperature | `temperature_2m` | °C | used as-is |
| Precipitation | `precipitation` | mm/hour | used as-is |
| Wind speed | `windspeed_10m` | km/h | used as-is |
| Visibility | `visibility` | meters | converted to km (÷1000) before scoring |

**Weather factors are taken on an hourly basis. For each factor, a score between 1 to 3 is assigned based on 
- temperature: min = 9, max = 25 
- precipitation: max = 10mm 
- wind speed: max = 28km/h 
- visibility: min = 1km 

| Score | Temperature (°C) | Precipitation (mm) | Wind speed (km/h) | Visibility (km) |
|---|---|---|---|---|
| 1 (low) | 13 – 21 | < 2.5 | < 10 | > 10 |
| 2 (medium) | 9–13 or 21–25 | 2.5 – 10 | 10 – 28 | 1 – 10 |
| 3 (high) | < 9 or > 25 | > 10 | > 28 | < 1 |


**`weather_risk_label`** — driven by the single worst factor, not an average:
- any factor scores 3 → `HIGH`
- else any factor scores 2 → `MEDIUM`
- else (all four factors score 1) → `LOW`

**`weather_risk_score`** — numeric companion to the label: sum of the four
factor scores, range 4–12 (higher = riskier).

**Which time field, and which hour(s):**

Priority order — `scheduled_at` → `assigned_at` → `posted_at`:

1. If `scheduled_at` is present, score using the single hour
   containing `scheduled_at`.
2. Else if `assigned_at` is present, score using the single hour
   containing `assigned_at` (floored to the hour if not exactly on one).
3. Else (typically `open` tasks with neither), fall back to `posted_at`:
   score every hour in the 72 hours following `posted_at`, then take the
   modal `weather_risk_label` across those 72 hourly labels. Ties are
   broken toward the higher-severity label (`HIGH` > `MEDIUM` > `LOW`).
   `weather_risk_score` in this case is the average of the 72 hourly scores.

**Category scope — applied uniformly, not filtered:** each task is scored the same way regardless of the category to handle ambiguous categories that could be either indoor or outdoor (such as Event Setup, Cleaning, Photography) and to provide more insights for analytics (are people posting jobs for online tutoring vs in person tutoring because of a weather factor?).

**Out-of-range tasks:** if the relevant time field falls outside the fetched
16-day forecast or 92 days past window (or the task's `location_id` doesn't resolve — see
Data Quality), `weather_risk_score` is `null` and `weather_risk_label` is
`unknown` rather than a guessed value. Future: if I had to do this in production, depending on the purpose of the asset, it would be better to look at current weather stats for open tasks. 

---

## Data quality

- **Duplicate `task_id`s** — some rows appear more than once with different
  `posted_at` values (replication glitch, per the brief). Fixed in
  `stg_tasks` by keeping only the most recent row per `task_id`
  (`row_number() over (partition by task_id order by posted_at desc) = 1`).
- **Orphaned `location_id`s** — some tasks reference a `location_id` absent
  from `locations_raw`. Handled with a left join from tasks to locations in
  the mart, so these rows survive with `weather_risk_label = 'unknown'`
  instead of being silently dropped — keeps them visible/auditable.

---

## Assumptions

- Weather stats are fetched and stored in UTC, matched directly against the UTC
  timestamp columns on `tasks_raw` — avoids needing each location's
  timezone for the join.
- `raw_weather_forecast` is called once per distinct location (~20 rows in
  `locations_raw`), not once per task, since many tasks share a location.
- `raw_weather_forecast` requests `forecast_days=16` (covers `scheduled_at`
  up to 14 days out) and `past_days=92` (covers `completed`/`cancelled`
  tasks' `scheduled_at`) in the same API call per location — so both
  future and recent-past tasks are scored from the same table.
- Risk is scored for tasks in every `state` (including `completed` /
  `cancelled`) if they have a resolvable time field — state-based filtering
  is treated as a downstream reporting concern, not something the pipeline
  should bake in. `completed` tasks resolve using observed (actual, not
  forecast) weather for their `scheduled_at` hour, which is if anything more
  accurate than a forecast would be.
