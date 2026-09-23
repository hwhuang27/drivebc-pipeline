import os
import time

import requests
from datetime import datetime, timezone
from dotenv import load_dotenv
from google.cloud import bigquery

# --- Config ---
load_dotenv()
PROJECT_ID = os.environ["GCP_PROJECT_ID"]
BRONZE_RAW_EVENTS_TABLE_ID = f"{PROJECT_ID}.bronze.raw_events"
BRONZE_POLL_LOG_TABLE_ID = f"{PROJECT_ID}.bronze.poll_log"

API_URL = "https://api.open511.gov.bc.ca/events"
PAGE_SIZE = 500
PAGE_DELAY_SECONDS = 10  # the API asks callers to space requests by 10s or more
MAX_ATTEMPTS = 3


def fetch_page(offset: int) -> dict:
    """Fetch one page, retrying when the API throttles (429) or errors (5xx)."""
    last_status = None
    for attempt in range(MAX_ATTEMPTS):
        resp = requests.get(
            API_URL,
            params={"format": "json", "status": "ACTIVE", "limit": PAGE_SIZE, "offset": offset},
            timeout=30,
        )
        last_status = resp.status_code
        if resp.status_code == 429 or resp.status_code >= 500:
            wait = int(resp.headers.get("Retry-After", PAGE_DELAY_SECONDS * (attempt + 1)))
            print(f"HTTP {resp.status_code} at offset {offset}, retrying in {wait}s")
            time.sleep(wait)
            continue
        resp.raise_for_status()
        return resp.json()
    raise RuntimeError(f"gave up after {MAX_ATTEMPTS} attempts, last status {last_status}")


def fetch_all_pages() -> list[dict]:
    """Return every raw page response, unchanged."""
    pages = []
    offset = 0
    while True:
        page = fetch_page(offset)
        pages.append(page)
        if len(page.get("events", [])) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
        time.sleep(PAGE_DELAY_SECONDS)
    return pages


def load_data(table_id: str, client: bigquery.Client, rows: list[dict]) -> None:
    table = client.get_table(table_id)

    job_config = bigquery.LoadJobConfig(
        schema=table.schema,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )
    
    job = client.load_table_from_json(rows, table_id, job_config=job_config)
    job.result()


def main() -> None:
    poll_ts = datetime.now(timezone.utc).replace(microsecond=0)
    client = bigquery.Client(project=PROJECT_ID)
    count = 0
    try:
        pages = fetch_all_pages()
        count = sum(len(p.get("events", [])) for p in pages)

        # Load rows for raw event
        payload = {"poll_ts": poll_ts.isoformat(), "pages": pages}
        raw_event_rows = [{
            "poll_ts": poll_ts.isoformat(), 
            "payload": payload
        }]
        load_data(BRONZE_RAW_EVENTS_TABLE_ID, client, raw_event_rows)

        # Load rows for poll log (success)
        poll_log_rows = [{
            "poll_ts": poll_ts.isoformat(),
            "status": "success",
            "event_count": count
        }]
        load_data(BRONZE_POLL_LOG_TABLE_ID, client, poll_log_rows)
        print(f"{poll_ts.isoformat()} status=success events={count}")

    except Exception as e:
        # Load rows for poll log (fail)
        poll_log_rows = [{
            "poll_ts": poll_ts.isoformat(),
            "status": "fail",
            "event_count": count,
            "error": str(e)
        }]
        load_data(BRONZE_POLL_LOG_TABLE_ID, client, poll_log_rows)
        print(f"{poll_ts.isoformat()} status=fail events={count} error={e}")
        raise

if __name__ == "__main__":
    main()