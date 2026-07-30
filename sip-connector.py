#!/usr/bin/env python3
"""Voice AI SIP connector — bridges telephony audio to Whisper, Ollama, and Piper."""

from __future__ import annotations

import asyncio
import contextlib
import hashlib
import logging
import os
import random
import re
import socket
from contextlib import asynccontextmanager
from typing import Any

import httpx
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse, Response

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s [sip-connector] %(message)s",
)
log = logging.getLogger("sip-connector")

OLLAMA_URL = os.getenv("OLLAMA_URL", "https://ai.tekreminnovations.com/api/generate")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2")
WHISPER_URL = os.getenv("WHISPER_URL", "http://whisper:9000").rstrip("/")
PIPER_URL = os.getenv("PIPER_URL", "http://piper:5000").rstrip("/")
SIP_HOST = os.getenv("SIP_HOST", "")
SIP_PORT = int(os.getenv("SIP_PORT", "5060"))
SIP_EXTENSION = os.getenv("SIP_EXTENSION", "9000")
SIP_SECRET = os.getenv("SIP_SECRET", "")
SIP_LOCAL_IP = os.getenv("SIP_LOCAL_IP", "")
SIP_REGISTER_INTERVAL = int(os.getenv("SIP_REGISTER_INTERVAL", "300"))
SYSTEM_PROMPT = os.getenv(
    "SYSTEM_PROMPT",
    "You are a helpful voice assistant on a phone call. Keep replies concise and conversational.",
)
HTTP_TIMEOUT = float(os.getenv("HTTP_TIMEOUT", "120"))


def _local_ip() -> str:
    if SIP_LOCAL_IP:
        return SIP_LOCAL_IP
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect((SIP_HOST or "8.8.8.8", 80))
            return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def _md5_hex(value: str) -> str:
    return hashlib.md5(value.encode()).hexdigest()


def _digest_response(username: str, realm: str, password: str, nonce: str, method: str, uri: str) -> str:
    ha1 = _md5_hex(f"{username}:{realm}:{password}")
    ha2 = _md5_hex(f"{method}:{uri}")
    return _md5_hex(f"{ha1}:{nonce}:{ha2}")


def _parse_digest_params(header: str) -> dict[str, str]:
    params: dict[str, str] = {}
    for match in re.finditer(r'(\w+)=(?:"([^"]*)"|([^\s,]+))', header):
        params[match.group(1)] = match.group(2) or match.group(3)
    return params


def _build_register(
    local_ip: str,
    call_id: str,
    tag: str,
    branch: str,
    cseq: int,
    authorization: str | None = None,
) -> bytes:
    contact = f"sip:{SIP_EXTENSION}@{local_ip}:5060"
    uri = f"sip:{SIP_HOST}:{SIP_PORT}"
    headers = [
        f"REGISTER {uri} SIP/2.0",
        f"Via: SIP/2.0/UDP {local_ip}:5060;branch={branch};rport",
        "Max-Forwards: 70",
        f"From: <sip:{SIP_EXTENSION}@{SIP_HOST}>;tag={tag}",
        f"To: <sip:{SIP_EXTENSION}@{SIP_HOST}>",
        f"Call-ID: {call_id}",
        f"CSeq: {cseq} REGISTER",
        f"Contact: <{contact}>",
        "Expires: 3600",
        "User-Agent: voice-sip-connector/1.0",
    ]
    if authorization:
        headers.append(f"Authorization: {authorization}")
    headers.extend(["Content-Length: 0", "", ""])
    return "\r\n".join(headers).encode()


def _authorization_from_challenge(challenge: str, uri: str) -> str | None:
    params = _parse_digest_params(challenge)
    realm = params.get("realm")
    nonce = params.get("nonce")
    if not realm or not nonce:
        return None
    response = _digest_response(SIP_EXTENSION, realm, SIP_SECRET, nonce, "REGISTER", uri)
    return (
        f'Digest username="{SIP_EXTENSION}", realm="{realm}", nonce="{nonce}", '
        f'uri="{uri}", response="{response}", algorithm=MD5'
    )


async def _recv_sip_response(sock: socket.socket, timeout: float = 3.0) -> str:
    loop = asyncio.get_event_loop()
    try:
        data, _addr = await asyncio.wait_for(loop.sock_recvfrom(sock, 65535), timeout=timeout)
        return data.decode("utf-8", errors="replace")
    except (asyncio.TimeoutError, OSError):
        return ""


async def sip_register_loop() -> None:
    if not SIP_HOST or not SIP_SECRET:
        log.info("SIP registration disabled (set SIP_HOST and SIP_SECRET to enable)")
        return

    local_ip = _local_ip()
    call_id = f"{random.randint(1, 999999)}@{local_ip}"
    tag = f"{random.randint(1, 999999)}"
    cseq = 1
    uri = f"sip:{SIP_HOST}:{SIP_PORT}"
    log.info("Starting SIP registration to %s:%s as extension %s", SIP_HOST, SIP_PORT, SIP_EXTENSION)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((local_ip, 0))
    sock.setblocking(False)

    while True:
        branch = f"z9hG4bK{random.randint(1, 999999999)}"
        payload = _build_register(local_ip, call_id, tag, branch, cseq)
        try:
            await asyncio.get_event_loop().sock_sendto(sock, payload, (SIP_HOST, SIP_PORT))
            response = await _recv_sip_response(sock)
            if "401" in response or "407" in response:
                auth_line = next(
                    (line.split(":", 1)[1].strip() for line in response.splitlines() if "WWW-Authenticate" in line or "Proxy-Authenticate" in line),
                    "",
                )
                authorization = _authorization_from_challenge(auth_line, uri)
                if authorization:
                    cseq += 1
                    branch = f"z9hG4bK{random.randint(1, 999999999)}"
                    payload = _build_register(local_ip, call_id, tag, branch, cseq, authorization)
                    await asyncio.get_event_loop().sock_sendto(sock, payload, (SIP_HOST, SIP_PORT))
                    response = await _recv_sip_response(sock)
            if response.startswith("SIP/2.0 200"):
                log.info("SIP registration successful")
            elif response:
                first_line = response.splitlines()[0]
                log.debug("SIP response: %s", first_line)
            else:
                log.debug("No SIP response received for REGISTER")
        except OSError as exc:
            log.warning("SIP REGISTER failed: %s", exc)
        cseq += 1
        await asyncio.sleep(SIP_REGISTER_INTERVAL)


async def transcribe_audio(client: httpx.AsyncClient, audio: bytes, filename: str) -> str:
    response = await client.post(
        f"{WHISPER_URL}/v1/audio/transcriptions",
        files={"file": (filename, audio, "audio/wav")},
        data={"model": "whisper-1"},
    )
    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"Whisper transcription failed: {response.status_code} {response.text}",
        )
    payload = response.json()
    text = payload.get("text", "").strip()
    if not text:
        raise HTTPException(status_code=422, detail="Whisper returned empty transcription")
    return text


async def generate_reply(client: httpx.AsyncClient, user_text: str) -> str:
    prompt = f"{SYSTEM_PROMPT}\n\nUser: {user_text}\nAssistant:"
    response = await client.post(
        OLLAMA_URL,
        json={
            "model": OLLAMA_MODEL,
            "prompt": prompt,
            "stream": False,
        },
    )
    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"Ollama generation failed: {response.status_code} {response.text}",
        )
    payload = response.json()
    reply = (payload.get("response") or payload.get("message", {}).get("content") or "").strip()
    if not reply:
        raise HTTPException(status_code=502, detail="Ollama returned empty response")
    return reply


async def synthesize_speech(client: httpx.AsyncClient, text: str) -> bytes:
    response = await client.post(
        f"{PIPER_URL}/api/tts",
        json={"text": text},
    )
    if response.status_code == 200 and response.content:
        content_type = response.headers.get("content-type", "")
        if "audio" in content_type or response.content[:4] == b"RIFF":
            return response.content

    # Fallback for OpenAI-style TTS endpoints.
    response = await client.post(
        f"{PIPER_URL}/v1/audio/speech",
        json={"input": text, "voice": "default"},
    )
    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"Piper synthesis failed: {response.status_code} {response.text}",
        )
    return response.content


async def check_dependency(client: httpx.AsyncClient, name: str, url: str) -> dict[str, Any]:
    try:
        response = await client.get(url, follow_redirects=True)
        return {"name": name, "url": url, "ok": response.status_code < 500, "status": response.status_code}
    except httpx.HTTPError as exc:
        return {"name": name, "url": url, "ok": False, "error": str(exc)}


@asynccontextmanager
async def lifespan(app: FastAPI):
    sip_task: asyncio.Task | None = None
    if SIP_HOST and SIP_SECRET:
        sip_task = asyncio.create_task(sip_register_loop())
    yield
    if sip_task:
        sip_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await sip_task


app = FastAPI(title="Voice SIP Connector", version="1.0.0", lifespan=lifespan)


@app.get("/health")
async def health() -> JSONResponse:
    async with httpx.AsyncClient(timeout=10) as client:
        checks = await asyncio.gather(
            check_dependency(client, "whisper", f"{WHISPER_URL}/v1/models"),
            check_dependency(client, "piper", f"{PIPER_URL}/health"),
        )
    healthy = all(item.get("ok") for item in checks)
    return JSONResponse(
        status_code=200 if healthy else 503,
        content={
            "status": "healthy" if healthy else "degraded",
            "services": checks,
            "sip": {
                "enabled": bool(SIP_HOST and SIP_SECRET),
                "host": SIP_HOST or None,
                "extension": SIP_EXTENSION,
            },
        },
    )


@app.post("/process_audio")
async def process_audio(audio: UploadFile = File(...)) -> Response:
    raw = await audio.read()
    if not raw:
        raise HTTPException(status_code=400, detail="Empty audio upload")

    filename = audio.filename or "audio.wav"
    async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
        transcript = await transcribe_audio(client, raw, filename)
        log.info("Transcript: %s", transcript)
        reply = await generate_reply(client, transcript)
        log.info("Reply: %s", reply)
        speech = await synthesize_speech(client, reply)

    headers = {
        "X-Transcript": transcript.encode("ascii", "ignore").decode(),
        "X-Reply": reply.encode("ascii", "ignore").decode(),
    }
    return Response(content=speech, media_type="audio/wav", headers=headers)


@app.get("/")
async def root() -> dict[str, str]:
    return {"service": "voice-sip-connector", "health": "/health", "process_audio": "/process_audio"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8080")),
        log_level=os.getenv("LOG_LEVEL", "info").lower(),
    )
