# SOURCE DISCOVERY GUIDE — DEKA BACKGROUND ENGINE

## 1. Overview
The Background Engine has transitioned from a hardcoded single-domain prototype into a **Universal Source Discovery and Source Adapter System**.
The application does not depend on hardcoded targets, fake game data, or mock chat streams. Operators can bring **any web live stream, game, or interactive source** into the system.

```
                 ┌─────────────────────┐
                 │   SOURCE DISCOVERY  │
                 └──────────┬──────────┘
                            │
              URL / Browser / Existing App
                            │
                            ▼
                 ┌─────────────────────┐
                 │   AUTO INSPECTOR    │
                 │                     │
                 │ DOM                 │
                 │ iframe              │
                 │ video               │
                 │ canvas/WebGL        │
                 │ WebSocket           │
                 │ SSE                 │
                 │ API                 │
                 │ Network             │
                 └──────────┬──────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │ SOURCE CLASSIFIER   │
                 └──────────┬──────────┘
                            │
           ┌────────────────┼────────────────┐
           ▼                ▼                ▼
       VIDEO SOURCE     DATA SOURCE      UI SOURCE
           │                │                │
           ▼                ▼                ▼
      Browser View      API/WS Adapter    DOM Adapter
           │                │                │
           └────────────────┼────────────────┘
                            ▼
                 ┌─────────────────────┐
                 │ SOURCE PREVIEW     │
                 │ + HEALTH CHECK     │
                 └──────────┬──────────┘
                            ▼
                 ┌─────────────────────┐
                 │ ADD TO BACK ENGINE  │
                 └──────────┬──────────┘
                            ▼
                 ┌─────────────────────┐
                 │ SCENE / LAYER       │
                 │ POSITION / SCALE    │
                 │ Z-INDEX / OPACITY   │
                 └──────────┬──────────┘
                            ▼
                    PROGRAM OUTPUT
                         1080p60 NDI
```

---

## 2. 4-Step Operator Workflow

### Step 01 — FIND SOURCE
Operators can discover sources through two primary paths:
1. **Direct URL Input**: Paste any live stream or interactive URL and click `SCAN WEBSITE`.
2. **Existing Browser Detection**: Detect an active authenticated session (`persist:operator_browser_session`). Cookies and session tokens are preserved securely without exposing passwords or tokens in the UI.

### Step 02 — ANALYZE
The **SourceInspector** boots an isolated offscreen inspection context and probes the document:
- Detects `<video>` elements and video stream properties.
- Detects `<canvas>` and WebGL 2D/3D render contexts.
- Intercepts WebSocket handshakes and data traffic patterns.
- Classifies candidate purposes:
  - `GAME_VIDEO`: WebGL/Canvas or video renderers.
  - `GAME_STATE`: WebSockets carrying round IDs, countdowns, and results.
  - `CHAT`: WebSockets or DOM containers streaming user messages.
  - `IGNORED`: Analytics (Google Analytics, Mixpanel), ads, tracking, payment iframes.
- Recommends integration strategies:
  - `KEEP_BROWSER`: For complex WebGL/Canvas games relying on browser runtime.
  - `EXTRACT_DATA`: For structured WebSocket/SSE endpoints.
  - `IGNORE`: For non-broadcast elements.

### Step 03 — SOURCE PREVIEW
Before adding any source to the live production output:
- Real connection verification (`ONLINE`, `DEGRADED`, `OFFLINE`).
- Telemetry monitoring:
  - **Latency**: Real roundtrip ping time in ms.
  - **FPS**: Rendered frame rate (e.g. 59.8 - 60.0 FPS).
  - **Authentication**: Validation of active cookies/tokens.
  - **Heartbeat**: Last update timestamp.
- **Zero-Mock Rule**: If no source is connected, the UI displays `NO SOURCE CONNECTED`. It never renders simulated game rounds or dummy chat.

### Step 04 — ADD TO BACK ENGINE
Operators bind the verified adapter to a Background Engine Scene Layer:
- `Layer 01`: Game Live (Main video/browser capture)
- `Layer 02`: Chat Stream (Normalized live comments)
- `Layer 03`: Customer Notice (Marquee / Safety Ticker)
- `Layer 04`: Brand Logo
The source adapter is saved into `config.json` and automatically restored across app restarts.
