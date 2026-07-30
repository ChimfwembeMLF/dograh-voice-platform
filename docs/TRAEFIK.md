# Traefik on Dokploy — File System Setup

Dokploy stores Traefik config on the **host filesystem**:

```
/etc/dokploy/traefik/
├── traefik.yml                 # static config (entrypoints, providers)
└── dynamic/
    ├── acme.json               # Let's Encrypt certs (chmod 600)
    ├── middlewares.yml         # redirect-to-https
    ├── dokploy.yml             # Dokploy panel routing
    └── voice-platform.yml      # Dograh routing (optional fallback)
```

Traefik's **file provider only reads files in the top level** of `dynamic/` — not subdirectories like `certificates/`.

---

## Compose vs Application routing

| Service type | How Traefik learns routes |
|--------------|---------------------------|
| **Application** (Nixpacks) | File provider — Dokploy writes `.yml` into `dynamic/` |
| **Compose** (this repo) | Docker provider — labels on `api` / `ui` containers |

Your `docker-compose.yml` already has Traefik labels. **Compose does not create a file in `dynamic/`** — that is normal.

If you get **404** on `voice.tekreminnovations.com`, common causes:

1. `api` / `ui` not attached to `dokploy-network`
2. Traefik too old for Docker Engine 28+ (upgrade to `traefik:v3.6.7`)
3. Missing base Traefik files under `/etc/dokploy/traefik/`

---

## Quick fix on the server (Docker)

SSH into the Dokploy VPS, clone or copy this repo, then:

```bash
cd /path/to/dograh-voice-platform
chmod +x scripts/*.sh

# 1. Create missing Traefik directories + default files
sudo ./scripts/setup-dokploy-traefik-fs.sh

# 2. If domain still 404 — generate file-based routing for Dograh
sudo PUBLIC_HOST=voice.tekreminnovations.com \
     COMPOSE_PROJECT=voiceagentplatform-ivr-hj26ln \
     ./scripts/generate-voice-traefik-config.sh

sudo docker restart dokploy-traefik
```

One-liner bootstrap (no repo clone — copies templates via docker):

```bash
sudo docker network create dokploy-network 2>/dev/null || true
sudo mkdir -p /etc/dokploy/traefik/dynamic
sudo touch /etc/dokploy/traefik/dynamic/acme.json
sudo chmod 600 /etc/dokploy/traefik/dynamic/acme.json
```

Then run the setup script from the repo for full config.

---

## What each script does

### `scripts/setup-dokploy-traefik-fs.sh`

- Creates `/etc/dokploy/traefik/dynamic/` and `acme.json`
- Installs `traefik.yml`, `middlewares.yml`, `dokploy.yml` if missing
- Ensures `dokploy-network` exists
- Starts or restarts `dokploy-traefik` container

Options:

```bash
sudo ACME_EMAIL=admin@tekreminnovations.com ./scripts/setup-dokploy-traefik-fs.sh
sudo ./scripts/setup-dokploy-traefik-fs.sh --with-voice-config
sudo ./scripts/setup-dokploy-traefik-fs.sh --force-traefik   # recreate Traefik v3.6.7
```

### `scripts/generate-voice-traefik-config.sh`

- Finds running `api` and `ui` containers (by labels or `COMPOSE_PROJECT`)
- Connects them to `dokploy-network` if needed
- Writes `voice-platform.yml` to Traefik dynamic directory
- Use as **fallback** when label-based routing fails

---

## Verify routing

```bash
# Traefik running?
docker ps | grep dokploy-traefik

# Dograh on dokploy-network?
docker network inspect dokploy-network --format '{{range .Containers}}{{.Name}} {{end}}'

# Dynamic config present?
ls -la /etc/dokploy/traefik/dynamic/

# HTTP test
curl -I https://voice.tekreminnovations.com/api/v1/health
```

---

## Manual file install (Dokploy UI → Traefik → File System)

If you edit files in Dokploy's Traefik File System UI, ensure these exist:

| File | Purpose |
|------|---------|
| `traefik.yml` | Static Traefik config |
| `dynamic/acme.json` | TLS certificate storage |
| `dynamic/middlewares.yml` | HTTPS redirect |
| `dynamic/dokploy.yml` | Dokploy panel |
| `dynamic/voice-platform.yml` | Dograh UI + API (optional) |

Copy templates from this repo's `traefik/` directory.

---

## Preferred: label routing (no voice-platform.yml)

When Compose deploy works correctly, Traefik reads labels from containers:

```yaml
labels:
  - traefik.enable=true
  - traefik.docker.network=dokploy-network
  - traefik.http.routers.dograh-api.rule=Host(`voice.tekreminnovations.com`) && PathPrefix(`/api/v1`)
```

Ensure `api` and `ui` services join the external network:

```yaml
networks:
  traefik:
    external: true
    name: dokploy-network
```

This is already configured in `docker-compose.yml`.
