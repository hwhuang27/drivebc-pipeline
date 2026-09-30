-- How many DriveBC events were active in each district, at each poll.
-- One row per (poll_ts, area_name).

with polls_that_ran as (

    -- Which polls actually happened, taken from the payloads themselves rather
    -- than from poll_log. The log row is written after the data load, so a
    -- collector killed in between leaves real data with no log row -- that
    -- happened on 2026-09-29 when two tasks hit the Cloud Run task timeout.
    -- A payload is evidence the poll ran; a log row is only a claim about it.
    -- poll_log remains the record of failures and of gaps between polls.
    select distinct poll_ts
    from {{ source('bronze', 'raw_events') }}
    where poll_ts >= timestamp('{{ var("uniform_polling_from") }}')

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
    polls_that_ran.poll_ts,
    -- Local wall-clock time for charting. BC moved to permanent daylight saving
    -- in March 2026, so Pacific is UTC-7 year-round; using the zone name rather
    -- than a fixed offset keeps this correct if that ever changes again.
    datetime(polls_that_ran.poll_ts, 'America/Vancouver') as poll_ts_pacific,
    counts_per_poll.area_name,
    counts_per_poll.construction_events,
    counts_per_poll.special_events,
    counts_per_poll.incident_events,
    counts_per_poll.weather_condition_events,
    counts_per_poll.road_condition_events,
    counts_per_poll.total_events
from polls_that_ran
inner join counts_per_poll using (poll_ts)
