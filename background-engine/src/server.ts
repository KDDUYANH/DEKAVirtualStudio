import express, { Request, Response } from 'express';
import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import path from 'path';
import cors from 'cors';
import { CONFIG } from './config.js';
import { DeviceAuthManager } from './auth/deviceAuth.js';
import { SceneManager } from './state/sceneManager.js';
import { ServerWatchdog } from './telemetry/watchdogServer.js';
import { WSMessage } from './types.js';

const app = express();
const httpServer = createServer(app);
const wss = new WebSocketServer({ server: httpServer, path: '/ws' });

app.use(cors());
app.use(express.json());

// Handle malformed JSON cleanly
app.use((err: any, _req: Request, res: Response, next: any) => {
  if (err && 'status' in err && err.status === 400) {
    return res.status(400).json({ error: 'Malformed JSON payload' });
  }
  next();
});

// Initialize Core Managers
export const authManager = new DeviceAuthManager();
export const sceneManager = new SceneManager();
export const watchdogServer = new ServerWatchdog();

// Serve Static Assets
app.use(express.static(CONFIG.PUBLIC_DIR));

// ============================================================================
// REST API ROUTES
// ============================================================================

// 1. Device Registration & 24/7 Session Token
app.post('/api/device/register', (req: Request, res: Response) => {
  const { deviceId, deviceName, tableId } = req.body;
  if (!deviceId || !tableId) {
    return res.status(400).json({ error: 'Missing deviceId or tableId' });
  }

  const result = authManager.registerDevice(deviceId, deviceName || 'Studio-PC', tableId);
  res.json({
    success: true,
    deviceId: result.session.deviceId,
    deviceName: result.session.deviceName,
    tableId: result.session.tableId,
    persistentToken: result.persistentToken,
    accessToken: result.accessToken,
    expiresIn: CONFIG.JWT_ACCESS_EXPIRY,
  });
});

// 2. Silent Token Refresh (Auto-refresh token without logging out)
app.post('/api/device/refresh', (req: Request, res: Response) => {
  const { persistentToken } = req.body;
  if (!persistentToken) {
    return res.status(400).json({ error: 'Missing persistentToken' });
  }

  const result = authManager.refreshAccessToken(persistentToken);
  if (!result) {
    return res.status(401).json({ error: 'Invalid or revoked persistent token' });
  }

  res.json({
    success: true,
    accessToken: result.accessToken,
    deviceId: result.deviceId,
    tableId: result.tableId,
    expiresIn: CONFIG.JWT_ACCESS_EXPIRY,
  });
});

// 3. Scene State Endpoints
app.get('/api/scene/:tableId', (req: Request, res: Response) => {
  const { tableId } = req.params;
  const scene = sceneManager.getScene(tableId);
  res.json({ success: true, scene });
});

app.post('/api/scene/:tableId/layer/:layerId', (req: Request, res: Response) => {
  const { tableId, layerId } = req.params;
  try {
    const updated = sceneManager.updateLayer(tableId, layerId, req.body);
    broadcastToRoom(tableId, {
      type: 'state:sync',
      tableId,
      payload: updated,
      timestamp: Date.now(),
    });
    res.json({ success: true, scene: updated });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

app.post('/api/scene/:tableId/reorder', (req: Request, res: Response) => {
  const { tableId } = req.params;
  const { orderedLayerIds } = req.body;
  try {
    const updated = sceneManager.reorderLayers(tableId, orderedLayerIds);
    broadcastToRoom(tableId, {
      type: 'state:sync',
      tableId,
      payload: updated,
      timestamp: Date.now(),
    });
    res.json({ success: true, scene: updated });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

app.post('/api/scene/:tableId/lock', (req: Request, res: Response) => {
  const { tableId } = req.params;
  const { locked } = req.body;
  const updated = sceneManager.setProductionLock(tableId, Boolean(locked));
  broadcastToRoom(tableId, {
    type: 'state:lock_toggle',
    tableId,
    payload: { locked: updated.lockedProduction },
    timestamp: Date.now(),
  });
  res.json({ success: true, locked: updated.lockedProduction });
});

app.post('/api/scene/:tableId/mode', (req: Request, res: Response) => {
  const { tableId } = req.params;
  const { mode } = req.body;
  try {
    const updated = sceneManager.setMode(tableId, mode);
    broadcastToRoom(tableId, {
      type: 'state:sync',
      tableId,
      payload: updated,
      timestamp: Date.now(),
    });
    res.json({ success: true, mode: updated.mode });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

// 4. Alert Actions
app.post('/api/scene/:tableId/alert', (req: Request, res: Response) => {
  const { tableId } = req.params;
  const { title, message, severity } = req.body;
  const updated = sceneManager.triggerAlert(tableId, { title, message, severity });
  broadcastToRoom(tableId, {
    type: 'action:trigger_alert',
    tableId,
    payload: { title, message, severity },
    timestamp: Date.now(),
  });
  res.json({ success: true, scene: updated });
});

app.delete('/api/scene/:tableId/alert', (req: Request, res: Response) => {
  const { tableId } = req.params;
  const updated = sceneManager.clearAlert(tableId);
  broadcastToRoom(tableId, {
    type: 'action:clear_alert',
    tableId,
    timestamp: Date.now(),
  });
  res.json({ success: true, scene: updated });
});

// 5. Telemetry API
app.get('/api/telemetry/:tableId', (req: Request, res: Response) => {
  const telemetry = watchdogServer.getTelemetry(req.params.tableId);
  res.json({ success: true, telemetry });
});

app.get('/api/telemetry', (_req: Request, res: Response) => {
  const list = watchdogServer.getAllTelemetry();
  res.json({ success: true, telemetry: list });
});

// 6. Demo Widgets (Game & Chat) to feed into Layers for testing
app.get('/api/demo/game-widget', (req: Request, res: Response) => {
  const tableId = (req.query.tableId as string) || 'table-01';
  res.send(`<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {
      margin: 0; padding: 16px; background: rgba(10, 15, 29, 0.95);
      color: #00f2fe; font-family: 'Segoe UI', sans-serif; overflow: hidden;
      border: 1px solid rgba(0, 242, 254, 0.3); border-radius: 8px;
    }
    .header { font-size: 14px; text-transform: uppercase; letter-spacing: 2px; color: #94a3b8; display: flex; justify-content: space-between; }
    .badge { background: #10b981; color: #000; padding: 2px 8px; border-radius: 4px; font-weight: bold; }
    .score-box { display: flex; justify-content: space-around; margin: 20px 0; }
    .team { text-align: center; }
    .score { font-size: 48px; font-weight: 800; color: #fff; text-shadow: 0 0 20px #00f2fe; }
    .timer { font-size: 18px; color: #f59e0b; text-align: center; font-weight: 600; }
  </style>
</head>
<body>
  <div class="header">
    <span>★ LIVE INTERACTIVE ARENA (${tableId})</span>
    <span class="badge">ON AIR</span>
  </div>
  <div class="score-box">
    <div class="team"><div>RED DRAGON</div><div id="scoreA" class="score">14</div></div>
    <div style="font-size: 36px; align-self: center; color: #64748b;">VS</div>
    <div class="team"><div>BLUE PHOENIX</div><div id="scoreB" class="score">09</div></div>
  </div>
  <div class="timer" id="clock">ROUND 03 • 02:45</div>
  <script>
    let a = 14, b = 9, sec = 165;
    setInterval(() => {
      if (Math.random() > 0.6) { a += 1; document.getElementById('scoreA').innerText = a; }
      else if (Math.random() > 0.6) { b += 1; document.getElementById('scoreB').innerText = b; }
      sec = sec > 0 ? sec - 1 : 180;
      const m = Math.floor(sec / 60).toString().padStart(2, '0');
      const s = (sec % 60).toString().padStart(2, '0');
      document.getElementById('clock').innerText = 'ROUND 03 • ' + m + ':' + s;
    }, 1500);
  </script>
</body>
</html>`);
});

app.get('/api/demo/chat-widget', (req: Request, res: Response) => {
  const tableId = (req.query.tableId as string) || 'table-01';
  res.send(`<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {
      margin: 0; padding: 12px; background: rgba(8, 12, 22, 0.92);
      color: #fff; font-family: 'Segoe UI', sans-serif; overflow: hidden;
      border: 1px solid rgba(255,255,255,0.1); border-radius: 8px;
    }
    .title { font-size: 12px; font-weight: bold; color: #38bdf8; margin-bottom: 8px; text-transform: uppercase; }
    .chat-list { display: flex; flex-direction: column; gap: 8px; max-height: 90vh; overflow: hidden; }
    .msg { background: rgba(255,255,255,0.05); padding: 6px 10px; border-radius: 6px; font-size: 13px; animation: slideIn 0.3s ease; }
    .user { font-weight: 700; color: #f43f5e; margin-right: 6px; }
    @keyframes slideIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
  </style>
</head>
<body>
  <div class="title">💬 STUDIO CHAT FEED (${tableId})</div>
  <div class="chat-list" id="chat">
    <div class="msg"><span class="user">Alex_99:</span> Chào studio! Âm thanh hình ảnh nét căng 🔥</div>
    <div class="msg"><span class="user">MinhVu:</span> Đặt cược vòng này kịch tính quá</div>
  </div>
  <script>
    const msgs = [
      'Giao diện vMix CEF mượt thật sự!',
      'Hôm nay MC nói chuyện cuốn ghê',
      'Chúc studio phát sóng 24/7 thành công!',
      'Cầu đỏ đang thắng thế rồi anh em ơi',
      'Đồ hoạ nét từng pixel, 60fps không giật lag'
    ];
    const names = ['QuangHai', 'StudioFan', 'CyberLive', 'BaoLong', 'DekaViewer'];
    setInterval(() => {
      const c = document.getElementById('chat');
      const div = document.createElement('div');
      div.className = 'msg';
      const u = names[Math.floor(Math.random() * names.length)];
      const m = msgs[Math.floor(Math.random() * msgs.length)];
      div.innerHTML = '<span class="user">' + u + ':</span> ' + m;
      c.appendChild(div);
      if (c.children.length > 7) c.removeChild(c.children[0]);
    }, 2500);
  </script>
</body>
</html>`);
});

// Output & Control Page Routes
app.get('/output/:tableId', (_req: Request, res: Response) => {
  res.sendFile(path.join(CONFIG.PUBLIC_DIR, 'output', 'index.html'));
});

app.get('/control/:tableId', (_req: Request, res: Response) => {
  res.sendFile(path.join(CONFIG.PUBLIC_DIR, 'control', 'index.html'));
});

app.get('/', (_req: Request, res: Response) => {
  res.redirect('/control/table-01');
});

// ============================================================================
// WEBSOCKET REAL-TIME GATEWAY (ROOM PER TABLE)
// ============================================================================

interface ClientMeta {
  ws: WebSocket;
  tableId: string;
  clientType: 'output' | 'control';
  deviceId?: string;
  isAlive: boolean;
}

const clients: Set<ClientMeta> = new Set();

function broadcastToRoom(tableId: string, message: WSMessage, excludeWs?: WebSocket): void {
  const payload = JSON.stringify(message);
  for (const client of clients) {
    if (client.tableId === tableId && client.ws.readyState === WebSocket.OPEN) {
      if (excludeWs && client.ws === excludeWs) continue;
      client.ws.send(payload);
    }
  }
}

wss.on('connection', (ws: WebSocket) => {
  const meta: ClientMeta = {
    ws,
    tableId: 'table-01',
    clientType: 'output',
    isAlive: true,
  };
  clients.add(meta);

  ws.on('pong', () => {
    meta.isAlive = true;
  });

  ws.on('message', (rawData: string) => {
    try {
      const msg: WSMessage = JSON.parse(rawData);

      switch (msg.type) {
        case 'auth:handshake': {
          meta.tableId = msg.tableId || 'table-01';
          meta.clientType = msg.payload?.clientType || 'output';
          meta.deviceId = msg.payload?.deviceId || 'anon';

          if (meta.deviceId) {
            authManager.touchSession(meta.deviceId);
          }

          // Send current scene state immediately upon connect
          const scene = sceneManager.getScene(meta.tableId);
          ws.send(
            JSON.stringify({
              type: 'auth:ack',
              tableId: meta.tableId,
              payload: {
                scene,
                telemetry: watchdogServer.getTelemetry(meta.tableId),
              },
              timestamp: Date.now(),
            } as WSMessage)
          );
          break;
        }

        case 'telemetry:heartbeat': {
          if (meta.clientType === 'output') {
            const telemetry = watchdogServer.recordHeartbeat({
              tableId: meta.tableId,
              deviceId: meta.deviceId,
              fps: msg.payload?.fps || 60,
              droppedFrames: msg.payload?.droppedFrames || 0,
              networkStatus: 'online',
              activeLayersCount: msg.payload?.activeLayersCount || 0,
              layerStatuses: msg.payload?.layerStatuses || {},
              uptimeSeconds: msg.payload?.uptimeSeconds || 0,
            });

            // Notify control plane operators of telemetry
            broadcastToRoom(
              meta.tableId,
              {
                type: 'telemetry:report',
                tableId: meta.tableId,
                payload: telemetry,
                timestamp: Date.now(),
              },
              ws
            );
          }
          break;
        }

        case 'state:update_layer': {
          if (msg.payload?.layerId) {
            try {
              const updated = sceneManager.updateLayer(meta.tableId, msg.payload.layerId, msg.payload.layer);
              broadcastToRoom(meta.tableId, {
                type: 'state:sync',
                tableId: meta.tableId,
                payload: updated,
                timestamp: Date.now(),
              });
            } catch (err: any) {
              ws.send(JSON.stringify({ type: 'auth:error', tableId: meta.tableId, payload: { error: err.message }, timestamp: Date.now() }));
            }
          }
          break;
        }

        case 'action:reload_layer': {
          broadcastToRoom(meta.tableId, msg);
          break;
        }

        case 'state:publish': {
          const scene = sceneManager.getScene(meta.tableId);
          broadcastToRoom(meta.tableId, {
            type: 'state:sync',
            tableId: meta.tableId,
            payload: scene,
            timestamp: Date.now(),
          });
          break;
        }
      }
    } catch (err) {
      console.error('[WebSocket] Error processing message:', err);
    }
  });

  ws.on('close', () => {
    clients.delete(meta);
  });

  ws.on('error', (err) => {
    console.error('[WebSocket] Client error:', err);
    clients.delete(meta);
  });
});

// Periodic ping to keep connections alive and clean up dead sockets
setInterval(() => {
  for (const client of clients) {
    if (!client.isAlive) {
      try {
        client.ws.terminate();
      } catch {}
      clients.delete(client);
      continue;
    }
    client.isAlive = false;
    try {
      client.ws.ping();
    } catch (err) {
      console.warn('[WebSocket] Ping failed, removing client:', err);
      clients.delete(client);
    }
  }
}, 10000);

// Global unhandled error handlers for 24/7 reliability
process.on('uncaughtException', (err) => {
  console.error('[Server] Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason) => {
  console.error('[Server] Unhandled Rejection:', reason);
});

// Start HTTP & WS Server
httpServer.listen(CONFIG.PORT, CONFIG.HOST, () => {
  console.log(`=======================================================`);
  console.log(`🎬 DEKA 24/7 BACKGROUND ENGINE & CONTROL HUB IS RUNNING`);
  console.log(`🌐 Server:  http://localhost:${CONFIG.PORT}`);
  console.log(`📺 vMix Output:  http://localhost:${CONFIG.PORT}/output/table-01`);
  console.log(`🎛️ Control Plane: http://localhost:${CONFIG.PORT}/control/table-01`);
  console.log(`=======================================================`);
});
