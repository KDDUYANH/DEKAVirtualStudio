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
import { fileURLToPath } from 'url';

import { PersistenceStore } from './persistenceStore.js';
import { SafetyGate } from './safetyGate.js';
import { AuthSessionManager } from './authSession.js';
import { SourceRecoveryManager } from './sourceRecovery.js';
import { NdiController } from './ndiController.js';
import { PositionEngine } from '../program/positionEngine.js';
import { AutoMoveSequencer } from '../program/autoMoveSequencer.js';
import { PositionId } from './types.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Core Singletons
let store: PersistenceStore;
let safetyGate: SafetyGate;
let authManager: AuthSessionManager;
let recoveryManager: SourceRecoveryManager;
let ndiController: NdiController;
let positionEngine: PositionEngine;
let autoMoveSequencer: AutoMoveSequencer;

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

  // 7. Start Local Diagnostic HTTP Server (Port 7800 fallback)
  startLocalHttpServer(7800);

  // 8. Create PROGRAM Output Window (1920x1080 Compositor)
  createProgramWindow();

  // 9. Create PREVIEW Operator Control Window
  createPreviewWindow();

  // 10. Wire Up Event Buses and Safety Gate
  wireUpSafetyAndRecovery();

  // 11. Initial Auth Check
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

function createProgramWindow() {
  programWindow = new BrowserWindow({
    width: 1920,
    height: 1080,
    show: false, // Runs off-screen or minimized as dedicated compositor
    frame: false,
    useContentSize: true,
    backgroundColor: '#000000',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      backgroundThrottling: false, // Ensure full 60fps when in background
    },
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
  authManager.openLoginWindow(previewWindow || undefined);
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
  if (authManager) authManager.destroy();
  if (recoveryManager) recoveryManager.destroy();
  if (autoMoveSequencer) autoMoveSequencer.destroy();
  if (store) store.flushSync();
});
