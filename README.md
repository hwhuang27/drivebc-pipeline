# drivebc-pipeline

A data pipeline that collects road event data from the [DriveBC Open511 API](https://api.open511.gov.bc.ca/help)
every 30 minutes and models it into a BigQuery warehouse with dbt, so questions
about British Columbia's road network can be answered over time.

## Architecture

```
DriveBC Open511 API
        │
        │  Cloud Scheduler, every 30 min
        ▼
Cloud Run job: collector (Python)
        │  full pull, paginated, retries on 429
        ▼
BigQuery  bronze.raw_events   one row per poll, response stored as raw JSON
          bronze.poll_log     one row per poll attempt, success or failure
        │
        │  Cloud Scheduler, daily at 10:00 UTC
        ▼
Cloud Run job: dbt build
        │
        ▼
BigQuery  dbt_prod.stg_drivebc__events            one row per (event, poll)
          dbt_prod.fct_active_events_by_district  one row per (poll, district)
```

Collection and transformation run on **separate schedules**: polling needs to be
frequent enough to catch short-lived incidents, while transforming more than once
a day would add cost without adding information.

Both Cloud Run jobs run as a service account with only `bigquery.jobUser` and
`bigquery.dataEditor`; credentials are resolved from the attached identity at
runtime, so no key material exists in the repository or in CI.

## Questions it answers

**Now**

- How many events are active in each district at any moment, split by type?

**Once more history accumulates**

- Median time to clear an incident, by highway or district
- How long roads stay fully closed
- Which road segments see repeat events
- When incidents *start*, by hour of day and day of week

## Data model

| Layer   | Table                           | One row is                            | Materialized                     |
| ------- | ------------------------------- | ------------------------------------- | -------------------------------- |
| bronze  | `raw_events`                    | one poll, response unmodified as JSON | table (written by the collector) |
| bronze  | `poll_log`                      | one poll attempt                      | table (written by the collector) |
| staging | `stg_drivebc__events`           | one event, as seen in one poll        | table                            |
| mart    | `fct_active_events_by_district` | one district, at one poll             | table                            |

Bronze is append-only and never modified, so any downstream model can be changed
and rebuilt from the original responses.

`fct_active_events_by_district` holds one count column per DriveBC event type
(construction, special event, incident, weather condition, road condition) plus a
total. It is built only from polls that succeeded, so a poll the collector missed
is **absent from the series** rather than appearing as zero events.

## Decisions and tradeoffs

**Cloud Scheduler instead of GitHub Actions cron.**
The collector originally ran on GitHub Actions. Against a 15-minute schedule it
fired twice in twelve hours. GitHub's own documentation says scheduled workflows "can be
delayed during periods of high loads" and that "some queued jobs may be dropped".
Cloud Scheduler has fired on time since. The workflow file is kept for manual runs.

**30-minute polling, not 15 or 60.**
Measured against four days of 15-minute data: hourly polling would have missed
16% of incidents entirely, 30-minute polling misses about 6%. Half of all
incidents observed had a lifespan under an hour, which is why the interval matters
at all. 30 minutes halves the storage of 15-minute polling for a small loss in
coverage.

**One raw JSON row per poll, not parsed columns.**
The collector does no interpretation. Every parsing decision lives in dbt, where
it can be corrected and re-run against the history already collected. It is also
what keeps the collector small enough to trust.

**Tables, not views, for dbt models.**
Staging began as a view. Because a view re-runs its query on every read, each of
the 20-odd tests and the mart paid a full scan of bronze's JSON — about a dozen
full scans per `dbt build`. As a table, bronze is read once per run and everything
downstream reads only the columns it needs: the mart now processes 3.7 MiB instead
of 157 MiB.

## Repository layout

```
collector/          the polling script, its Dockerfile and dependencies
transform/          the dbt project, plus the Dockerfile for the scheduled run
infra/              setup SQL for the BigQuery datasets and tables
.github/workflows/  the original GitHub Actions collector, kept for manual runs
```

## Data licence

Road event data is published by the Province of British Columbia under the
[Open Government Licence – British Columbia](https://www2.gov.bc.ca/gov/content/data/open-data/open-government-licence-bc).
No personal data is collected.
