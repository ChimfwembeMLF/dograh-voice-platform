#!/usr/bin/env bash
# Generate /etc/dokploy/traefik/dynamic/voice-platform.yml for Dograh Compose routing.
# Use when Docker label routing fails (common with older Traefik + Docker Engine 28+).
#
# Usage:
#   sudo ./scripts/generate-voice-traefik-config.sh
#   sudo PUBLIC_HOST=voice.tekreminnovations.com COMPOSE_PROJECT=voiceagentplatform-ivr-hj26ln ./scripts/generate-voice-traefik-config.sh

set -euo pipefail

PUBLIC_HOST="${PUBLIC_HOST:-voice.tekreminnovations.com}"
TRAEFIK_NETWORK="${TRAEFIK_NETWORK:-dokploy-network}"
DYNAMIC_DIR="${DYNAMIC_DIR:-/etc/dokploy/traefik/dynamic}"
OUTPUT="${OUTPUT:-${DYNAMIC_DIR}/voice-platform.yml}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE="${REPO_ROOT}/traefik/dynamic/voice-platform.yml.template"

find_container() {
  local role="$1"
  local name=""

  if [[ -n "${COMPOSE_PROJECT}" ]]; then
    name="$(docker ps --format '{{.Names}}' | grep -E "^${COMPOSE_PROJECT}.*-${role}-[0-9]+\$" | head -1 || true)"
    if [[ -n "${name}" ]]; then
      echo "${name}"
      return 0
    fi
    name="$(docker ps --format '{{.Names}}' | grep -E "^${COMPOSE_PROJECT}.*${role}" | head -1 || true)"
    if [[ -n "${name}" ]]; then
      echo "${name}"
      return 0
    fi
  fi

  case "${role}" in
    api)
      name="$(docker ps --filter "label=traefik.http.routers.dograh-api.rule" --format '{{.Names}}' | head -1 || true)"
      ;;
    ui)
      name="$(docker ps --filter "label=traefik.http.routers.dograh-ui.rule" --format '{{.Names}}' | head -1 || true)"
      ;;
  esac

  if [[ -n "${name}" ]]; then
    echo "${name}"
    return 0
  fi

  name="$(docker ps --format '{{.Names}}' | grep -Ei 'dograh.*api|voiceagent.*api|.*-api-[0-9]+\$' | head -1 || true)"
  if [[ "${role}" == "api" && -n "${name}" ]]; then
    echo "${name}"
    return 0
  fi

  name="$(docker ps --format '{{.Names}}' | grep -Ei 'dograh.*ui|voiceagent.*ui|.*-ui-[0-9]+\$' | head -1 || true)"
  if [[ "${role}" == "ui" && -n "${name}" ]]; then
    echo "${name}"
    return 0
  fi

  return 1
}

on_network() {
  local container="$1"
  docker network inspect "${TRAEFIK_NETWORK}" --format '{{range .Containers}}{{.Name}} {{end}}' \
    | tr ' ' '\n' | grep -qx "${container}"
}

connect_to_network() {
  local container="$1"
  if on_network "${container}"; then
    echo "  ${container} already on ${TRAEFIK_NETWORK}"
    return 0
  fi
  echo "  connecting ${container} to ${TRAEFIK_NETWORK}"
  docker network connect "${TRAEFIK_NETWORK}" "${container}"
}

main() {
  if [[ ! -f "${TEMPLATE}" ]]; then
    echo "ERROR: template not found: ${TEMPLATE}" >&2
    exit 1
  fi

  echo "==> Detecting Dograh containers"
  API_CONTAINER="$(find_container api)" || {
    echo "ERROR: could not find api container. Set COMPOSE_PROJECT or deploy Dograh first." >&2
    docker ps --format '{{.Names}}' | sort
    exit 1
  }
  UI_CONTAINER="$(find_container ui)" || {
    echo "ERROR: could not find ui container." >&2
    exit 1
  }

  echo "  api: ${API_CONTAINER}"
  echo "  ui:  ${UI_CONTAINER}"

  connect_to_network "${API_CONTAINER}"
  connect_to_network "${UI_CONTAINER}"

  mkdir -p "${DYNAMIC_DIR}"
  sed \
    -e "s/PUBLIC_HOST/${PUBLIC_HOST}/g" \
    -e "s/API_UPSTREAM/${API_CONTAINER}/g" \
    -e "s/UI_UPSTREAM/${UI_CONTAINER}/g" \
    "${TEMPLATE}" > "${OUTPUT}.tmp"

  docker run --rm \
    -v "${DYNAMIC_DIR}:${DYNAMIC_DIR}" \
    -v "${OUTPUT}.tmp:${OUTPUT}.tmp:ro" \
    alpine:3.20 sh -c "mv '${OUTPUT}.tmp' '${OUTPUT}' && chmod 644 '${OUTPUT}'"

  echo "==> Wrote ${OUTPUT}"
  echo ""
  cat "${OUTPUT}"
  echo ""
  echo "Restart Traefik: docker restart dokploy-traefik"
}

main "$@"
