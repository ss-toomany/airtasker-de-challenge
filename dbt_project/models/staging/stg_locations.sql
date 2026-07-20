with source as (
    select * from {{ ref('raw_locations') }}
)

select * from source
