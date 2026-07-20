.PHONY: up up-d down reset build rebuild logs shell test dbt-run dbt-test

# ── Start ──────────────────────────────────────────────────────────────────────

## Start the full stack in the foreground (builds if needed)
up:
	docker compose up

## Start detached (runs in background)
up-d:
	docker compose up -d

# ── Stop ───────────────────────────────────────────────────────────────────────

## Stop containers, keep volumes (data persists)
down:
	docker compose down

## Destroy containers AND volumes — forces a clean reseed on next `make up`
reset:
	docker compose down -v
	rm -f ./data/challenge.duckdb

# ── Build ──────────────────────────────────────────────────────────────────────

## Build the Docker image without starting
build:
	docker compose build

## Full clean rebuild: destroy volumes, rebuild image, start
rebuild: reset
	docker compose up --build

# ── Observe ────────────────────────────────────────────────────────────────────

## Follow container logs
logs:
	docker compose logs -f

## Open a bash shell inside the running container
shell:
	docker compose exec dagster bash

## Run the test suite inside the container
test:
	docker compose exec dagster pytest

# ── dbt (run from inside the container) ───────────────────────────────────────

## Run all dbt models
dbt-run:
	docker compose exec dagster bash -c "cd /app/dbt_project && dbt run --profiles-dir ."

## Run all dbt tests
dbt-test:
	docker compose exec dagster bash -c "cd /app/dbt_project && dbt test --profiles-dir ."
