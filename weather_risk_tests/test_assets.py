from dagster import AssetsDefinition

from weather_risk.assets.weather import raw_weather_forecast
from weather_risk.definitions import defs


def test_defs_loads():
    """Verify the Definitions object loads without errors."""
    assert defs is not None


def test_raw_weather_forecast_asset_defined():
    """Verify raw_weather_forecast is a valid asset definition with the expected key."""
    assert isinstance(raw_weather_forecast, AssetsDefinition)
    keys = [str(k) for k in raw_weather_forecast.keys]
    assert "raw_weather_forecast" in keys
