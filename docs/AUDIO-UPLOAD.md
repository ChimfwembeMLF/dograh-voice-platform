# Uploading Training Audio

## Directory Structure

```
/var/lib/asterisk/sounds/en/training/
├── english/
│   ├── module1.wav    # English Module 1
│   ├── module2.wav    # English Module 2
│   └── ...
├── bemba/
│   ├── module1.wav    # Bemba Module 1
│   └── ...
├── nyanja/
│   ├── module1.wav    # Nyanja Module 1
│   └── ...
└── swahili/
    ├── module1.wav    # Swahili Module 1
    └── ...
```

## Audio Format Requirements

| Parameter | Value |
|-----------|-------|
| Format | WAV (Microsoft) |
| Channels | Mono |
| Sample Rate | 8000 Hz |
| Bit Depth | 16-bit PCM |
| Codec | PCMU (μ-law) or signed 16-bit PCM |

## Convert Audio to Correct Format

### Using ffmpeg

```bash
ffmpeg -i input.mp3 -ar 8000 -ac 1 -sample_fmt s16 output.wav
```

### Using Python

```python
import wave, struct

# Read any WAV
with wave.open("input.wav", "rb") as win:
    params = win.getparams()
    raw = win.readframes(params.nframes)

# Write 8kHz mono 16-bit
with wave.open("output.wav", "wb") as wout:
    wout.setnchannels(1)
    wout.setsampwidth(2)
    wout.setframerate(8000)
    wout.writeframes(raw)
```

## Upload Audio Files

```bash
# Copy to Asterisk container
docker cp module1.wav voiceagentplatform-ivr-b5lhvg-asterisk-1:/var/lib/asterisk/sounds/en/training/english/module1.wav
docker cp module1.wav voiceagentplatform-ivr-b5lhvg-asterisk-1:/var/lib/asterisk/sounds/en/training/bemba/module1.wav

# Verify
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 ls -la /var/lib/asterisk/sounds/en/training/english/
```

## Adding More Modules

1. Upload audio file to the correct language directory
2. Add a dialplan entry for the new module:

```bash
docker exec voiceagentplatform-ivr-b5lhvg-asterisk-1 asterisk -rx '
dialplan add extension 12,1,Playback,training/english/module2 into training
same => n,Goto(1,modules)
'
```

Or add permanently to `asterisk/extensions.conf`:

```ini
[training]
; English Module 2
exten => 12,1,Playback(training/english/module2)
 same => n,Goto(1,modules)
```

## Testing

Dial `*200` from a SIP phone, select language, then press the module number.

```bash
# Watch audio playback
docker logs -f voiceagentplatform-ivr-b5lhvg-asterisk-1 | grep -i 'playing\|training'
```
