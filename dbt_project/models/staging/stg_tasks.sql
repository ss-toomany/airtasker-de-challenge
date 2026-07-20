with source as (
    select * from {{ source('raw', 'raw_tasks') }}
)

select * from source
