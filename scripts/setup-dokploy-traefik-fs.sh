#!/usr/bin/env bash
# Bootstrap Dokploy Traefik filesystem on the VPS using Docker.
# Run on the Dokploy server as root (or with sudo).
#
# Creates:
#   /etc/dokploy/traefik/traefik.yml
#   /etc/dokploy/traefik/dynamic/acme.json
#   /etc/dokploy/traefik/dynamic/middlewares.yml
#   /etc/dokploy/traefik/dynamic/dokploy.yml
#
# Usage:
#   sudo ./scripts/setup-dokploy-traefik-fs.sh
#   sudo ./scripts/setup-dokploy-traefik-fs.sh --with-voice-config
#   sudo ACME_EMAIL=you@tekreminnovations.com ./scripts/setup-dokploy-traefik-fs.sh

set -euo pipefail

TRAEFIK_ROOT="${TRAEFIK_ROOT:-/etc/dokploy/traefik}"
DYNAMIC_DIR="${TRAEFIK_ROOT}/dynamic"
NETWORK="${TRAEFIK_NETWORK:-dokploy-network}"
ACME_EMAIL="${ACME_EMAIL:-admin@tekreminnovations.com}"
WITH_VOICE=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: setup-dokploy-traefik-fs.sh [options]

Options:
  --with-voice-config   Also generate voice-platform.yml for Dograh routing
  --force-traefik       Recreate dokploy-traefik container on v3.6.7+
  -h, --help            Show this help

Environment:
  TRAEFIK_ROOT          Default: /etc/dokploy/traefik
  TRAEFIK_NETWORK       Default: dokploy-network
  ACME_EMAIL            Let's Encrypt contact email
  PUBLIC_HOST           Default: voice.tekreminnovations.com
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-voice-config) WITH_VOICE=1; shift ;;
    --force-traefik) FORCE_TRAEFIK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is not installed." >&2
    exit 1
  fi
}

ensure_network() {
  if ! docker network inspect "${NETWORK}" >/dev/null 2>&1; then
    echo "Creating Docker network: ${NETWORK}"
    docker network create "${NETWORK}"
  fi
}

install_file() {
  local src="$1"
  local dest="$2"
  local mode="${3:-644}"

  if [[ -f "${dest}" ]]; then
    echo "  exists: ${dest}"
    return 0
  fi

  docker run --rm \
    -v "${TRAEFIK_ROOT}:${TRAEFIK_ROOT}" \
    -v "${src}:${src}:ro" \
    alpine:3.20 sh -c "cp '${src}' '${dest}' && chmod ${mode} '${dest}'"
  echo "  created: ${dest}"
}

bootstrap_dirs() {
  echo "==> Creating Traefik directories under ${TRAEFIK_ROOT}"
  docker run --rm \
    -v "${TRAEFIK_ROOT}:${TRAEFIK_ROOT}" \
    alpine:3.20 sh -c "
      mkdir -p '${DYNAMIC_DIR}/certificates'
      touch '${DYNAMIC_DIR}/acme.json'
      chmod 600 '${DYNAMIC_DIR}/acme.json'
    "
}

write_traefik_yml() {
  local dest="${TRAEFIK_ROOT}/traefik.yml"
  if [[ -f "${dest}" ]]; then
    echo "==> traefik.yml already exists — skipping"
    return 0
  fi

  echo "==> Writing ${dest}"
  docker run --rm \
    -v "${TRAEFIK_ROOT}:${TRAEFIK_ROOT}" \
    -v "${REPO_ROOT}/traefik/traefik.yml:/src/traefik.yml:ro" \
    alpine:3.20 sh -c "
      cp /src/traefik.yml '${dest}'
      sed -i 's/admin@localhost/${ACME_EMAIL//\//\\/}/g' '${dest}' || true
      chmod 644 '${dest}'
    "
}

install_dynamic_files() {
  echo "==> Installing dynamic Traefik files"
  install_file "${REPO_ROOT}/traefik/dynamic/middlewares.yml" "${DYNAMIC_DIR}/middlewares.yml" 644
  install_file "${REPO_ROOT}/traefik/dynamic/dokploy.yml" "${DYNAMIC_DIR}/dokploy.yml" 644
}

ensure_traefik_container() {
  local image="traefik:v3.6.7"
  local name="dokploy-traefik"

  if docker ps -a --format '{{.Names}}' | grep -qx "${name}"; then
    if [[ "${FORCE_TRAEFIK:-0}" == "1" ]]; then
      echo "==> Recreating ${name} (${image})"
      docker rm -f "${name}" >/dev/null
    else
      echo "==> ${name} already exists — restart only (use --force-traefik to recreate)"
      docker restart "${name}" >/dev/null || true
      return 0
    fi
  fi

  echo "==> Starting ${name} (${image})"
  docker run -d \
    --name "${name}" \
    --restart always \
    --network "${NETWORK}" \
    -p 80:80 \
    -p 443:443 \
    -p 443:443/udp \
    -v "${TRAEFIK_ROOT}/traefik.yml:/etc/traefik/traefik.yml:ro" \
    -v "${DYNAMIC_DIR}:/etc/dokploy/traefik/dynamic" \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    "${image}" >/dev/null
}

verify() {
  echo ""
  echo "==> Verification"
  echo "Directories:"
  docker run --rm -v "${TRAEFIK_ROOT}:${TRAEFIK_ROOT}" alpine:3.20 sh -c "find '${TRAEFIK_ROOT}' -maxdepth 2 -type f | sort"
  echo ""
  echo "Traefik container:"
  docker ps --filter name=dokploy-traefik --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
  echo ""
  echo "Files in dynamic/ (top level only — Traefik file provider does not recurse):"
  docker run --rm -v "${DYNAMIC_DIR}:${DYNAMIC_DIR}" alpine:3.20 sh -c "ls -la '${DYNAMIC_DIR}'"
}

main() {
  require_docker
  ensure_network
  bootstrap_dirs
  write_traefik_yml
  install_dynamic_files

  if [[ "${WITH_VOICE}" == "1" ]]; then
    echo "==> Generating voice-platform.yml"
    PUBLIC_HOST="${PUBLIC_HOST:-voice.tekreminnovations.com}" \
      bash "${SCRIPT_DIR}/generate-voice-traefik-config.sh"
  fi

  ensure_traefik_container
  verify

  cat <<EOF

Done.

Next steps:
  1. Ensure Dograh api/ui containers are on network: ${NETWORK}
  2. If routing still 404s, run:
       sudo PUBLIC_HOST=voice.tekreminnovations.com ./scripts/generate-voice-traefik-config.sh
       docker restart dokploy-traefik
  3. Test: curl -I https://voice.tekreminnovations.com/api/v1/health

See docs/TRAEFIK.md
EOF
}

main "$@"
