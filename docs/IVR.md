# IVR Setup

## Overview

The voice IVR at `*100` uses **Piper TTS** to generate spoken prompts in WAV format.

## Dialplan

```
*100 → Answer
     → Wait(1)
     → Background(ivr/ivr-welcome)     # "Welcome to Tekrem Innovations..."
     → WaitExten(10)                    # Wait 10s for DTMF
     → Playback(ivr/ivr-goodbye)       # "Thank you for calling..."
     → Hangup

1    → Playback(ivr/ivr-sales)         # "Connecting you to sales..."
     → Dial(PJSIP/9000,30)
     → Hangup

2    → Playback(ivr/ivr-support)        # "Connecting you to support..."
     → Dial(PJSIP/9001,30)
     → Hangup

0    → Playback(ivr/ivr-operator)       # "Connecting you to an operator..."
     → Dial(PJSIP/9000,30)
     → Hangup

i    → Playback(ivr/ivr-invalid)        # "Invalid option..."
     → Goto(*100,3)                     # Replay menu
```

## Audio Files

Generated via Piper TTS HTTP API, stored in Asterisk sounds directory:

```
/var/lib/asterisk/sounds/en/ivr/
├── ivr-welcome.wav     "Welcome to Tekrem Innovations. Press 1 for sales..."
├── ivr-sales.wav       "Connecting you to sales. Please hold."
├── ivr-support.wav     "Connecting you to support. Please hold."
├── ivr-operator.wav    "Connecting you to an operator. Please hold."
├── ivr-goodbye.wav     "Thank you for calling. Goodbye."
└── ivr-invalid.wav     "Invalid option. Please try again."
```

## Generating Audio Files

Run from within the Asterisk container:

```python
import subprocess, wave, struct, os, json

prompts = {
    "ivr-welcome": "Welcome to Tekrem Innovations. Press 1 for sales...",
    "ivr-sales": "Connecting you to sales...",
    # ... more prompts
}

for name, text in prompts.items():
    payload = json.dumps({"model": "en_US-lessac-medium", "text": text})
    subprocess.run([
        "curl", "-s", "-X", "POST",
        "http://piper:5000/v1/audio/speech",
        "-H", "Content-Type: application/json",
        "-d", payload, "-o", "/tmp/raw.pcm"
    ])
    
    with open("/tmp/raw.pcm", "rb") as f:
        raw = f.read()
    
    samples = struct.unpack(f"<{len(raw)//2}h", raw)
    downsampled = [samples[i] for i in range(0, len(samples), 3)]
    
    with wave.open(f"/var/lib/asterisk/sounds/en/ivr/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(8000)
        w.writeframes(struct.pack(f"<{len(downsampled)}h", *downsampled))
```

### Audio Format

- **Source**: Piper TTS returns raw 16-bit PCM at 22050Hz
- **Target**: 8kHz mono 16-bit WAV (Asterisk format)
- **Downsampling**: Every 3rd sample (22050 ÷ 3 ≈ 7350Hz)

## Adding Custom Prompts

1. Add entry to the `prompts` dict in the generation script
2. Run the script
3. Add dialplan entry using `Background()` or `Playback()`

## Adding Dialplan Entries

```bash
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx \
  'dialplan add extension *100,3,Background,ivr/ivr-welcome into from-internal'
```

> **Note:** Dynamic dialplan entries are lost on Asterisk restart. Add them permanently to `asterisk/extensions.conf` for persistence.
