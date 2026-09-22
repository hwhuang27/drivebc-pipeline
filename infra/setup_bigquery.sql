
-- Dataset (BigQuery's version of a schema)
CREATE SCHEMA IF NOT EXISTS `drivebc-pipeline.bronze`
OPTIONS (location = 'US');

-- One row per poll, the raw API response
CREATE TABLE IF NOT EXISTS `drivebc-pipeline.bronze.raw_events` (
  poll_ts TIMESTAMP NOT NULL,
  payload JSON NOT NULL
)
PARTITION BY DATE(poll_ts);

-- ONE row per poll attempt, success or fail
CREATE TABLE IF NOT EXISTS `drivebc-pipeline.bronze.poll_log` (
  poll_ts TIMESTAMP NOT NULL,
  status STRING NOT NULL,
  event_count INT64,
  error STRING
);
