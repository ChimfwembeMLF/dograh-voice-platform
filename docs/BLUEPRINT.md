# MicroLoan Foundation Zambia — Unified Communications Platform

## Project Blueprint / Requirements Document

**Version:** 1.0
**Status:** Blueprint — for new implementation
**Reference Implementation:** `dograh-voice-platform` (Tekrem server)

---

## 1. Overview

A self-hosted, open-source communications platform for MicroLoan Foundation Zambia providing:

- Voice IVR (loan info, repayments, training)
- SMS messaging (reminders, OTPs, two-way)
- Digital training modules (multi-language audio)
- AI-powered customer support
- Unified admin dashboard

All components are open-source and can run on a single VPS without external API dependencies except the LLM provider.

---

## 2. System Architecture

```
                    ┌──────────────────────────────┐
                    │      Africa's Talking /       │
                    │      MTN / Airtel             │
                    │   (Voice shortcodes + SMS)    │
                    └──────────┬───────────────────┘
                               │
                    ┌──────────▼───────────────────┐
                    │       Traefik / Nginx         │
                    │      (TLS termination)        │
                    └──────────┬───────────────────┘
                               │
            ┌──────────────────┼──────────────────┐
            ▼                  ▼                  ▼
   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
   │  Asterisk   │    │  Hermes     │    │  Dashboard  │
   │    PBX      │    │   Agent     │    │   (Web UI)  │
   │   :5060     │    │   :8644     │    │   :3000     │
   └──────┬──────┘    └──────┬──────┘    └─────────────┘
          │                  │
   ┌──────┴──────┐    ┌──────┴──────┐
   ▼             ▼    ▼             ▼
┌───────┐  ┌────────┐ ┌────────┐ ┌──────────┐
│Piper  │  │Whisper │ │DeepSeek│ │ Android  │
│ TTS   │  │  STT   │ │  AI    │ │SMS GW    │
│:5000  │  │ local  │ │ (API)  │ │  :5000   │
└───────┘  └────────┘ └────────┘ └──────────┘
```

### Networks
| Network | Purpose | Services |
|---------|---------|----------|
| `voice-net` | Voice/media traffic | Asterisk, Piper, Whisper, AI Bridge |
| `app-net` | Internal services | Hermes, Dashboard, PostgreSQL |
| `public` | External access | Traefik/Nginx, SIP (UDP 5060) |

---

## 3. Component Requirements

### 3.1 Asterisk PBX

**Purpose:** Call handling, IVR, SIP routing

| Requirement | Detail |
|-------------|--------|
| SIP Endpoints | Dynamic creation per customer/group |
| IVR Menus | Multi-language, configurable without restart |
| Audio Playback | WAV files (8kHz mono 16-bit PCM) |
| DTMF Handling | RFC 4733 telephone-event |
| NAT Traversal | rtp_symmetric, direct_media=no, rewrite_contact |
| RTP Ports | Configurable range, matched to Docker |
| Recording | Optional call recording to WAV |
| CDR | Call detail records to database |
| SIP Trunks | IP-based auth for carriers (AT, MTN, Airtel) |

**IVR Flows:**

```
Main (*100):
  Welcome → Press 1 for Loans → Sub-menu → Agent
           Press 2 for Repayments → Sub-menu → Balance readout
           Press 0 for Operator → Ring extension

Training (*200):
  Language select (EN/BEM/NYA/SWA)
  → Module select → Play audio
  → Track completion → Mark in DB

Agent Queue (*300):
  Hold music → Ring available agent → Voicemail on timeout
```

**Extensions:**
| Ext | Username | Password | Purpose |
|-----|----------|----------|---------|
| 100 | mlf-agent-01 | (auto-generated) | Agent desk |
| 200-299 | mlf-trainee-* | (PIN-based) | Training access |
| 8000 | ai-bridge | - | AI agent bridge |

### 3.2 TTS Engine (Piper)

**Purpose:** Generate spoken prompts in English

| Requirement | Detail |
|-------------|--------|
| API | HTTP REST, OpenAI-compatible `/v1/audio/speech` |
| Voice | `en_US-lessac-medium` |
| Format | Raw 16-bit PCM → Convert to 8kHz WAV |
| Caching | Cache generated files to disk |

**Prompts Needed:**
- Language selection (English part)
- Navigation prompts ("Press 1 for...")
- Loan balance readouts
- Repayment confirmations
- Error/invalid messages

> **Note:** Bemba, Nyanja, Swahili prompts must be **pre-recorded** human audio. Provide a recording script and upload mechanism.

### 3.3 STT Engine (faster-whisper)

**Purpose:** Transcribe voice messages and calls

| Requirement | Detail |
|-------------|--------|
| Model | `base` or `small` (CPU-optimized) |
| Languages | English, Bemba, Nyanja, Swahili |
| API | Via Hermes STT integration |
| Performance | < 3s transcription for 30s audio |

### 3.4 SMS Gateway (Android)

**Purpose:** Send/receive SMS via local SIM

| Requirement | Detail |
|-------------|--------|
| App | Android SMS Gateway (Apache 2.0) |
| API | REST at `http://<phone-ip>:5000` |
| Webhook | POST incoming SMS to Hermes |
| Rate | ~1 SMS/second (carrier limit, not app limit) |
| Failover | Optional second phone for load balancing |

**SMS Templates:**
```
Training reminder:  "MicroLoan: Your Module {N} training is ready. Dial *200 now."
Loan repayment:     "MicroLoan: Your repayment of K{amount} is due on {date}. Pay now to avoid penalties."
OTP:                "MicroLoan: Your verification code is {code}. Valid for 5 minutes."
Balance inquiry:    "MicroLoan: Your loan balance is K{balance}. Next payment: {date}."
```

### 3.5 AI Agent (DeepSeek / Mistral)

**Purpose:** Handle customer conversations via voice and SMS

| Requirement | Detail |
|-------------|--------|
| Provider | DeepSeek V3 or Mistral Large |
| API | REST with OpenAI-compatible format |
| Context | Customer profile + conversation history |
| Functions | Loan lookup, repayment schedule, training status |

**System Prompt:**
```
You are a MicroLoan Foundation Zambia assistant. You help customers with:
- Loan applications and status
- Repayment schedules and amounts
- Training module enrollment and progress

Always be polite, concise, and speak simply. Use the customer's preferred language.
```

**AI-to-Asterisk Bridge:**
- Connects AI responses to Asterisk calls
- Handles TTS for AI responses
- Manages call state (hold, transfer, hangup)
- ~100 lines of Python using Asterisk ARI

### 3.6 Database (PostgreSQL)

**Purpose:** Persistent storage for all data

**Tables:**

```sql
-- Customers
customers (
    id, phone_number, name, language, group_id,
    loan_amount, loan_balance, repayment_schedule,
    created_at, updated_at
)

-- Training modules
modules (
    id, language, title, audio_file_path,
    duration_seconds, order_index
)

-- Training progress
training_progress (
    id, customer_id, module_id,
    started_at, completed_at, completion_percentage
)

-- Call records
calls (
    id, customer_id, from_number, to_extension,
    direction, duration_seconds, recording_path,
    started_at, ended_at
)

-- SMS messages
sms_messages (
    id, customer_id, from_number, to_number,
    direction, body, status,
    sent_at, delivered_at
)

-- AI conversations
conversations (
    id, customer_id, channel (voice/sms),
    messages (JSON array), resolved, created_at
)

-- IVR menu config
ivr_menus (
    id, tenant_id, extension, language,
    audio_prompt, actions (JSON), parent_id
)

-- Tenants (multi-tenancy)
tenants (
    id, name, short_code, context_name,
    active, created_at
)
```

### 3.7 Unified Dashboard (Web UI)

**Purpose:** Admin interface for everything

| Page | Shows |
|------|-------|
| **Dashboard** | Active calls, SMS stats, training completions, AI usage |
| **Calls** | Live calls, CDR history, recordings |
| **SMS** | Send SMS, inbox, templates, blast |
| **Training** | Upload audio, manage modules, view progress |
| **AI Chats** | Conversation history, search, export |
| **Settings** | Extensions, IVR config, API keys, tenants |

**Tech Stack:**
- Plain HTML / CSS / JavaScript
- No frameworks (no React, Vue, Angular)
- Bootstrap or Pico.css for styling
- Fetch API for backend calls
- Charts via Chart.js

**Authentication:**
- Simple username/password
- Session-based (cookies)
- One admin account per tenant

---

## 4. API Specifications

### 4.1 Dashboard API (Python / FastAPI on :3000)

```
GET    /api/health              → Service health
GET    /api/status              → All systems status
GET    /api/calls               → List call records
GET    /api/calls/active        → Currently active calls
GET    /api/sms                 → List SMS messages
POST   /api/sms/send            → Send SMS
GET    /api/training/modules    → List modules
POST   /api/training/upload     → Upload audio module
GET    /api/training/progress   → Trainee progress
POST   /api/ai/chat             → Send message to AI
GET    /api/ai/conversations    → List conversations
GET    /api/tenants             → List tenants (admin)
POST   /api/tenants             → Create tenant (admin)
```

### 4.2 SMS Webhook (Hermes on :8644)

```
POST   /webhooks/sms-inbound    → Incoming SMS from Android gateway
Headers: X-Hub-Signature-256    → HMAC-SHA256 for verification
Body: {
    "from": "+260977123456",
    "message": "LOAN STATUS",
    "sent_timestamp": "..."
}
```

### 4.3 Africa's Talking Callback (if using AT API directly)

```
POST   /api/voice/callback      → AT voice events
POST   /api/sms/callback        → AT SMS delivery reports
```

### 4.4 Asterisk ARI

```
POST   /ari/channels            → Originate call
POST   /ari/bridges             → Create bridge
POST   /ari/playbacks           → Play audio
GET    /ari/endpoints           → List SIP endpoints
```

---

## 5. Multi-Tenancy Design

| Tenant | Short Code | Extension Prefix | Audio Dir |
|--------|-----------|-----------------|-----------|
| `microloan` (MLF) | *200# | `2xx` | `/audio/microloan/` |
| `tenant-b` | *300# | `3xx` | `/audio/tenant-b/` |
| `tenant-c` | *400# | `4xx` | `/audio/tenant-c/` |

Each tenant has:
- Isolated Asterisk context
- Separate audio directory
- Separate DB rows (filtered by tenant_id)
- Own short code / inbound route

---

## 6. Deployment

### 6.1 Single VPS (Production)

```
OS: Ubuntu 22.04+
CPU: 4 cores
RAM: 8 GB
Disk: 40 GB SSD
Bandwidth: Unmetered
Static IP: Required
```

### 6.2 Docker Compose

```yaml
services:
  asterisk:     # PBX
  dashboard:    # Web UI + API
  hermes:       # AI agent + SMS handler
  piper:        # TTS
  postgres:     # Database
  traefik:      # Reverse proxy
```

### 6.3 Ports

| Port | Service | Public? |
|------|---------|---------|
| 5060/udp | SIP | ✅ Yes |
| 8088 | ARI | ❌ Internal |
| 10000-10019/udp | RTP | ✅ Yes |
| 3000 | Dashboard | ✅ Yes (HTTPS) |
| 8644 | Hermes webhook | ❌ Internal |
| 5000 | SMS Gateway (phone) | ❌ LAN only |

### 6.4 Environment Variables

```env
# AI
DEEPSEEK_API_KEY=sk-...
# or
MISTRAL_API_KEY=...

# Database
POSTGRES_USER=...
POSTGRES_PASSWORD=...
POSTGRES_DB=microloan

# Dashboard
DASHBOARD_USER=admin
DASHBOARD_PASSWORD=...
DASHBOARD_SECRET=...

# SMS Gateway
SMS_GATEWAY_URL=http://192.168.1.100:5000
SMS_GATEWAY_PASSWORD=...

# Asterisk
ASTERISK_ARI_USER=dashboard
ASTERISK_ARI_PASSWORD=...
```

---

## 7. Development Phases

### Phase 1: Core Voice (Week 1-2)
- [ ] Asterisk PBX with NAT working
- [ ] Piper TTS integration
- [ ] faster-whisper STT
- [ ] IVR menus (*100, *200) with audio files
- [ ] SIP extensions and inter-extension calling

### Phase 2: SMS (Week 2-3)
- [ ] Android SMS Gateway setup
- [ ] Hermes webhook for incoming SMS
- [ ] SMS templates and sending
- [ ] Two-way SMS conversation flow

### Phase 3: AI Integration (Week 3-4)
- [ ] DeepSeek/Mistral API integration
- [ ] AI-to-Asterisk bridge
- [ ] AI SMS responses
- [ ] Context-aware conversations

### Phase 4: Dashboard (Week 4-5)
- [ ] Web UI with all views
- [ ] REST API endpoints
- [ ] Authentication
- [ ] CDR and analytics

### Phase 5: Multi-Tenancy + Training (Week 5-6)
- [ ] Tenant isolation
- [ ] Training module management
- [ ] Audio uploader
- [ ] Progress tracking

### Phase 6: Production Hardening (Week 6-7)
- [ ] Load testing
- [ ] Monitoring and alerts
- [ ] Backup strategy
- [ ] Documentation

---

## 8. Cost Estimate

| Item | Monthly Cost |
|------|-------------|
| VPS (4 CPU, 8 GB RAM) | ~$40 |
| DeepSeek API (~10K calls/mo) | ~$5 |
| Africa's Talking short code | ~$20 |
| Android phone (one-time) | Free (existing) |
| Domain + DNS | ~$1 |
| **Total** | **~$66/month** |

Fully open-source, no SaaS fees, no vendor lock-in.

---

## 9. Reference Implementation

Current working components on Tekrem server (`38.242.147.192`):

| Component | Status | Location |
|-----------|--------|----------|
| Asterisk PBX | ✅ Live | Docker, port 5060 |
| Piper TTS | ✅ Live | Docker, port 5000 |
| faster-whisper | ✅ Live | Docker, port 9000 |
| Hermes Agent | ✅ Live | Gateway, port 8644 |
| IVR (*100) | ✅ Live | Asterisk dialplan |
| Training (*200) | ✅ Live | 4 languages |
| SIP Trunk (AT) | ✅ Configured | pjsip.conf |
| SMS Webhook | ✅ Configured | /webhooks/sms-inbound |
| Audio files | ✅ Generated | Piper TTS |
| Documentation | ✅ Complete | docs/*.md |
| Dashboard | 🔨 To build | Phase 4 |

Repo: `github.com/ChimfwembeMLF/dograh-voice-platform`
Branch: `docs/voice-platform`

---

## 10. Open Questions

1. **Production SMS:** Android Gateway or SMPP (Kannel) to MTN/Airtel directly?
2. **Local languages audio:** Will MicroLoan provide Bemba/Nyanja/Swahili recordings?
3. **Loan data integration:** Connect to existing MicroLoan loan management system, or standalone?
4. **USSD:** Do you need USSD menus alongside SMS, or SMS-only?
5. **Scale:** How many concurrent calls and SMS/day expected?
