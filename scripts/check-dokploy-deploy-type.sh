#!/usr/bin/env bash
# Run on the Dokploy VPS to see why Nixpacks keeps running.
# Usage: sudo ./scripts/check-dokploy-deploy-type.sh

set -euo pipefail

echo "=== Dokploy service paths ==="
echo "Applications (Nixpacks — WRONG for this repo):"
if [[ -d /etc/dokploy/applications ]]; then
  ls -la /etc/dokploy/applications/ 2>/dev/null || echo "  (empty)"
else
  echo "  /etc/dokploy/applications not found"
fi

echo ""
echo "Compose (docker compose — CORRECT for this repo):"
if [[ -d /etc/dokploy/compose ]]; then
  ls -la /etc/dokploy/compose/ 2>/dev/null || echo "  (empty)"
else
  echo "  /etc/dokploy/compose not found"
fi

echo ""
echo "=== Recent deploy logs mentioning nixpacks ==="
if docker ps -a --format '{{.Names}}' | grep -q dokploy; then
  docker logs dokploy 2>&1 | grep -i nixpacks | tail -5 || echo "  (none in dokploy logs)"
fi

echo ""
echo "=== Running voice-related containers ==="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -Ei 'voice|dograh|whisper|piper|postgres|api|ui' || echo "  (none)"

echo ""
echo "=== FIX ==="
cat <<'EOF'
If you see nixpacks in deploy logs:

1. Dokploy UI → find ANY service named like "voiceplatform-*" with type Application
2. Delete it OR disable Auto Deploy on it
3. Use ONLY the Compose service: voiceagentplatform-ivr-hj26ln
4. Compose path: docker-compose.yml
5. Deploy from Compose service only

Piper build succeeding (#8 pip install) = Compose is working.
Nixpacks failing after git clone = a separate Application is still deploying.
EOF
