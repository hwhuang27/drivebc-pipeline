-- One row per DriveBC event: when it started, when it ended, and what it looked
-- like when last seen. Collapses the many per-poll observations in staging.

with polls as (

    -- Every poll that returned data, same source as the district mart.
    select distinct poll_ts
    from {{ source('bronze', 'raw_events') }}
    where poll_ts >= timestamp('{{ var("uniform_polling_from") }}')

),

collection_window as (

    select min(poll_ts) as first_poll_at, max(poll_ts) as last_poll_at
    from polls

),

observed as (

    -- What repeated observation tells us: when we saw it, and how often.
    select
        event_id,
        min(created_utc) as created_utc,
        min(poll_ts)     as first_seen_at,
        max(poll_ts)     as last_seen_at,
        count(*)         as polls_seen
    from {{ ref('stg_drivebc__events') }}
    where poll_ts >= timestamp('{{ var("uniform_polling_from") }}')
    group by event_id

),

latest as (

    -- Attributes as of the most recent poll that saw the event. Severity and
    -- road state change over an event's life, so "latest" is a choice, not a
    -- given: row_number picks one specific row per event rather than
    -- aggregating across them.
    select
        event_id,
        event_type,
        severity,
        status,
        road_name,
        road_state,
        area_name,
        linear_reference_km,
        updated_utc
    from {{ ref('stg_drivebc__events') }}
    where poll_ts >= timestamp('{{ var("uniform_polling_from") }}')
    qualify row_number() over (partition by event_id order by poll_ts desc) = 1

),

first_missing as (

    -- The first poll after the event was last seen. An event disappears rather
    -- than being marked as ended, so this is the earliest moment we know it was
    -- gone. Null means it was still present in the most recent poll.
    select
        observed.event_id,
        min(polls.poll_ts) as first_missing_poll_at
    from observed
    join polls
        on polls.poll_ts > observed.last_seen_at
    group by observed.event_id

)

select
    observed.event_id,

    -- what it was, as last seen
    latest.event_type,
    latest.severity,
    latest.status,
    latest.road_name,
    latest.road_state,
    latest.area_name,
    latest.linear_reference_km,

    -- timestamps from the API
    observed.created_utc,
    latest.updated_utc,

    -- timestamps from our observation
    observed.first_seen_at,
    observed.last_seen_at,
    observed.polls_seen,

    -- lifecycle
    first_missing.first_missing_poll_at as cleared_at,
    first_missing.first_missing_poll_at is not null as is_cleared,
    timestamp_diff(first_missing.first_missing_poll_at, observed.created_utc, minute)
        as duration_minutes,

    -- How wide the uncertainty on cleared_at is: the event ended somewhere
    -- between last_seen_at and cleared_at. Normally one poll interval, but wider
    -- if the collector missed polls, so analysis can exclude imprecise rows.
    timestamp_diff(first_missing.first_missing_poll_at, observed.last_seen_at, minute)
        as clear_window_minutes,

    -- True when the event was already running before collection began, so its
    -- observed start is our start, not its own.
    observed.first_seen_at = collection_window.first_poll_at
        as was_active_at_collection_start

from observed
inner join latest using (event_id)
left join first_missing using (event_id)
cross join collection_window
