# SIP & NAT Configuration

## Problem

SIP clients behind NAT experience:
- **No audio** — RTP sent to private IP instead of public IP
- **One-way audio** — client can hear but can't be heard (or vice versa)
- **Registration failures** — 403 Forbidden on re-register

## Root Cause

Asterisk sends its Docker internal IP (`172.25.0.x`) in SDP, and the client sends its LAN IP (`192.168.x.x`). Neither side can route to the other's private address.

## Solution

### pjsip.conf Settings

Applied to transport and all endpoints:

```ini
[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060
local_net=172.16.0.0/12
local_net=10.0.0.0/8
external_media_address=38.242.147.192
external_signaling_address=38.242.147.192

[9000]
type=endpoint
direct_media=no          # Force RTP through Asterisk
rewrite_contact=yes       # Rewrite Contact to public IP
force_rport=yes           # Use received port, not SDP port
rtp_symmetric=yes         # Send RTP to source IP of received packets
media_address=38.242.147.192  # Public IP in SDP c= line
```

### rtp.conf Settings

```ini
[general]
rtpstart=10000
rtpend=10019              # Must match Docker port mapping
```

### Docker Port Mapping

```yaml
ports:
  - "5060:5060/udp"
  - "5060:5060/tcp"
  - "8088:8088"
  - "10000-10019:10000-10019/udp"  # Must match rtp.conf range
```

### Key Settings Explained

| Setting | Value | Why |
|---------|-------|-----|
| `direct_media` | `no` | Routes RTP through Asterisk instead of peer-to-peer |
| `rtp_symmetric` | `yes` | Sends RTP to the IP:port packets arrive from, not SDP address |
| `rewrite_contact` | `yes` | Replaces private IP in Contact header with public IP |
| `force_rport` | `yes` | Uses the port from received packet, ignores SDP port |
| `external_media_address` | public IP | Puts public IP in SDP c= line instead of Docker IP |
| `max_contacts` | `5` | Prevents 403 on re-registration |
| `remove_existing` | `yes` | Replaces old contact instead of rejecting |

## Verification

```bash
# Check endpoint settings
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx \
  'pjsip show endpoint 9000' | grep -E 'direct_media|rtp_sym|rewrite|force_rport'

# Check RTP flow (both directions should show)
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx 'rtp set debug on'
# Make a call, then:
docker logs voiceagentplatform-ivr-b5lhvg-asterisk-1 | grep -E 'Sent RTP|Got  RTP'

# Check SDP (should show public IP)
docker logs voiceagentplatform-ivr-b5lhvg-asterisk-1 | grep 'c=IN IP'
```

## Cloudflare DNS

SIP/RTP domains must have proxy **disabled**:

| Domain | Proxy | Reason |
|--------|-------|--------|
| pbx.tekreminnovations.com | ❌ Off | SIP uses UDP, proxy blocks it |
| sip.tekreminnovations.com | ❌ Off | Same |
| turn.tekreminnovations.com | ❌ Off | TURN/STUN uses UDP |
