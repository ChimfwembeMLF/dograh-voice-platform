# Tekrem Innovations — Voice Platform (Dograh + Asterisk + Piper + Whisper)

Self-hosted voice platform integrating Asterisk PBX with Dograh AI voice agents, Piper TTS, and Whisper STT.

> **Dokploy:** Use service type **Compose**, NOT Application.  
> See **[docs/DOKPLOY.md](docs/DOKPLOY.md)** — Applications fail with `Nixpacks build failed`.

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Linphone   │────▶│   Asterisk   │────▶│  Dograh API  │
│  (SIP Client) │     │   (PBX/ARI)  │     │  (Voice AI)  │
└──────────────┘     └──────┬───────┘     └──────┬───────┘
                            │                    │
                    ┌───────┴───────┐    ┌───────┴───────┐
                    │  Piper (TTS)  │    │ Whisper (STT) │
                    └───────────────┘    └───────────────┘
```

## Quick Start

### Test Extensions

| Extension | Username | Password | Purpose |
|-----------|----------|----------|---------|
| 100       | 100      | test123  | Test extension |
| 9000      | 9000     | dograh9000 | Sales |
| 9001      | 9001     | dograh9001 | Support |

### Linphone Setup

```
Username:  9000 (or 9001, 100)
Password:  <see table above>
Domain:    38.242.147.192 (or pbx.tekreminnovations.com)
Transport: UDP
```

### IVR Menu

Dial `*100` to reach the voice IVR:

| Press | Route |
|-------|-------|
| 1 | Sales → extension 9000 |
| 2 | Support → extension 9001 |
| 0 | Operator → extension 9000 |

### Dograh Voice AI

Dial `8000` to connect to the Dograh AI voice agent (requires Dograh telephony configured).

## Stack

| Component | Image | Port |
|-----------|-------|------|
| Asterisk PBX | andrius/asterisk:latest | 5060 (SIP), 8088 (ARI), 5038 (AMI) |
| Dograh API | dograhai/dograh-api | 8000 |
| Dograh UI | dograhai/dograh-ui | 3010 |
| Piper TTS | custom (Dockerfile.piper) | 5000 |
| Whisper STT | hwdsl2/whisper-server | 9000 |
| PostgreSQL | pgvector/pgvector:pg17 | 5432 |
| CoTURN | coturn/coturn:4.8.0 | 3478, 5349 |

## DNS (Cloudflare)

All A records point to `38.242.147.192`:

| Subdomain | Proxied | Notes |
|-----------|---------|-------|
| dograh.tekreminnovations.com | ✅ | Dograh UI |
| app.tekreminnovations.com | ✅ | App UI |
| voice.tekreminnovations.com | ✅ | Voice platform |
| pbx.tekreminnovations.com | ❌ | SIP PBX (no proxy) |
| sip.tekreminnovations.com | ❌ | SIP (no proxy) |
| turn.tekreminnovations.com | ❌ | TURN (no proxy) |

> **Important:** SIP and TURN domains must have Cloudflare proxy **disabled** (DNS-only) — proxying blocks UDP.

## Documentation

- **[Deployment Guide](docs/DOKPLOY.md)** — Dokploy setup
- **[Architecture](docs/ARCHITECTURE.md)** — System design and data flow
- **[SIP & NAT Configuration](docs/SIP-NAT.md)** — NAT traversal and audio fixes
- **[IVR Setup](docs/IVR.md)** — Voice menus and TTS audio
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** — Common issues

## Quick Commands

```bash
# Redeploy
cd /etc/dokploy/compose/voiceagentplatform-ivr-b5lhvg/code
docker compose up -d

# Check registrations
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx 'pjsip show endpoints'

# Check ARI
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 curl -s -u dograh:dograh_ari_secret http://localhost:8088/ari/applications

# Watch logs
docker logs -f voiceagentplatform-ivr-b5lhvg-asterisk-1
```
