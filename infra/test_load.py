import gzip
import json
import os
from pathlib import Path

from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv()
PROJECT_ID = os.environ["GCP_PROJECT_ID"]
TABLE_ID = f"{PROJECT_ID}.bronze.raw_events"

# Grab the newest poll file saved earlier
local_file = sorted(Path("data/raw").glob("*.json.gz"))[-1]
data = json.loads(gzip.decompress(local_file.read_bytes()))

client = bigquery.Client(project=PROJECT_ID)
table = client.get_table(TABLE_ID)  # reuse the table's own schema

job_config = bigquery.LoadJobConfig(
    schema=table.schema,
    write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
)
rows = [{"poll_ts": data["poll_ts"], "payload": data}]
job = client.load_table_from_json(rows, TABLE_ID, job_config=job_config)
job.result()  # waits; raises if the load failed

print(f"Loaded {local_file.name} -> {TABLE_ID} ({job.output_rows} row)")