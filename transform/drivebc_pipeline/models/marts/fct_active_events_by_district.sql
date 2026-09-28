-- How many DriveBC events were active in each district, at each poll.
-- One row per (poll_ts, area_name).

with successful_polls as (

    -- Only polls that actually ran. A poll that never happened should be
    -- missing from the series, not reported as zero events.
    select poll_ts
    from {{ source('bronze', 'poll_log') }}
    where status = 'success'
      and poll_ts >= timestamp('{{ var("uniform_polling_from") }}')

),

counts_per_poll as (

    -- One column per event type. Counting rows is safe here because staging is
    -- one row per (event_id, poll_ts), which its uniqueness test enforces.
    select
        poll_ts,
        coalesce(area_name, 'Unknown') as area_name,
        countif(event_type = 'CONSTRUCTION')      as construction_events,
        countif(event_type = 'SPECIAL_EVENT')     as special_events,
        countif(event_type = 'INCIDENT')          as incident_events,
        countif(event_type = 'WEATHER_CONDITION') as weather_condition_events,
        countif(event_type = 'ROAD_CONDITION')    as road_condition_events,
        count(*)                                  as total_events
    from {{ ref('stg_drivebc__events') }}
    group by poll_ts, area_name

)

select
    successful_polls.poll_ts,
    counts_per_poll.area_name,
    counts_per_poll.construction_events,
    counts_per_poll.special_events,
    counts_per_poll.incident_events,
    counts_per_poll.weather_condition_events,
    counts_per_poll.road_condition_events,
    counts_per_poll.total_events
from successful_polls
inner join counts_per_poll using (poll_ts)
