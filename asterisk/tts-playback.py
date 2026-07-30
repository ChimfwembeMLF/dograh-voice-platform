#!/usr/bin/env python3
"""AGI script: takes text, calls Piper TTS, plays resulting audio."""
import sys, os, subprocess, tempfile

def agi_cmd(cmd):
    sys.stdout.write(cmd + "\n")
    sys.stdout.flush()
    return sys.stdin.readline().strip()

text = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "No message provided."
agi_cmd("VERBOSE \"TTS: generating speech for: {}\" 1".format(text[:80]))

# Call Piper TTS
tmpfile = "/tmp/tts_msg.wav"
try:
    subprocess.run([
        "curl", "-s", "-X", "POST",
        "http://piper:5000/v1/audio/speech",
        "-H", "Content-Type: application/json",
        "-d", model:en_US-lessac-medium,
        "-o", tmpfile
    ], timeout=15, check=True)
    # Stream the file
    result = agi_cmd("STREAM FILE {} \"\"".format(tmpfile.replace(".wav","")))
except Exception as e:
    agi_cmd("VERBOSE \"TTS failed: {}\" 1".format(str(e)))
    agi_cmd("STREAM FILE invalid \"\"")
