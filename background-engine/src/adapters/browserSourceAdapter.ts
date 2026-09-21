import { BrowserWindow } from 'electron';
import { BaseSourceAdapter } from './baseAdapter';
import { SourceAdapterConfig } from '../main/sourceTypes';

export class BrowserSourceAdapter extends BaseSourceAdapter {
  private captureWindow: BrowserWindow | null = null;
  private frameInterval: NodeJS.Timeout | null = null;
  private lastFrameTime = 0;
  private frameCount = 0;
  private fpsTimer: NodeJS.Timeout | null = null;

  constructor(config: SourceAdapterConfig) {
    super(config);
  }

  public getCapabilities(): string[] {
    return ['VIDEO_STREAM', 'DOM_INTERACTION', 'OFFSCREEN_RENDER', 'AUTHENTICATED_SESSION'];
  }

  public async connect(): Promise<void> {
    if (this.captureWindow) {
      return;
    }

    this.setStatus('CONNECTING');

    try {
      this.captureWindow = new BrowserWindow({
        width: 1280,
        height: 720,
        show: false, // Run offscreen for video rendering
        webPreferences: {
          partition: 'persist:operator_browser_session',
          nodeIntegration: false,
          contextIsolation: true,
          backgroundThrottling: false,
        },
      });

      this.captureWindow.webContents.on('did-finish-load', () => {
        this.setStatus('ONLINE');
        this.startCaptureLoop();
      });

      this.captureWindow.webContents.on('did-fail-load', (_e, errorCode, errorDesc) => {
        this.setStatus('DEGRADED', `Page load failed: ${errorDesc} (${errorCode})`);
      });

      this.captureWindow.webContents.on('render-process-gone', (_e, details) => {
        this.setStatus('OFFLINE', `Render process crashed: ${details.reason}`);
        if (this.config.autoReconnect) {
          this.reconnect();
        }
      });

      await this.captureWindow.loadURL(this.config.targetUrl);
    } catch (err: any) {
      this.setStatus('OFFLINE', err.message || 'Failed to start browser capture');
      throw err;
    }
  }

  private startCaptureLoop(): void {
    if (this.frameInterval) clearInterval(this.frameInterval);
    if (this.fpsTimer) clearInterval(this.fpsTimer);

    this.frameCount = 0;
    this.lastFrameTime = Date.now();

    // Measure FPS window
    this.fpsTimer = setInterval(() => {
      const now = Date.now();
      const elapsed = (now - this.lastFrameTime) / 1000;
      const fps = elapsed > 0 ? Math.round(this.frameCount / elapsed) : 0;
      this.frameCount = 0;
      this.lastFrameTime = now;
      this.updateHeartbeat(15, fps);
    }, 1000);

    // Frame capture tick: 30-60 FPS capture rate
    this.frameInterval = setInterval(async () => {
      if (!this.captureWindow || this.captureWindow.isDestroyed()) return;

      try {
        const image = await this.captureWindow.webContents.capturePage();
        if (!image.isEmpty()) {
          this.frameCount++;
          const dataUrl = image.toDataURL();
          this.emit('frame', {
            sourceId: this.getId(),
            dataUrl,
            width: image.getSize().width,
            height: image.getSize().height,
            timestamp: Date.now(),
          });
        }
      } catch (e: any) {
        // capturePage might fail if window is closing
      }
    }, 33); // ~30 fps default preview capture
  }

  public async disconnect(): Promise<void> {
    if (this.frameInterval) {
      clearInterval(this.frameInterval);
      this.frameInterval = null;
    }
    if (this.fpsTimer) {
      clearInterval(this.fpsTimer);
      this.fpsTimer = null;
    }

    if (this.captureWindow && !this.captureWindow.isDestroyed()) {
      this.captureWindow.destroy();
    }
    this.captureWindow = null;
    this.setStatus('OFFLINE');
  }

  public async reconnect(): Promise<void> {
    this.setStatus('RECONNECTING');
    await this.disconnect();
    await new Promise((r) => setTimeout(r, 1000));
    await this.connect();
  }

  public getOutput(): any {
    return {
      type: 'BROWSER_CAPTURE',
      sourceId: this.getId(),
      status: this.status,
      health: this.getHealth(),
    };
  }
}
