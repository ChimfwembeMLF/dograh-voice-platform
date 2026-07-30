# Tekrem Innovations — Voice Platform (Dograh + Whisper + Piper)

> **Dokploy:** Use service type **Compose**, NOT Application.  
> See **[docs/DOKPLOY.md](docs/DOKPLOY.md)** — Applications fail with `Nixpacks build failed`.

Self-hosted deployment for **Dograh** (voice agent platform) and voice AI backends, integrated with Asterisk ARI and external Ollama.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Telephony Paths: ARI vs sip-connector](#telephony-paths-ari-vs-sip-connector)
3. [Asterisk ARI + Dograh (Recommended)](#asterisk-ari--dograh-recommended-for-sip--ui-management)
4. [Implementation Plan](#implementation-plan)
5. [Strategies Used](#strategies-used)
6. [File Structure](#file-structure)
7. [Prerequisites](#prerequisites)
8. [Deployment Guide](#deployment-guide)
9. [Dokploy Setup](#dokploy-setup)
10. [Dograh Models (Self-Hosted AI)](#dograh-models-self-hosted-ai)
11. [sip-connector API Reference](#sip-connector-api-reference)
12. [Monitoring](#monitoring)
13. [Troubleshooting](#troubleshooting)
14. [Security Checklist](#security-checklist)
15. [Future Enhancements](#future-enhancements)

---

## Architecture

### Two-Server Model

| Server | Role | Components |
|--------|------|------------|
| **Server A** | Telephony | Asterisk / FreePBX / SIP trunk — handles PSTN/SIP calls |
| **Server B** | AI Platform | Dokploy, Dograh, Whisper, Piper, SIP connector, external Ollama |

```
                    ┌─────────────────────────────────────────────┐
                    │              Server A (Telephony)            │
                    │  Asterisk — extensions 8000 (Dograh) / 9000  │
                    └───────────────┬─────────────┬───────────────┘
                                    │             │
                         ARI + WSS  │             │  SIP optional
                         (primary)  │             │  sip-connector
                                    ▼             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                        Server B (AI Platform / Dokploy)                   │
│  Dograh api+ui ──► Whisper + Piper (voice-network)                        │
│  Traefik: voice.tekreminnovations.com                                     │
└──────────────────────────────────────────────────┬───────────────────────┘
                                                   │ HTTPS → Ollama (external)
```

External dependencies: Redis (`REDIS_URL`), MinIO/S3 (`S3_*`).

### Voice pipeline flows

**Path A — Asterisk ARI → Dograh (recommended for SIP + UI):**

```
Caller → Stasis(dograh) → Dograh workflow → Whisper / Ollama / Piper → caller
```

**Path B — sip-connector (optional fixed pipeline):**

```
Caller audio → POST /process_audio → Whisper → Ollama → Piper → WAV
```

### Docker Networks

| Network | Purpose |
|---------|---------|
| `app-network` | Dograh services (postgres, api, ui, coturn) |
| `voice-network` | Whisper, Piper, sip-connector, Prometheus |
| `dokploy-network` (external) | Traefik routing for Dograh UI/API |

The **`api` service joins both `app-network` and `voice-network`** so Dograh can reach `http://whisper:9000` and `http://piper:5000` when you configure self-hosted models in the UI.

---

## Telephony Paths: ARI vs sip-connector

| | **Asterisk ARI → Dograh** (recommended) | **sip-connector** (optional) |
|---|----------------------------------------|------------------------------|
| SIP still works? | **Yes** — Asterisk handles SIP | **Yes** — REGISTER as ext 9000 |
| Managed from Dograh UI? | **Yes** — workflows, recordings, models | **No** |
| Pre-recorded audio | Dograh **Recordings** + `@` in prompts | Asterisk `Playback()` or custom clips |
| Extension example | `8000` → `Stasis(dograh)` | `9000` → sip-connector |
| Deploy command | `./quickstart.sh dograh` | `./quickstart.sh voice` |

**Both can run at the same time** on different extensions.

---

## Asterisk ARI + Dograh (Recommended for SIP + UI management)

SIP calls stay on **Server A (Asterisk)**. Dograh on **Server B** controls the call over **ARI + WebSocket audio** — no `sip-connector` required for production inbound.

### Call flow

```
Caller (PSTN/SIP)
    → Asterisk dialplan: Stasis(dograh)
    → ARI StasisStart event → Dograh API
    → WebSocket external media (ulaw)
    → Dograh workflow (STT → LLM → TTS, @recordings)
    → Whisper / Ollama / Piper (via Models config)
    → Audio back to caller
```

### Step 1 — Deploy Dograh + voice backends on Server B

```bash
cd /opt/voice-ai
cp dograh.env.example dograh.env   # edit secrets
./quickstart.sh dograh
```

This starts: `postgres`, `coturn`, `api`, `ui`, `whisper`, `piper`.

Verify:

```bash
curl -sf https://voice.tekreminnovations.com/api/v1/health
docker exec $(docker ps -qf name=api) curl -sf http://whisper:9000/v1/models
docker exec $(docker ps -qf name=api) curl -sf http://piper:5000/health
```

### Step 2 — Configure Asterisk on Server A

Templates are in [`asterisk/`](asterisk/):

| File | Purpose |
|------|---------|
| `ari.conf.example` | ARI user/password for Dograh |
| `http.conf.example` | HTTP server on port 8088 |
| `extensions.conf.example` | Route ext `8000` → `Stasis(dograh)` |
| `extensions_voice.conf.example` | Bank voice-ai dialplan snippet |
| `websocket_client.conf.example` | Point Asterisk media WS at Dograh |
| `pjsip.conf.snippet.example` | Allow `ulaw` codec |

Copy and edit on Server A:

```bash
# On Server A
sudo cp ari.conf.example /etc/asterisk/ari.conf
sudo cp http.conf.example /etc/asterisk/http.conf
sudo cp websocket_client.conf.example /etc/asterisk/websocket_client.conf
# Merge extensions.conf.example into /etc/asterisk/extensions.conf

asterisk -rvvv
ari reload
dialplan reload
module reload res_websocket_client.so
```

**Critical:** `websocket_client.conf` URI must match `DOGRAH_ARI_WS_URI` in `dograh.env`:

```ini
[dograh]
type = websocket_client
uri = wss://voice.tekreminnovations.com/api/v1/telephony/ws/ari
protocols = media
tls_enabled = yes
ca_list_file = /etc/ssl/certs/ca-certificates.crt
```

**Firewall (Server A ↔ Server B):**

| Direction | Port | Purpose |
|-----------|------|---------|
| Server B → Server A | TCP 8088 | Dograh → Asterisk ARI REST |
| Server A → Server B | TCP 443 (wss) | Asterisk → Dograh WebSocket media |
| SIP/RTP | UDP 5060, RTP range | Normal telephony (unchanged) |

### Step 3 — Configure Dograh telephony UI

1. Open `https://voice.tekreminnovations.com/telephony-configurations`
2. **Add configuration** → **Asterisk ARI**
3. Fill in:

| Dograh field | Value (from `dograh.env`) |
|--------------|---------------------------|
| ARI Endpoint URL | `http://ASTERISK_HOST:8088` |
| Stasis App Name | `dograh` (= `ARI_APP_NAME`) |
| App Password | same as `ARI_APP_PASSWORD` / `ari.conf` |
| WebSocket Client Name | `dograh` (= `websocket_client.conf` section) |

4. Add **phone number** `8000` (or your `DOGRAH_INBOUND_EXTENSION`)
5. Assign an **Inbound workflow** (your voice agent)
6. Save and place a test call to extension `8000`

### Step 4 — Configure self-hosted models in Dograh

See [Dograh Models (Self-Hosted AI)](#dograh-models-self-hosted-ai) below.

### Step 5 — Pre-recorded audio in Dograh

1. Go to **Recordings** in Dograh UI
2. Upload WAV files (greeting, FAQ, etc.)
3. In your workflow prompt, type `@` to insert a recording
4. Dynamic parts use TTS; fixed parts play instantly (lower latency, no TTS cost)

### Inbound dialplan (Server A)

```ini
[from-external]
exten => 8000,1,NoOp(Inbound call to Dograh)
 same => n,Stasis(dograh)
 same => n,Hangup()
```

Replace `dograh` with your `ARI_APP_NAME` if different.

---

## Implementation Plan

### Phase 1 — Foundation (Done)

| Step | Task | Output |
|------|------|--------|
| 1.1 | Dograh compose (Postgres, coturn, api, ui) | `docker-compose.yaml` |
| 1.2 | External Redis + MinIO via env | `dograh.env.example` |
| 1.3 | Traefik labels for Dokploy | api/ui service labels |

### Phase 2 — Voice AI Stack (Done)

| Step | Task | Output |
|------|------|--------|
| 2.1 | Whisper STT container (OpenAI-compatible API) | `whisper` service |
| 2.2 | Piper TTS HTTP wrapper | `piper-server.py`, `Dockerfile.piper` |
| 2.3 | SIP connector orchestrator | `sip-connector.py`, `Dockerfile.sip` |
| 2.4 | Health checks + dependency ordering | compose `depends_on` + healthchecks |
| 2.5 | SIP REGISTER with digest auth | background task in sip-connector |

### Phase 3 — Deploy & Validate

| Step | Task | Command |
|------|------|---------|
| 3.1 | Copy project to Server B | `scp -r . user@SERVER:/opt/voice-ai/` |
| 3.2 | Configure secrets | `cp dograh.env.example dograh.env` |
| 3.3 | Start Dograh + voice backends | `./quickstart.sh dograh` |
| 3.4 | Configure Asterisk ARI on Server A | copy files from `asterisk/` |
| 3.5 | Configure Dograh telephony + Models UI | ARI + extension `8000` |
| 3.6 | Test inbound SIP call | dial extension `8000` |
| 3.7 | (Optional) sip-connector stack | `./quickstart.sh voice` |

### Phase 4 — Production Hardening (Recommended)

| Step | Task |
|------|------|
| 4.1 | Restrict ARI port 8088 to Server B IP only (Server A firewall) |
| 4.2 | Use `wss://` for Asterisk → Dograh WebSocket media |
| 4.3 | Enable Prometheus: `./quickstart.sh monitoring` |
| 4.4 | Tune Whisper model size (`WHISPER_MODEL`) for CPU/GPU |
| 4.5 | Upload pre-recorded greetings to Dograh **Recordings** |
| 4.6 | (Optional) Restrict sip-connector `:8080` if still in use |

---

## Strategies Used

### 1. Microservice Orchestration (Not Monolith)

**Strategy:** Each AI capability runs in its own container; `sip-connector` is a thin orchestrator.

**Why:**
- Whisper and Piper have different resource profiles (CPU/memory).
- Services can be scaled or swapped independently (e.g., swap Piper for Kokoro).
- Failures are isolated — a Piper crash does not take down Dograh.

### 2. OpenAI-Compatible APIs Where Possible

**Strategy:** Use `hwdsl2/whisper-server` with `/v1/audio/transcriptions`.

**Why:**
- Industry-standard interface; easy to swap STT providers.
- Minimal custom protocol code in sip-connector.

### 3. External LLM (Ollama)

**Strategy:** Ollama runs at `ai.tekreminnovations.com`, not in this compose file.

**Why:**
- LLM inference is GPU-heavy; likely already centralized.
- Avoids duplicating Ollama on the same host as Dograh + Whisper.
- sip-connector only needs an HTTP URL.

### 4. Custom Piper HTTP Wrapper

**Strategy:** Built `piper-server.py` + `Dockerfile.piper` because Piper natively uses CLI/Wyoming, not HTTP on port 5000.

**Why:**
- Your spec required `PIPER_URL=http://piper:5000`.
- Auto-downloads voice models on first use.
- Exposes `/api/tts` and `/v1/audio/speech` for flexibility.

### 5. SIP Registration Without Heavy PJSIP

**Strategy:** Lightweight UDP SIP REGISTER with MD5 digest authentication.

**Why:**
- Avoids multi-stage PJSIP builds in Docker.
- Sufficient for registering extension 9000 with Asterisk/FreePBX.
- Live RTP call handling is delegated to Server A → HTTP webhook pattern (Phase 4).

**Limitation:** Full bidirectional RTP media handling is not in v1; use `/process_audio` or Asterisk AudioSocket integration for call audio.

### 6. Network Segmentation

**Strategy:** `app-network` vs `voice-network`.

**Why:**
- Dograh web stack and voice backends have different exposure needs.
- `api` bridges both networks so Dograh reaches Whisper/Piper internally.
- Traefik only exposes Dograh UI/API publicly.

### 7. Environment-Driven Configuration

**Strategy:** Single `dograh.env` for Dokploy and voice services.

**Why:**
- One file to manage in Dokploy UI.
- Compose `${VAR:-default}` pattern for safe defaults.

### 8. Health-Gated Startup

**Strategy:** `depends_on: condition: service_healthy` for sip-connector.

**Why:**
- Prevents orchestrator from starting before Whisper/Piper are ready.
- Reduces startup race errors.

### 9. Dograh as Telephony Control Plane (ARI)

**Strategy:** Asterisk handles SIP/RTP; Dograh handles agent logic via ARI + WebSocket.

**Why:**
- SIP continues to work — Asterisk is unchanged for carriers/trunks.
- Workflows, recordings, models, and campaigns managed in one UI.
- Avoids maintaining a parallel `sip-connector` pipeline for production calls.

---

## File Structure

```
/opt/voice-ai/
├── docker-compose.yaml
├── dograh.env / dograh.env.example
├── asterisk/                           # Server A config templates
│   ├── ari.conf.example
│   ├── http.conf.example
│   ├── extensions.conf.example
│   ├── websocket_client.conf.example
│   └── README.md
├── sip-connector.py                    # Optional — fixed pipeline
├── Dockerfile.sip
├── piper-server.py / Dockerfile.piper
├── whisper (compose service)
├── quickstart.sh                       # dograh | voice | full | monitoring
└── README.md
```

---

## Prerequisites

### Server B (AI Platform)

- Docker Engine 24+ and Docker Compose v2
- Dokploy installed (optional but recommended)
- 8 GB+ RAM (16 GB recommended with Whisper `small.en`)
- Ports available: 8080 (sip-connector), 3478/5349/49152-49200 (coturn)
- Outbound HTTPS to `ai.tekreminnovations.com`

### Server A (Telephony)

- Asterisk 20 LTS or 22+ with `chan_websocket` and `res_websocket_client`
- ARI enabled (`ari.conf`, `http.conf` on port 8088)
- Extension `8000` (or `DOGRAH_INBOUND_EXTENSION`) routed to `Stasis(dograh)`
- Firewall: allow Server B → TCP 8088; Server A → Server B TCP 443 (wss)
- Optional: extension `9000` for legacy `sip-connector` path

### External Services

- Redis instance reachable from Docker network
- MinIO/S3-compatible storage
- Ollama API at configured `OLLAMA_URL`

---

## Deployment Guide

### 1. Copy Files to Server B

```bash
ssh user@YOUR_AI_SERVER_IP
sudo mkdir -p /opt/voice-ai
sudo chown -R $USER:$USER /opt/voice-ai

# From your workstation:
scp -r . user@YOUR_AI_SERVER_IP:/opt/voice-ai/
```

### 2. Configure Environment

```bash
cd /opt/voice-ai
cp dograh.env.example dograh.env
nano dograh.env
```

**Required ARI values (Server A ↔ Dograh):**

```bash
ASTERISK_HOST=YOUR_TELEPHONY_SERVER_IP
ARI_APP_NAME=dograh
ARI_APP_PASSWORD=change-me-ari-password
DOGRAH_ARI_WS_URI=wss://voice.tekreminnovations.com/api/v1/telephony/ws/ari
DOGRAH_INBOUND_EXTENSION=8000
```

**Required Dograh values:**

```bash
REDIS_URL=redis://...
S3_ENDPOINT_URL=https://...
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
TURN_HOST=...
TURN_SECRET=...
OSS_JWT_SECRET=...
```

### 3. Deploy (recommended: Dograh + ARI)

```bash
chmod +x quickstart.sh
./quickstart.sh dograh
```

Then configure Server A using [`asterisk/`](asterisk/) and Dograh telephony UI (see [Asterisk ARI + Dograh](#asterisk-ari--dograh-recommended-for-sip--ui-management)).

### 4. Verify Dograh + voice backends

```bash
curl -sf https://voice.tekreminnovations.com/api/v1/health | python3 -m json.tool
docker exec $(docker ps -qf name=dograh-api) curl -sf http://whisper:9000/v1/models
docker exec $(docker ps -qf name=dograh-api) curl -sf http://piper:5000/health
```

### 5. Optional — sip-connector stack

```bash
./quickstart.sh voice   # whisper + piper + sip-connector only
./quickstart.sh full    # everything
```

---

## Dokploy Setup

### Dograh (existing project)

1. Create project in Dokploy (e.g. `voice-ai-platform`)
2. Point compose path to `/opt/voice-ai/docker-compose.yaml`
3. Paste `dograh.env` contents into Dokploy Environment
4. Ensure `dokploy-network` exists and Traefik is running
Deploy `postgres`, `coturn`, `api`, `ui`, `whisper`, `piper` from the same compose project.

**Option B — Separate Dokploy service for sip-connector:**

| Setting | Value |
|---------|-------|
| Name | `sip-connector` |
| Build | `Dockerfile.sip` |
| Port | `8080:8080` |
| Env | Same as `dograh.env` voice section |

Deploy `whisper` and `piper` with Dograh for ARI path. Add `sip-connector` only if needed.

---

## Dograh Models (Self-Hosted AI)

Configure in Dograh UI: **Models → BYOK** (Bring Your Own Key).

Because `api` is on `voice-network`, use **internal Docker hostnames** from the Dograh API container:

### LLM (OpenAI-compatible / Ollama)

| Field | Value |
|-------|-------|
| Provider | **OpenAI** |
| base_url | `https://ai.tekreminnovations.com/v1` |
| model | `llama3.2` (or your Ollama model name) |
| api_key | leave blank if not required |

### STT / Transcriber (Whisper)

| Field | Value |
|-------|-------|
| Provider | **OpenAI** |
| base_url | `http://whisper:9000/v1` |
| model | `whisper-1` |
| api_key | leave blank |

### TTS / Voice (Piper)

| Field | Value |
|-------|-------|
| Provider | **OpenAI** |
| base_url | `http://piper:5000/v1` |
| model | `tts-1` |
| voice | `default` |
| api_key | leave blank |

> **Tip:** Test connectivity from the api container before saving Models:
> `docker exec $(docker ps -qf name=api) curl -sf http://whisper:9000/v1/models`

### Pre-recorded audio

Managed entirely in Dograh — no sip-connector needed:

1. **Recordings** page → upload WAV
2. Workflow prompt → type `@` to insert recording
3. Hybrid: recordings for fixed phrases, TTS for dynamic replies

---

## sip-connector API Reference

Optional service for a fixed STT→LLM→TTS pipeline (extension 9000 path).

### `GET /health`

Returns dependency status for Whisper and Piper.

```json
{
  "status": "healthy",
  "services": [
    {"name": "whisper", "url": "http://whisper:9000/v1/models", "ok": true, "status": 200},
    {"name": "piper", "url": "http://piper:5000/health", "ok": true, "status": 200}
  ],
  "sip": {
    "enabled": true,
    "host": "10.0.0.5",
    "extension": "9000"
  }
}
```

### `POST /process_audio`

| Field | Type | Description |
|-------|------|-------------|
| `audio` | file | WAV/audio file (multipart form) |

**Response:** `audio/wav` body

**Headers:**
- `X-Transcript` — Whisper transcription
- `X-Reply` — Ollama response text

### Piper `POST /api/tts`

```json
{"text": "Hello from Piper"}
```

Returns WAV audio.

### sip-connector telephony (optional)

1. Create extension **9000** on Server A with `SIP_SECRET`
2. Deploy: `./quickstart.sh voice`
3. sip-connector REGISTERs to `SIP_HOST` every 300s

For production SIP with full UI control, use **Asterisk ARI → Dograh** (extension 8000) instead.

---

## Monitoring

Enable Prometheus (optional profile):

```bash
./quickstart.sh monitoring
# or
docker compose --env-file dograh.env --profile monitoring up -d prometheus
```

Prometheus UI: `http://SERVER_B:9090`

Scrape targets configured in `prometheus.yml`:
- sip-connector:8080/health
- whisper:9000/v1/models
- piper:5000/health

---

## Troubleshooting

| Problem | Check | Fix |
|---------|-------|-----|
| ARI auth failed | `ari.conf` vs Dograh telephony creds | Match `ARI_APP_NAME` + password |
| No audio on ARI call | Asterisk modules | `chan_websocket`, `res_websocket_client` Running |
| WebSocket media fails | `websocket_client.conf` URI | Must match `DOGRAH_ARI_WS_URI` (wss + tls_enabled) |
| Call hangs up immediately | Dograh telephony numbers | Add ext `8000` + assign inbound workflow |
| Dograh can't reach Whisper | api on voice-network? | `docker compose up -d api`; test from api container |
| sip-connector unhealthy | `docker logs voice-sip-connector` | Verify Whisper/Piper healthy |
| Whisper slow to start | First run downloads model | Wait 2–5 min |
| Ollama 502 | `curl -I $OLLAMA_URL` | Verify model name and URL |
| Dograh api fails | `REDIS_URL`, S3 vars | Fill required env vars |

**Useful commands:**

```bash
# From Dograh api container → voice backends
docker exec $(docker ps -qf name=api) curl -sf http://whisper:9000/v1/models
docker exec $(docker ps -qf name=api) curl -sf http://piper:5000/health

# Asterisk CLI (Server A)
asterisk -rx "module show like chan_websocket"
asterisk -rvvv

# sip-connector (optional)
docker logs -f voice-sip-connector
curl http://localhost:8080/health
```

---

## Security Checklist

- [ ] Replace all `change-me-*` values in `dograh.env`
- [ ] Do not commit `dograh.env` to git (use `.gitignore`)
- [ ] Restrict Asterisk ARI (8088) to Server B IP only
- [ ] Use `wss://` for Asterisk → Dograh WebSocket
- [ ] Match `ARI_APP_PASSWORD` across `ari.conf` and Dograh UI
- [ ] Restrict sip-connector port 8080 if deployed (optional)
- [ ] Use strong `OSS_JWT_SECRET`
- [ ] Review coturn port exposure (3478, 49152-49200)

---

## Future Enhancements

1. **GPU Whisper** — `hwdsl2/whisper-server:cuda`
2. **Speaches** — streaming STT if batch Whisper latency is too high on live ARI calls
3. **Outbound campaigns** — Dograh CSV dialer via ARI
4. **Metrics** — Prometheus latency histograms per pipeline stage

---

## Quick Reference

| Service | Container | Port | URL |
|---------|-----------|------|-----|
| Dograh UI | ui | 3010 (Traefik) | `https://voice.tekreminnovations.com` |
| Dograh API | api | 8000 (Traefik) | `https://voice.tekreminnovations.com/api/v1` |
| ARI WebSocket | api | 443 (wss) | `wss://voice.tekreminnovations.com/api/v1/telephony/ws/ari` |
| Asterisk ARI | Server A | 8088 | `http://ASTERISK_HOST:8088` |
| Whisper | whisper | 9000 | `http://whisper:9000` (from api container) |
| Piper | piper | 5000 | `http://piper:5000` (from api container) |
| sip-connector (opt) | voice-sip-connector | 8080 | `http://localhost:8080` |
| Ollama (external) | — | 443 | `https://ai.tekreminnovations.com/v1` |

### quickstart.sh modes

| Command | Starts |
|---------|--------|
| `./quickstart.sh dograh` | Dograh + Whisper + Piper (**recommended**) |
| `./quickstart.sh voice` | sip-connector stack only |
| `./quickstart.sh full` | Everything |
| `./quickstart.sh monitoring` | Voice stack + Prometheus |
