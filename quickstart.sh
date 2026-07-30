#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

MODE="${1:-voice}"

if [[ ! -f dograh.env ]]; then
  if [[ -f dograh.env.example ]]; then
    echo "Creating dograh.env from dograh.env.example — edit it before production use."
    cp dograh.env.example dograh.env
  else
    echo "Missing dograh.env — copy dograh.env.example to dograh.env and edit values."
    exit 1
  fi
fi

set -a
# shellcheck disable=SC1091
source dograh.env
set +a

case "$MODE" in
  voice)
    SERVICES=(whisper piper sip-connector)
    PROFILES=(--profile sip-connector)
    ;;
  dograh)
    SERVICES=(postgres coturn api ui whisper piper)
    PROFILES=()
    ;;
  full)
    SERVICES=(postgres coturn api ui whisper piper sip-connector)
    PROFILES=(--profile sip-connector)
    ;;
  monitoring)
    SERVICES=(whisper piper sip-connector prometheus)
    PROFILES=(--profile sip-connector --profile monitoring)
    ;;
  *)
    echo "Usage: $0 [voice|dograh|full|monitoring]"
    echo "  voice      — sip-connector stack only"
    echo "  dograh     — Dograh + Whisper + Piper (ARI/SIP via Dograh UI)"
    echo "  full       — everything including sip-connector"
    echo "  monitoring — voice stack + Prometheus"
    exit 1
    ;;
esac

echo "Building and starting: ${SERVICES[*]}"
docker compose --env-file dograh.env "${PROFILES[@]}" up -d --build "${SERVICES[@]}"

echo
echo "Waiting for health checks..."
sleep 15

echo
if [[ "$MODE" == "dograh" || "$MODE" == "full" ]]; then
  echo "Dograh API health:"
  curl -sf "https://${PUBLIC_HOST:-localhost}/api/v1/health" 2>/dev/null | python3 -m json.tool || \
    curl -sf "http://localhost:8000/api/v1/health" | python3 -m json.tool || true
  echo
  echo "Next: configure Asterisk ARI — see README.md and asterisk/"
fi

if [[ "$MODE" != "dograh" ]]; then
  echo "SIP connector health:"
  curl -sf "http://localhost:${SIP_CONNECTOR_PORT:-8080}/health" | python3 -m json.tool || true
fi

echo
echo "Running containers:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo
echo "Test audio pipeline:"
echo "  curl -X POST http://localhost:${SIP_CONNECTOR_PORT:-8080}/process_audio -F \"audio=@/path/to/test.wav\" -o reply.wav -D -"
