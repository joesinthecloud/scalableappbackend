FROM python:3.12-slim

WORKDIR /loadtest

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY locustfile.py .
COPY entrypoint.sh .
RUN chmod +x /loadtest/entrypoint.sh

ENTRYPOINT ["/loadtest/entrypoint.sh"]
