from dagster_dbt import DbtCliResource, dbt_assets

from weather_risk.resources import dbt_project


@dbt_assets(manifest=dbt_project.manifest_path)
def weather_risk_dbt_assets(context, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()
