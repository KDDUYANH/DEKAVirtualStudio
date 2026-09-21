# ARCHITECTURE REVIEW & GAP ANALYSIS

**Project**: Background Engine — Production Windows Broadcast Engine  
**Subject**: Architectural Review of Previous Build (`BCKGENGINE` / v0.4.0) vs Refactored Production Architecture (v1.0.0)

---

## 1. Executive Summary

An exhaustive audit of the previous codebase revealed critical architectural vulnerabilities regarding broadcast safety, resource overhead, and output reliability:
1. **Source Leakage**: Technical browser chrome, login dialogues, and error redirects were vulnerable to leaking directly onto the live production feed.
2. **Excessive Compression Overhead**: Attempting to encode 1080p60 frames via CPU/GPU H.264 WebCodecs over WebSocket caused frame drops and high CPU usage for local PC-to-PC transmission.
3. **Fragile Position Handling**: Switching between motion phases risked resetting media elements or reloading web views.

The refactored architecture completely resolves these issues through **physical separation of Preview and Program**, **uncompressed NDI High Bandwidth output**, and a **fail-closed Safety Gate**.

---

## 2. Detailed Architectural Comparison

| Feature / Domain | Previous Architecture (`BCKGENGINE` / v0.4.0) | Refactored Final Architecture (v1.0.0) | Benefit / Rationale |
| :--- | :--- | :--- | :--- |
| **Preview vs Program** | Merged into single window or shared DOM iframe | **Two completely independent application surfaces** | Absolute isolation: operator workspace cannot leak onto stream. |
| **Live Output Pipeline** | WebSocket H.264/VP8/JPEG compression to CEF browser source (`:7800/output`) | **NDI High Bandwidth (`BackgroundEngine-PGM`)** | Native ingest in vMix & OBS DistroAV. Zero CPU H.264 re-encoding. |
| **Authentication Safety** | In-page modal or iframe inside output canvas | **Isolated partition (`persist:sunwin_auth`) in Preview only** | Zero plain text password storage; login screen never enters Program. |
| **Safety Gate** | Ad-hoc error flags | **Formal 4-state fail-closed state machine** (`SAFE`, `READY`, `DEGRADED`, `AUTH`) | Program drops dynamic layers instantly if authentication fails. |
| **Three Positions** | Re-applied CSS classes with potential DOM reload | **GPU geometry interpolation via Position Engine** | Zero source reload, zero decoder restart during P1/P2/P3 switches. |
| **Auto Move** | Simple `setInterval` loop in client JS | **Dedicated AutoMoveSequencer with countdown & loop controls** | Predictable broadcast choreography with pause/next/loop controls. |
| **Recovery Strategy** | Page reload on error | **Independent exponential backoff (1s..30s, max 5 tries)** | Game recovery does not restart Chat; Chat recovery does not touch Game. |
| **Output Disconnect** | Output disconnection hung WebSocket engine | **Resilient NDI Sender with zero-impact reconnect** | Disconnecting vMix/OBS does not disrupt compositor or browser sources. |
| **Data Persistence** | Mixed in project root or unversioned JSON | **Predictable directory under `%LOCALAPPDATA%\BackgroundEngine`** | Atomic writes with `.bak` last-known-good backups. |

---

## 3. Security & Integrity Review

1. **Zero Credential Scraping**: The engine adheres strictly to standard Chromium security practices. Operators log in via the normal Sunwin portal in Preview. No passwords or tokens are stored in plaintext.
2. **Fail-Closed Protection**: In the event of network disruption or session timeout, the Safety Gate isolates dynamic layers within 1 frame (16.6ms), ensuring that live viewers only see official ambient branding and safety tickers.
3. **No Unnecessary Network Exposure**: Local IPC operates over Windows Named Pipes and localhost loopback; no external network ports are left exposed.
