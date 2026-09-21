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
  private authPartition = 'persist:sunwin_auth';
  private loginWindow: BrowserWindow | null = null;
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

  public openLoginWindow(parentWindow?: BrowserWindow): void {
    if (this.loginWindow && !this.loginWindow.isDestroyed()) {
      this.loginWindow.focus();
      return;
    }

    this.loginWindow = new BrowserWindow({
      width: 1024,
      height: 720,
      title: 'Xác Thực Đăng Nhập Sunwin (Preview Workspace Only)',
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

    this.loginWindow.loadURL('https://play.sunwin.agency/');

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
      const cookies = await sess.cookies.get({ domain: 'sunwin.agency' });

      // Check for presence of authenticated session tokens/cookies
      const hasAuthCookie = cookies.some(c => 
        c.name.includes('token') || 
        c.name.includes('session') || 
        c.name.includes('auth') ||
        c.name.includes('user')
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
