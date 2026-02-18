# Therin iOS — Feature Spec

*Competitor analysis: aight.cool*
*Date: 2026-02-15*

## Target Features

### 1. Multi-Session Management ⭐
- Separate conversations per topic
- Star/pin important sessions  
- Search across all sessions
- Unread badges
- Session list view with last message preview

**Gateway API needed:** `sessions.list`, `sessions.history`

### 2. Security Audit ⭐
- Prompt extraction defense check
- Injection attack protection scan
- Config scanner with severity flags
- One-tap fixes
- Pre-skill-install security scan

**Gateway API needed:** Custom analysis or `health` endpoint extension

### 5. Voice Mode ⭐
- Push-to-talk button
- Hands-free continuous mode (optional)
- Real-time transcription display
- Animated orb/waveform UI
- TTS playback (ElevenLabs or system)

**iOS APIs:** `AVAudioEngine`, `SFSpeechRecognizer`, `AVSpeechSynthesizer`

### 6. Gateway Dashboard ⭐
- Version info
- Uptime
- CPU / Memory / Disk usage
- Connection status (live)
- Health indicators

**Gateway API:** `health`, `status` methods (already in protocol)

### 7. Usage/Cost Tracking ⭐
- Token breakdown by session
- Token breakdown by model
- Rate-limit status
- Context window usage
- Cost estimates (per model pricing)

**Gateway API:** `usage.status`, `usage.cost` methods

---

## Explicitly NOT Building (v1)

- ❌ Skills browser/marketplace (foam for mobile)
- ❌ Moltbook / social features
- ❌ AWS relay (Tailscale-first)

---

## Architecture

```
┌─────────────────────────────────────────┐
│            Therin iOS App               │
├─────────────────────────────────────────┤
│  Sessions │ Chat │ Voice │ Dashboard    │
├─────────────────────────────────────────┤
│         GatewayClient (WebSocket)       │
├─────────────────────────────────────────┤
│              Tailscale                  │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│           OpenClaw Gateway              │
│  (wss://openclaw.your-tailnet.ts.net)   │
└─────────────────────────────────────────┘
```

---

## UI Tabs (proposed)

1. **Sessions** — List of conversations, tap to open
2. **Chat** — Current conversation (your existing ChatView)
3. **Voice** — Push-to-talk / hands-free mode
4. **Status** — Gateway health + usage dashboard

---

## Differentiators vs Aight

| Us | Them |
|----|------|
| Native Swift | React Native (Expo) |
| Open source (potentially) | Closed |
| Tailscale-first, simple | Multiple connection methods |
| Focused feature set | Feature bloat |
| You control it | They control TestFlight |

---

## Current Scaffold Status

- [x] Basic chat UI
- [x] WebSocket + protocol
- [x] Gateway connect/auth
- [x] Message streaming
- [x] Settings view
- [x] Multi-session (sessions list, switching, star/pin, search, unread badges, rename, delete)
- [x] Voice input (push-to-talk, continuous mode, live transcription, animated orb, TTS playback)
- [x] Gateway dashboard (live-updating, CPU/memory/disk gauges, auto-refresh)
- [x] Usage tracking (token breakdown, cost estimates, per-model breakdown, rate-limit, context window)
- [x] Security audit (config scanner, severity flags, prompt defense checks, score card)
