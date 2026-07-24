with source as (
    select * from {{ source('raw', 'raw_tasks') }}
),

deduped as (
    select
        *,
        row_number() over (
            partition by task_id
            order by posted_at desc
        ) as row_num
    from source
)

select
    task_id,
    title,
    category,
    location_id,
    posted_at,
    state,
    budget,
    assigned_at,
    scheduled_at
from deduped
where row_num = 1
