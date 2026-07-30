# Deployment Checklist — Tekrem Voice Platform

## Day 1 — Server B (Dokploy)

- [ ] Rotate secrets exposed in old Git commits (Redis, TURN, JWT, S3)
- [ ] Use **Compose** service `voiceagentplatform-ivr-hj26ln` (not Application)
- [ ] Git: `ChimfwembeMLF/dograh-voice-platform`, path `docker-compose.yaml`
- [ ] Paste sanitized env from `dograh.env.example` into Dokploy Environment
- [ ] Deploy → verify `whisper`, `piper`, `api`, `ui` healthy
- [ ] `curl https://voice.tekreminnovations.com/api/v1/health`

```bash
docker ps | grep -E 'whisper|piper|api'
docker exec $(docker ps -qf name=voiceagentplatform-ivr-hj26ln-api) curl -sf http://whisper:9000/v1/models
docker exec $(docker ps -qf name=voiceagentplatform-ivr-hj26ln-api) curl -sf http://piper:5000/health
```

## Day 2 — Dograh UI

- [ ] Models → BYOK: LLM, STT, TTS (see README)
- [ ] Create workflow (e.g. Mako bank assistant)
- [ ] Upload Recordings → use `@` in prompts
- [ ] Test Web Call
- [ ] Confirm recordings land in MinIO bucket `mako`

## Day 3–4 — Server A (Telephony)

- [ ] Install Asterisk 20+ with `chan_websocket`, `res_websocket_client`, `res_ari`
- [ ] Copy `asterisk/*.example` → `/etc/asterisk/`
- [ ] Use `uri = wss://voice.tekreminnovations.com/api/v1/telephony/ws/ari` in `websocket_client.conf`
- [ ] Dialplan: extension `8000` → `Stasis(dograh)`
- [ ] Dograh → Telephony → Asterisk ARI → add extension `8000` + workflow
- [ ] Configure MTN/Airtel SIP trunk + inbound route

## Day 5 — Go-live test

- [ ] PSTN call → AI responds → recording in MinIO
- [ ] Latency under ~3s per turn (target)
- [ ] Human transfer path tested

## Skip for MVP

- [ ] sip-connector (`COMPOSE_PROFILES=sip-connector`)
- [ ] Prometheus/Grafana (week 2)

## Backup

```bash
chmod +x scripts/backup-postgres.sh
./scripts/backup-postgres.sh /var/backups/dograh
```
