import { BrowserWindow, ipcMain } from 'electron';
import { EventEmitter } from 'events';

export interface InteractiveSourceState {
  isOpen: boolean;
  isCapturing: boolean;
  currentUrl: string;
  fps: number;
}

export class InteractiveSourceWindow extends EventEmitter {
  private window: BrowserWindow | null = null;
  private captureInterval: NodeJS.Timeout | null = null;
  private fpsTimer: NodeJS.Timeout | null = null;
  private frameCount = 0;
  private lastFpsTime = Date.now();
  private isCapturing = false;
  private partition = 'persist:operator_browser_session';

  constructor() {
    super();
  }

  public open(defaultUrl: string = 'https://google.com'): void {
    if (this.window && !this.window.isDestroyed()) {
      this.window.focus();
      return;
    }

    this.window = new BrowserWindow({
      width: 1280,
      height: 800,
      title: 'Trình Duyệt Nguồn Trực Tiếp — Đăng Nhập & Chọn Bàn Nhanh',
      backgroundColor: '#0f1117',
      webPreferences: {
        partition: this.partition,
        nodeIntegration: false,
        contextIsolation: true,
        backgroundThrottling: false,
      },
    });

    this.window.on('closed', () => {
      this.stopCapture();
      this.window = null;
      this.emit('closed');
    });

    this.window.webContents.on('did-finish-load', () => {
      this.injectQuickActionBar();
      // Auto-start frame capture once operator navigates to content
      if (!this.isCapturing) {
        this.startCapture();
      }
    });

    this.window.loadURL(defaultUrl).catch((err) => {
      console.warn('[InteractiveSource] loadURL warning:', err.message);
    });

    this.emit('opened', { url: defaultUrl });
  }

  /**
   * Injects a lightweight, non-intrusive floating Action Bar into the top of the browser.
   * Operator can click directly on the game, login, and click 1 button to broadcast.
   */
  private injectQuickActionBar(): void {
    if (!this.window || this.window.isDestroyed()) return;

    const script = `
      (function() {
        if (document.getElementById('deka-operator-dock')) return;

        const dock = document.createElement('div');
        dock.id = 'deka-operator-dock';
        dock.style.cssText = \`
          position: fixed;
          top: 10px;
          right: 10px;
          z-index: 2147483647;
          background: rgba(15, 17, 23, 0.92);
          backdrop-filter: blur(12px);
          border: 1px solid rgba(255, 215, 0, 0.4);
          box-shadow: 0 4px 20px rgba(0, 0, 0, 0.6);
          border-radius: 8px;
          padding: 8px 14px;
          display: flex;
          align-items: center;
          gap: 10px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          color: #fff;
          font-size: 12px;
          user-select: none;
        \`;

        dock.innerHTML = \`
          <span style="font-weight: 800; color: #ffd700; letter-spacing: 0.5px;">BACKGROUND ENGINE</span>
          <span id="dock-status" style="display: flex; align-items: center; gap: 4px; color: #10b981; font-weight: 700;">
            <span style="width: 8px; height: 8px; border-radius: 50%; background: #10b981; box-shadow: 0 0 6px #10b981;"></span>
            LIVE CAPTURE ON
          </span>
          <button id="btn-toggle-capture" style="
            background: #ffd700;
            color: #100609;
            border: none;
            border-radius: 4px;
            padding: 5px 10px;
            font-weight: 700;
            cursor: pointer;
          ">PAUSE</button>
        \`;

        document.body.appendChild(dock);

        let active = true;
        const btn = document.getElementById('btn-toggle-capture');
        const st = document.getElementById('dock-status');

        btn.addEventListener('click', () => {
          active = !active;
          if (active) {
            btn.innerText = 'PAUSE';
            btn.style.background = '#ffd700';
            st.innerHTML = '<span style="width:8px;height:8px;border-radius:50%;background:#10b981;box-shadow:0 0 6px #10b981;"></span> LIVE CAPTURE ON';
            st.style.color = '#10b981';
          } else {
            btn.innerText = 'RESUME';
            btn.style.background = '#3b82f6';
            st.innerHTML = '<span style="width:8px;height:8px;border-radius:50%;background:#ef4444;"></span> CAPTURE PAUSED';
            st.style.color = '#ef4444';
          }
        });
      })();
    `;

    this.window.webContents.executeJavaScript(script).catch(() => {});
  }

  public startCapture(): void {
    if (this.captureInterval) clearInterval(this.captureInterval);
    if (this.fpsTimer) clearInterval(this.fpsTimer);

    this.isCapturing = true;
    this.frameCount = 0;
    this.lastFpsTime = Date.now();

    // FPS Meter
    this.fpsTimer = setInterval(() => {
      const now = Date.now();
      const elapsed = (now - this.lastFpsTime) / 1000;
      const currentFps = elapsed > 0 ? Math.round(this.frameCount / elapsed) : 0;
      this.frameCount = 0;
      this.lastFpsTime = now;
      this.emit('fps', currentFps);
    }, 1000);

    // Continuous capture tick (~30 FPS preview & GPU feed)
    this.captureInterval = setInterval(async () => {
      if (!this.window || this.window.isDestroyed() || !this.isCapturing) return;

      try {
        const image = await this.window.webContents.capturePage();
        if (!image.isEmpty()) {
          this.frameCount++;
          const dataUrl = image.toDataURL();
          this.emit('frame', {
            dataUrl,
            width: image.getSize().width,
            height: image.getSize().height,
            timestamp: Date.now(),
          });
        }
      } catch {
        // Window closing or transitioning
      }
    }, 33);

    this.emit('capture-started');
  }

  public stopCapture(): void {
    this.isCapturing = false;
    if (this.captureInterval) {
      clearInterval(this.captureInterval);
      this.captureInterval = null;
    }
    if (this.fpsTimer) {
      clearInterval(this.fpsTimer);
      this.fpsTimer = null;
    }
    this.emit('capture-stopped');
  }

  public isWindowOpen(): boolean {
    return this.window !== null && !this.window.isDestroyed();
  }

  public getCapturingState(): boolean {
    return this.isCapturing;
  }

  public close(): void {
    this.stopCapture();
    if (this.window && !this.window.isDestroyed()) {
      this.window.close();
    }
    this.window = null;
  }
}
