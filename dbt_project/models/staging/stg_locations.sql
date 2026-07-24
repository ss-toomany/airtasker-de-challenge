with source as (
    select * from {{ ref('raw_locations') }}
)

select
    location_id,
    city,
    country,
    lat,
    lng,
    timezone
from source
