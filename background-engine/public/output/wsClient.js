/**
 * DEKA BACKGROUND ENGINE - RESILIENT WEBSOCKET CLIENT
 * Implements 24/7 Auto-Reconnect, Silent Auth, and Exponential Backoff
 */

class ResilientWSClient {
  constructor(tableId, onMessage, onStatusChange) {
    this.tableId = tableId;
    this.onMessage = onMessage;
    this.onStatusChange = onStatusChange;
    this.ws = null;
    this.retryCount = 0;
    this.reconnectTimer = null;
    this.heartbeatTimer = null;
    this.isClosedManually = false;
    this.deviceId = this.getOrCreateDeviceId();

    this.connect();
  }

  getOrCreateDeviceId() {
    let id = localStorage.getItem('deka_device_id');
    if (!id) {
      id = 'STUDIO-VMIX-' + Math.random().toString(36).substring(2, 8).toUpperCase();
      localStorage.setItem('deka_device_id', id);
    }
    return id;
  }

  getWsUrl() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${protocol}//${window.location.host}/ws`;
  }

  connect() {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    try {
      this.ws = new WebSocket(this.getWsUrl());

      this.ws.onopen = () => {
        console.log('[ResilientWS] Connected to Background Gateway');
        this.retryCount = 0;
        this.onStatusChange('online');

        // Send Handshake
        this.send({
          type: 'auth:handshake',
          tableId: this.tableId,
          payload: {
            clientType: 'output',
            deviceId: this.deviceId,
            userAgent: navigator.userAgent,
          },
          timestamp: Date.now(),
        });

        this.startHeartbeat();
      };

      this.ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          this.onMessage(msg);
        } catch (err) {
          console.error('[ResilientWS] Failed to parse message:', err);
        }
      };

      this.ws.onclose = () => {
        this.stopHeartbeat();
        this.onStatusChange('degraded');
        this.scheduleReconnect();
      };

      this.ws.onerror = (err) => {
        console.warn('[ResilientWS] Socket error, will reconnect:', err);
        this.ws.close();
      };
    } catch (err) {
      console.error('[ResilientWS] Connection attempt failed:', err);
      this.scheduleReconnect();
    }
  }

  scheduleReconnect() {
    if (this.isClosedManually) return;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);

    // Exponential Backoff: 1s -> 3s -> 5s -> 10s (capped)
    const delays = [1000, 3000, 5000, 10000];
    const delay = delays[Math.min(this.retryCount, delays.length - 1)];
    this.retryCount += 1;

    console.log(`[ResilientWS] Reconnecting in ${delay / 1000}s (attempt ${this.retryCount})...`);
    this.reconnectTimer = setTimeout(() => {
      this.connect();
    }, delay);
  }

  startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        // Collect telemetry metrics
        const fps = window.watchdog ? window.watchdog.currentFps : 60;
        const dropped = window.watchdog ? window.watchdog.droppedFrames : 0;
        const uptime = Math.floor((Date.now() - (window.engineStartTime || Date.now())) / 1000);

        this.send({
          type: 'telemetry:heartbeat',
          tableId: this.tableId,
          payload: {
            fps,
            droppedFrames: dropped,
            uptimeSeconds: uptime,
            activeLayersCount: document.querySelectorAll('.layer-node:not(.hidden)').length,
          },
          timestamp: Date.now(),
        });
      }
    }, 5000);
  }

  stopHeartbeat() {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
  }

  send(msg) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
    }
  }

  disconnect() {
    this.isClosedManually = true;
    this.stopHeartbeat();
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    if (this.ws) this.ws.close();
  }
}

window.ResilientWSClient = ResilientWSClient;
