with weather_matches as (
    select * from {{ ref('int_tasks_locations_weather_forecast') }}
),

tasks as (
    select * from {{ ref('stg_tasks') }}
),

-- How many of a task's matched hours fell into each label bucket
-- (1=LOW, 2=MEDIUM, 3=HIGH). Excludes unmatched/null hours.
-- number of hours for each task and label 
label_counts as (
    select
        task_id,
        label_rank,
        count(*) as hour_count
    from weather_matches
    where label_rank is not null
    group by task_id, label_rank
),
-- Mode across matched hours, ties broken toward the higher-severity label.
-- Scheduled/assigned tasks only ever have 1 matched hour, so this formula
-- trivially returns that hour's label for them too — no branching needed
-- between the single-hour and 72-hour-window cases.
modal_label as (
    select
        task_id,
        label_rank,
        row_number() over (
            partition by task_id
            order by hour_count desc, label_rank desc
        ) as rn
    from label_counts
),
-- Average of each matched hour's combined score (4-12). For a single
-- matched hour this is just that hour's score.
avg_score as (
    select
        task_id,
        avg(hourly_score) as weather_risk_score
    from weather_matches
    where hourly_score is not null
    group by 1
),

risk as (
    select
        modal_label.task_id,
        avg_score.weather_risk_score,
        case modal_label.label_rank
            when 3 then 'HIGH'
            when 2 then 'MEDIUM'
            when 1 then 'LOW'
        end as weather_risk_label
    from modal_label
    left join avg_score on modal_label.task_id = avg_score.task_id
    where modal_label.rn = 1
)

select
    tasks.task_id,
    tasks.title,
    tasks.category,
    tasks.location_id,
    tasks.state,
    tasks.budget,
    tasks.posted_at,
    tasks.assigned_at,
    tasks.scheduled_at,
    risk.weather_risk_score,
    coalesce(risk.weather_risk_label, 'unknown') as weather_risk_label
from tasks
left join risk on tasks.task_id = risk.task_id
