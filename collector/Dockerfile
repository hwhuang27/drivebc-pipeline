# Container for the Cloud Run job that polls DriveBC and loads BigQuery.
FROM python:3.12-slim

WORKDIR /app

# Install dependencies first so this layer is cached when only the code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY collector.py .

CMD ["python", "collector.py"]
