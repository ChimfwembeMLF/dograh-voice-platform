# Africa's Talking SIP Trunk

## Overview

Africa's Talking routes calls from your short code to Asterisk via SIP.

```
Caller → Short Code → Africa's Talking → SIP → Asterisk → Training IVR
```

## Asterisk Configuration

Already configured in `asterisk/pjsip.conf`:

```ini
[africastalking]
type=endpoint
context=from-external
disallow=all
allow=ulaw
allow=alaw
direct_media=no
rewrite_contact=yes
force_rport=yes
rtp_symmetric=yes

[africastalking]
type=identify
endpoint=africastalking
match=41.223.144.0/20    # Kenya
match=197.248.0.0/14      # Kenya
match=105.29.0.0/16        # Additional ranges

[africastalking]
type=aor
max_contacts=10
```

### Inbound Routing

All calls from Africa's Talking go to the **Training IVR** (`*200`):

```
from-external → Goto(training,menu,1)
```

## Africa's Talking Dashboard Setup

1. Go to [Africa's Talking Dashboard](https://account.africastalking.com)
2. Navigate to **Voice** → **SIP Trunks**
3. Create a new SIP trunk:

| Field | Value |
|-------|-------|
| **SIP URI** | `sip:38.242.147.192:5060` |
| **Transport** | UDP |
| **Codec** | PCMU (ulaw) or PCMA (alaw) |

4. Assign your short code to this SIP trunk
5. Test by calling the short code

## Testing

```bash
# Monitor incoming calls
docker logs -f voiceagentplatform-ivr-b5lhvg-asterisk-1 | grep -i 'africastalking\|from-external'

# Check endpoint status
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx 'pjsip show endpoint africastalking'
```

## Short Code Routing

Currently all inbound calls go to the **Training IVR**. To route different short codes to different destinations, edit `asterisk/extensions.conf`:

```ini
[from-external]
; Short code 1234 → Training
exten => 1234,1,Goto(training,menu,1)

; Short code 5678 → Sales
exten => 5678,1,Goto(from-internal,*100,1)

; Short code 9999 → Dograh AI
exten => 9999,1,Stasis(dograh)
```

## Additional Notes

- **Firewall**: Ensure port 5060 (UDP) and 10000-10019 (UDP) are open to Africa's Talking IP ranges
- **Audio Codec**: Africa's Talking uses PCMU (G.711 μ-law) — already configured
- **IP Ranges**: Matched via `identify` section — no SIP registration required
- **NAT**: `direct_media=no` ensures RTP flows through Asterisk
