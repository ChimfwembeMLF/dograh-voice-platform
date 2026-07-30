FROM python:3.12-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements-sip.txt .
RUN pip install --no-cache-dir -r requirements-sip.txt

COPY sip-connector.py .

RUN chmod +x sip-connector.py

ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -sf http://127.0.0.1:8080/health || exit 1

CMD ["python", "sip-connector.py"]
