import { EventEmitter } from 'events';
import { BrowserWindow, session } from 'electron';
import path from 'path';

export interface AuthStatus {
  isAuthenticated: boolean;
  username?: string;
  avatar?: string;
  lastChecked: number;
}

export class AuthSessionManager extends EventEmitter {
  private profileDir: string;
  private authPartition = 'persist:operator_browser_session';
  private loginWindow: BrowserWindow | null = null;
  private activeTargetUrl: string = '';
  private currentStatus: AuthStatus = {
    isAuthenticated: false,
    lastChecked: Date.now(),
  };
  private checkInterval: NodeJS.Timeout | null = null;

  constructor(profileDir: string) {
    super();
    this.profileDir = profileDir;
    this.startPeriodicVerification();
  }

  public getSessionPartition(): string {
    return this.authPartition;
  }

  public getStatus(): AuthStatus {
    return { ...this.currentStatus };
  }

  public setTargetUrl(url: string): void {
    this.activeTargetUrl = url;
  }

  public openLoginWindow(targetUrl?: string, parentWindow?: BrowserWindow): void {
    const urlToLoad = targetUrl || this.activeTargetUrl;
    if (!urlToLoad) {
      console.warn('[AuthSession] Cannot open login window without a target URL');
      return;
    }

    if (this.loginWindow && !this.loginWindow.isDestroyed()) {
      this.loginWindow.focus();
      return;
    }

    this.loginWindow = new BrowserWindow({
      width: 1100,
      height: 760,
      title: 'Xác Thực Đăng Nhập Nguồn (Operator Workspace)',
      parent: parentWindow,
      modal: true,
      autoHideMenuBar: true,
      webPreferences: {
        partition: this.authPartition,
        nodeIntegration: false,
        contextIsolation: true,
        sandbox: true,
      },
    });

    this.loginWindow.loadURL(urlToLoad);

    this.loginWindow.webContents.on('did-finish-load', () => {
      this.verifySession();
    });

    this.loginWindow.on('closed', () => {
      this.loginWindow = null;
      this.verifySession();
    });
  }

  public async verifySession(): Promise<boolean> {
    try {
      const sess = session.fromPartition(this.authPartition);
      const cookies = await sess.cookies.get({});

      // Check for presence of authenticated session tokens/cookies
      const hasAuthCookie = cookies.some(c => 
        c.name.toLowerCase().includes('token') || 
        c.name.toLowerCase().includes('session') || 
        c.name.toLowerCase().includes('auth') ||
        c.name.toLowerCase().includes('user') ||
        c.name.toLowerCase().includes('jwt')
      );

      const isAuthed = hasAuthCookie || cookies.length > 2;

      this.currentStatus = {
        isAuthenticated: isAuthed,
        username: isAuthed ? 'Studio_Operator' : undefined,
        lastChecked: Date.now(),
      };

      this.emit('auth-status-changed', this.currentStatus);
      return isAuthed;
    } catch (err) {
      console.error('[AuthSession] Session check error:', err);
      this.currentStatus = {
        isAuthenticated: false,
        lastChecked: Date.now(),
      };
      this.emit('auth-status-changed', this.currentStatus);
      return false;
    }
  }

  public async logout(): Promise<void> {
    const sess = session.fromPartition(this.authPartition);
    await sess.clearStorageData();
    this.currentStatus = {
      isAuthenticated: false,
      lastChecked: Date.now(),
    };
    this.emit('auth-status-changed', this.currentStatus);
    console.log('[AuthSession] Logged out & session cleared.');
  }

  private startPeriodicVerification(): void {
    // Silently verify every 30 seconds
    this.checkInterval = setInterval(() => {
      this.verifySession();
    }, 30000);
  }

  public destroy(): void {
    if (this.checkInterval) {
      clearInterval(this.checkInterval);
    }
    if (this.loginWindow && !this.loginWindow.isDestroyed()) {
      this.loginWindow.close();
    }
  }
}
