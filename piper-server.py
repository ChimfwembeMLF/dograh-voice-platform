#!/usr/bin/env python3
"""Minimal HTTP wrapper around Piper TTS."""

from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

PIPER_MODEL = os.getenv("PIPER_MODEL", "en_US-lessac-medium")
PIPER_VOICE_DIR = Path(os.getenv("PIPER_VOICE_DIR", "/data"))

app = FastAPI(title="Piper HTTP", version="1.0.0")


class TTSRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


def _ensure_model() -> Path:
    PIPER_VOICE_DIR.mkdir(parents=True, exist_ok=True)
    model_path = PIPER_VOICE_DIR / f"{PIPER_MODEL}.onnx"
    if model_path.exists():
        return model_path

    try:
        from piper.download_voices import download_voice

        download_voice(PIPER_MODEL, PIPER_VOICE_DIR)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=503, detail=f"Failed to download Piper model: {exc}") from exc

    if not model_path.exists():
        raise HTTPException(status_code=503, detail=f"Piper model missing at {model_path}")
    return model_path


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "model": PIPER_MODEL}


@app.post("/api/tts")
def synthesize(request: TTSRequest) -> Response:
    model_path = _ensure_model()

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        output_path = tmp.name

    try:
        result = subprocess.run(
            [
                "piper",
                "--model",
                model_path,
                "--output_file",
                output_path,
            ],
            input=request.text.encode("utf-8"),
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise HTTPException(
                status_code=500,
                detail=result.stderr.decode("utf-8", errors="replace") or "Piper failed",
            )
        with open(output_path, "rb") as handle:
            audio = handle.read()
    finally:
        if os.path.exists(output_path):
            os.unlink(output_path)

    return Response(content=audio, media_type="audio/wav")


@app.post("/v1/audio/speech")
def synthesize_openai(request: TTSRequest) -> Response:
    return synthesize(request)
