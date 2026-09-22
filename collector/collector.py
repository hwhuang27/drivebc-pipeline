import gzip
import json
from datetime import datetime, timezone
from pathlib import Path

import requests

# --- Config ---
API_URL = "https://api.open511.gov.bc.ca/events"
PAGE_SIZE = 500
DATA_DIR = Path(__file__).resolve().parent.parent / "data"
RAW_DIR = DATA_DIR / "raw"
LOG_FILE = DATA_DIR / "poll_log.jsonl"


def fetch_all_pages() -> list[dict]:
    """Return every raw page response, unchanged."""
    pages = []
    offset = 0
    while True:
        resp = requests.get(
            API_URL,
            params={"format": "json", "status": "ACTIVE", "limit": PAGE_SIZE, "offset": offset},
            timeout=30,
        )
        resp.raise_for_status()
        page = resp.json()
        pages.append(page)
        if len(page.get("events", [])) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
    return pages


def save_raw(pages: list[dict], poll_ts: datetime) -> Path:
    """Write one gzipped file per poll. Write to a temp file, then rename."""
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    path = RAW_DIR / f"{poll_ts:%Y-%m-%dT%H-%M-%SZ}.json.gz"
    tmp = path.with_suffix(".tmp")
    payload = json.dumps({"poll_ts": poll_ts.isoformat(), "pages": pages}).encode("utf-8")
    tmp.write_bytes(gzip.compress(payload))
    tmp.replace(path)
    return path


def log_poll(poll_ts: datetime, status: str, event_count: int = 0, error: str | None = None) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    entry = {"poll_ts": poll_ts.isoformat(), "status": status, "event_count": event_count, "error": error}
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


def main() -> None:
    poll_ts = datetime.now(timezone.utc).replace(microsecond=0)
    try:
        pages = fetch_all_pages()
        count = sum(len(p.get("events", [])) for p in pages)
        save_raw(pages, poll_ts)
        log_poll(poll_ts, "success", count)
    except Exception as e:
        log_poll(poll_ts, "failed", error=str(e))
        raise


if __name__ == "__main__":
    main()