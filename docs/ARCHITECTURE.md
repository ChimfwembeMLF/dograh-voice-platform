# Architecture

## System Overview

```
                    Internet
                       │
                       ▼
              ┌────────────────┐
              │  Cloudflare DNS │  (pbx,sip,turn = DNS-only)
              └───────┬────────┘
                      │
              ┌───────▼────────┐
              │  Traefik Proxy │  (websecure only, Let's Encrypt)
              └───────┬────────┘
                      │
         ┌────────────┼────────────┐
         ▼            ▼            ▼
    ┌─────────┐ ┌─────────┐ ┌──────────┐
    │ Dograh  │ │ Dograh  │ │ Asterisk │
    │   UI    │ │   API   │ │   PBX    │
    │  :3010  │ │  :8000  │ │ :5060    │
    └─────────┘ └────┬────┘ │ :8088    │
                     │      │ :10000-  │
                     │      │  10019   │
         ┌───────────┤      └────┬─────┘
         ▼           ▼           ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │  Piper  │ │ Whisper │ │ Postgres│
    │  (TTS)  │ │  (STT)  │ │(pgvector)│
    │  :5000  │ │  :9000  │ │  :5432  │
    └─────────┘ └─────────┘ └─────────┘
```

## Networks

Three Docker networks:

| Network | Purpose | Containers |
|---------|---------|------------|
| `app-network` | Internal services | postgres, api, ui |
| `voice-network` | Voice/media | asterisk, piper, whisper, api |
| `traefik` / `dokploy-network` | External routing | api, ui, traefik |

## Call Flow

### IVR Call (`*100`)

```
SIP Client → Asterisk → Background(ivr/ivr-welcome) [Piper TTS audio]
              │
              ├─ DTMF 1 → Dial(PJSIP/9000) → Sales
              ├─ DTMF 2 → Dial(PJSIP/9001) → Support
              └─ DTMF 0 → Dial(PJSIP/9000) → Operator
```

### Dograh AI Call (`8000`)

```
SIP Client → Asterisk → Stasis(dograh) → Dograh ARI WebSocket
                                           │
                              ┌────────────┼────────────┐
                              ▼            ▼            ▼
                          Piper TTS    LLM (Ollama)  Whisper STT
```

### Extension-to-Extension

```
SIP 9000 → Asterisk (bridges RTP) → SIP 9001
```

## RTP Flow

```
Client (74.244.x.x) ──RTP──▶ Asterisk (172.25.0.x:10000-10019)
                               │
                               ├─ ext-to-ext: bridge → other client
                               ├─ IVR: local audio (SayDigits/Playback)
                               └─ Dograh: external media via ARI
```

NAT traversal settings:
- `rtp_symmetric=yes` — send RTP to source IP of received packets
- `direct_media=no` — force RTP through Asterisk
- `rewrite_contact=yes` — rewrite SIP Contact header
- `force_rport=yes` — use received port
- `external_media_address=38.242.147.192` — public IP in SDP

## ARI Integration

Dograh connects to Asterisk via ARI WebSocket:
```
ws://asterisk:8088/ari/events?app=dograh&api_key=dograh:dograh_ari_secret
```

Credentials (in `asterisk/ari.conf`):
```
[dograh]
type = user
read_only = no
password = dograh_ari_secret
```

## Port Map

| Port | Protocol | Service |
|------|----------|---------|
| 5060 | UDP/TCP | SIP |
| 8088 | TCP | ARI (HTTP/WS) |
| 5038 | TCP | AMI |
| 10000-10019 | UDP | RTP |
| 3478 | UDP/TCP | TURN/STUN |
| 5349 | UDP/TCP | TURN/TLS |
