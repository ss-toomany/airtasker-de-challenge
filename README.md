# Data Engineering Take-Home Challenge

## Overview

You are building a data pipeline for a marketplace platform. The platform has tasks posted by users — things like "Roof Cleaning in Sydney" or "Tax Return in London" — each associated with a city location.

The product team wants to surface a **weather risk score** for tasks with upcoming scheduled work: given a task's location and when it's scheduled to happen, how much does the weather forecast put it at risk?

Your job is to design and build a pipeline that enriches task data with weather forecasts and produces a risk score per task.

---

## The Stack

- **Dagster** — orchestration and asset definitions
- **dbt Core** — data transformation (connected to Dagster via `dagster-dbt`)
- **DuckDB** — local data warehouse
- **Python** — ingestion assets and business logic
- **Open-Meteo** — weather forecast API (free, no API key required)

The boilerplate repo has Docker Compose and a Dagster project scaffold.

```bash
docker compose up   # or: make up
```

Once the startup sequence finishes, open **http://localhost:3000** in your browser to access the Dagster UI.

### Querying DuckDB

The DuckDB database file is written to `./data/challenge.duckdb` and can be queried directly from your host machine once the pipeline has run.

**Via CLI:**
```bash
duckdb ./data/challenge.duckdb

# Once in the DuckDB shell:
SHOW ALL TABLES;                        -- list all tables across all schemas
SELECT * FROM <schema>.<table> LIMIT 10;
.quit                                   -- exit the shell
```

**Via Python:**
```python
import duckdb
con = duckdb.connect("./data/challenge.duckdb")
con.sql("SELECT * FROM ...").show()
```

---

## Data Provided

Two seed tables are loaded into DuckDB via `dbt seed`.

### `tasks_raw`

| Column | Type | Description |
|---|---|---|
| `task_id` | string | Unique task identifier |
| `title` | string | Task title |
| `category` | string | Task category (see below) |
| `location_id` | string | FK to `locations_raw` |
| `posted_at` | timestamp | When the task was posted (UTC) |
| `state` | string | `open`, `assigned`, `completed`, `cancelled` |
| `budget` | numeric | Task budget |
| `assigned_at` | timestamp | When the task was assigned (UTC). NULL if not yet assigned. |
| `scheduled_at` | timestamp | When the work is scheduled to occur (UTC). Present on assigned tasks. |

**Categories in the dataset:** Gardening, Roof Cleaning, Lawn Mowing, Pool Cleaning, Exterior Painting, Tax Return, Online Tutoring, Graphic Design, Bookkeeping, Photography, Event Setup, Moving & Removals, Cleaning

### `locations_raw`

| Column | Type | Description |
|---|---|---|
| `location_id` | string | Unique location identifier |
| `city` | string | City name |
| `country` | string | Country code (`AU`, `US`, `GB`) |
| `lat` | float | Latitude |
| `lng` | float | Longitude |
| `timezone` | string | IANA timezone string |

Locations span Australia, the United States, and the United Kingdom.

### Known data quality issues

We're flagging these upfront because a real ticket would include this context — but there may be other issues we haven't mentioned:

- **Duplicate task IDs:** Some tasks appear more than once with different `posted_at` timestamps. This is a replication glitch. Keep the most recent record.
- **Orphaned location references:** Some tasks reference a `location_id` that doesn't exist in `locations_raw`. Your pipeline should handle this gracefully.

---

## Weather API

Use the **Open-Meteo forecast API** — free, no key required.

Documentation: https://open-meteo.com/en/docs

Relevant endpoint: `GET https://api.open-meteo.com/v1/forecast`

Read the API docs. The parameters you choose will affect the correctness of your output.

---

## What to Build

Work through these in order. Timebox: incomplete P1 work scores better than complete P3 work.

### P1 — Core pipeline (required)

1. A Dagster asset that fetches weather forecast data from Open-Meteo and stores it in DuckDB
2. dbt staging models for tasks and locations (`stg_tasks`, `stg_locations`)
3. A dbt model that joins tasks, locations, and forecasts, and produces a weather risk score per task:
   - A `weather_risk_score` column — your definition, documented in your spec
   - A `weather_risk_label` column — e.g. `low`, `medium`, `high`

### P2 — Quality (expected)

4. At least 2 dbt schema tests on your staging models
5. At least 1 dbt unit test for your risk scoring logic
6. Basic error handling in your API ingestion asset

### P3 — Stretch (differentiation)

7. Partitioned or incremental-aware asset design
8. A `DECISIONS.md` noting trade-offs and what you'd do differently in production
9. Retry logic on the API asset

---

## Your Spec Document

**Write `SPEC.md` before you write any code.** We read it first.

We expect you to write this collaboratively with your AI tool — that's fine, and we encourage it. What we're assessing is your ability to think through a problem clearly and defend the decisions you made.

Your spec should cover at minimum:

- **Asset graph:** What assets exist, what depends on what (a text diagram is fine)
- **Risk model:** How you're defining weather risk — which categories are weather-sensitive and why, what weather variables you're using, what the score range is, and how you handle ambiguous cases
- **Data quality:** What issues you found and how you handled each one
- **Assumptions:** Anything you assumed about the data, API, or business requirements

A half-page of clear reasoning beats two pages of vague generalities. Be prepared to defend every decision in a follow-up conversation.

---

## Submission

- Commit your work to the provided repository
- Use branches and pull requests — your git history is part of the assessment
- Submit a pull request from a branch named `solution/<your-name>` when you're done
- Include `SPEC.md` at the repo root (and optionally `DECISIONS.md`)

**Do not commit:**
- The DuckDB database file
- Any `.env` files or credentials
- Large generated files

---

## What we're looking for

- Does the pipeline run end-to-end?
- Is your risk model documented and defensible?
- Did you handle the data quality issues correctly?
- Are your tests testing the right things?
- Does your git history show incremental, intentional progress?
- Can you explain every part of what you built?

## What we're not looking for

- Kubernetes or cloud deployment knowledge
- Snowflake-specific syntax (DuckDB is the stand-in)
- A perfect risk model — there isn't one
- Full test coverage of every edge case
- A pipeline that's been entirely written by AI with no evidence of human judgment
