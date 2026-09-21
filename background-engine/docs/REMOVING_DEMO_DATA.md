# REMOVING DEMO DATA AUDIT REPORT — ZERO-MOCK COMPLIANCE

## 1. Compliance Executive Summary
The Background Engine runtime has been completely audited and purged of all mock, demo, fake, and hardcoded simulation code. The system runs on a **Strict Zero-Mock Architecture**.

| Audit Area | Previous Prototype State | Current Production State |
|---|---|---|
| **Game State** | Hardcoded rounds, simulated countdown timers, fake dice results | Normalized WebSocket/REST stream with `NO_SOURCE` default; returns `null` when offline |
| **Chat Stream** | Hardcoded `demoMessages` array, periodic fake bot chats | Real WebSocket / DOM stream; empty when disconnected |
| **Target URLs** | Hardcoded domain names (`sunwin.agency`, `sandboxg1.win`) | Completely removed; operator supplies any URL or browser session |
| **Fallback Strategy** | Silent fallback to mock games when network failed | Fail-closed standby card (`CHẾ ĐỘ AN TOÀN PHÁT SÓNG` / `NO SOURCE CONNECTED`) |
| **Auth Session** | Hardcoded cookie checks for single website | Generic persistent partition (`persist:operator_browser_session`) with universal token heuristics |
| **Compositor Branding** | Hardcoded single brand logo and marquee text | Universal neutral studio broadcast branding (`STUDIO LIVE`, `OFFICIAL BROADCAST`) |

---

## 2. Standard State Model (No DEMO State)

The application adheres strictly to the 8 standard operational states:
```
NO_SOURCE        -> Initial state before any source adapter is configured.
DISCOVERING      -> Auto-inspector is scanning target URL / DOM.
AUTH_REQUIRED    -> Target requires operator login session.
CONNECTING       -> Adapter is establishing real connection.
ONLINE           -> Stream is live, verified, and rendering.
DEGRADED         -> Temporary frame drop or data disconnect; auto-reconnecting.
RECONNECTING     -> Exponential backoff retry in progress.
OFFLINE          -> Source unreachable or intentionally closed.
```

**Under no circumstances does the application transition to a "DEMO" state.**

---

## 3. Verified Code Artifacts

- `src/main/sourceTypes.ts`: Contains zero-mock normalized definitions.
- `src/main/defaultPresets.ts`: Config initialized with `configuredSources: []` and neutral layouts.
- `src/adapters/websocketSourceAdapter.ts`: Parses live payloads only; emits `null` when empty.
- `src/program/programCompositor.ts`: Displays empty placeholder or safe standby card when no live frame is received.
- `tests/sourceDiscovery.test.js`: Verified through automated unit tests that initial state is strictly `NO_SOURCE` with `null` data caches.
