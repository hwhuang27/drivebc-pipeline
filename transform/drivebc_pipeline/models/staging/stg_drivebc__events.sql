-- One row per (event_id, poll_ts): every event as it looked in every poll.
-- Cleaning only -- no joins, no business logic. Those belong in marts.

with polls as (

    -- One payload per poll. A retried collector run can load the same poll
    -- twice; keep a single copy so events are not double counted.
    select
        poll_ts,
        payload
    from {{ source('bronze', 'raw_events') }}
    qualify row_number() over (partition by poll_ts order by poll_ts) = 1

),

flattened as (

    -- payload -> pages -> events, so each event becomes its own row
    select
        polls.poll_ts,
        event
    from polls,
        unnest(json_query_array(polls.payload, '$.pages')) as page,
        unnest(json_query_array(page, '$.events')) as event

)

select
    -- keys
    poll_ts,
    json_value(event, '$.id')                       as event_id,

    -- what kind of event
    json_value(event, '$.event_type')               as event_type,
    json_value_array(event, '$.event_subtypes')     as event_subtypes,
    json_value(event, '$.severity')                 as severity,
    json_value(event, '$.status')                   as status,

    -- timestamps, normalised to UTC from the API's -07:00 / -08:00 offsets
    timestamp(json_value(event, '$.created'))       as created_utc,
    timestamp(json_value(event, '$.updated'))       as updated_utc,

    -- location: first road only. Every event seen so far lists exactly one;
    -- multi-road events would need a bridge table.
    json_value(event, '$.roads[0].name')            as road_name,
    json_value(event, '$.roads[0].from')            as road_from,
    json_value(event, '$.roads[0].to')              as road_to,
    json_value(event, '$.roads[0].direction')       as road_direction,
    nullif(json_value(event, '$.roads[0].state'), '') as road_state,
    safe_cast(json_value(event, '$.roads[0]."+delay"') as int64) as delay_minutes,
    json_value(event, '$.areas[0].name')            as area_name,
    json_value(event, '$.areas[0].id')              as area_id,

    -- distance marker along the highway. The API uses -1 to mean "not set".
    nullif(safe_cast(json_value(event, '$."+linear_reference_km"') as float64), -1)
                                                    as linear_reference_km,
    json_value(event, '$.geography.type')           as geometry_type,

    -- text
    json_value(event, '$.headline')                 as headline,
    json_value(event, '$.description')              as description

from flattened
