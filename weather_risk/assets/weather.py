import pandas as pd
import requests
from dagster import AssetExecutionContext, MaterializeResult, asset
from dagster_duckdb import DuckDBResource

# Open-Meteo forecast API docs: https://open-meteo.com/en/docs
# Endpoint: https://api.open-meteo.com/v1/forecast
# No API key required.

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

HOURLY_VARIABLES = ["temperature_2m", "precipitation", "windspeed_10m", "visibility"]

# forecast_days=16 covers scheduled_at up to 14 days out; past_days=92 covers
# completed/cancelled tasks whose scheduled_at is in the recent past. Both are
# returned by the same /v1/forecast call. See SPEC.md for the full rationale.
FORECAST_DAYS = 16
PAST_DAYS = 92


@asset
def raw_weather_forecast(
    context: AssetExecutionContext, duckdb: DuckDBResource
) -> MaterializeResult:
    """
    Fetch weather forecasts from Open-Meteo for relevant locations.
    Store results in DuckDB as raw.raw_weather_forecast.

    Read the API docs carefully — some parameters affect the correctness
    of the daily forecast data, not just what fields are returned.
    """
    with duckdb.get_connection() as conn:
        locations = conn.execute(
            "select location_id, lat, lng from raw.raw_locations"
        ).fetchall()

    rows = []
    failed_locations = []
    for location_id, lat, lng in locations:
        try:
            response = requests.get(
                OPEN_METEO_URL,
                params={
                    "latitude": lat,
                    "longitude": lng,
                    "hourly": ",".join(HOURLY_VARIABLES),
                    "forecast_days": FORECAST_DAYS,
                    "past_days": PAST_DAYS,
                    "timezone": "UTC",
                },
                timeout=30,
            )
            response.raise_for_status()
            hourly = response.json()["hourly"]
        except (requests.exceptions.RequestException, KeyError, ValueError) as e:
            # One bad location (timeout, HTTP error, malformed response) shouldn't
            # take down the whole run and discard every other location's data.
            context.log.warning(f"Failed to fetch weather for {location_id}: {e}")
            failed_locations.append(location_id)
            continue

        for i, time in enumerate(hourly["time"]):
            rows.append(
                {
                    "location_id": location_id,
                    "time": time,
                    "temperature_2m": hourly["temperature_2m"][i],
                    "precipitation": hourly["precipitation"][i],
                    "windspeed_10m": hourly["windspeed_10m"][i],
                    "visibility": hourly["visibility"][i],
                }
            )
        context.log.info(f"Fetched {len(hourly['time'])} hourly rows for {location_id}")

    if not rows:
        raise RuntimeError(
            f"Failed to fetch weather for all {len(locations)} locations; aborting "
            f"rather than writing an empty table. Failed: {failed_locations}"
        )

    weather_df = pd.DataFrame(rows)
    weather_df["time"] = pd.to_datetime(weather_df["time"])

    with duckdb.get_connection() as conn:
        conn.execute("CREATE SCHEMA IF NOT EXISTS raw")
        conn.execute(
            "CREATE OR REPLACE TABLE raw.raw_weather_forecast AS SELECT * FROM weather_df"
        )

    return MaterializeResult(
        metadata={
            "num_locations_succeeded": len(locations) - len(failed_locations),
            "num_locations_failed": len(failed_locations),
            "failed_locations": failed_locations,
            "num_rows": len(weather_df),
        }
    )
