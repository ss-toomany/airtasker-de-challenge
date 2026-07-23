with tasks as (
    select * from {{ ref('stg_tasks') }}
),

locations as (
    select * from {{ ref('stg_locations') }}
),

weather as (
    select * from {{ ref('stg_weather_forecast') }}
),

-- Priority order: scheduled_at -> assigned_at -> posted_at. A single hour is
-- modeled as a 1-hour window so the downstream join/aggregation logic is
-- identical for both the "single hour" and "72-hour posted fallback" cases.
task_windows as (
    select
        task_id,
        location_id,
        case
            when scheduled_at is not null then date_trunc('hour', scheduled_at)
            when assigned_at is not null then date_trunc('hour', assigned_at)
            else posted_at
        end as window_start,
        case
            when scheduled_at is not null then date_trunc('hour', scheduled_at) + interval '1 hour'
            when assigned_at is not null then date_trunc('hour', assigned_at) + interval '1 hour'
            else posted_at + interval '72 hours'
        end as window_end,
        case
            when scheduled_at is not null then 'scheduled'
            when assigned_at is not null then 'assigned'
            else 'posted'
        end as match_source
    from tasks
),

task_locations as (
    select
        task_windows.*,
        locations.city,
        locations.country
    from task_windows
    left join locations on task_windows.location_id = locations.location_id
),

-- Left join so orphaned-location tasks and tasks with no hour in range
-- (see SPEC.md Data Quality) still produce a row, just with null weather —
-- the `weather.temperature_2m is not null` check in the ON clause also
-- excludes the null rows Open-Meteo returns for the oldest ~15 days of the
-- past_days=92 window, without dropping the task row itself.
matched_weather as (
    select
        task_locations.task_id,
        task_locations.location_id,
        task_locations.city,
        task_locations.country,
        task_locations.match_source,
        weather.time as weather_time,
        weather.temperature_2m,
        weather.precipitation,
        weather.windspeed_10m,
        weather.visibility_km
    from task_locations
    left join weather
        on task_locations.location_id = weather.location_id
        and weather.time >= task_locations.window_start
        and weather.time < task_locations.window_end
        and weather.temperature_2m is not null
),

-- Per-factor scores (1/2/3), per SPEC.md's thresholds table. Null weather
-- (no matched hour at all) propagates to null scores rather than
-- defaulting to "low risk".
scored as (
    select
        task_id,
        location_id,
        city,
        country,
        match_source,
        weather_time,
        case
            when temperature_2m is null then null
            when temperature_2m < 9 or temperature_2m > 25 then 3
            when temperature_2m <= 13 or temperature_2m >= 21 then 2
            else 1
        end as temp_score,
        case
            when precipitation is null then null
            when precipitation > 10 then 3
            when precipitation >= 2.5 then 2
            else 1
        end as precip_score,
        case
            when windspeed_10m is null then null
            when windspeed_10m > 28 then 3
            when windspeed_10m >= 10 then 2
            else 1
        end as wind_score,
        case
            when visibility_km is null then null
            when visibility_km < 1 then 3
            when visibility_km <= 10 then 2
            else 1
        end as visibility_score
    from matched_weather
)

select
    task_id,
    location_id,
    city,
    country,
    match_source,
    weather_time,
    temp_score,
    precip_score,
    wind_score,
    visibility_score,
    case
        when temp_score is null then null
        else greatest(temp_score, precip_score, wind_score, visibility_score)
    end as label_rank,
    case
        when temp_score is null then null
        else temp_score + precip_score + wind_score + visibility_score
    end as hourly_score
from scored
