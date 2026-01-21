FROM python:3.12-slim

WORKDIR /loadtest

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY locustfile.py .

# We will run Locust headless in ECS (no UI)
ENTRYPOINT ["locust"]
