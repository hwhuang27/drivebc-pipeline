-- How many DriveBC events were active in each district, at each poll.
-- One row per (poll_ts, area_name).

with successful_polls as (

    -- Only polls that actually ran. A poll that never happened should be
    -- missing from the series, not reported as zero events.
    select poll_ts
    from {{ source('bronze', 'poll_log') }}
    where status = 'success'

),

counts_per_poll as (

    select
        poll_ts,
        coalesce(area_name, 'Unknown') as area_name,
        count(distinct event_id) as active_events
    from {{ ref('stg_drivebc__events') }}
    group by poll_ts, area_name

)

select
    successful_polls.poll_ts,
    counts_per_poll.area_name,
    counts_per_poll.active_events
from successful_polls
inner join counts_per_poll using (poll_ts)
