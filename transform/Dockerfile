# Container for the Cloud Run job that rebuilds the dbt models daily.
FROM python:3.12-slim

WORKDIR /app

# Pinned to the versions the project was developed against.
RUN pip install --no-cache-dir dbt-bigquery==1.12.1

COPY profiles.yml ./profiles.yml
COPY drivebc_pipeline/ ./drivebc_pipeline/

# Where dbt looks for profiles.yml, since the container has no ~/.dbt folder.
ENV DBT_PROFILES_DIR=/app

WORKDIR /app/drivebc_pipeline

# Builds every model and runs every test. A failing test exits non-zero, which
# Cloud Run reports as a failed job.
CMD ["dbt", "build", "--target", "prod"]
