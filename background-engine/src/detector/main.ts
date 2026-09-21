import { app, BrowserWindow, ipcMain, session } from 'electron';
import path from 'path';
import fs from 'fs';
import { SourceInspector } from '../main/sourceInspector.js';
import { PersistenceStore } from '../main/persistenceStore.js';

let detectorWindow: BrowserWindow | null = null;
let inspector: SourceInspector;
let store: PersistenceStore;

function createWindow() {
  detectorWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 1100,
    minHeight: 700,
    title: 'DEKA Source Detector — Deep Protocol & Stream Analyzer',
    backgroundColor: '#0c0e14',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
    },
  });

  const htmlPath = fs.existsSync(path.join(__dirname, 'index.html'))
    ? path.join(__dirname, 'index.html')
    : path.join(process.cwd(), 'src', 'detector', 'index.html');
  detectorWindow.loadFile(htmlPath);

  detectorWindow.on('closed', () => {
    detectorWindow = null;
  });
}

app.whenReady().then(() => {
  store = new PersistenceStore();
  inspector = new SourceInspector('persist:operator_browser_session');
  createWindow();

  ipcMain.handle('inspect-url', async (_e, { url }: { url: string }) => {
    console.log(`[SourceDetector App] Inspecting: ${url}`);
    return await inspector.inspectUrl(url);
  });

  ipcMain.handle('get-session-cookies', async () => {
    const sess = session.fromPartition('persist:operator_browser_session');
    const cookies = await sess.cookies.get({});
    return {
      cookieCount: cookies.length,
      domains: Array.from(new Set(cookies.map((c) => c.domain))),
      hasAuthCookie: cookies.some((c) =>
        c.name.toLowerCase().includes('token') ||
        c.name.toLowerCase().includes('session') ||
        c.name.toLowerCase().includes('auth') ||
        c.name.toLowerCase().includes('user')
      ),
    };
  });

  ipcMain.handle('export-adapter-to-engine', async (_e, adapterConfig: any) => {
    console.log('[SourceDetector App] Exporting adapter to Background Engine:', adapterConfig);
    const currentConfig = store.getConfig();
    const existing = (currentConfig.configuredSources || []).filter((s) => s.id !== adapterConfig.id);
    existing.push(adapterConfig);
    store.updateConfig({ configuredSources: existing });
    return { success: true, count: existing.length };
  });

  ipcMain.on('open-interactive-browser', (_e, targetUrl: string) => {
    const win = new BrowserWindow({
      width: 1200,
      height: 800,
      title: 'Trình Duyệt Tương Tác — Đăng Nhập & Bắt Gói',
      webPreferences: {
        partition: 'persist:operator_browser_session',
      },
    });
    win.loadURL(targetUrl || 'https://google.com');
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
