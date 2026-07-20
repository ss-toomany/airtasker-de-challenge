#!/bin/bash
set -e

DUCKDB_PATH="/app/data/challenge.duckdb"
mkdir -p /app/data
mkdir -p /app/.dagster
touch /app/.dagster/dagster.yaml

echo "--- Generating task data ---"
python /app/scripts/generate_tasks.py "$DUCKDB_PATH"

echo "--- Seeding locations ---"
cd /app/dbt_project && dbt seed --select raw_locations --profiles-dir .

echo "--- Starting Dagster ---"
echo ""
echo "  Dagster UI → http://localhost:3000"
echo ""
cd /app
dagster dev -h 0.0.0.0 -p 3000
