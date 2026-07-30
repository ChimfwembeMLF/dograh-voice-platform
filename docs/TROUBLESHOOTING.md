# Troubleshooting

## No Audio / One-Way Audio

**Symptom**: Call connects but no audio in one or both directions.

**Check**:
```bash
# Verify NAT settings
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx \
  'pjsip show endpoint 9000' | grep -E 'direct_media|rtp_sym|rewrite|force_rport'

# Expected: direct_media=false, rtp_symmetric=true, rewrite_contact=true, force_rport=true
```

**Fix**: See [SIP & NAT Configuration](SIP-NAT.md).

## No Audio on IVR (*100)

**Symptom**: Ext-to-ext calls work but `*100` is silent.

**Check**:
```bash
# Verify sound files exist
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 \
  ls /var/lib/asterisk/sounds/en/digits/
```

**Fix**: Install Asterisk core sounds:
```bash
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 sh -c '
cd /tmp && curl -sLO https://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-ulaw-current.tar.gz
tar xzf asterisk-core-sounds-en-ulaw-current.tar.gz -C /var/lib/asterisk/sounds/en/
'
```

## Registration Fails (403 Forbidden)

**Symptom**: Linphone shows "Wrong password" or "Forbidden".

**Check**:
```bash
# Check auth failures
docker logs voiceagentplatform-ivr-b5lhvg-asterisk-1 | grep 'Failed to authenticate'

# Check endpoint
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx 'pjsip show endpoint 9000'
```

**Common causes**:
1. Wrong password — verify in `asterisk/pjsip.conf`
2. `max_contacts=1` exceeded — increase to 5 and add `remove_existing=yes`
3. Realm mismatch — set `realm=asterisk` on auth

## DTMF Not Detected

**Symptom**: IVR doesn't respond to key presses.

**Check**:
```bash
# Enable DTMF debug
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx 'rtp set debug on'

# Check DTMF mode
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx \
  'pjsip show endpoint 9000' | grep dtmf_mode
```

**Fix**: Ensure `dtmf_mode=rfc4733` (default). If using SIP INFO, add `dtmf_mode=info`.

## Dograh ARI Not Connecting

**Symptom**: `8000` connects but no AI response, or ARI logs show connection failures.

**Check**:
```bash
# DNS resolution from Dograh API
docker exec voiceagentplatform-ivr-b5lhvg-api-1 \
  python3 -c "import socket; print(socket.gethostbyname('asterisk'))"

# ARI applications
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 \
  curl -s -u dograh:dograh_ari_secret http://localhost:8088/ari/applications

# Dograh telephony config
docker exec voiceagentplatform-ivr-b5lhvg-postgres-1 \
  psql -U postgres -d dograh-db \
  -c "SELECT credentials FROM telephony_configurations WHERE id=1;"
```

**Fix**:
1. Ensure `asterisk` DNS alias exists on voice-network
2. Verify `ari_endpoint: "http://asterisk:8088"` in telephony config
3. Verify `app_name: "dograh"` and `app_password: "dograh_ari_secret"`

## Docker Container Stuck

**Symptom**: `docker start` or `docker compose up` hangs on Asterisk.

**Fix**:
```bash
# Kill stale docker-proxy processes
pkill -f "docker-proxy.*5060"
pkill -f "docker-proxy.*8088"

# Remove stuck container
docker rm -f voiceagentplatform-ivr-b5lhvg-asterisk-1

# Restart (with reduced port range)
docker compose up -d asterisk
```

## Lost Dialplan After Restart

**Symptom**: `*100` stops working after Asterisk restart.

**Fix**: Dynamic dialplan entries (added via `dialplan add`) are in-memory only. Add them permanently:
1. Edit `asterisk/extensions.conf`
2. Or run the setup commands after each restart

## Check Overall Health

```bash
# All voice containers
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep voiceagent

# Asterisk uptime
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx 'core show uptime'

# Registrations
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx 'pjsip show endpoints'

# ARI
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 \
  curl -s -u dograh:dograh_ari_secret http://localhost:8088/ari/asterisk/info
```
