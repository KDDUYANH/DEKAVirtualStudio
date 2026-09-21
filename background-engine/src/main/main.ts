/**
 * DEKA BACKGROUND ENGINE — MAIN PROCESS ORCHESTRATOR
 * Production Architecture Refactor:
 * PREVIEW (Operator Workspace) != PROGRAM (1920x1080 60FPS GPU Compositor)
 * Primary Output: NDI High Bandwidth ('BackgroundEngine-PGM')
 */

import { app, BrowserWindow, ipcMain, WebContentsView } from 'electron';
import path from 'path';
import http from 'http';
import fs from 'fs';

import { PersistenceStore } from './persistenceStore.js';
import { SafetyGate } from './safetyGate.js';
import { AuthSessionManager } from './authSession.js';
import { SourceRecoveryManager } from './sourceRecovery.js';
import { NdiController } from './ndiController.js';
import { PositionEngine } from '../program/positionEngine.js';
import { AutoMoveSequencer } from '../program/autoMoveSequencer.js';
import { PositionId } from './types.js';
import { SourceInspector } from './sourceInspector.js';
import { AdapterManager } from '../adapters/adapterManager.js';
import { SourceAdapterConfig } from './sourceTypes.js';

// Core Singletons
let store: PersistenceStore;
let safetyGate: SafetyGate;
let authManager: AuthSessionManager;
let recoveryManager: SourceRecoveryManager;
let ndiController: NdiController;
let positionEngine: PositionEngine;
let autoMoveSequencer: AutoMoveSequencer;
let sourceInspector: SourceInspector;
let adapterManager: AdapterManager;

let previewWindow: BrowserWindow | null = null;
let programWindow: BrowserWindow | null = null;
let localHttpServer: http.Server | null = null;

const startTime = Date.now();

async function bootstrap() {
  console.log('===============================================================');
  console.log('  🎬 DEKA BACKGROUND ENGINE — STARTING INITIALIZATION');
  console.log('===============================================================');

  // 1. Load configuration and restore persistence
  store = new PersistenceStore();
  const config = store.getConfig();
  console.log(`[Bootstrap] Config loaded from: ${store.paths.config}`);

  // 2. Initialize Safety Gate (Default: PROGRAM_SAFE)
  safetyGate = new SafetyGate();

  // 3. Initialize Auth Session Manager (Persistent profile)
  authManager = new AuthSessionManager(store.paths.browserProfile);

  // 4. Initialize Source Recovery Manager
  recoveryManager = new SourceRecoveryManager(config.targets);

  // 5. Initialize Position Engine & Auto Move
  positionEngine = new PositionEngine(config.positions, config.currentPosition);
  autoMoveSequencer = new AutoMoveSequencer(
    positionEngine,
    config.autoMoveEnabled,
    config.autoMoveLoop
  );

  // 6. Initialize NDI High Bandwidth Controller
  ndiController = new NdiController(config.ndiStreamName);
  ndiController.start();

  // 7. Initialize Source Discovery Inspector & Adapter Manager
  sourceInspector = new SourceInspector();
  adapterManager = new AdapterManager();

  // Restore configured sources if any
  if (config.configuredSources && config.configuredSources.length > 0) {
    for (const sourceCfg of config.configuredSources) {
      adapterManager.registerAdapter(sourceCfg).catch((err) => {
        console.warn(`[Bootstrap] Error restoring source adapter ${sourceCfg.id}:`, err);
      });
    }
  }

  // 8. Start Local Diagnostic HTTP Server (Port 7800 fallback)
  startLocalHttpServer(7800);

  // 9. Create PROGRAM Output Window (1920x1080 Compositor)
  createProgramWindow();

  // 10. Create PREVIEW Operator Control Window
  createPreviewWindow();

  // 11. Wire Up Event Buses and Safety Gate
  wireUpSafetyAndRecovery();

  // 12. Initial Auth Check
  await authManager.verifySession();

  console.log('===============================================================');
  console.log('  🚀 BACKGROUND ENGINE INITIALIZATION COMPLETE');
  console.log(`  📺 NDI Output Stream:  ${config.ndiStreamName} (1080p60)`);
  console.log(`  🌐 Local Monitor:      http://127.0.0.1:7800/output`);
  console.log('===============================================================');
}

// ============================================================================
// WINDOW CREATION (PREVIEW != PROGRAM)
// ============================================================================
function createPreviewWindow() {
  previewWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1200,
    minHeight: 750,
    title: 'DEKA Background Engine — Preview & Operator Workspace',
    backgroundColor: '#0f1117',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
    },
  });

  const previewPath = path.join(process.cwd(), 'src', 'preview', 'index.html');
  previewWindow.loadFile(previewPath);

  previewWindow.on('closed', () => {
    previewWindow = null;
    app.quit();
  });
}

// Chromium Command Line Flags for 60 FPS Low-Latency GPU Compositing
app.commandLine.appendSwitch('enable-gpu-rasterization');
app.commandLine.appendSwitch('enable-zero-copy');
app.commandLine.appendSwitch('ignore-gpu-blocklist');
app.commandLine.appendSwitch('use-angle', 'd3d11');
app.commandLine.appendSwitch('disable-background-timer-throttling');
app.commandLine.appendSwitch('disable-renderer-backgrounding');
app.commandLine.appendSwitch('disable-backgrounding-occluded-windows');
app.commandLine.appendSwitch('disable-features', 'CalculateNativeWinOcclusion');

function createProgramWindow() {
  programWindow = new BrowserWindow({
    width: 1920,
    height: 1080,
    show: false,
    frame: false,
    useContentSize: true,
    backgroundColor: '#000000',
    webPreferences: {
      offscreen: true, // Native GPU offscreen rendering
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      backgroundThrottling: false, // Maintain 60fps even when hidden
    },
  });

  // Lock compositor to 60.0 FPS
  programWindow.webContents.setFrameRate(60);

  // Hook uncompressed frame buffer directly from GPU compositor into NDI pipe
  programWindow.webContents.on('paint', (_event, _dirty, image) => {
    if (!ndiController) return;
    const bgraBuffer = image.getBitmap();
    ndiController.sendFrame(bgraBuffer);
  });

  const programPath = path.join(process.cwd(), 'src', 'program', 'index.html');
  programWindow.loadFile(programPath);

  programWindow.webContents.on('did-finish-load', () => {
    // Sync initial state to compositor
    syncCompositorState();
  });
}

// ============================================================================
// EVENT WIRING & SAFETY STATE MACHINE
// ============================================================================
function wireUpSafetyAndRecovery() {
  // Safety Gate Transitions
  safetyGate.on('state-changed', (change) => {
    // Notify PREVIEW UI
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('safety-state-changed', change);
    }
    // Notify PROGRAM Compositor
    if (programWindow && !programWindow.isDestroyed()) {
      programWindow.webContents.send('set-safety-state', change.current);
    }
  });

  // Auth Status Updates
  authManager.on('auth-status-changed', (status) => {
    safetyGate.updateInputs({ isAuthenticated: status.isAuthenticated });
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('auth-status-changed', status);
    }
  });

  // Game Recovery Updates
  recoveryManager.on('game-state-changed', (data) => {
    const isOk = data.state === 'LIVE' || data.state === 'READY';
    safetyGate.updateInputs({
      isGameVerified: isOk,
      isGameHealthy: isOk,
    });
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('game-state-changed', data);
    }
  });

  // Chat Recovery Updates
  recoveryManager.on('chat-state-changed', (data) => {
    const isOk = data.state === 'CONNECTED' || data.state === 'READY';
    safetyGate.updateInputs({
      isChatVerified: isOk,
      isChatHealthy: isOk,
    });
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('chat-state-changed', data);
    }
  });

  // Position Changes (Changing position NEVER restarts Game or Chat!)
  positionEngine.on('position-changed', (data) => {
    store.updateConfig({ currentPosition: data.current });
    if (programWindow && !programWindow.isDestroyed()) {
      programWindow.webContents.send('set-position', data.preset);
    }
  });

  positionEngine.on('preset-saved', (data) => {
    store.savePosition(data.posId, data.preset);
  });

  // Auto Move Ticks
  autoMoveSequencer.on('tick', (status) => {
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('automove-tick', status);
    }
  });

  // NDI Telemetry Updates
  ndiController.on('telemetry-updated', (telem) => {
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('ndi-telemetry', telem);
    }
  });

  // Modular Source Adapters Event Wiring
  adapterManager.on('adapter-status-changed', (event) => {
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('adapter-status-changed', event);
    }
  });

  adapterManager.on('adapter-health', (event) => {
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('adapter-health', event);
    }
  });

  adapterManager.on('adapter-frame', (frame) => {
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('adapter-frame', frame);
    }
    if (programWindow && !programWindow.isDestroyed()) {
      programWindow.webContents.send('adapter-frame', frame);
    }
  });

  adapterManager.on('adapter-game-state', (payload) => {
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('adapter-game-state', payload);
    }
    if (programWindow && !programWindow.isDestroyed()) {
      programWindow.webContents.send('game-state-update', payload.state);
    }
  });

  adapterManager.on('adapter-chat-message', (payload) => {
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('adapter-chat-message', payload);
    }
    if (programWindow && !programWindow.isDestroyed()) {
      programWindow.webContents.send('new-chat-message', payload.msg);
    }
  });

  // Periodic System Telemetry
  setInterval(() => {
    const mem = process.memoryUsage();
    const uptime = Math.floor((Date.now() - startTime) / 1000);
    if (previewWindow && !previewWindow.isDestroyed()) {
      previewWindow.webContents.send('app-telemetry', {
        uptimeSeconds: uptime,
        memoryMb: Math.round(mem.rss / (1024 * 1024)),
        fps: 60,
      });
    }
  }, 1000);
}

function syncCompositorState() {
  if (!programWindow || programWindow.isDestroyed()) return;
  programWindow.webContents.send('set-safety-state', safetyGate.getState());
  programWindow.webContents.send('set-position', positionEngine.getActivePreset());
}

// ============================================================================
// IPC ACTION HANDLERS (OPERATOR COMMANDS)
// ============================================================================
ipcMain.on('open-login', () => {
  authManager.openLoginWindow(undefined, previewWindow || undefined);
});

ipcMain.on('logout', async () => {
  await authManager.logout();
  safetyGate.updateInputs({ isAuthenticated: false });
});

ipcMain.on('set-position', (_event, posId: PositionId) => {
  positionEngine.setPosition(posId);
});

ipcMain.on('save-position', (_event, posId: PositionId) => {
  const current = positionEngine.getActivePreset();
  positionEngine.savePreset(posId, current);
});

ipcMain.on('automove-cmd', (_event, cmd: any) => {
  if (typeof cmd === 'string') {
    if (cmd === 'start') autoMoveSequencer.start();
    if (cmd === 'pause') autoMoveSequencer.pause();
    if (cmd === 'stop') autoMoveSequencer.stop();
    if (cmd === 'next') autoMoveSequencer.next();
    if (cmd === 'previous') autoMoveSequencer.previous();
  } else if (cmd && cmd.action === 'set-loop') {
    autoMoveSequencer.setLoop(Boolean(cmd.loop));
  }
});

ipcMain.on('test-output', () => {
  // Briefly show program output window for manual operator inspection if requested
  if (programWindow && !programWindow.isDestroyed()) {
    if (programWindow.isVisible()) {
      programWindow.hide();
    } else {
      programWindow.show();
      programWindow.focus();
    }
  }
});

ipcMain.on('recheck-sources', async () => {
  await authManager.verifySession();
  recoveryManager.resetGameRecovery();
  recoveryManager.resetChatRecovery();
});

ipcMain.on('reconnect-game', () => {
  recoveryManager.resetGameRecovery();
});

ipcMain.on('reconnect-chat', () => {
  recoveryManager.resetChatRecovery();
});

// ============================================================================
// IPC ACTION HANDLERS (SOURCE DISCOVERY & ADAPTERS)
// ============================================================================
ipcMain.handle('scan-source', async (_event, data: { url: string }) => {
  if (!data || !data.url) {
    throw new Error('URL is required for source scanning');
  }
  return await sourceInspector.inspect(data.url);
});

ipcMain.handle('detect-browser', async () => {
  const isAuthed = await authManager.verifySession();
  const status = authManager.getStatus();
  return {
    authenticated: isAuthed,
    user: { username: status.username },
    sessionPartition: 'persist:operator_browser_session',
  };
});

ipcMain.handle('add-source-adapter', async (_event, config: SourceAdapterConfig) => {
  const adapter = await adapterManager.registerAdapter(config);

  // Persist into config
  const currentConfig = store.getConfig();
  const existingSources = (currentConfig.configuredSources || []).filter((s) => s.id !== config.id);
  existingSources.push(config);
  store.updateConfig({ configuredSources: existingSources });

  if (previewWindow && !previewWindow.isDestroyed()) {
    previewWindow.webContents.send('configured-sources-changed', existingSources);
  }

  // If chat or game was added, update safety gate
  if (config.boundLayerKey === 'game') {
    safetyGate.updateInputs({ isGameVerified: true, isGameHealthy: true });
  } else if (config.boundLayerKey === 'chat') {
    safetyGate.updateInputs({ isChatVerified: true, isChatHealthy: true });
  }

  return {
    success: true,
    id: config.id,
    status: adapter.getStatus(),
  };
});

ipcMain.handle('remove-source-adapter', async (_event, id: string) => {
  const removed = await adapterManager.removeAdapter(id);
  const currentConfig = store.getConfig();
  const filtered = (currentConfig.configuredSources || []).filter((s) => s.id !== id);
  store.updateConfig({ configuredSources: filtered });

  if (previewWindow && !previewWindow.isDestroyed()) {
    previewWindow.webContents.send('configured-sources-changed', filtered);
  }

  return { success: removed };
});

ipcMain.handle('get-configured-sources', () => {
  return store.getConfig().configuredSources || [];
});

ipcMain.on('reconnect-adapter', async (_event, id: string) => {
  const adapter = adapterManager.getAdapter(id);
  if (adapter) {
    await adapter.reconnect();
  }
});

// ============================================================================
// LOCAL HTTP DIAGNOSTIC SERVER (PORT 7800 FALLBACK)
// ============================================================================
function startLocalHttpServer(port: number) {
  localHttpServer = http.createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Cache-Control', 'no-cache');

    const url = new URL(req.url || '/', `http://${req.headers.host}`);
    if (url.pathname === '/' || url.pathname === '/output') {
      const htmlPath = path.join(process.cwd(), 'src', 'program', 'index.html');
      fs.readFile(htmlPath, (err, data) => {
        if (err) {
          res.writeHead(500);
          res.end('Error loading output page');
          return;
        }
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(data);
      });
      return;
    }

    if (url.pathname === '/style.css') {
      const cssPath = path.join(process.cwd(), 'src', 'program', 'style.css');
      fs.readFile(cssPath, (err, data) => {
        if (err) { res.writeHead(404); res.end(); return; }
        res.writeHead(200, { 'Content-Type': 'text/css' });
        res.end(data);
      });
      return;
    }

    if (url.pathname === '/programCompositor.js') {
      const jsPath = path.join(process.cwd(), 'dist', 'program', 'programCompositor.js');
      fs.readFile(jsPath, (err, data) => {
        if (err) { res.writeHead(404); res.end(); return; }
        res.writeHead(200, { 'Content-Type': 'application/javascript' });
        res.end(data);
      });
      return;
    }

    res.writeHead(404);
    res.end('Not Found');
  });

  localHttpServer.listen(port, '127.0.0.1', () => {
    console.log(`[HttpServer] Local diagnostic output available at http://127.0.0.1:${port}/output`);
  });
}

// ============================================================================
// APP LIFECYCLE
// ============================================================================
app.whenReady().then(bootstrap);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('before-quit', () => {
  if (ndiController) ndiController.stop();
  if (localHttpServer) localHttpServer.close();
  if (sourceInspector) sourceInspector.destroy();
  if (adapterManager) adapterManager.shutdown();
  if (authManager) authManager.destroy();
  if (recoveryManager) recoveryManager.destroy();
  if (autoMoveSequencer) autoMoveSequencer.destroy();
  if (store) store.flushSync();
});
