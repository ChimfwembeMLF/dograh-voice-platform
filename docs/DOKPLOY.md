# Dokploy deployment — READ THIS FIRST

## The error you are seeing

```
Starting nixpacks build...
Nixpacks was unable to generate a build plan for this app.
```

**Cause:** Dokploy service type is **Application** (uses Nixpacks).  
**Fix:** Use **Compose** (uses `docker compose up`).

This cannot be fixed in Git — you must change the service type in Dokploy.

---

## Step-by-step fix

### 1. Stop using the failed Application

In Dokploy, find **`voiceplatform-uximrt`** (or any service whose deploy log shows `nixpacks`).

- **Delete it**, or stop clicking Deploy on it.

Applications live under `/etc/dokploy/applications/...` — wrong for this repo.

### 2. Use your existing Dograh Compose stack (recommended)

You already run Dograh as **`voiceagentplatform-ivr-hj26ln`**.

1. Dokploy → **Projects** → open that service
2. Confirm the badge says **Compose** (not Application)
3. **General** tab:
   - Provider: GitHub
   - Repository: `ChimfwembeMLF/dograh-voice-platform`
   - Branch: `main`
   - **Compose path:** `docker-compose.yml`
4. **Environment** tab: paste `dograh.env.example` (replace placeholders with real secrets)
5. Click **Deploy**

### 3. Or create a new Compose service

If you cannot find the existing stack:

1. Dokploy → your project → **Add Service**
2. Choose **Compose** → type **Docker Compose**
3. Connect GitHub repo + branch
4. **Compose path:** `docker-compose.yml`
5. Paste environment variables
6. **Deploy**

---

## How to verify you picked the right type

| | Wrong (Application) | Correct (Compose) |
|---|---------------------|-------------------|
| Deploy log starts with | `Starting nixpacks build...` | `docker compose ... up` |
| Server path | `/etc/dokploy/applications/...` | `/etc/dokploy/compose/...` |
| Builds | One Nixpacks image | All services in compose file |

---

## Environment variables

Dokploy writes the Environment tab to a `.env` file next to the compose file.  
This compose file uses `${VAR_NAME}` — Docker Compose reads `.env` automatically.

Do **not** commit `dograh.env` with secrets. Use `dograh.env.example` as the template.

---

## After successful deploy

SSH to the server:

```bash
docker ps | grep -E 'whisper|piper|api'
docker exec $(docker ps -qf name=voiceagentplatform-ivr-hj26ln-api) curl -sf http://whisper:9000/v1/models
docker exec $(docker ps -qf name=voiceagentplatform-ivr-hj26ln-api) curl -sf http://piper:5000/health
curl -sf https://voice.tekreminnovations.com/api/v1/health
```

---

## Fallback: Raw Compose (no Git Application)

If Git keeps creating an Application by mistake:

1. Create **Compose** service
2. Provider: **Raw**
3. Paste contents of `docker-compose.yml`
4. Add environment variables in the Environment tab
5. Deploy

See also [TRAEFIK.md](./TRAEFIK.md) (bootstrap `/etc/dokploy/traefik/` on the server).

See also [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md).
