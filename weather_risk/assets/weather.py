import requests
from dagster import asset
from dagster_duckdb import DuckDBResource

# Open-Meteo forecast API docs: https://open-meteo.com/en/docs
# Endpoint: https://api.open-meteo.com/v1/forecast
# No API key required.

@asset
def raw_weather_forecast(duckdb: DuckDBResource):
    """
    Fetch weather forecasts from Open-Meteo for relevant locations.
    Store results in DuckDB as raw.raw_weather_forecast.

    Read the API docs carefully — some parameters affect the correctness
    of the daily forecast data, not just what fields are returned.
    """
    # TODO: implement
    pass
