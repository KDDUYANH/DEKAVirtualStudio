# DEKA BACKGROUND ENGINE — ARCHITECTURE SPECIFICATION

## 1. System Overview

Background Engine is a high-performance Windows broadcast graphics and layer composition engine engineered specifically for 24/7 live production environments targeting **vMix** (via native NDI) and **OBS Studio** (via DistroAV / obs-ndi).

```
                            [ OPERATOR WORKSPACE ]
                                PREVIEW WINDOW
                     ┌────────────────────────────────────┐
                     │ • Authentication (Isolated Profile)│
                     │ • Target Selection & Health Cards  │
                     │ • Three Positions (P1 / P2 / P3)   │
                     │ • Auto Move Timeline Sequencer     │
                     │ • NDI Output Controller & Widget   │
                     │ • Diagnostics & Telemetry          │
                     └─────────────────┬──────────────────┘
                                       │
                                       │ Verified Commands & Telemetry Only
                                       ▼
                            [ PRODUCTION OUTPUT ]
                          1920x1080 60FPS COMPOSITOR
                     ┌────────────────────────────────────┐
                     │       FAIL-CLOSED SAFETY GATE      │
                     │  SAFE | READY | DEGRADED | AUTH    │
                     ├────────────────────────────────────┤
                     │ L1: Luxury Ambient Background Waves│
                     │ L2: Brand Logo Header              │
                     │ L3: Safety Warning Marquee Ticker  │
                     │ L4: Verified Game (or Fallback)    │
                     │ L5: Verified Chat (or Fallback)    │
                     │ L6: Speed Nạp / Payment Badges     │
                     │ L7: 24/7 Studio Live Clock         │
                     └─────────────────┬──────────────────┘
                                       │
                                       │ Raw Uncompressed BGRA Frames (60 FPS)
                                       │ (Zero-Copy Named Pipe / Shared Memory)
                                       ▼
                            [ NDI TRANSMITTER ]
                         NDI HIGH BANDWIDTH BRIDGE
                     ┌────────────────────────────────────┐
                     │ Stream: BackgroundEngine-PGM       │
                     │ 1920x1080 @ 60.00 FPS              │
                     │ Zero CPU H.264 Intermediate Encode │
                     └─────────┬────────────────┬─────────┘
                               │                │
                               ▼                ▼
                              vMix             OBS
                          (Native NDI)      (DistroAV)
```

---

## 2. Core Architectural Separation: PREVIEW != PROGRAM

The fundamental principle of this engine is strict physical and logical isolation between:
1. **PREVIEW (Operator Control Workspace)**:
   - Dedicated desktop window with native-look, lightweight UI.
   - Authentication happens exclusively in an isolated modal partition (`persist:sunwin_auth`).
   - Browser chrome, login forms, CAPTCHA, navigation bars, error pages, and diagnostic statistics are confined here.
   - **Never enters the production stream under any circumstance.**

2. **PROGRAM (Production Output Compositor)**:
   - Dedicated, hardware-accelerated 1920×1080 60 FPS compositor.
   - Strictly compositor-approved layers only.
   - If authentication expires or becomes invalid: Dynamic layers (Game and Chat) are immediately hidden, falling back to safe static graphics.
   - Receives uncompressed BGRA frame capture and delivers directly to NDI.

---

## 3. NDI High Bandwidth Pipeline

- **Stream Name**: `BackgroundEngine-PGM`
- **Video Standard**: 1080p60 (1920×1080 @ 60.00 FPS progressive, FourCC BGRA)
- **Zero Intermediate Compression**: Does **not** perform CPU H.264/VP8 encoding or decoding across local memory. Frames flow over high-speed Windows Named Pipe / Shared Memory directly into the official NewTek/NDI SDK C API (`NDIlib_send_send_video_v2`).
- **Receiver Tolerance**: If vMix or OBS reconnects, drops, or restarts, the Background Engine compositor and web sources continue running without interruption.

---

## 4. Fail-Closed Safety Gate State Machine

The safety gate continuously verifies inputs and enforces one of four authoritative states:

| State | Condition | Dynamic Layers in Program | Program Output Appearance |
| :--- | :--- | :---: | :--- |
| **`PROGRAM_SAFE`** | Boot default or authenticated with sources pending | **HIDDEN** | Safe luxury background, logo, warning ticker, payment badges, studio clock. |
| **`PROGRAM_READY`** | Auth valid + Game verified + Chat verified | **VISIBLE** | Full 1920x1080 production composition with live game video and chat. |
| **`PROGRAM_DEGRADED`** | One source lost/reconnecting, other healthy | **PARTIAL** | Healthy source renders normally; failed source displays safe reconnecting card. |
| **`PROGRAM_AUTH_REQUIRED`** | Session expired, logged out, or unauthenticated | **HIDDEN** | Only safe static graphics. Dynamic layers are immediately stripped. |

---

## 5. Three Positions & Auto Move

- **Three Dedicated Presets**:
  - **POSITION 1**: Split Source (1280x720) & Live Chat (510x910) (Duration: 30s).
  - **POSITION 2**: Security Warning Focus (1100x620) & Compact Chat (Duration: 20s).
  - **POSITION 3**: Full Action Showcase (1360x765) & Speed Nạp Focus (Duration: 30s).
- **Zero-Reload Switching**: Switching positions interpolates CSS/GPU transforms (`left`, `top`, `width`, `height`, `scale`). It **never** reloads the game, never reloads chat, never restarts WebView, and never resets output.
- **Auto Move Sequencer**: Automatic progression `P1 → P2 → P3 → P1` with customizable durations, start/pause/stop/next/previous controls, and loop toggling.

---

## 6. Directory Isolation

All persistent data resides strictly in `%LOCALAPPDATA%\BackgroundEngine\`:
- `config/`: Application settings and atomic JSON configurations.
- `layouts/`: Saved `P1.json`, `P2.json`, `P3.json` presets.
- `browser profile/`: Persistent Chromium user profile partition for authentic Sunwin login.
- `backups/`: Last-known-good configuration snapshots (`.bak`).
- `logs/`: Diagnostic and recovery execution logs.
