import os
from pathlib import Path

from dagster_dbt import DbtCliResource, DbtProject
from dagster_duckdb import DuckDBResource

DBT_PROJECT_DIR = Path(__file__).parent.parent.parent / "dbt_project"
DUCKDB_PATH = os.environ.get("DUCKDB_PATH", "/app/data/challenge.duckdb")

dbt_project = DbtProject(project_dir=DBT_PROJECT_DIR)
dbt_project.prepare_if_dev()

resources = {
    "dbt": DbtCliResource(
        project_dir=str(DBT_PROJECT_DIR),
        profiles_dir=str(DBT_PROJECT_DIR),
    ),
    "duckdb": DuckDBResource(database=DUCKDB_PATH),
}
