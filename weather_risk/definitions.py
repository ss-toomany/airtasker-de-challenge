from dagster import Definitions

from weather_risk.assets.dbt import weather_risk_dbt_assets
from weather_risk.assets.weather import raw_weather_forecast
from weather_risk.jobs import jobs
from weather_risk.resources import resources
from weather_risk.schedules import schedules

defs = Definitions(
    assets=[weather_risk_dbt_assets, raw_weather_forecast],
    resources=resources,
    jobs=jobs,
    schedules=schedules,
)
