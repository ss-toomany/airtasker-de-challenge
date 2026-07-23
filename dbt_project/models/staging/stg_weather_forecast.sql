with source as (
    select * from {{ source('raw', 'raw_weather_forecast') }}
)

select
    location_id,
    time,
    temperature_2m,
    precipitation,
    windspeed_10m,
    visibility / 1000.0 as visibility_km
from source
