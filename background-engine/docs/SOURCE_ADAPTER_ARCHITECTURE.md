# SOURCE ADAPTER ARCHITECTURE — DEKA BACKGROUND ENGINE

## 1. Architectural Philosophy
The Background Engine compositor operates strictly on **Normalized Data Streams**. It has zero coupling to specific websites, proprietary DOM class names, or obfuscated WebSocket packet structures.

```
ANY SOURCE (Web, WS, SRT, RTMP, WebRTC)
                 │
                 ▼
         SOURCE ADAPTER
  (Captures, parses, normalizes)
                 │
                 ▼
      NORMALIZED STREAM
  (video frame, game state, chat)
                 │
                 ▼
     BACKGROUND ENGINE COMPOSITOR
       (1920x1080 @ 60 FPS GPU)
                 │
                 ▼
     NDI HIGH BANDWIDTH OUTPUT
```

---

## 2. Adapter Lifecycle & Interfaces

All adapters extend `BaseSourceAdapter`:
- `connect(): Promise<void>`: Establishes the real stream connection.
- `disconnect(): Promise<void>`: Tears down network sockets and renderer windows without lingering event listeners.
- `reconnect(): Promise<void>`: Performs isolated reconnection with exponential backoff (1s, 2s, 4s, up to 15s max).
- `getStatus(): SourceStatus`: Current state (`NO_SOURCE`, `CONNECTING`, `ONLINE`, `DEGRADED`, `OFFLINE`).
- `getHealth(): SourceHealth`: Latency in ms, FPS, lastDataTimestamp, errorCount.
- `getOutput(): any`: Returns current frame buffer or normalized data cache.

### Supported Adapters:
1. **`BrowserSourceAdapter`** (`src/adapters/browserSourceAdapter.ts`):
   - Runs offscreen Chromium page instances within `persist:operator_browser_session`.
   - Captures paint surfaces at 30-60 FPS using zero-copy image captures.
   - Forwards real base64/BGRA frames to preview monitors and compositor layers.
2. **`WebSocketSourceAdapter`** (`src/adapters/websocketSourceAdapter.ts`):
   - Connects to raw WebSocket endpoints.
   - Inspects JSON payloads dynamically to extract round ID, countdown seconds, and game results.
   - Normalizes chat messages (`username`, `message`, `vipLevel`, `avatarUrl`).
   - Automatically tracks ping/pong heartbeat and network latency.

---

## 3. Normalized Data Models

### Normalized Game State:
```typescript
interface NormalizedGameState {
  status: 'WAITING' | 'BETTING' | 'CLOSED' | 'RESULT' | 'PAUSED' | 'UNKNOWN';
  roundId?: string;
  countdownSeconds?: number;
  result?: {
    winningOutcome?: string;
    dice?: number[];
    cards?: string[];
    raw?: any;
  };
  statistics?: Record<string, any>;
  timestamp: number;
}
```

### Normalized Chat Message:
```typescript
interface NormalizedChatMessage {
  id: string;
  username: string;
  message: string;
  timestamp: number;
  type: 'USER' | 'MOD' | 'SYSTEM' | 'VIP';
  vipLevel?: number;
  avatarUrl?: string;
}
```

---

## 4. Fault Isolation & Failure Resilience
- **Fail-Closed Safety**: If a video or data source drops, the adapter transitions to `DEGRADED` or `OFFLINE`.
- **Compositor Stability**: A dropped source **never crashes** the 60 FPS GPU compositor. Ambient particles, 24/7 studio clock, branding logos, and ticker bars continue broadcasting cleanly over NDI without interruption.
- **Isolated Reconnect**: Each adapter manages its own retry timer. Reconnecting a video stream does not restart or interrupt active chat or layout positions.
